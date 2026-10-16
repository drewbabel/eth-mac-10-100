import random
import re
import zlib

SEED = 1
NUM_RANDOM = 12
TB = "tb/rmii_rx_tb.sv"
POLY = 0x04C11DB7
MASK = 0xFFFFFFFF
RESIDUE = 0xC704DD7B
TAG = (0x81, 0x00)
TYPE_BYTE = 12
HOLD_BYTES = 5


def tb_param(tb, name):
    return int(re.search(rf"localparam int {name} = (\d+);", tb).group(1))


def crc_reg(bits):
    reg = MASK
    for bit in bits:
        top = reg >> 31
        reg = (reg << 1) & MASK
        if top ^ bit:
            reg ^= POLY
    return reg


def byte_bits(data):
    return [(b >> i) & 1 for b in data for i in range(8)]


def fcs_bits(bits):
    sent = crc_reg(bits) ^ MASK
    return [(sent >> (31 - k)) & 1 for k in range(32)]


def make_frame(rng, n, div, **kw):
    data = bytearray(rng.randrange(256) for _ in range(n))
    if kw.get("tag") and n > TYPE_BYTE + 1:
        data[TYPE_BYTE], data[TYPE_BYTE + 1] = TAG
    bits = byte_bits(data)
    if kw.get("nibble_inside"):
        bits += [rng.randrange(2) for _ in range(4)]
    bits += fcs_bits(bits)
    if kw.get("nibble_after"):
        bits += [rng.randrange(2) for _ in range(4)]
    if kw.get("corrupt"):
        bits[rng.randrange(len(bits))] ^= 1

    pins = [(1, 0)] * kw.get("lead", 2)
    pins += [(1, 1)] * (4 * kw.get("preamble", 7))
    if kw.get("no_body"):
        bits = []
    else:
        pins += [(1, 1), (1, 1), (1, 1), (1, 3)]
    dibits = [bits[i] | bits[i + 1] << 1 for i in range(0, len(bits), 2)]
    toggles = kw.get("toggles", 0)
    for i, d in enumerate(dibits):
        in_toggle = i // 2 >= len(dibits) // 2 - toggles
        pins.append((0 if in_toggle and i % 2 == 0 else 1, d))
    pins += [(0, 0)] * kw.get("gap", 24)

    return {
        "div": div,
        "phase": rng.randrange(div),
        "pins": pins,
        "bits": bits,
        "rst_at": kw.get("rst_at", 0),
    }


def expected(frame, min_bytes, max_bytes, max_tagged):
    bits = frame["bits"]
    full = len(bits) // 8
    if frame["rst_at"] or full < HOLD_BYTES:
        return []
    got = [sum(bits[8 * j + i] << i for i in range(8)) for j in range(full)]
    tagged = full > TYPE_BYTE + 1 and tuple(got[TYPE_BYTE : TYPE_BYTE + 2]) == TAG
    limit = max_tagged if tagged else max_bytes
    bad = (
        crc_reg(bits[: 8 * full]) != RESIDUE
        or full < min_bytes
        or full > limit
    )
    out = got[: full - 4]
    return [
        (b, j == len(out) - 1, bad and j == len(out) - 1)
        for j, b in enumerate(out)
    ]


def make_frames(rng):
    frames = []
    for div in (1, 10):
        plan = [(n - 4, {}) for n in (19, 20, 21, 63, 64, 65, 200, 201, 1518, 1519)]
        plan += [(n - 4, {"tag": True}) for n in (204, 205, 1522, 1523)]
        plan += [
            (1, {}),
            (60, {"preamble": 12}),
            (60, {"preamble": 1, "lead": 0}),
            (60, {"preamble": 0}),
            (60, {"no_body": True}),
            (60, {"preamble": 0, "lead": 6, "no_body": True}),
            (60, {"toggles": 1}),
            (60, {"toggles": 3}),
            (60, {"corrupt": True}),
            (60, {"nibble_after": True}),
            (60, {"nibble_inside": True}),
            (60, {"nibble_inside": True, "toggles": 2}),
            (60, {"gap": 2}),
            (60, {"gap": 2}),
            (60, {}),
            (100, {"rst_at": 300}),
            (60, {}),
        ]
        for _ in range(NUM_RANDOM):
            n = rng.randint(1, 1530)
            kw = {
                "preamble": rng.randint(0, 9),
                "lead": rng.randint(0, 4),
                "toggles": rng.randint(0, 3),
                "gap": rng.randint(2, 40),
                "corrupt": rng.random() < 0.3,
            }
            plan.append((n, kw))
        frames += [make_frame(rng, n, div, **kw) for n, kw in plan]
    return frames


def main():
    tb = open(TB).read()
    rng = random.Random(SEED)

    check = bytes(rng.randrange(256) for _ in range(60))
    body = check + zlib.crc32(check).to_bytes(4, "little")
    assert byte_bits(body) == byte_bits(check) + fcs_bits(byte_bits(check))
    assert crc_reg(byte_bits(body)) == RESIDUE

    frames = make_frames(rng)
    with (
        open("tb/rmii_rx_frames.hex", "w") as frame_file,
        open("tb/rmii_rx_pins.hex", "w") as pin_file,
    ):
        for f in frames:
            fields = (f["div"], f["phase"], len(f["pins"]), f["rst_at"])
            frame_file.write("{:02x}{:02x}{:04x}{:04x}\n".format(*fields))
            pin_file.writelines(f"{crs << 2 | d:x}\n" for crs, d in f["pins"])

    sizes = (
        ("NumFrames", len(frames)),
        ("NumPins", sum(len(f["pins"]) for f in frames)),
    )
    for prefix, suffix in (("", ""), ("Alt", "_alt")):
        limits = [
            tb_param(tb, f"{prefix}{name}")
            for name in ("MinFrameBytes", "MaxFrameBytes", "MaxTaggedFrameBytes")
        ]
        outs = [o for f in frames for o in expected(f, *limits)]
        with open(f"tb/rmii_rx_expect{suffix}.hex", "w") as expect_file:
            for b, last, bad in outs:
                expect_file.write(f"{bad << 1 | last:x}{b:02x}\n")
        sizes += ((f"{prefix}NumOut", len(outs)),)

    for name, value in sizes:
        if tb_param(tb, name) != value:
            raise SystemExit(f"set {name} = {value} in {TB}")

    print(", ".join(f"{name} {value}" for name, value in sizes))


if __name__ == "__main__":
    main()
