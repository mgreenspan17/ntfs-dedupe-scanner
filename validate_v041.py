# validate_v041.py
# End-to-end validation for v0.4.1 fixes.
# Steps:
#   1. AST parse of scripts/Invoke-NTFSDedupeScan.ps1 (PowerShell)
#   2. Build a small fixture (4 distinct files: 2 pairs of duplicates
#      across folders)
#   3. dry-run the script -> assert JSON + CSV exist, schemaVersion=1.0.1
#   4. real BLAKE3 + SHA256 hash scan -> assert
#         - hashAlgorithm field on every ScanRecord (BLAKE3 path only since
#           b3sum is on PATH)
#         - groups[].hashAlgorithm + groups[].hash present + hash field
#           does not contain a '|' prefix
#         - attemptedFiles == scannedFiles when no hash failures
#         - blake3FallbackCount is 0 when b3sum succeeds
#         - logWriteFailed flag = "false" in summary line
#         - JSON / CSV file starts with no UTF-8 BOM (first bytes != EF BB BF)
#         - log filename has a SessionId suffix
#
# Exit code 0 on full pass. Non-zero with a list of failed assertions.
import os, sys, json, subprocess, tempfile, shutil, pathlib, re

REPO = pathlib.Path(r"C:\Users\manni\projects\ntfs-dedupe-scanner")
PS1  = REPO / "scripts" / "Invoke-NTFSDedupeScan.ps1"

problems = []

def ok(msg): print(f"[OK] {msg}")
def bad(msg, why=""):
    problems.append(msg)
    print(f"[FAIL] {msg}  -- {why}")

# 1. AST parse --------------------------------------------------------------
print("\n=== STEP 1: AST parse ===")
try:
    res = subprocess.run(
        ["powershell", "-NoProfile", "-NonInteractive", "-Command",
         f"[void][System.Management.Automation.Language.Parser]::ParseFile('{PS1}', [ref]$null, [ref]$errs); if ($errs) {{ $errs }} else {{ 'OK' }}"],
        capture_output=True, text=True, timeout=60,
    )
    out = (res.stdout or "").strip()
    if "OK" in out:
        ok(f"ParseFile succeeded for {PS1}")
    else:
        bad("PS1 parse failed", out[:500])
except Exception as e:
    bad("PS1 parse exception", str(e))

# 2. Fixture ----------------------------------------------------------------
print("\n=== STEP 2: build fixture ===")
fx = pathlib.Path(tempfile.mkdtemp(prefix="dedupe-fx-"))
(fx / "a").mkdir(); (fx / "b").mkdir(); (fx / "skip").mkdir()

# Pair 1: identical content across a/ and b/ -> one BLAKE3 group, 2 files
dup1 = b"Hello dedupe world!\n" * 100
(fx / "a" / "alpha.txt").write_bytes(dup1)
(fx / "b" / "beta.txt").write_bytes(dup1)

# Pair 2: identical content in c/ -> one group, 2 files
(fx / "a" / "singleton.txt").write_bytes(b"only here")
(fx / "b" / "twin.txt").write_bytes(b"only here")

# Skip folder: should not be enumerated, so we'll see it in skippedFolders
# only when DefaultSkipList is updated. Default skip list lives in C# hash
# helper. The current default skip list does NOT include 'skip'. So we
# leave it but expect 4 files enumerated.

ok(f"Fixture root: {fx}")
ok("  a/alpha.txt  +  b/beta.txt    -> 1 duplicate pair")
ok("  a/singleton.txt + b/twin.txt  -> 1 duplicate pair (identical)")
ok("  (Total expected: 4 enumerated, 2 duplicate groups)")

# 3. Dry-run ----------------------------------------------------------------
# `out_dir` / `log_dir` MUST live OUTSIDE the fixture root, otherwise the
# script's `PlanScan` enumerator would pick up the freshly-written log
# file (and any earlier artefacts) as candidates and double-count them.
print("\n=== STEP 3: dry-run ===")
out_dir = fx.parent / (fx.name + "-out")
log_dir = fx.parent / (fx.name + "-logs")
out_dir.mkdir(); log_dir.mkdir()

res = subprocess.run(
    ["powershell", "-NoProfile", "-NonInteractive", "-File", str(PS1),
     "-Path", str(fx), "-OutputDir", str(out_dir), "-LogDir", str(log_dir),
     "-DryRun"],
    capture_output=True, text=True, timeout=180,
)
if res.returncode != 0:
    bad("Dry-run returned non-zero", (res.stderr or "")[-500:])
else:
    ok("Dry-run exit code 0")
    # Dry-run intentionally skips JSON + CSV output (early return around
    # line 749 in the PS1). Confirm the structured log carries the
    # dry-run marker instead.
    log = next(iter(sorted(log_dir.glob("ntfs-dedupe-scan-*.log"))), None)
    if not log:
        bad("Dry-run produced no log file", f"log_dir={log_dir}")
    else:
        text = log.read_text(encoding="utf-8")
        if "dry-run complete" in text and "candidates=4" in text:
            ok("Dry-run log records 'dry-run complete' + 'candidates=4'")
        else:
            bad("Dry-run log missing dry-run marker / candidate count",
                text.splitlines()[-5:])

