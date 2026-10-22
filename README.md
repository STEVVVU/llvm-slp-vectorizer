# Bounded LLVM SLP Vectorizer

This project adds a small, real LLVM function pass for packing independent scalar integer operations into two-lane SIMD operations. It is built on the complete MIT-licensed history of [`llvm-tutor`](https://github.com/banach-space/llvm-tutor), which remains in this repository as the tutorial collection. The exact inherited README is preserved in [`README.upstream.md`](README.upstream.md), and inherited CI workflows are retained byte-for-byte under [`docs/upstream/workflows`](docs/upstream/workflows/).

## What it does

The pass considers independent `add`, `sub`, and `mul` instructions with the same integer type in one basic block. It checks operand dominance and matching operation flags before packing, then replaces scalar results with vector lanes. Exact mode uses bounded subset dynamic programming for up to 16 candidates in a block; larger blocks use the adjacent-pair greedy fallback. `--greedy` selects the baseline directly.

The cost decision uses target arithmetic costs and subtracts target insertion costs for computed scalar operands. This rejects a measured case where lane materialization erased arithmetic savings. Invalid target costs reject the candidate conservatively; foldable scalar loads retain the existing supported packing path. The estimate still omits some construction and extraction costs, so it is not a complete profitability model and does not promise a speedup. This is an explicitly bounded packing pass, not a full LLVM SLP implementation.

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

The historical Windows run used LLVM 23.1.4 and MSVC 14.44, before computed-operand insertion costs were added. Exact mode then formed six vector adds, greedy mode five, and the 16-candidate exact-search case completed in 16.767 ms in that local verification host. LLVM's verifier accepted the outputs. `llc -O2 -mattr=+sse2` emitted `paddd`; native differential checks passed 65,600 arithmetic inputs and eight pointer/alias cases. Its tiny nine-round sample measured medians of 1.46646 ns/call scalar and 1.21037 ns/call transformed. These historical microtimes do not describe the current profitability policy or establish representative performance. The current fixtures require five packed adds in each mode, including one in `packing_shape`; independent arithmetic oracles remain unchanged.

The [matched hosted campaign](https://github.com/STEVVVU/llvm-slp-vectorizer/actions/runs/39730682620) built the original pass `66b66ba2e86640a8f96bfc5d0299461b10513c29` and current pass on the same four-vCPU AMD EPYC 7763 runner, LLVM 23.1.4 and SSE2 `llc -O3` backend. Eight integer kernels at 16K/1M/8M outputs used seven rotated samples of eight calls per side, with full independent output/sentinel oracles. The scalar side disables IR vectorizers; upstream SLP is a separate optimized control. At 1M outputs, ns/output medians [full seven-sample ranges] were:

| Kernel | Scalar | Original bounded | Current bounded | Greedy | Upstream SLP |
| --- | --- | --- | --- | --- | --- |
| add2 | .3912 [.3872,.3982] | .3170 [.3144,.3265] | .3173 [.3158,.3187] | .3171 [.3144,.3269] | .2170 [.2080,.2376] |
| add8 | .4193 [.4149,.4237] | .1897 [.1887,.1942] | .1926 [.1901,.2559] | .1926 [.1896,.2142] | .1740 [.1720,.2046] |
| sub8 | .4185 [.4171,.5503] | .1912 [.1888,.2089] | .1958 [.1882,.2709] | .1906 [.1891,.2638] | .1733 [.1612,.2304] |
| mul8 | .4880 [.4816,.5058] | .4830 [.4798,.5235] | .4824 [.4797,.4866] | .4822 [.4796,.5229] | .2356 [.2126,.2694] |
| mixed8 | .4214 [.4176,.4297] | .4030 [.3982,.4052] | .4001 [.3980,.4096] | .4172 [.4149,.4242] | .3184 [.3162,.3253] |
| affine8 | .4626 [.4606,.4695] | .5993 [.5972,.6089] | .4809 [.4798,.4830] | .4643 [.4611,.4724] | .2479 [.2280,.2592] |
| strided4 | .5834 [.5448,.6066] | .5359 [.5180,.5672] | .5375 [.4975,.5629] | .5280 [.4881,.5465] | .5641 [.5477,.6095] |
| add16 | .3931 [.3881,.4043] | .1906 [.1886,.1918] | .1887 [.1870,.2701] | .1905 [.1871,.2479] | .1675 [.1612,.2348] |

The insertion-cost fix reduces `affine8` from .5993 to .4809 ns/output at 1M, about 19.8%, with nonoverlapping ranges at all three sizes. Original assembly materializes eight computed lanes using eight `movd` and six `punpck` instructions; current assembly removes them and has the same function body as scalar. Its remaining approximately 4% gap to scalar at 1M is observed but is not explained by different function instructions. The other 21 original/current kernel-size comparisons have overlapping ranges, so no win or new regression is established there. Upstream SLP is faster on most dense kernels; this is not an adoption or general superiority result.

Current whole-suite pass time median is 13.602 ms [13.317,14.663], versus original 13.608 [13.452,14.289], scalar pipeline 12.762 [12.230,13.296], and upstream SLP 16.738 [16.141,17.653]. Current object/text sizes are 2,528/1,435 bytes versus original 2,768/1,467 and upstream 2,352/1,063. Compile time excludes plugin compilation; every pipeline also records separate common-backend codegen time. Hardware counters were blocked by hosted `perf_event_paranoid=4`; no policy was changed or hardware limiter inferred.

[Curated native evidence](docs/evidence/native-metrics.json) retains all 120 distributions/840 samples, all 24 old/current range comparisons, source/plugin/library hashes, object/codegen metrics and eight-function assembly review. Source commit is `0a38df175ad53d1fa693f62aeb476c11c525ffcb`; current pass source SHA256 is `9aae7fd0c78f1868d0369192ffdd77c5d3bb7fdcfe3571f425bb407d0b7f4318`. Reproduce with `python3 scripts/benchmark.py --run --before-ref 66b66ba2e86640a8f96bfc5d0299461b10513c29` on the pinned hosted setup; `scripts/summarize-native.py <artifact-directory>` validates retained receipts without measuring new work. Earlier Windows and cross-runner receipts remain preserved as historical/diagnostic evidence.

Compact primary artifacts are in [`docs/evidence`](docs/evidence/). The local verification workflow also retains full run evidence under `.verify/evidence/`, which is ignored by Git. The Linux workflow builds and verifies the pinned LLVM plugin and uploads benchmark artifacts on manual dispatch.

The upstream tutorial suite and conventional plugin loading on Windows were not validated by the local run. The Linux CI job exercises the pass plugin path when run. The exact-search bound and incomplete cost estimate are intentional limits of this project.
