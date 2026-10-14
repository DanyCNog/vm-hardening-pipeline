#!/usr/bin/env python3
"""Build a before/after hardening report from Lynis and OpenSCAP results.

Each results directory must contain lynis-report.dat and oscap-results.xml,
as produced by scanning/linux/scan.sh.
"""

import argparse
import html
import re
import sys
import xml.etree.ElementTree as ET
from datetime import datetime, timezone
from pathlib import Path

XCCDF = "http://checklists.nist.gov/xccdf/1.2"
NS = {"x": XCCDF}

CSS = """
:root{--ink:#1d2433;--muted:#5b6475;--line:#e3e6ec;--bg:#f6f7f9;--card:#fff;
--good:#1e7a46;--bad:#b3261e;--before:#9aa3b2;--after:#1f4e8c}
*{box-sizing:border-box}
body{margin:0;background:var(--bg);color:var(--ink);
font:15px/1.5 system-ui,-apple-system,"Segoe UI",Roboto,sans-serif}
main{max-width:1100px;margin:0 auto;padding:32px 20px 60px}
h1{margin:0 0 4px;font-size:26px}
h2{font-size:18px;margin:36px 0 12px;border-bottom:1px solid var(--line);padding-bottom:6px}
.meta{color:var(--muted);margin:0}
.cards{display:grid;grid-template-columns:repeat(auto-fit,minmax(200px,1fr));gap:14px;margin-top:24px}
.card{background:var(--card);border:1px solid var(--line);border-radius:8px;padding:16px}
.label{color:var(--muted);font-size:12px;text-transform:uppercase;letter-spacing:.04em}
.values{font-size:24px;font-weight:600;margin:6px 0}
.before{color:var(--before)}
.arrow{color:var(--muted);margin:0 8px;font-weight:400}
.delta{font-size:13px;font-weight:600;padding:2px 8px;border-radius:10px}
.delta.good{background:#e3f3ea;color:var(--good)}
.delta.bad{background:#fbe5e3;color:var(--bad)}
.delta.neutral{background:#eceef2;color:var(--muted)}
svg{width:100%;max-width:560px;display:block}
.axis{stroke:var(--line);stroke-width:1}
.bar-before{fill:var(--before)}
.bar-after{fill:var(--after)}
.value{font-size:12px;text-anchor:middle;fill:var(--ink)}
.group{font-size:13px;text-anchor:middle;fill:var(--muted)}
.legend{color:var(--muted);font-size:13px}
.swatch{display:inline-block;width:12px;height:12px;border-radius:2px;margin:0 6px 0 14px;vertical-align:-1px}
.swatch.bar-before{background:var(--before)}
.swatch.bar-after{background:var(--after)}
table{width:100%;border-collapse:collapse;background:var(--card);border:1px solid var(--line);font-size:14px}
th,td{padding:8px 10px;border-bottom:1px solid var(--line);text-align:left;vertical-align:top}
th{background:#eef1f5;font-weight:600}
td.cis{white-space:nowrap;font-variant-numeric:tabular-nums;color:var(--muted)}
.pill{font-size:12px;padding:1px 8px;border-radius:10px;background:#eceef2}
.pill.pass{background:#e3f3ea;color:var(--good)}
.pill.fail{background:#fbe5e3;color:var(--bad)}
.empty{color:var(--muted)}
"""


def natural_key(text):
    return [int(part) if part.isdigit() else part for part in re.split(r"(\d+)", text or "~")]


def parse_lynis(path):
    data = {"index": None, "warnings": 0, "suggestions": 0}
    if not path.is_file():
        return data
    for line in path.read_text(errors="replace").splitlines():
        if line.startswith("hardening_index="):
            data["index"] = int(line.split("=", 1)[1])
        elif line.startswith("warning[]="):
            data["warnings"] += 1
        elif line.startswith("suggestion[]="):
            data["suggestions"] += 1
    return data


