#!/usr/bin/env python3
"""Before/after report from two HardeningKitty audit reports (Windows).

Reuses the layout of generate_report.py so the Linux and Windows reports look the same.
"""
import argparse
import csv
import sys
from datetime import datetime, timezone
from pathlib import Path

from generate_report import CSS, bar_chart, card, esc, natural_key, rule_table

# HardeningKitty scoring: Passed = 4, Low = 2, Medium = 1, High = 0
POINTS = {"Passed": 4, "Low": 2, "Medium": 1, "High": 0}


def load(path):
    with open(path, newline="", encoding="utf-8-sig") as fh:
        rows = list(csv.DictReader(fh))
    if not rows:
        sys.exit(f"ERROR: {path} has no rows")
    columns = list(rows[0].keys())
    result_col = next(
        (c for c in columns
         if any(r[c] == "Passed" for r in rows) and all(r[c] in POINTS for r in rows)),
        None,
    )
    if result_col is None:
        sys.exit(f"ERROR: no Passed/Low/Medium/High column in {path}. Columns: {columns}")
    return {
        (r.get("ID") or r.get("Name")): {"name": r.get("Name", ""), "level": r[result_col]}
        for r in rows
    }


def tally(findings):
    levels = [f["level"] for f in findings.values()]
    passed = levels.count("Passed")
    return {
        "pass": passed,
        "fail": len(levels) - passed,
        "high": levels.count("High"),
        "rate": round(100 * passed / len(levels), 1),
        "score": round(sum(POINTS[x] for x in levels) / (4 * len(levels)) * 5 + 1, 2),
    }


def compare(base, final):
    rows = []
    for key in sorted(set(base) | set(final), key=natural_key):
        before = base.get(key, {}).get("level", "n/a")
        after = final.get(key, {}).get("level", "n/a")
        name = (final.get(key) or base.get(key))["name"]
        rows.append({
            "cis": key,
            "title": name if after in ("Passed", "n/a") else f"{name} ({after})",
            "before": "pass" if before == "Passed" else ("n/a" if before == "n/a" else "fail"),
            "after": "pass" if after == "Passed" else ("n/a" if after == "n/a" else "fail"),
        })
    fixed = [r for r in rows if r["before"] == "fail" and r["after"] == "pass"]
    still = [r for r in rows if r["before"] == "fail" and r["after"] == "fail"]
    regressed = [r for r in rows if r["before"] == "pass" and r["after"] == "fail"]
    return fixed, still, regressed


def main():
    parser = argparse.ArgumentParser(description="Windows before/after hardening report")
    parser.add_argument("--baseline", required=True, type=Path)
    parser.add_argument("--final", required=True, type=Path)
    parser.add_argument("--out", required=True, type=Path)
    parser.add_argument("--title", default="Windows hardening report")
    parser.add_argument("--profile-label", default="CIS")
    args = parser.parse_args()

    base, final = load(args.baseline), load(args.final)
    tb, tf = tally(base), tally(final)
    fixed, still, regressed = compare(base, final)
    generated = datetime.now(timezone.utc).strftime("%Y-%m-%d %H:%M UTC")

    cards = "".join([
        card("HardeningKitty score (1 to 6)", tb["score"], tf["score"]),
        card("CIS pass rate", tb["rate"], tf["rate"], suffix="%", delta_suffix=" pp"),
        card("Checks passed", tb["pass"], tf["pass"]),
        card("Checks failed", tb["fail"], tf["fail"], higher_is_better=False),
        card("High severity findings", tb["high"], tf["high"], higher_is_better=False),
    ])

    page = f"""<!doctype html>
<html lang="en"><head><meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>{esc(args.title)}</title><style>{CSS}</style></head>
<body><main>
<header><h1>{esc(args.title)}</h1>
<p class="meta">Generated {generated} &middot; {esc(args.profile_label)} &middot; HardeningKitty audit</p></header>
<section class="cards">{cards}</section>
<section><h2>Check results</h2>{bar_chart(tb, tf)}
<p class="legend"><span class="swatch bar-before"></span>Before hardening<span class="swatch bar-after"></span>After hardening</p></section>
<section><h2>Fixed by the hardening step ({len(fixed)})</h2>{rule_table(fixed, "No check changed from failed to passed.")}</section>
<section><h2>Regressions ({len(regressed)})</h2>{rule_table(regressed, "None.")}</section>
<section><h2>Still failing ({len(still)})</h2>
<p>Severity in brackets. Documented exceptions are listed in docs/EXCEPTIONS.md in the repository.</p>
{rule_table(still, "None.")}</section>
</main></body></html>
"""
    args.out.parent.mkdir(parents=True, exist_ok=True)
    args.out.write_text(page, encoding="utf-8")
    print(f"HardeningKitty score: {tb['score']} -> {tf['score']}")
    print(f"CIS checks passed:    {tb['pass']} -> {tf['pass']}  (failed {tb['fail']} -> {tf['fail']})")
    print(f"Report written to {args.out}")


if __name__ == "__main__":
    main()
