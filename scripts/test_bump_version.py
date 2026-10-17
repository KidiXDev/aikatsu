"""Run with: python3 -m unittest discover -s scripts"""

from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import unittest


class BumpVersionTest(unittest.TestCase):
    def test_bump_and_reject_invalid_input_without_writing(self):
        root = Path(__file__).resolve().parent.parent
        files = ("Cargo.toml", "Cargo.lock", "mobile/pubspec.yaml")
        with tempfile.TemporaryDirectory() as directory:
            copy = Path(directory)
            before = {
                "Cargo.toml": '[workspace.package]\nversion = "0.3.2"\nedition = "2024"\n',
                "Cargo.lock": "".join(
                    f'[[package]]\nname = "{name}"\nversion = "0.3.2"\n\n'
                    for name in ("aikatsu", "aikatsu-core", "aikatsu_mobile", "unrelated")
                ),
                "mobile/pubspec.yaml": "name: aikatsu\nversion: 0.3.2+1\n",
            }
            for name, content in before.items():
                target = copy / name
                target.parent.mkdir(parents=True, exist_ok=True)
                target.write_text(content)
            script = copy / "scripts/bump-version.py"
            script.parent.mkdir()
            shutil.copyfile(root / "scripts/bump-version.py", script)
            result = subprocess.run([sys.executable, script, "1.2.3"], cwd=directory, capture_output=True)
            self.assertEqual(result.returncode, 0, result.stderr)
            expected = {
                "Cargo.toml": before["Cargo.toml"].replace('version = "0.3.2"', 'version = "1.2.3"'),
                "Cargo.lock": before["Cargo.lock"],
                "mobile/pubspec.yaml": before["mobile/pubspec.yaml"].replace("version: 0.3.2+1", "version: 1.2.3+1"),
            }
            for name in ("aikatsu", "aikatsu-core", "aikatsu_mobile"):
                expected["Cargo.lock"] = expected["Cargo.lock"].replace(
                    f'name = "{name}"\nversion = "0.3.2"', f'name = "{name}"\nversion = "1.2.3"'
                )
            self.assertEqual({name: (copy / name).read_text() for name in files}, expected)
            result = subprocess.run([sys.executable, script, "bad-version"], capture_output=True)
            self.assertNotEqual(result.returncode, 0)
            self.assertEqual({name: (copy / name).read_text() for name in files}, expected)
            (copy / "mobile/pubspec.yaml").write_text("invalid manifest\n")
            damaged = {name: (copy / name).read_text() for name in files}
            result = subprocess.run([sys.executable, script, "2.0.0"], capture_output=True)
            self.assertNotEqual(result.returncode, 0)
            self.assertEqual({name: (copy / name).read_text() for name in files}, damaged)