def parse_oscap(path):
    root = ET.parse(path).getroot()
    rules = {}
    for rule in root.iter(f"{{{XCCDF}}}Rule"):
        title_el = rule.find("x:title", NS)
        title = " ".join("".join(title_el.itertext()).split()) if title_el is not None else rule.get("id")
        cis = sorted(
            {ref.text.strip() for ref in rule.findall("x:reference", NS)
             if ref.text and "cisecurity" in (ref.get("href") or "")},
            key=natural_key,
        )
        rules[rule.get("id")] = {"title": title, "cis": ", ".join(cis)}

    test_results = list(root.iter(f"{{{XCCDF}}}TestResult"))
    if not test_results:
        sys.exit(f"ERROR: no TestResult in {path}")
    test_result = test_results[-1]

    results = {}
    for rule_result in test_result.findall("x:rule-result", NS):
        result_el = rule_result.find("x:result", NS)
        value = result_el.text.strip() if result_el is not None and result_el.text else "unknown"
        if value != "notselected":
            results[rule_result.get("idref")] = value

    score_el = test_result.find("x:score", NS)
    score = round(float(score_el.text), 1) if score_el is not None and score_el.text else None
    return {"rules": rules, "results": results, "score": score}


def tally(results):
    passed = sum(1 for v in results.values() if v == "pass")
    failed = sum(1 for v in results.values() if v == "fail")
    rate = round(100 * passed / (passed + failed), 1) if passed + failed else None
    return {"pass": passed, "fail": failed, "rate": rate}


def compare(base, final):
    rules = {**base["rules"], **final["rules"]}
    rows = []
    for rule_id in set(base["results"]) | set(final["results"]):
        info = rules.get(rule_id, {"title": rule_id, "cis": ""})
        rows.append({
            "title": info["title"],
            "cis": info["cis"],
            "before": base["results"].get(rule_id, "n/a"),
            "after": final["results"].get(rule_id, "n/a"),
        })
    rows.sort(key=lambda r: (natural_key(r["cis"]), r["title"]))
    fixed = [r for r in rows if r["before"] == "fail" and r["after"] == "pass"]
    still = [r for r in rows if r["before"] == "fail" and r["after"] == "fail"]
    regressed = [r for r in rows if r["before"] == "pass" and r["after"] == "fail"]
    return fixed, still, regressed


def esc(value):
    return html.escape(str(value))


def show(value, suffix=""):
    return "n/a" if value is None else f"{value}{suffix}"


def delta(before, after, higher_is_better=True, suffix=""):
    if before is None or after is None:
        return '<span class="delta neutral">n/a</span>'
    diff = round(after - before, 1)
    if diff == 0:
        cls = "neutral"
    elif (diff > 0) == higher_is_better:
        cls = "good"
    else:
        cls = "bad"
    sign = "+" if diff > 0 else ""
    return f'<span class="delta {cls}">{sign}{diff:g}{suffix}</span>'


def card(label, before, after, higher_is_better=True, suffix="", delta_suffix=""):
    return (
        '<div class="card">'
        f'<div class="label">{esc(label)}</div>'
        f'<div class="values"><span class="before">{esc(show(before, suffix))}</span>'
        '<span class="arrow">&rarr;</span>'
        f'<span>{esc(show(after, suffix))}</span></div>'
        f'{delta(before, after, higher_is_better, delta_suffix)}'
        '</div>'
    )


def bar_chart(base, final):
    groups = [("Passed", base["pass"], final["pass"]), ("Failed", base["fail"], final["fail"])]
    top = max([v for _, b, f in groups for v in (b, f)] + [1])
    width, height, pad, bar_w = 560, 240, 40, 60
    plot_h = height - 2 * pad
    parts = [f'<svg viewBox="0 0 {width} {height}" role="img" aria-label="OpenSCAP rule results">',
             f'<line x1="{pad}" y1="{height - pad}" x2="{width - pad}" y2="{height - pad}" class="axis"/>']
    for i, (label, before, after) in enumerate(groups):
        x0 = pad + 40 + i * 240
        for j, (value, cls) in enumerate(((before, "bar-before"), (after, "bar-after"))):
            h = plot_h * value / top
            x = x0 + j * (bar_w + 10)
            y = height - pad - h
            parts.append(f'<rect x="{x}" y="{y:.1f}" width="{bar_w}" height="{h:.1f}" class="{cls}"/>')
            parts.append(f'<text x="{x + bar_w / 2}" y="{y - 6:.1f}" class="value">{value}</text>')
        parts.append(f'<text x="{x0 + bar_w + 5}" y="{height - pad + 22}" class="group">{label}</text>')
    parts.append("</svg>")
    return "".join(parts)


