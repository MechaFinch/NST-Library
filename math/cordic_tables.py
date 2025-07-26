
# script for getting cordic tables

import math

data_size = 16
fixed_factor = 2 ** 8
num_iters = 8


def to_fixed(n):
    return int(n * fixed_factor) & ((2 ** data_size) - 1)

def from_fixed(n):
    return n / fixed_factor


def main():
    k = 1
    
    for i in range(num_iters):
        gamma = math.atan2(1, 2 ** i)
        k *= 1 / math.sqrt(1 + (2 ** (-2 * i)))
        print(f"0x{to_fixed(gamma):08X}, ", end="")
    
    print()
    print(f"    K = {to_fixed(k):08X}")
    print(f"   pi = {to_fixed(math.pi):08X}")
    print(f"  -pi = {to_fixed(-math.pi):08X}")
    print(f" pi/2 = {to_fixed(math.pi / 2):08X}")
    print(f"-pi/2 = {to_fixed(-math.pi / 2):08X}")


if __name__ == "__main__":
    main()
