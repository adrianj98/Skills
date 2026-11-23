#!/usr/bin/env python3
"""Summarize a Stryker mutation report (mutation-testing-report-schema JSON).

Usage: summarize.py <mutation.json> [--json]

Prints, per source file: the score, every surviving or uncovered mutant with its
line and replacement, and every test that covered mutants in this run but killed
none of them (a zero-kill test). Needs the report from a run with
`coverageAnalysis: perTest`; without per-test data it says so and lists survivors
only.
"""
import json
import sys
from collections import defaultdict

LIVE = {"Survived", "NoCoverage"}
DEAD = {"Killed", "Timeout"}


def main():
    args = [a for a in sys.argv[1:] if not a.startswith("--")]
    as_json = "--json" in sys.argv
    if len(args) != 1:
        print(__doc__.strip(), file=sys.stderr)
        sys.exit(2)
    with open(args[0]) as f:
        report = json.load(f)

    tests = {}  # id -> {name, file, line}
    for path, tf in (report.get("testFiles") or {}).items():
        for t in tf.get("tests", []):
            loc = (t.get("location") or {}).get("start") or {}
            tests[t["id"]] = {"name": t.get("name", t["id"]), "file": path, "line": loc.get("line")}

    kills = defaultdict(int)
    covers = defaultdict(int)
    per_test = False
    files_out = []
    for path, fr in sorted(report.get("files", {}).items()):
        killed = live = 0
        survivors = []
        for m in fr.get("mutants", []):
            status = m.get("status")
            for t in m.get("killedBy") or []:
                kills[t] += 1
            if m.get("coveredBy") is not None:
                per_test = True
                for t in m["coveredBy"]:
                    covers[t] += 1
            if status in DEAD:
                killed += 1
            elif status in LIVE:
                live += 1
                start = (m.get("location") or {}).get("start") or {}
                survivors.append({
                    "id": m.get("id"),
                    "status": status,
                    "line": start.get("line"),
                    "column": start.get("column"),
                    "mutator": m.get("mutatorName"),
                    "replacement": m.get("replacement"),
                    "coveredBy": [tests.get(t, {"name": t})["name"] for t in m.get("coveredBy") or []],
                })
        total = killed + live
        files_out.append({
            "file": path,
            "score": round(100 * killed / total, 1) if total else None,
            "killed": killed,
            "live": live,
            "survivors": sorted(survivors, key=lambda s: (s["line"] or 0, s["column"] or 0)),
        })

    zero_kill = []
    if per_test:
        for tid, n in covers.items():
            if n and not kills.get(tid):
                t = tests.get(tid, {"name": tid, "file": None, "line": None})
                zero_kill.append({**t, "id": tid, "covered": n})
        zero_kill.sort(key=lambda t: (t["file"] or "", t["line"] or 0))

    if as_json:
        json.dump({"perTest": per_test, "files": files_out, "zeroKillTests": zero_kill}, sys.stdout, indent=2)
        print()
        return

    for f in files_out:
        score = "n/a" if f["score"] is None else f"{f['score']}%"
        print(f"== {f['file']}  score {score}  killed {f['killed']}  live {f['live']}")
        for s in f["survivors"]:
            print(f"  {s['status']:<10} L{s['line']}:{s['column']}  {s['mutator']}  -> {s['replacement']!r}  [id {s['id']}]")
            if s["coveredBy"]:
                print(f"             covered by: {'; '.join(s['coveredBy'][:5])}"
                      + (f" (+{len(s['coveredBy']) - 5})" if len(s["coveredBy"]) > 5 else ""))
    print()
    if not per_test:
        print("No per-test coverage in this report (run with coverageAnalysis perTest); zero-kill tests unknown.")
    elif zero_kill:
        print(f"== zero-kill tests ({len(zero_kill)}): covered mutants in this run, killed none")
        for t in zero_kill:
            print(f"  {t['file']}:{t['line']}  {t['name']}  (covered {t['covered']})")
    else:
        print("== zero-kill tests: none")


if __name__ == "__main__":
    main()
