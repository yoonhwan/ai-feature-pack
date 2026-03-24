#!/usr/bin/env python3
import sys
import json
from pathlib import Path


def main():
    if len(sys.argv) < 2:
        print("Usage: pdf_read.py <path/to/file.pdf>")
        sys.exit(1)
    p = Path(sys.argv[1])
    if not p.exists():
        print(f"File not found: {p}")
        sys.exit(2)
    # Minimal stub: return filename and size as JSON for demo
    info = {
        "path": str(p),
        "size_bytes": p.stat().st_size,
        "notes": "stub: integrate PyMuPDF/pdfminer for real extraction"
    }
    print(json.dumps(info, indent=2))

if __name__ == "__main__":
    main()
