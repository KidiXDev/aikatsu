from pathlib import Path
from tempfile import TemporaryDirectory
import unittest

from installer_files import uninstall_commands


class InstallerFilesTest(unittest.TestCase):
    def test_only_packaged_files_are_removed_and_children_come_first(self):
        with TemporaryDirectory() as folder:
            dist = Path(folder)
            (dist / "aikatsu.exe").touch()
            nested = dist / "qt plugins" / "imageformats"
            nested.mkdir(parents=True)
            (nested / "$cover.dll").touch()
            commands = uninstall_commands(dist).splitlines()

        self.assertEqual(commands, [
            "!macro UninstallFiles",
            '    Delete "$INSTDIR\\aikatsu.exe"',
            '    Delete "$INSTDIR\\qt plugins\\imageformats\\$$cover.dll"',
            '    RMDir "$INSTDIR\\qt plugins\\imageformats"',
            '    RMDir "$INSTDIR\\qt plugins"',
            "!macroend",
        ])

    def test_rejects_missing_app(self):
        with TemporaryDirectory() as folder:
            with self.assertRaisesRegex(ValueError, "aikatsu.exe"):
                uninstall_commands(Path(folder))


if __name__ == "__main__":
    unittest.main()
