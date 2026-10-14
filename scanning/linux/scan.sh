#!/usr/bin/env bash
# Runs Lynis and OpenSCAP and packages the results.
# Usage (as root): scan.sh baseline|final
set -euo pipefail

PHASE="${1:?usage: scan.sh baseline|final}"
DS="/var/tmp/ssg-debian13-ds.xml"
PROFILE="xccdf_org.ssgproject.content_profile_cis_level1_server"
OUT="/var/tmp/scan/${PHASE}"
OWNER="${SUDO_USER:-root}"

rm -rf "$OUT"
mkdir -p "$OUT"

echo "[scan:${PHASE}] Lynis"
lynis audit system --quick --no-colors \
  --report-file "$OUT/lynis-report.dat" \
  --log-file "$OUT/lynis.log" > "$OUT/lynis-stdout.txt" 2>&1 || true
grep '^hardening_index=' "$OUT/lynis-report.dat" || echo "hardening_index not found"

echo "[scan:${PHASE}] OpenSCAP (${PROFILE})"
set +e
oscap xccdf eval --profile "$PROFILE" \
  --results "$OUT/oscap-results.xml" \
  --report "$OUT/oscap-report.html" \
  "$DS" > "$OUT/oscap-stdout.txt" 2>&1
rc=$?
set -e
# oscap exit codes: 0 = all rules passed, 2 = at least one rule failed, anything else = error
if [ "$rc" -ne 0 ] && [ "$rc" -ne 2 ]; then
  echo "oscap failed with exit code $rc"
  tail -20 "$OUT/oscap-stdout.txt"
  exit 1
fi
echo "pass: $(grep -c '^Result.*pass$' "$OUT/oscap-stdout.txt" || true)  fail: $(grep -c '^Result.*fail$' "$OUT/oscap-stdout.txt" || true)"

tar -czf "/var/tmp/scan/${PHASE}.tar.gz" -C /var/tmp/scan "$PHASE"
chown "$OWNER" "/var/tmp/scan/${PHASE}.tar.gz"
echo "[scan:${PHASE}] done: /var/tmp/scan/${PHASE}.tar.gz"