def rule_table(rows, empty_text):
    if not rows:
        return f'<p class="empty">{esc(empty_text)}</p>'
    body = "".join(
        f'<tr><td class="cis">{esc(r["cis"] or "-")}</td><td>{esc(r["title"])}</td>'
        f'<td><span class="pill {esc(r["before"])}">{esc(r["before"])}</span></td>'
        f'<td><span class="pill {esc(r["after"])}">{esc(r["after"])}</span></td></tr>'
        for r in rows
    )
    return ('<table><thead><tr><th>CIS</th><th>Rule</th><th>Before</th><th>After</th></tr></thead>'
            f"<tbody>{body}</tbody></table>")


def main():
    parser = argparse.ArgumentParser(description="Before/after hardening report")
    parser.add_argument("--baseline", required=True, type=Path)
    parser.add_argument("--final", required=True, type=Path)
    parser.add_argument("--out", required=True, type=Path)
    parser.add_argument("--title", default="Hardening report")
    parser.add_argument("--profile-label", default="CIS Level 1 Server")
    args = parser.parse_args()

    lynis_b = parse_lynis(args.baseline / "lynis-report.dat")
    lynis_f = parse_lynis(args.final / "lynis-report.dat")
    oscap_b = parse_oscap(args.baseline / "oscap-results.xml")
    oscap_f = parse_oscap(args.final / "oscap-results.xml")
    tb, tf = tally(oscap_b["results"]), tally(oscap_f["results"])
    fixed, still, regressed = compare(oscap_b, oscap_f)
    generated = datetime.now(timezone.utc).strftime("%Y-%m-%d %H:%M UTC")

    cards = "".join([
        card("Lynis hardening index", lynis_b["index"], lynis_f["index"]),
        card("CIS L1 pass rate", tb["rate"], tf["rate"], suffix="%", delta_suffix=" pp"),
        card("CIS rules passed", tb["pass"], tf["pass"]),
        card("CIS rules failed", tb["fail"], tf["fail"], higher_is_better=False),
        card("OpenSCAP score", oscap_b["score"], oscap_f["score"]),
        card("Lynis warnings", lynis_b["warnings"], lynis_f["warnings"], higher_is_better=False),
    ])

    page = f"""<!doctype html>
<html lang="en"><head><meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>{esc(args.title)}</title><style>{CSS}</style></head>
<body><main>
<header><h1>{esc(args.title)}</h1>
<p class="meta">Generated {generated} &middot; OpenSCAP profile: {esc(args.profile_label)} &middot; Lynis quick audit</p></header>
<section class="cards">{cards}</section>
<section><h2>OpenSCAP rule results</h2>{bar_chart(tb, tf)}
<p class="legend"><span class="swatch bar-before"></span>Before hardening<span class="swatch bar-after"></span>After hardening</p></section>
<section><h2>Fixed by the hardening role ({len(fixed)})</h2>{rule_table(fixed, "No rule changed from fail to pass.")}</section>
<section><h2>Regressions ({len(regressed)})</h2>{rule_table(regressed, "None.")}</section>
<section><h2>Still failing ({len(still)})</h2>
<p>Some of these are documented exceptions. See docs/EXCEPTIONS.md in the repository.</p>
{rule_table(still, "None.")}</section>
</main></body></html>
"""
    args.out.parent.mkdir(parents=True, exist_ok=True)
    args.out.write_text(page, encoding="utf-8")
    print(f"Lynis hardening index: {show(lynis_b['index'])} -> {show(lynis_f['index'])}")
    print(f"CIS L1 rules passed:   {tb['pass']} -> {tf['pass']}  (failed {tb['fail']} -> {tf['fail']})")
    print(f"Report written to {args.out}")


if __name__ == "__main__":
    main()
