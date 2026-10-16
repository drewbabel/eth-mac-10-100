import random
import re
import zlib

SEED = 1
NUM_RANDOM = 12
TB = "tb/rmii_tx_tb.sv"
STALL_EARLY = (40, 10)
STALL_LATE = (100, 70)
RESET_MID = (100, 30)


def tb_param(tb, name):
    return int(re.search(rf"localparam int {name} = (\d+);", tb).group(1))


def wire_pairs(payload, preamble, pad_to, bad):
    body = payload + bytes(max(0, pad_to - len(payload)))
    fcs = zlib.crc32(body) ^ (0xFFFFFFFF if bad else 0)
    wire = bytes([0x55] * preamble + [0xD5]) + body + fcs.to_bytes(4, "little")
    return [(b >> (2 * k)) & 3 for b in wire for k in range(4)]


def make_frames(rng):
    frames = []
    for div in (1, 10):
        plan = [(n, 0, 0, 0) for n in (1, 29, 30, 31, 59, 60, 61, 1518)]
        plan += [(STALL_EARLY[0], 0, STALL_EARLY[1], 0), (60, 0, 0, 0)]
        plan += [(STALL_LATE[0], 0, STALL_LATE[1], 0), (60, 0, 0, 0)]
        plan += [(RESET_MID[0], 0, 0, RESET_MID[1]), (60, 0, 0, 0)]
        for _ in range(NUM_RANDOM):
            plan.append((rng.randint(1, 1518), rng.randint(0, 50), 0, 0))
        for n, idle, stall, rst in plan:
            data = bytes(rng.randrange(256) for _ in range(n))
            frames.append((div, idle, data, stall, rst))
    return frames


def write_config(frames, preamble, pad_to, suffix):
    num_pairs = 0
    with (
        open(f"tb/rmii_tx_frames{suffix}.hex", "w") as frame_file,
        open(f"tb/rmii_tx_expect{suffix}.hex", "w") as expect_file,
    ):
        for div, idle, data, stall, rst in frames:
            sent = data[:stall] if stall else data
            pairs = wire_pairs(sent, preamble, pad_to, bad=bool(stall))
            expect_file.writelines(f"{p:x}\n" for p in pairs)
            fields = (div, idle, len(data), stall, rst, len(pairs))
            frame_file.write("{:02x}{:04x}{:04x}{:04x}{:04x}{:08x}\n".format(*fields))
            num_pairs += len(pairs)
    return num_pairs


def main():
    tb = open(TB).read()
    frames = make_frames(random.Random(SEED))

    with open("tb/rmii_tx_data.hex", "w") as data_file:
        for frame in frames:
            data_file.writelines(f"{b:02x}\n" for b in frame[2])

    sizes = (
        ("NumFrames", len(frames)),
        ("NumBytes", sum(len(frame[2]) for frame in frames)),
    )
    for prefix, suffix in (("", ""), ("Alt", "_alt")):
        preamble = tb_param(tb, f"{prefix}PreambleBytes")
        pad_to = tb_param(tb, f"{prefix}PadToBytes")
        num_pairs = write_config(frames, preamble, pad_to, suffix)
        sizes += ((f"{prefix}NumPairs", num_pairs),)

    for name, value in sizes:
        if tb_param(tb, name) != value:
            raise SystemExit(f"set {name} = {value} in {TB}")

    print(", ".join(f"{name} {value}" for name, value in sizes))


if __name__ == "__main__":
    main()
