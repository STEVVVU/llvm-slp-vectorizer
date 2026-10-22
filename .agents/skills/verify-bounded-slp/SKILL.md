---
name: verify-bounded-slp
description: Build, run, and capture evidence for the LLVM bounded basic-block SLP pass on Windows with the pinned LLVM 23.1.4 SDK.
---

# Verify bounded SLP

Use this skill to build the standalone pass driver, verify its IR output, emit native x86 code, and run the mapped basic-block packing feature. The supported surface is the `slp-opt.exe` compiler CLI. The verification script uses the real LLVM 23.1.4 headers, static libraries, verifier, and native backend.

## Launch

Run `powershell -NoProfile -ExecutionPolicy Bypass -File scripts/verify.ps1 -Phase Launch` from the repository root. Launch builds `build/verify/slp-opt.exe` with the installed Visual Studio 2022 x64 developer tools. It is ready when the script prints `LAUNCH_OK` with the compiler path. The build is short lived and starts no server.

The default SDK is `%USERPROFILE%\.codex\tools\coursework-llvm\clang+llvm-23.1.4-x86_64-pc-windows-msvc`; the default dependency prefix is `%USERPROFILE%\.codex\tools\coursework-llvm\deps`. Override them with `LLVM_SDK_ROOT` and `LLVM_DEPS_ROOT` when necessary. Launch fails if LLVM is not exactly 23.1.4 or the real `zs.lib` and `zstd_static.lib` archives are absent.

## Doctor

Run `powershell -NoProfile -ExecutionPolicy Bypass -File scripts/verify.ps1 -Phase Doctor`. It checks the pinned SDK tools and version, both compression archives, the driver executable, and that the system drive retains at least 10 GB free. Doctor is read only and prints `DOCTOR_OK` only when these inputs exist.

## Drive

Run `powershell -NoProfile -ExecutionPolicy Bypass -File scripts/verify.ps1 -Phase Drive`. The driver processes `test/BoundedSLP.ll` in exact and greedy modes. The script checks the expected vector-operation counts, verifies both outputs with the SDK's `opt -passes=verify`, and runs a generated 16-candidate block to exercise the exact-search limit. It emits optimized native assembly with `llc` and checks for packed integer addition. The native harness differentially checks arithmetic extremes, generated inputs, and aliasing pointer cases. Its scalar baseline object is disassembled to confirm that it uses scalar addition and contains no packed/vector add. Repeated interleaved timing samples are recorded as measurements, not used as a performance promise.

## Evidence

Run `powershell -NoProfile -ExecutionPolicy Bypass -File scripts/verify.ps1 -Phase Evidence` after Drive. It copies both transformed modules, the native assembly, the driver output, the 16-candidate input, and a timestamped command/result transcript to `.verify/evidence/<run-id>/`. The transcript records command outcomes and observed vector-operation counts. Evidence captures the actual CLI action and resulting IR/native code.

## Cleanup

Run `powershell -NoProfile -ExecutionPolicy Bypass -File scripts/verify.ps1 -Phase Cleanup`. Cleanup removes only `build/verify/`, after checking that the resolved path is inside this checkout. It does not kill processes by name and leaves `.verify/evidence/` intact. Verify that the evidence run directory still exists after cleanup.

## Helpers

`scripts/verify.ps1 -Phase All` runs Launch, Doctor, Drive, Evidence, and Cleanup in order. It leaves evidence in `.verify/evidence/`; it does not delete or overwrite prior evidence.
