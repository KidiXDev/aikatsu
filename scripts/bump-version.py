#!/usr/bin/env python3
"""Usage: python3 scripts/bump-version.py 0.3.3 (keeps Flutter's build number)."""

import argparse
from pathlib import Path
import re


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("version", help="new version, e.g. 0.3.3")
    version = parser.parse_args().version
    if not re.fullmatch(r"(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)", version):
        parser.error("version must be MAJOR.MINOR.PATCH, e.g. 0.3.3")

    root = Path(__file__).resolve().parent.parent
    edits = {
        "Cargo.toml": [r'(\[workspace\.package\]\s*\nversion = ")[^"]+(")'],
        "Cargo.lock": [
            rf'(\[\[package\]\]\nname = "{name}"\nversion = ")[^"]+(")'
            for name in ("aikatsu", "aikatsu-core", "aikatsu_mobile")
        ],
        "mobile/pubspec.yaml": [r"^(version: )[^+\n]+(\+[0-9]+)$"],
    }
    updated = {}
    for filename, patterns in edits.items():
        path = root / filename
        content = path.read_text()
        for pattern in patterns:
            content, count = re.subn(pattern, lambda m: m[1] + version + m[2], content, flags=re.M)
            if count != 1:
                parser.error(f"expected one version entry in {filename}, found {count}")
        updated[path] = content

    # Validate every entry before writing any file.
    for path, content in updated.items():
        path.write_text(content)
    print(f"Updated Cargo.toml, Cargo.lock and mobile/pubspec.yaml to {version}")


if __name__ == "__main__":
    main()
