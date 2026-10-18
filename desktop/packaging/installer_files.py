"""Generate NSIS uninstall commands for the packaged files only."""

from pathlib import Path
import sys


def uninstall_commands(dist):
    if not (dist / "aikatsu.exe").is_file():
        raise ValueError("The distribution folder must contain aikatsu.exe")

    paths = sorted(dist.rglob("*"))
    lines = ["!macro UninstallFiles"]
    for path in paths:
        if path.is_file():
            relative = path.relative_to(dist).as_posix().replace("/", "\\").replace("$", "$$")
            lines.append(f'    Delete "$INSTDIR\\{relative}"')
    for path in sorted(paths, key=lambda path: len(path.parts), reverse=True):
        if path.is_dir():
            relative = path.relative_to(dist).as_posix().replace("/", "\\").replace("$", "$$")
            lines.append(f'    RMDir "$INSTDIR\\{relative}"')
    return "\n".join([*lines, "!macroend", ""])


if __name__ == "__main__":
    Path(sys.argv[2]).write_text(uninstall_commands(Path(sys.argv[1])), encoding="utf-8")
