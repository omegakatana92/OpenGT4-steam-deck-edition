"""AppRun path persistence and argv boundaries without a real disc or game."""
import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[2]

FAKE_GAME = """#!/usr/bin/env python3
import json, os, sys
print(json.dumps({
    "args": sys.argv[1:],
    "ffmpeg": os.environ["OPENGT4_FFMPEG_BINARY"],
    "ld_library_path": os.environ.get("LD_LIBRARY_PATH"),
}))
"""


class AppRunTest(unittest.TestCase):
    def setUp(self):
        self.directory = tempfile.TemporaryDirectory(prefix="opengt4 wrapper ")
        self.addCleanup(self.directory.cleanup)
        self.root = Path(self.directory.name)
        self.app = self.root / "AppDir"
        (self.app / "usr/bin").mkdir(parents=True)
        shutil.copy2(ROOT / "packaging/linux/AppRun", self.app / "AppRun")
        game = self.app / "usr/bin/opengt4"
        game.write_text(FAKE_GAME)
        game.chmod(0o755)
        self.env = {k: v for k, v in os.environ.items() if k != "LD_LIBRARY_PATH"}
        self.env["XDG_CONFIG_HOME"] = str(self.root / "config")

    def run_apprun(self, *args):
        result = subprocess.run([str(self.app / "AppRun"), *args], env=self.env,
                                text=True, capture_output=True, check=True)
        return json.loads(result.stdout)

    def test_arguments_and_remembered_disc(self):
        disc = self.root / "disc $(no-shell) ' spaces.iso"
        disc.touch()
        first = self.run_apprun(str(disc), "--save-dir", str(self.root / "my saves"))
        self.assertEqual(first["args"], [str(disc), "--fullscreen", "--save-dir", str(self.root / "my saves")])
        self.assertEqual(first["ffmpeg"], str(self.app / "usr/bin/ffmpeg"))
        self.assertEqual(self.run_apprun()["args"], [str(disc), "--fullscreen"])
        # An explicit relative path must survive a later working-directory change.
        relative = os.path.relpath(disc)
        self.assertEqual(self.run_apprun(relative)["args"], [str(disc), "--fullscreen"])
        self.assertEqual(self.run_apprun()["args"], [str(disc), "--fullscreen"])

    def test_video_check_needs_no_disc(self):
        # The startup diagnostic must be usable before a disc has been chosen.
        result = self.run_apprun("--video-check")
        self.assertEqual(result["args"], ["--video-check"])

    def test_does_not_shadow_system_libraries(self):
        # The image bundles no libraries, so LD_LIBRARY_PATH must stay untouched.
        disc = self.root / "disc.iso"
        disc.touch()
        self.assertIsNone(self.run_apprun(str(disc))["ld_library_path"])


if __name__ == "__main__":
    unittest.main()
