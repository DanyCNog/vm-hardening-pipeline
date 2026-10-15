#!/usr/bin/env python3
"""Extract a zip made by Windows PowerShell 5.1.

Compress-Archive in PowerShell 5.1 writes backslashes as path separators, which
Info-ZIP unzip warns about (exit code 1). Paths are normalised here, and entries
that would land outside the destination folder (zip slip) are refused.
"""
import sys
import zipfile
from pathlib import Path


def main():
    if len(sys.argv) != 3:
        sys.exit("usage: extract_zip.py ARCHIVE DEST")
    archive, dest = Path(sys.argv[1]), Path(sys.argv[2]).resolve()
    with zipfile.ZipFile(archive) as zf:
        for info in zf.infolist():
            name = info.filename.replace("\\", "/")
            target = (dest / name).resolve()
            if dest not in target.parents and target != dest:
                sys.exit(f"Refusing to extract outside {dest}: {info.filename}")
            if name.endswith("/"):
                target.mkdir(parents=True, exist_ok=True)
                continue
            target.parent.mkdir(parents=True, exist_ok=True)
            target.write_bytes(zf.read(info))
    print(f"Extracted {archive.name} -> {dest}")


if __name__ == "__main__":
    main()
