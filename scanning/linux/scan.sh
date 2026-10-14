#!/usr/bin/env bash
# Runs Lynis and OpenSCAP and packages the results.
# Usage (as root): scan.sh baseline|final
# Optional overrides: SCAN_DS=/path/to/datastream.xml SCAN_PROFILE=<profile id>
set -euo pipefail

PHASE="${1:?usage: scan.sh baseline|final}"
OUT="/var/tmp/scan/${PHASE}"
OWNER="${SUDO_USER:-root}"

# Datastream: one uploaded to /var/tmp wins, otherwise the one shipped by the distribution
DS="${SCAN_DS:-}"
if [ -z "$DS" ]; then
  for candidate in /var/tmp/ssg-*-ds.xml \
                   /usr/share/xml/scap/ssg/content/ssg-rl*-ds.xml \
                   /usr/share/xml/scap/ssg/content/ssg-rocky*-ds.xml \
                   /usr/share/xml/scap/ssg/content/ssg-rhel*-ds.xml; do
    if [ -f "$candidate" ]; then DS="$candidate"; break; fi
  done
fi
[ -n "$DS" ] || { echo "No SCAP datastream found"; exit 1; }

# Profile: CIS Level 1 Server (Debian names it cis_level1_server, RHEL cis_server_l1)
PROFILE="${SCAN_PROFILE:-$(oscap info --profiles "$DS" 2>/dev/null | grep -E 'cis_(level1_server|server_l1):' | head -1 | cut -d: -f1 || true)}"
if [ -z "$PROFILE" ]; then
  echo "No CIS Level 1 Server profile found in $DS. Available profiles:"
  oscap info --profiles "$DS"
  exit 1
fi

echo "[scan:${PHASE}] datastream: $DS"
echo "[scan:${PHASE}] profile:    $PROFILE"

rm -rf "$OUT"
mkdir -p "$OUT"

echo "[scan:${PHASE}] Lynis"
lynis audit system --quick --no-colors \
  --report-file "$OUT/lynis-report.dat" \
  --log-file "$OUT/lynis.log" > "$OUT/lynis-stdout.txt" 2>&1 || true
grep '^hardening_index=' "$OUT/lynis-report.dat" || echo "hardening_index not found"

echo "[scan:${PHASE}] OpenSCAP"
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

PASS=$(grep -c '^Result.*pass$' "$OUT/oscap-stdout.txt" || true)
FAIL=$(grep -c '^Result.*fail$' "$OUT/oscap-stdout.txt" || true)
echo "pass: $PASS  fail: $FAIL"
if [ "$((PASS + FAIL))" -eq 0 ]; then
  echo "No rule was evaluated. The datastream probably does not match this OS (CPE check)."
  exit 1
fi

tar -czf "/var/tmp/scan/${PHASE}.tar.gz" -C /var/tmp/scan "$PHASE"
chown "$OWNER" "/var/tmp/scan/${PHASE}.tar.gz"
echo "[scan:${PHASE}] done: /var/tmp/scan/${PHASE}.tar.gz"
