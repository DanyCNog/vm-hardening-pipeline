"""Unit tests for the report and finding-list tools.

Run from the repository root: python3 -m unittest discover -s tests -v
"""
import csv
import subprocess
import sys
import tempfile
import unittest
import zipfile
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT / "reporting"))

import generate_report  # noqa: E402
import generate_windows_report as gwr  # noqa: E402


def write_csv(path, header, rows):
    with open(path, "w", newline="", encoding="utf-8") as fh:
        writer = csv.writer(fh, quoting=csv.QUOTE_ALL)
        writer.writerow(header)
        writer.writerows(rows)


class LinuxReportTests(unittest.TestCase):
    def test_parse_lynis(self):
        with tempfile.TemporaryDirectory() as tmp:
            path = Path(tmp) / "lynis-report.dat"
            path.write_text("hardening_index=64\nwarning[]=A\nsuggestion[]=B\nsuggestion[]=C\n")
            data = generate_report.parse_lynis(path)
        self.assertEqual(data, {"index": 64, "warnings": 1, "suggestions": 2})


class WindowsReportTests(unittest.TestCase):
    HEADER = ["ID", "Category", "Name", "Severity", "Result", "Recommended"]

    def _load(self, rows):
        with tempfile.TemporaryDirectory() as tmp:
            path = Path(tmp) / "report.csv"
            write_csv(path, self.HEADER, rows)
            return gwr.load(path)

    def test_result_column_and_score(self):
        findings = self._load([
            ["1", "A", "Setting one", "Passed", "1", "1"],
            ["2", "A", "Setting two", "High", "0", "1"],
        ])
        totals = gwr.tally(findings)
        self.assertEqual((totals["pass"], totals["high"]), (1, 1))
        self.assertEqual(totals["score"], 3.5)  # (4 + 0) / 8 * 5 + 1

    def test_compare_detects_fixed_and_regressed(self):
        base = self._load([["1", "A", "One", "Passed", "", ""], ["2", "A", "Two", "Medium", "", ""]])
        final = self._load([["1", "A", "One", "Low", "", ""], ["2", "A", "Two", "Passed", "", ""]])
        fixed, still, regressed = gwr.compare(base, final)
        self.assertEqual([r["cis"] for r in fixed], ["2"])
        self.assertEqual([r["cis"] for r in regressed], ["1"])
        self.assertEqual(still, [])


class TailorListTests(unittest.TestCase):
    def test_exceptions_are_removed_case_insensitive(self):
        with tempfile.TemporaryDirectory() as tmp:
            tmp = Path(tmp)
            src, exc, out = tmp / "list.csv", tmp / "exceptions.txt", tmp / "out.csv"
            write_csv(src, ["ID", "Name", "Method"], [
                ["1", "Deny access to this computer from the network", "x"],
                ["2", "Minimum password length", "y"],
            ])
            exc.write_text("# comment\ndeny ACCESS to this computer\n", encoding="utf-8")
            result = subprocess.run(
                [sys.executable, str(ROOT / "windows-hardening" / "tailor_list.py"),
                 "--in", str(src), "--exceptions", str(exc), "--out", str(out)],
                capture_output=True, text=True, check=True,
            )
            with open(out, newline="", encoding="utf-8") as fh:
                names = [row["Name"] for row in csv.DictReader(fh)]
        self.assertEqual(names, ["Minimum password length"])
        self.assertIn("Removed:       1", result.stdout)


class ExtractZipTests(unittest.TestCase):
    SCRIPT = str(ROOT / "reporting" / "extract_zip.py")

    def test_backslash_paths_are_normalised(self):
        with tempfile.TemporaryDirectory() as tmp:
            tmp = Path(tmp)
            archive = tmp / "baseline.zip"
            with zipfile.ZipFile(archive, "w") as zf:
                zf.writestr("baseline\\hk-report.csv", "data")
            subprocess.run([sys.executable, self.SCRIPT, str(archive), str(tmp / "out")],
                           check=True, capture_output=True)
            self.assertTrue((tmp / "out" / "baseline" / "hk-report.csv").is_file())

    def test_zip_slip_is_refused(self):
        with tempfile.TemporaryDirectory() as tmp:
            tmp = Path(tmp)
            archive = tmp / "evil.zip"
            with zipfile.ZipFile(archive, "w") as zf:
                zf.writestr("..\\evil.txt", "data")
            result = subprocess.run([sys.executable, self.SCRIPT, str(archive), str(tmp / "out")],
                                    capture_output=True, text=True)
            self.assertNotEqual(result.returncode, 0)
            self.assertFalse((tmp / "evil.txt").exists())


if __name__ == "__main__":
    unittest.main()
