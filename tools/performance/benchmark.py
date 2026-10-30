#!/usr/bin/env python3
"""Compile current SHA/ZIP sources with -O and measure each run in a fresh process."""
import argparse
import hashlib
import json
from pathlib import Path
import platform
import resource
import statistics
import subprocess
import sys
import tempfile
import zipfile


def measure(binary, mode, archive):
    # This process has no compiler children. Its child usage belongs only to this run.
    result = subprocess.run([binary, mode, archive], check=True, capture_output=True, text=True)
    sample = json.loads(result.stdout)
    peak = resource.getrusage(resource.RUSAGE_CHILDREN).ru_maxrss
    sample["peak_rss_bytes"] = peak if sys.platform == "darwin" else peak * 1024
    print(json.dumps(sample))


DRIVER = r'''
import Foundation

let mode = CommandLine.arguments[1]
let clock = ContinuousClock()
let start = clock.now
var result: [String: Any] = ["workload": mode]
switch mode {
case "sha-legacy", "sha-modern":
    let data = Data(repeating: 97, count: 16_000_000)
    let digest = mode == "sha-legacy" ? SHA256Pure.legacyHash(data) : SHA256Pure.hash(data)
    if mode == "sha-legacy" { result["implementation"] = "legacy" }
    else if #available(iOS 26, macOS 26, tvOS 26, watchOS 26, visionOS 26, *) {
        result["implementation"] = "inline-span"
    } else { result["implementation"] = "legacy-fallback" }
    result["sha256"] = digest.map { String(format: "%02x", $0) }.joined()
    result["input_bytes"] = data.count
case "zip":
    let xml = String(repeating: "<t>สวัสดี &amp; hello</t>", count: 1_000_000)
    let photo = Data(repeating: 42, count: 8_000_000)
    var zip = ZipArchive()
    zip.set("เอกสาร/sheet.xml", xml)
    zip.set("photo.jpg", photo)
    zip.set("empty", Data())
    let data = try zip.write()
    let decoded = try ZipArchive(data)
    precondition(decoded.string("เอกสาร/sheet.xml") == xml)
    precondition(decoded.data("photo.jpg") == photo)
    precondition(decoded.data("empty") == Data())
    result["input_bytes"] = xml.utf8.count + photo.count
    result["archive_bytes"] = data.count
    try data.write(to: URL(fileURLWithPath: CommandLine.arguments[2]))
default:
    fatalError("Unknown workload")
}
let elapsed = start.duration(to: clock.now).components
result["seconds"] = Double(elapsed.seconds) + Double(elapsed.attoseconds) / 1e18
print(String(decoding: try JSONSerialization.data(withJSONObject: result, options: [.sortedKeys]), as: UTF8.self))
'''


def benchmark(samples):
    repo = Path(__file__).resolve().parents[2]
    sources = repo / "TCRoofKit/Sources"
    toolchain = subprocess.check_output(["swiftc", "--version"], text=True).strip()
    if samples < 1:
        raise ValueError("--samples must be at least 1")
    report = {"toolchain": toolchain, "platform": platform.platform(), "optimization": "-O", "samples": {}}
    with tempfile.TemporaryDirectory(prefix="tcroof-performance-") as folder:
        work = Path(folder)
        # Compile the production SHA implementation without the app model entry points.
        sha = (sources / "TCRoofCore/Review/FormHash.swift").read_text()
        (work / "SHA.swift").write_text("import Foundation\n" + sha[sha.index("enum SHA256Pure {"):])
        (work / "Zip.swift").write_text((sources / "ExcelExport/Zip.swift").read_text())
        (work / "main.swift").write_text(DRIVER)
        header = str(sources / "CZlib/include/czlib.h")
        (work / "module.modulemap").write_text(f'module CZlib {{ header {json.dumps(header)} link "z" export * }}\n')
        subprocess.run(["clang", "-O2", "-I", str(sources / "CZlib/include"), "-c",
                        str(sources / "CZlib/czlib.c"), "-o", str(work / "czlib.o")], check=True)
        binary = str(work / "benchmark")
        subprocess.run(["swiftc", "-swift-version", "5", "-O", "-I", str(work), str(work / "SHA.swift"),
                        str(work / "Zip.swift"), str(work / "main.swift"), str(work / "czlib.o"), "-o", binary], check=True)
        expected = hashlib.sha256(b"a" * 16_000_000).hexdigest()
        archive = str(work / "roundtrip.zip")
        for mode in ("sha-legacy", "sha-modern", "zip"):
            runs = []
            for _ in range(samples):
                output = subprocess.check_output([sys.executable, str(Path(__file__).resolve()),
                                                  "--measure", binary, mode, archive], text=True)
                sample = json.loads(output)
                if mode.startswith("sha-") and sample["sha256"] != expected:
                    raise ValueError(f"Incorrect SHA-256 output: {mode}")
                runs.append(sample)
            report["samples"][mode] = {
                "runs": runs,
                "median_seconds": statistics.median(s["seconds"] for s in runs),
                "median_peak_rss_bytes": statistics.median(s["peak_rss_bytes"] for s in runs),
            }
        # Independent ZIP reader checks CRCs and the entry compression methods.
        with zipfile.ZipFile(archive) as zip_file:
            assert zip_file.testzip() is None
            assert zip_file.getinfo("เอกสาร/sheet.xml").compress_type == zipfile.ZIP_DEFLATED
            assert zip_file.getinfo("photo.jpg").compress_type == zipfile.ZIP_STORED
            assert zip_file.read("empty") == b""
        report["correctness"] = "SHA-256 matches hashlib; ZIP CRCs and compression methods verified"
        report["scope"] = "Synthetic Linux/macOS microbenchmarks; not on-device iOS profiling"
    print(json.dumps(report, indent=2))


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--samples", type=int, default=3)
    parser.add_argument("--measure", nargs=3, help=argparse.SUPPRESS)
    args = parser.parse_args()
    if args.measure:
        measure(*args.measure)
    else:
        benchmark(args.samples)
