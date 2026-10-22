# Basic-block integer packing

The pass packs two independent integer add, subtract, or multiply instructions from one basic block into a two-lane vector operation. Exact mode selects non-overlapping pairs across at most 16 candidates; larger blocks use adjacent greedy pairing.

## Sub-features

- Greedy adjacent pairing is available with `--greedy`.
- Exact bounded packing uses subset dynamic programming for up to 16 candidates.
- Legality guards require matching opcode, type, flags, independent operations, and operands available before the first packed instruction.

## How to get to it (user POV)

Build the real CLI with `scripts/verify.ps1 -Phase Launch`, then give `build/verify/slp-opt.exe` a textual LLVM IR module and an output path. Exact mode is the default; add `--greedy` for the baseline.

## Driving it with PowerShell

Run `scripts/verify.ps1 -Phase Drive`. It invokes the CLI on `test/BoundedSLP.ll` in both modes, verifies the written IR with LLVM `opt`, checks exact versus greedy packing counts, and sends the exact output through the native `llc` backend.

The observable end state is valid transformed IR with one packed add in `packing_shape` for both modes, plus the independently packed `slp_add2`, constant-pair, pointer, and volatile-load fixtures. Exact and greedy modes each form five packed adds overall. The computed-operand fixture remains scalar after accounting for lane insertion costs; invalid target costs conservatively reject packing. The emitted assembly must contain a packed integer add instruction. The native harness checks 65,600 arithmetic inputs and pointer-output alias cases.

## Gotchas

The maintained `scripts/benchmark.py` prepares eight deterministic scalar-IR kernels. On the pinned Linux runner, `--run` compares scalar, bounded exact, greedy and upstream LLVM SLP through the same SSE2 native backend at 16K, 1M and 8M outputs. `--before-ref 66b66ba2e86640a8f96bfc5d0299461b10513c29` adds the original pass built with the same LLVM/CMake flags on that runner as a fifth side. Seven rotated repeats retain per-element runtime, pass/codegen time, object/text size, checksums and independent full-output checks. `test/benchmark_native.cpp --smoke` performs untimed correctness checks. Workflow dispatch runs this campaign and retains `.verify/benchmark/`. Same-runner run39730682620 passed all840 samples; `docs/evidence/native-metrics.json` preserves all120 distributions, hashes and eight-function assembly review. Only affine8 has nonoverlapping old/new improvement ranges at all three sizes; the other21 comparisons overlap. The computed-lane materialization is removed while arithmetic oracles remain unchanged. A separate perf counter attempt records failures explicitly; unavailable counters do not establish a hardware limiter.

- Scalar constant pairs are emitted as vector instructions without IRBuilder constant folding the operation into a `Constant`; otherwise there is no instruction to replace the original scalar operations.
- The target arithmetic cost comparison excludes lane construction and extraction costs. It is a bounded selection heuristic, not a complete profitability model.
- Exact-search evidence only characterizes the 16-candidate bound. Above that count the pass uses greedy pairing.
- The Windows SDK ships static LLVM archives. `opt -load-pass-plugin` is not the validated Windows path; use the standalone driver linked against the same SDK.
