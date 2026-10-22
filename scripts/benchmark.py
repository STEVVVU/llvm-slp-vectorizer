"""Frozen native basic-block suite. Run on the isolated pinned Linux LLVM runner."""

import argparse
import csv
import hashlib
import json
import os
from pathlib import Path
import platform
import re
import shutil
import statistics
import subprocess
import time

ROOT = Path(__file__).resolve().parents[1]
KERNELS = (("add2", 2, 1), ("add8", 8, 1), ("sub8", 8, 1), ("mul8", 8, 1), ("mixed8", 8, 1), ("affine8", 8, 1), ("strided4", 4, 2), ("add16", 16, 1))
SIDES = {"scalar": "verify", "bounded": "bounded-slp", "greedy": "bounded-slp-greedy", "upstream": "slp-vectorizer"}


def workload():
    functions = []
    for name, width, stride in KERNELS:
        body = [f"define void @{name}(ptr noalias %out, ptr noalias %a, ptr noalias %b, i64 %n) {{", "entry:", "  br label %loop", "loop:"]
        for label, initial in (("pa", "a"), ("pb", "b"), ("po", "out")):
            body.append(f"  %{label} = phi ptr [ %{initial}, %entry ], [ %next_{label}, %loop ]")
        body.append("  %i = phi i64 [ 0, %entry ], [ %next, %loop ]")
        for lane in range(width):
            for label in ("pa", "pb", "po"):
                body.append(f"  %{label}{lane} = getelementptr i32, ptr %{label}, i64 {lane * stride}")
            body += [f"  %a{lane} = load i32, ptr %pa{lane}, align 4", f"  %b{lane} = load i32, ptr %pb{lane}, align 4"]
        for lane in range(width):
            operation = ("add", "sub", "mul")[lane % 3] if name == "mixed8" else "sub" if name == "sub8" else "mul" if name in ("mul8", "affine8") else "add"
            body.append(f"  %x{lane} = {operation} i32 %a{lane}, %b{lane}")
        if name == "affine8":
            for lane in range(width):
                body.append(f"  %y{lane} = add i32 %x{lane}, 17")
        for lane in range(width):
            body.append(f"  store i32 %{'y' if name == 'affine8' else 'x'}{lane}, ptr %po{lane}, align 4")
        for label in ("pa", "pb", "po"):
            body.append(f"  %next_{label} = getelementptr i32, ptr %{label}, i64 {width * stride}")
        body += [f"  %next = add i64 %i, {width}", "  %more = icmp ult i64 %next, %n", "  br i1 %more, label %loop, label %exit", "exit:", "  ret void", "}"]
        functions.append("\n".join(body))
    return 'target triple = "x86_64-pc-linux-gnu"\n\n' + "\n\n".join(functions) + "\n"


def run(command, **kwargs):
    kwargs.setdefault("stderr", subprocess.PIPE)
    return subprocess.run(list(map(str, command)), check=True, timeout=kwargs.pop("timeout", 120), **kwargs)


