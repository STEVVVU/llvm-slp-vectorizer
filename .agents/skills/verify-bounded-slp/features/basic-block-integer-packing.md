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

The observable end state is valid transformed IR with two packed adds in `packing_shape` for exact mode versus one for greedy mode, plus the independently packed `slp_add2`, constant-pair, pointer, and volatile-load fixtures. The emitted assembly must contain a packed integer add instruction. The native harness checks 65,600 arithmetic inputs and pointer-output alias cases.

## Gotchas

- Scalar constant pairs are emitted as vector instructions without IRBuilder constant folding the operation into a `Constant`; otherwise there is no instruction to replace the original scalar operations.
- The target arithmetic cost comparison excludes lane construction and extraction costs. It is a bounded selection heuristic, not a complete profitability model.
- Exact-search evidence only characterizes the 16-candidate bound. Above that count the pass uses greedy pairing.
- The Windows SDK ships static LLVM archives. `opt -load-pass-plugin` is not the validated Windows path; use the standalone driver linked against the same SDK.
