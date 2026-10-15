#!/usr/bin/env bash
# Extracts saved scan results and builds the before/after report for one platform.
# Used by the Packer post-processors and by the Makefile.
# Usage: reporting/make_report.sh debian|rocky|windows
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUT="$ROOT/reporting/output"
mkdir -p "$OUT"

case "${1:-}" in
  debian)
    R="$ROOT/scanning/results/debian13"
    rm -rf "$R/baseline" "$R/final"
    tar -xzf "$R/baseline.tar.gz" -C "$R"
    tar -xzf "$R/final.tar.gz" -C "$R"
    python3 "$ROOT/reporting/generate_report.py" \
      --baseline "$R/baseline" --final "$R/final" \
      --out "$OUT/debian13-report.html" \
      --title "Debian 13 hardening report" \
      --profile-label "CIS Debian 13 Level 1 Server"
    ;;
  rocky)
    R="$ROOT/scanning/results/rocky10"
    rm -rf "$R/baseline" "$R/final"
    tar -xzf "$R/baseline.tar.gz" -C "$R"
    tar -xzf "$R/final.tar.gz" -C "$R"
    python3 "$ROOT/reporting/generate_report.py" \
      --baseline "$R/baseline" --final "$R/final" \
      --out "$OUT/rocky10-report.html" \
      --title "Rocky Linux 10 hardening report" \
      --profile-label "CIS RHEL 10 Level 1 Server"
    ;;
  windows)
    R="$ROOT/scanning/results/ws2025"
    rm -rf "$R/baseline" "$R/final"
    python3 "$ROOT/reporting/extract_zip.py" "$R/baseline.zip" "$R"
    python3 "$ROOT/reporting/extract_zip.py" "$R/final.zip" "$R"
    python3 "$ROOT/reporting/generate_windows_report.py" \
      --baseline "$R/baseline/hk-report.csv" --final "$R/final/hk-report.csv" \
      --out "$OUT/ws2025-report.html" \
      --title "Windows Server 2025 hardening report" \
      --profile-label "CIS Windows Server 2025 v1.0.0 (HardeningKitty machine list)"
    ;;
  *)
    echo "usage: $0 debian|rocky|windows" >&2
    exit 2
    ;;
esac
