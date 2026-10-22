# Project guidance

This repository preserves the upstream MIT-licensed `llvm-tutor` history and adds a bounded integer SLP pass. Keep upstream tutorials and provenance intact.

The supported local Windows verification path is `.agents/skills/verify-bounded-slp/SKILL.md`, driven by `scripts/verify.ps1`. It requires the isolated LLVM 23.1.4 SDK and matching static zlib/zstd dependencies described there. Do not use global LLVM installations or fabricate imported CMake targets to work around missing SDK exports.

The pass only considers independent, same-opcode integer add/sub/mul instructions in one basic block. Its exact mode uses subset dynamic programming for at most 16 candidates per block and falls back to adjacent greedy pairing above that bound. Keep legality checks ahead of cost decisions, preserve per-operation flags, and verify transformed IR with LLVM's verifier.