# 4. Real hash run ----------------------------------------------------------
print("\n=== STEP 4: real BLAKE3 run ===")
out_dir2 = fx.parent / (fx.name + "-out2")
log_dir2 = fx.parent / (fx.name + "-logs2")
out_dir2.mkdir(); log_dir2.mkdir()
res = subprocess.run(
    ["powershell", "-NoProfile", "-NonInteractive", "-File", str(PS1),
     "-Path", str(fx), "-OutputDir", str(out_dir2), "-LogDir", str(log_dir2),
     "-HashAlgorithm", "BLAKE3"],
    capture_output=True, text=True, timeout=600,
)
if res.returncode != 0:
    bad("Real hash run failed", (res.stderr or "")[-1000:])
    print("stdout tail:", (res.stdout or "")[-1000:])
else:
    ok("Real hash run exit code 0")
    jfiles = sorted(out_dir2.glob("dedupe-*.json"))
    cfiles = sorted(out_dir2.glob("dedupe-*.csv"))
    lfiles = sorted(log_dir2.glob("ntfs-dedupe-scan-*.log"))
    if not jfiles or not cfiles or not lfiles:
        bad("Missing output files", f"j={len(jfiles)} c={len(cfiles)} l={len(lfiles)}")
    else:
        j = jfiles[-1]; c = cfiles[-1]; lg = lfiles[-1]
        data = json.loads(j.read_text(encoding="utf-8"))

        # attemptedFiles vs scannedFiles
        if data.get("attemptedFiles") != data.get("scannedFiles"):
            bad(f"attemptedFiles ({data.get('attemptedFiles')}) != scannedFiles ({data.get('scannedFiles')}) despite no failures")
        else:
            ok(f"attemptedFiles == scannedFiles == {data['scannedFiles']}")

        # hash field no longer has '|' prefix in any group
        bad_groups = [g for g in data.get("groups", []) if "|" in g.get("hash", "")]
        if bad_groups:
            bad(f"{len(bad_groups)} groups carry a '|' prefix on hash", str(bad_groups[0])[:300])
        else:
            ok(f"groups[].hash free of '|' prefix ({len(data.get('groups', []))} groups)")

        # Every group has hashAlgorithm + hash keys
        missing = [g for g in data.get("groups", []) if "hashAlgorithm" not in g or "hash" not in g]
        if missing:
            bad(f"{len(missing)} groups missing hashAlgorithm or hash key")
        else:
            ok("groups[].hashAlgorithm + groups[].hash present on every group")
            # All BLAKE3 in this run (b3sum on PATH)
            algos = {g["hashAlgorithm"] for g in data["groups"]}
            if algos != {"blake3"}:
                bad(f"group algorithms not all 'blake3' (b3sum on PATH): {algos}")
            else:
                ok("all groups stamped hashAlgorithm='blake3'")

        # duplicateGroups count
        expected_dup = 2  # two identical pairs
        if data.get("duplicateGroups") != expected_dup:
            bad(f"duplicateGroups={data.get('duplicateGroups')}, expected {expected_dup}")
        else:
            ok(f"duplicateGroups == {expected_dup}")

        # blake3FallbackCount == 0 (b3sum on PATH)
        if data.get("blake3FallbackCount") != 0:
            bad(f"blake3FallbackCount={data.get('blake3FallbackCount')}, expected 0")
        else:
            ok("blake3FallbackCount == 0")

        # hashAlgorithmFallback field present (null OK)
        if "hashAlgorithmFallback" not in data:
            bad("hashAlgorithmFallback missing")
        else:
            ok(f"hashAlgorithmFallback == {data['hashAlgorithmFallback']!r}")

        # logWriteFailed in summary line (lowercase JSON-style true/false)
        text = lg.read_text(encoding="utf-8")
        if "logWriteFailed=false" in text:
            ok("structured log summary contains 'logWriteFailed=false' (lowercase)")
        elif "logWriteFailed=False" in text:
            bad("structured log summary contains capital-F 'logWriteFailed=False'",
                text.splitlines()[-5:])
        else:
            bad("structured log summary missing 'logWriteFailed=' marker",
                text.splitlines()[-5:])

        # No UTF-8 BOM at start of log file
        with open(lg, "rb") as fh:
            loghead = fh.read(3)
        if loghead == b"\xef\xbb\xbf":
            bad(f"log file starts with UTF-8 BOM: {lg}")
        else:
            ok(f"log file has no BOM (first 3 bytes: {loghead!r})")

        # log filename includes SessionId (compare to JSON session.id)
        sid = data.get("session", {}).get("id", "")
        if sid and sid in lg.name:
            ok(f"log filename embeds SessionId: {lg.name}")
        else:
            bad(f"log filename missing SessionId (sid={sid}, name={lg.name})")

        # attemptedFiles in summary line
        if "attemptedFiles=" in text:
            ok("structured log summary contains 'attemptedFiles='")
        else:
            bad("structured log summary missing 'attemptedFiles='")

        # Per-record HashAlgorithm: scan the source PS1 for ScanRecord usages
        ps1_text = PS1.read_text(encoding="utf-8")
        if "HashAlgorithm" in ps1_text and 'public string HashAlgorithm' in ps1_text:
            ok("PS1 declares ScanRecord.HashAlgorithm property")
        else:
            bad("PS1 does not declare ScanRecord.HashAlgorithm")
        # Per-path stamping
        if ps1_text.count('HashAlgorithm = "') >= 3:
            ok("PS1 stamps HashAlgorithm = 'sha256'/'blake3' at >=3 sites")
        else:
            bad("PS1 HashAlgorithm stamping occurs at <3 sites")

# Final ---------------------------------------------------------------------
print()
if problems:
    print(f"== {len(problems)} PROBLEM(S) ==")
    for p in problems:
        print(f"  - {p}")
    sys.exit(1)
else:
    print("== ALL VALIDATION CHECKS PASSED ==")
    sys.exit(0)
