#!/usr/bin/env python3
"""Build a tailored HardeningKitty finding list: the official list minus documented exceptions.

The official list is kept for auditing. The tailored list is only used to apply settings.
"""
import argparse
import csv
import sys
from pathlib import Path


def main():
    parser = argparse.ArgumentParser(description="Remove documented exceptions from a finding list")
    parser.add_argument("--in", dest="src", required=True, type=Path)
    parser.add_argument("--exceptions", required=True, type=Path)
    parser.add_argument("--out", required=True, type=Path)
    args = parser.parse_args()

    patterns = [
        line.strip() for line in args.exceptions.read_text(encoding="utf-8").splitlines()
        if line.strip() and not line.lstrip().startswith("#")
    ]

    with open(args.src, newline="", encoding="utf-8-sig") as fh:
        reader = csv.DictReader(fh)
        fields = reader.fieldnames
        rows = list(reader)
    if not rows or "Name" not in fields:
        sys.exit(f"ERROR: {args.src} is empty or has no Name column. Columns: {fields}")

    kept, removed, matched = [], [], {p: 0 for p in patterns}
    for row in rows:
        hits = [p for p in patterns if p.lower() in row["Name"].lower()]
        if hits:
            removed.append(row)
            for p in hits:
                matched[p] += 1
        else:
            kept.append(row)

    args.out.parent.mkdir(parents=True, exist_ok=True)
    with open(args.out, "w", newline="", encoding="utf-8") as fh:
        writer = csv.DictWriter(fh, fieldnames=fields, quoting=csv.QUOTE_ALL)
        writer.writeheader()
        writer.writerows(kept)

    print(f"Official list: {len(rows)} findings")
    print(f"Removed:       {len(removed)}")
    for row in removed:
        print(f"  - {row.get('ID', '?')}  {row['Name']}")
    for pattern, count in matched.items():
        if count == 0:
            print(f"  WARNING: no finding matched '{pattern}'")
    print(f"Tailored list: {len(kept)} findings -> {args.out}")


if __name__ == "__main__":
    main()
