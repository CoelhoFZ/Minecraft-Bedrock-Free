// Copyright (C) 2026 CoelhoFZ
// SPDX-License-Identifier: GPL-3.0-only
// This file is part of unlocker-CoelhoFZ (GPLv3, see LICENSE).

// chacha20.h - ChaCha20 (RFC 8439), 256-bit key, 96-bit nonce.
//
// Replaces the LCG of the 2-stage packer (F1 of HARDENING-PLAN): the LCG is
// a trivial stream (the known PE plaintext 'MZ' recovers the keystream
// without the key); ChaCha20 requires the 32-byte key, which in the binary
// only exists masked/derived at runtime.
//
// Word contract (identical to tools/pack_payload.py):
//   key[8]   = 8 x uint32 (little-endian in the state, as in the RFC)
//   nonce[3] = 3 x uint32 (bytes 13..15 of the state)
//   counter  = block uint32 (state[12]); starts at 0 and increments every
//              64-byte block (Cipher adds off/64).
// Encrypt == decrypt (XOR with the keystream).
//
// No external dependency, no allocation, no exceptions: runs on the same
// --harden flags (-fno-exceptions -fno-rtti -fno-threadsafe-statics).

#pragma once

#include <cstdint>
#include <cstring>

namespace chacha20 {

namespace detail {

inline uint32_t Rol(uint32_t v, int c) { return (v << c) | (v >> (32 - c)); }

#define CHACHA_QR(a, b, c, d)               \
    a += b; d ^= a; d = Rol(d, 16);         \
    c += d; b ^= c; b = Rol(b, 12);         \
    a += b; d ^= a; d = Rol(d, 8);          \
    c += d; b ^= c; b = Rol(b, 7)

// One double round (8 quarter-rounds) over the 16-word state.
inline void DoubleRound(uint32_t x[16]) {
    // columns
    CHACHA_QR(x[0], x[4], x[8], x[12]);
    CHACHA_QR(x[1], x[5], x[9], x[13]);
    CHACHA_QR(x[2], x[6], x[10], x[14]);
    CHACHA_QR(x[3], x[7], x[11], x[15]);
    // diagonals
    CHACHA_QR(x[0], x[5], x[10], x[15]);
    CHACHA_QR(x[1], x[6], x[11], x[12]);
    CHACHA_QR(x[2], x[7], x[8], x[13]);
    CHACHA_QR(x[3], x[4], x[9], x[14]);
}

#undef CHACHA_QR

}  // namespace detail

// Generates a 64-byte keystream block for (key, counter, nonce).
inline void Block(const uint32_t key[8], uint32_t counter,
                  const uint32_t nonce[3], uint8_t out[64]) {
    uint32_t st[16];
    st[0] = 0x61707865u;
    st[1] = 0x3320646eu;
    st[2] = 0x79622d32u;
    st[3] = 0x6b206574u;
    std::memcpy(&st[4], key, 8 * sizeof(uint32_t));   // LE words of the state
    st[12] = counter;
    std::memcpy(&st[13], nonce, 3 * sizeof(uint32_t));
    uint32_t x[16];
    std::memcpy(x, st, sizeof(x));
    for (int r = 0; r < 10; ++r) detail::DoubleRound(x);
    for (int i = 0; i < 16; ++i) x[i] += st[i];
    for (int i = 0; i < 16; ++i) {
        out[i * 4 + 0] = static_cast<uint8_t>(x[i]);
        out[i * 4 + 1] = static_cast<uint8_t>(x[i] >> 8);
        out[i * 4 + 2] = static_cast<uint8_t>(x[i] >> 16);
        out[i * 4 + 3] = static_cast<uint8_t>(x[i] >> 24);
    }
}

// XORs the keystream over buf[0..n). counter = index of the first block.
inline void Cipher(uint8_t* buf, uint32_t n, const uint32_t key[8],
                   uint32_t counter, const uint32_t nonce[3]) {
    for (uint32_t off = 0; off < n; off += 64) {
        uint8_t ks[64];
        Block(key, counter + off / 64, nonce, ks);
        const uint32_t lim = (n - off < 64) ? (n - off) : 64;
        for (uint32_t i = 0; i < lim; ++i) buf[off + i] ^= ks[i];
    }
}

}  // namespace chacha20
