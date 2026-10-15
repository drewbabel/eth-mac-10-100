import random
import re
import sys

sys.dont_write_bytecode = True

from rmii_line_ref import HEADER_PAIRS, PAD_TO_BYTES, expected, random_data  # noqa: E402

SEED = 1
NUM_RANDOM = 8
TB = "tb/eth_mac_tb.sv"


def tb_param(tb, name):
    return int(re.search(rf"localparam int {name} = (\d+);", tb).group(1))


def make_frames(rng):
    frames = []
    for div in (1, 10):
        plan = [(n, 0, 0) for n in (1, 59, 60, 61, 1514, 1515)]
        data_pairs = 4 * 100
        for k in (0, data_pairs // 2, data_pairs - 1, data_pairs + 5):
            plan.append((100, 0, HEADER_PAIRS + k))
        for _ in range(NUM_RANDOM):
            n = rng.randint(1, 1514)
            pairs = 4 * (max(n, PAD_TO_BYTES) + 4)
            flip = HEADER_PAIRS + rng.randrange(pairs) if rng.random() < 0.5 else 0
            plan.append((n, rng.randint(0, 50), flip))
        for n, idle, flip in plan:
            frames.append((div, idle, random_data(rng, n), flip))
    return frames


def main():
    tb = open(TB).read()
    frames = make_frames(random.Random(SEED))

    with (
        open("tb/eth_mac_data.hex", "w") as data_file,
        open("tb/eth_mac_frames.hex", "w") as frame_file,
    ):
        for div, idle, data, flip in frames:
            data_file.writelines(f"{b:02x}\n" for b in data)
            fields = (div, idle, len(data), flip)
            frame_file.write("{:02x}{:04x}{:04x}{:04x}\n".format(*fields))

    sizes = (
        ("NumFrames", len(frames)),
        ("NumBytes", sum(len(f[2]) for f in frames)),
    )
    for prefix, suffix, flips in (("", "", False), ("Wire", "_wire", True)):
        outs = []
        for f in frames:
            frame = expected(f[2], 0, f[3] if flips else 0)
            if not frame[-1][2]:
                outs += frame
        with open(f"tb/eth_mac_expect{suffix}.hex", "w") as expect_file:
            for b, last, _ in outs:
                expect_file.write(f"{int(last):x}{b:02x}\n")
        sizes += ((f"{prefix}NumOut", len(outs)),)

    for name, value in sizes:
        if tb_param(tb, name) != value:
            raise SystemExit(f"set {name} = {value} in {TB}")

    print(", ".join(f"{name} {value}" for name, value in sizes))


if __name__ == "__main__":
    main()
