# Bounded LLVM SLP Vectorizer

This project adds a small, real LLVM function pass for packing independent scalar integer operations into two-lane SIMD operations. It is built on the complete MIT-licensed history of [`llvm-tutor`](https://github.com/banach-space/llvm-tutor), which remains in this repository as the tutorial collection. The exact inherited README is preserved in [`README.upstream.md`](README.upstream.md), and inherited CI workflows are retained byte-for-byte under [`docs/upstream/workflows`](docs/upstream/workflows/).

## What it does

The pass considers independent `add`, `sub`, and `mul` instructions with the same integer type in one basic block. It checks operand dominance and matching operation flags before packing, then replaces scalar results with vector lanes. Exact mode uses bounded subset dynamic programming for up to 16 candidates in a block; larger blocks use the adjacent-pair greedy fallback. `--greedy` selects the baseline directly.

The cost decision uses target arithmetic costs and estimates arithmetic savings. It does not account for all vector construction, insertion, and extraction costs, so it is not a complete profitability model and does not promise a speedup. This is an explicitly bounded packing pass, not a full LLVM SLP implementation.

## Build and run on Windows

The supported Windows setup uses the isolated LLVM 23.1.4 SDK and dependencies described in [the verification guide](.agents/skills/verify-bounded-slp/SKILL.md). No system-wide LLVM installation is required. From PowerShell:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/verify.ps1 -Phase Launch
build/verify/slp-opt.exe test/BoundedSLP.ll -o build/verify/exact.ll
build/verify/slp-opt.exe test/BoundedSLP.ll --greedy -o build/verify/greedy.ll
& "$env:USERPROFILE\.codex\tools\coursework-llvm\clang+llvm-23.1.4-x86_64-pc-windows-msvc\bin\opt.exe" -passes=verify -disable-output build/verify/exact.ll
& "$env:USERPROFILE\.codex\tools\coursework-llvm\clang+llvm-23.1.4-x86_64-pc-windows-msvc\bin\llc.exe" -O2 -mattr=+sse2 -filetype=asm build/verify/exact.ll -o build/verify/exact.s
```

`slp-opt.exe` verifies input and output IR itself. The explicit `opt` command above is an additional verifier check; `llc` lowers the transformed module to native x86 assembly. The pass source also registers `bounded-slp` and `bounded-slp-greedy` for a shared-LLVM plugin host. On Windows the pinned SDK is statically linked, so the documented, exercised entry point is the standalone `slp-opt.exe` driver.

Run the complete local workflow with:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/verify.ps1 -Phase All
```

It builds the driver, checks the SDK and disk reserve, drives exact and greedy modes, verifies transformed IR, emits assembly and an object, checks native arithmetic and pointer cases, records interleaved timings, saves evidence, then removes only its build scratch directory. The reusable steps and feature map are in [`.agents/skills/verify-bounded-slp`](.agents/skills/verify-bounded-slp/).

## Provenance and design mapping

The bounded pass is the project work. The retained `llvm-tutor` code, authorship, and original MIT license are reused as the host tutorial project and LLVM out-of-tree build convention; the new pass and driver are original additions in the same MIT-licensed repository. See [`README.upstream.md`](README.upstream.md), [`LICENSE`](LICENSE), and the preserved Git history for provenance.

The motivation follows the scalar-group detection and SIMD lowering problem represented in the [CMU 15-745 Fall 2024 actual-project gallery](https://www.cs.cmu.edu/afs/cs.cmu.edu/academic/class/15745-f24/www/project_info/actual_projects.html). The packing comparison is informed by the statement-packing and cost ideas in the [goSLP OOPSLA 2018 paper](https://commit.csail.mit.edu/papers/2018/oopsla-goslp.pdf). This implementation does not copy student project code and does not claim to reproduce goSLP's whole-function ILP, solver, or published benchmark results.

## Verification evidence

The Windows run used LLVM 23.1.4 and MSVC 14.44. Exact mode formed six vector adds, greedy mode formed five, and the 16-candidate exact-search case completed in 16.767 ms in the local verification host. LLVM's verifier accepted the outputs. `llc -O2 -mattr=+sse2` emitted `paddd`; native differential checks passed 65,600 arithmetic inputs and eight pointer/alias cases. The nine-round interleaved sample measured medians of 1.46646 ns/call for the scalar baseline and 1.21037 ns/call for the transformed function. These measurements describe one local run only and are not a performance guarantee.

Compact primary artifacts are in [`docs/evidence`](docs/evidence/): transformed exact and greedy IR, emitted assembly, and the recorded Windows transcripts. The local verification workflow also retains full run evidence under `.verify/evidence/`, which is ignored by Git. A separate Linux CI workflow is configured to build and exercise the LLVM plugin against the versioned LLVM 23.1.4 release; it is read-only and does not publish artifacts.

The upstream tutorial suite and conventional plugin loading on Windows were not validated by the local run. The Linux CI job exercises the pass plugin path when run. The exact-search bound and incomplete cost estimate are intentional limits of this project.
