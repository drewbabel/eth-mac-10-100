import random
import re
import zlib

SEED = 1
NUM_RANDOM = 8
TB = "tb/rmii_line_tb.sv"
PREAMBLE_BYTES = 7
PAD_TO_BYTES = 60
MAX_FRAME_BYTES = 1518
HEADER_PAIRS = 4 * (PREAMBLE_BYTES + 1)
TAG = bytes([0x81, 0x00])
STALL = (100, 40)


def tb_param(tb, name):
    return int(re.search(rf"localparam int {name} = (\d+);", tb).group(1))


def random_data(rng, n):
    while True:
        data = bytes(rng.randrange(256) for _ in range(n))
        if data[12:14] != TAG:
            return data


def wire_body(data, stall):
    sent = data[:stall] if stall else data
    body = sent + bytes(max(0, PAD_TO_BYTES - len(sent)))
    fcs = zlib.crc32(body) ^ (0xFFFFFFFF if stall else 0)
    return body, body + fcs.to_bytes(4, "little")


def expected(data, stall, flip):
    body, wire = wire_body(data, stall)
    wire = bytearray(wire)
    if flip:
        k = flip - HEADER_PAIRS
        wire[k // 4] ^= 1 << (2 * (k % 4))
    bad = bool(stall) or bool(flip) or len(wire) > MAX_FRAME_BYTES
    out = wire[: len(body)]
    return [
        (b, j == len(out) - 1, bad and j == len(out) - 1)
        for j, b in enumerate(out)
    ]


def make_frames(rng):
    frames = []
    for div in (1, 10):
        plan = [(n, 0, 0, 0) for n in (1, 59, 60, 61, 1514, 1515)]
        plan.append((STALL[0], 0, STALL[1], 0))
        data_pairs = 4 * 100
        for k in (0, data_pairs // 2, data_pairs - 1, data_pairs, data_pairs + 5,
                  data_pairs + 10, data_pairs + 15):
            plan.append((100, 0, 0, HEADER_PAIRS + k))
        plan.append((1, 0, 0, HEADER_PAIRS + 4 * 30))
        for _ in range(NUM_RANDOM):
            n = rng.randint(1, 1514)
            pairs = 4 * (max(n, PAD_TO_BYTES) + 4)
            flip = HEADER_PAIRS + rng.randrange(pairs) if rng.random() < 0.5 else 0
            plan.append((n, rng.randint(0, 50), 0, flip))
        for n, idle, stall, flip in plan:
            frames.append((div, idle, random_data(rng, n), stall, flip))
    return frames


def main():
    tb = open(TB).read()
    frames = make_frames(random.Random(SEED))

    with (
        open("tb/rmii_line_data.hex", "w") as data_file,
        open("tb/rmii_line_frames.hex", "w") as frame_file,
    ):
        for div, idle, data, stall, flip in frames:
            data_file.writelines(f"{b:02x}\n" for b in data)
            fields = (div, idle, len(data), stall, flip)
            frame_file.write("{:02x}{:04x}{:04x}{:04x}{:04x}\n".format(*fields))

    sizes = (
        ("NumFrames", len(frames)),
        ("NumBytes", sum(len(f[2]) for f in frames)),
    )
    for prefix, suffix, flips in (("", "", False), ("Wire", "_wire", True)):
        outs = [o for f in frames for o in expected(f[2], f[3], f[4] if flips else 0)]
        with open(f"tb/rmii_line_expect{suffix}.hex", "w") as expect_file:
            for b, last, bad in outs:
                expect_file.write(f"{bad << 1 | last:x}{b:02x}\n")
        sizes += ((f"{prefix}NumOut", len(outs)),)

    for name, value in sizes:
        if tb_param(tb, name) != value:
            raise SystemExit(f"set {name} = {value} in {TB}")

    print(", ".join(f"{name} {value}" for name, value in sizes))


if __name__ == "__main__":
    main()
