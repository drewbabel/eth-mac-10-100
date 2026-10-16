import random
import re
import zlib

POLY = 0x04C11DB7
MASK = 0xFFFFFFFF
SEED = 1
NUM_RANDOM = 24
TB = "tb/crc_tb.sv"


def bitrev32(x):
    return int(f"{x:032b}"[::-1], 2)


def crc_reg(data):
    reg = MASK
    for byte in data:
        for i in range(8):
            top = reg >> 31
            reg = (reg << 1) & MASK
            if top ^ ((byte >> i) & 1):
                reg ^= POLY
    return reg


def make_frames():
    rng = random.Random(SEED)
    lengths = [1, 2, 3, 4, 60, 64, 1514, 1518]
    lengths += [rng.randint(60, 1518) for _ in range(NUM_RANDOM)]
    frames = [b"123456789"]
    frames += [bytes(rng.randrange(256) for _ in range(n)) for n in lengths]
    return frames


def main():
    # Standard check value
    assert zlib.crc32(b"123456789") == 0xCBF43926

    frames = make_frames()
    with (
        open("tb/crc_data.hex", "w") as data_file,
        open("tb/crc_expect.hex", "w") as expect_file,
    ):
        for frame in frames:
            reg = crc_reg(frame)
            assert reg == bitrev32(zlib.crc32(frame) ^ MASK)
            data_file.writelines(f"{b:02x}\n" for b in frame)
            expect_file.write(f"{len(frame):04x}{reg:08x}\n")

    num_bytes = sum(map(len, frames))
    tb = open(TB).read()
    for name, value in (("NumFrames", len(frames)), ("NumBytes", num_bytes)):
        if not re.search(rf"localparam int {name} = {value};", tb):
            raise SystemExit(f"set {name} = {value} in {TB}")

    print(f"{len(frames)} frames, {num_bytes} bytes")


if __name__ == "__main__":
    main()