def summary(values):
    return {"samples": values, "median": statistics.median(values), "range": [min(values), max(values)], "p95_nearest_rank": sorted(values)[-1]}


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--run", action="store_true")
    parser.add_argument("--llvm", type=Path, default=Path("/usr/lib/llvm-23/bin"))
    parser.add_argument("--plugin", type=Path, default=ROOT / "build/ci/lib/libBoundedSLP.so")
    parser.add_argument("--output", type=Path, default=ROOT / ".verify/benchmark")
    parser.add_argument("--before-ref", choices=["66b66ba2e86640a8f96bfc5d0299461b10513c29"])
    args = parser.parse_args()
    if shutil.disk_usage(ROOT).free < 10 * 1024**3:
        raise RuntimeError("10 GiB free disk required")
    args.output.mkdir(parents=True, exist_ok=True)
    source = args.output / "suite.ll"
    source.write_text(workload(), encoding="utf-8")
    assert len(KERNELS) == 8 and len(set(name for name, _, _ in KERNELS)) == 8
    assert all(16384 % width == 0 for _, width, _ in KERNELS)
    if not args.run:
        print(f"Prepared frozen IR at {source}; no builds or timers executed")
        return
    if platform.system() != "Linux":
        raise RuntimeError("native benchmark requires the isolated Linux hosted runner")
    opt, llc = args.llvm / "opt", args.llvm / "llc"
    version = subprocess.check_output([args.llvm / "llvm-config", "--version"], text=True).strip()
    if version != "23.1.4":
        raise RuntimeError(f"Expected LLVM 23.1.4, found {version}")
    sides = dict(SIDES)
    plugins = {"bounded": args.plugin, "greedy": args.plugin}
    before_source = None
    if args.before_ref:
        before_source = ROOT / "build/benchmark-before-source"
        before_source.mkdir(parents=True, exist_ok=False)
        archive = ROOT / "build/benchmark-before.tar"
        with archive.open("wb") as stream:
            run(["git", "archive", args.before_ref], cwd=ROOT, stdout=stream)
        run(["tar", "-xf", archive, "-C", before_source])
        before_build = ROOT / "build/benchmark-before"
        run(["cmake", "-S", before_source, "-B", before_build, "-G", "Ninja", "-DCMAKE_BUILD_TYPE=Release", "-DLT_LLVM_INSTALL_DIR=/usr/lib/llvm-23", "-DLLVM_DIR=/usr/lib/llvm-23/lib/cmake/llvm"])
        run(["cmake", "--build", before_build, "--target", "BoundedSLP"], timeout=300)
        sides["before"] = "bounded-slp"
        plugins["before"] = before_build / "lib/libBoundedSLP.so"
    record = {"source_sha": subprocess.check_output(["git", "rev-parse", "HEAD"], cwd=ROOT, text=True).strip(), "workload_sha256": hashlib.sha256(source.read_bytes()).hexdigest(), "llvm": version, "platform": platform.platform(), "cpu": subprocess.check_output(["lscpu"], text=True), "load": os.getloadavg(), "cpus": os.cpu_count(), "workloads": KERNELS, "sizes": [16384, 1048576, 8388608], "scope": "fixed unrolled integer array kernels, common llc O3 x86-64 SSE2 backend; scalar disables IR vectorizers, upstream uses LLVM SLP; not a general application/compiler adoption result", "compile": {}}
    run(["g++", "-O3", "-std=c++17", ROOT / "test/benchmark_native.cpp", "-ldl", "-o", args.output / "native-suite"])
    libraries = []
    record["before_ref"] = args.before_ref
    record["source_and_plugin_sha256"] = {str(path): hashlib.sha256(path.read_bytes()).hexdigest() for path in [ROOT / "lib/BoundedSLP.cpp", args.plugin] + ([before_source / "lib/BoundedSLP.cpp", plugins["before"]] if before_source else [])}
    for name in sides:
        record["compile"][name] = {"opt_ms": [], "codegen_ms": []}
    for repeat in range(7):
        names = list(sides)
        names = names[repeat % len(names):] + names[:repeat % len(names)]
        for name in names:
            target = args.output / f"{name}.ll"
            command = [opt, "-S", "-verify-each", f"-passes={sides[name]}", source, "-o", target]
            if name in plugins:
                command += ["-load-pass-plugin", plugins[name]]
            start = time.perf_counter()
            run(command, stdout=subprocess.DEVNULL)
            record["compile"][name]["opt_ms"].append((time.perf_counter() - start) * 1000)
            start = time.perf_counter()
            run([llc, "-O3", "-mcpu=x86-64", "-mattr=+sse2", "-relocation-model=pic", "-filetype=obj", target, "-o", args.output / f"{name}.o"])
            record["compile"][name]["codegen_ms"].append((time.perf_counter() - start) * 1000)
    for name in sides:
        library = args.output / f"{name}.so"
        run(["g++", "-shared", args.output / f"{name}.o", "-o", library])
        libraries.append(library.resolve())
        run([llc, "-O3", "-mcpu=x86-64", "-mattr=+sse2", "-filetype=asm", args.output / f"{name}.ll", "-o", args.output / f"{name}.s"])
        ir = (args.output / f"{name}.ll").read_text()
        record["compile"][name]["vector_arithmetic_instructions"] = len(re.findall(r"\b(?:add|sub|mul) <\d+ x i32>", ir))
        if name == "scalar" and re.search(r"\b(?:v?padd\w*|v?psub\w*|v?pmul\w*)\b", (args.output / f"{name}.s").read_text()):
            raise AssertionError("scalar baseline contains packed arithmetic")
        record["compile"][name]["object_bytes"] = (args.output / f"{name}.o").stat().st_size
        record["compile"][name]["native_library_sha256"] = hashlib.sha256(library.read_bytes()).hexdigest()
        record["compile"][name]["text_size"] = subprocess.check_output([args.llvm / "llvm-size", args.output / f"{name}.o"], text=True)
        for timing in ("opt_ms", "codegen_ms"):
            record["compile"][name][timing] = summary(record["compile"][name][timing])
    run([args.output / "native-suite", "--smoke", *libraries])
    with (args.output / "samples.csv").open("w") as stream:
        run([args.output / "native-suite", "--measure", *libraries], stdout=stream, timeout=300)
    grouped = {}
    with (args.output / "samples.csv").open() as stream:
        for row in csv.DictReader(stream):
            key = f"{row['kernel']}/{row['elements']}/{row['side']}"
            grouped.setdefault(key, []).append(float(row["ns_per_element"]))
    if len(grouped) != len(KERNELS) * 3 * len(sides) or any(len(values) != 7 for values in grouped.values()):
        raise AssertionError("missing benchmark samples")
    record["runtime_ns_per_element"] = {key: summary(values) for key, values in grouped.items()}
    record["profile"] = {}
    for library in libraries:
        path = args.output / f"perf-{library.stem}.csv"
        try:
            result = subprocess.run(["perf", "stat", "-x,", "-e", "cycles,instructions,cache-misses,branches,branch-misses", "-o", str(path), str(args.output / "native-suite"), "--profile", str(library)], timeout=120, capture_output=True, text=True)
            record["profile"][library.stem] = {"exit": result.returncode, "stderr": result.stderr, "counter_file": str(path), "scope": "separate diagnostic run, not reported benchmark timings"}
        except FileNotFoundError:
            record["profile"][library.stem] = {"blocked": "perf is unavailable; no hardware limiter claim"}
    record["verdict"] = "Observations only until native assembly and separate counter evidence identify the limiter; overlapping ranges establish no win."
    (args.output / "result.json").write_text(json.dumps(record, indent=2) + "\n")
    print(args.output / "result.json")


if __name__ == "__main__":
    main()
