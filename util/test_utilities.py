"""Unprivileged regression tests for the installer and README helpers."""

import importlib.util
import os
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

HERE = Path(__file__).resolve().parent


def load(name, filename):
    spec = importlib.util.spec_from_file_location(name, HERE / filename)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


sudoers = load("sudoers", "generate-sudoers.py")
readme = load("readme", "readme.py")


class SudoersTests(unittest.TestCase):
    def test_extends_path_preserving_quotes_and_comments(self):
        for quote in ('"', ''):
            original = f'Defaults secure_path = {quote}/bin:/nix/bin{quote} # keep\n'
            updated = sudoers.make_sudoers(original, "/nix/bin:/root/.nix-profile/bin")
            self.assertIn(
                f'{quote}/bin:/nix/bin:/root/.nix-profile/bin{quote} # keep\n', updated
            )
            self.assertIn("Defaults\tenv_keep += NIX_PATH\n", updated)
            self.assertEqual(
                sudoers.make_sudoers(updated, "/nix/bin:/root/.nix-profile/bin"), ""
            )

    def test_adds_missing_defaults_without_joining_lines(self):
        for original in ("", "root ALL=(ALL) ALL", "root ALL=(ALL) ALL\n"):
            updated = sudoers.make_sudoers(original, "/nix/bin")
            self.assertIn('Defaults\tsecure_path = "/nix/bin"\n', updated)
            if original:
                self.assertTrue(updated.startswith("root ALL=(ALL) ALL\n"))
            self.assertEqual(sudoers.make_sudoers(updated, "/nix/bin"), "")


class ReadmeTests(unittest.TestCase):
    def test_extracts_only_example_block(self):
        text = "## Other\n```bash\nwrong\n```\n## Example\nIntro\n```bash\necho hello\n```\n## Usage\n```\nhelp\n```\n"
        start, end = readme.code_block(text, "Example", "bash")
        self.assertEqual(text[start:end], "echo hello\n")

    def test_missing_block_does_not_take_next_section(self):
        with self.assertRaises(ValueError):
            readme.code_block(
                "## Example\nNo code\n## Other\n```bash\nwrong\n```\n", "Example", "bash"
            )

    def test_updates_only_usage_and_is_repeatable(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "README.md"
            path.write_text("before\n## Usage\n```\nstale\n```\nafter\n")
            command = [
                sys.executable,
                str(HERE / "readme.py"),
                "update-usage",
                "--readme",
                str(path),
            ]
            subprocess.run(command, check=True, capture_output=True)
            output = path.read_text()
            self.assertTrue(output.startswith("before\n## Usage\n```\nextra-container create"))
            self.assertTrue(output.endswith("```\nafter\n"))
            self.assertNotIn("stale", output)
            self.assertEqual(subprocess.check_output(command, text=True), "")
            self.assertEqual(path.read_text(), output)

    def test_actual_example_is_valid_bash(self):
        text = (HERE.parent / "README.md").read_text()
        start, end = readme.code_block(text, "Example", "bash")
        subprocess.run(["bash", "-n"], input=text[start:end], text=True, check=True)


class ExampleRunnerTests(unittest.TestCase):
    def run_example(self, response="hello", existing=False):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            (root / "util").mkdir()
            (root / "README.md").write_text((HERE.parent / "README.md").read_text())
            (root / "util/readme.py").write_text((HERE / "readme.py").read_text())
            # Exercise the real runner with fake commands, skipping only sudo elevation.
            runner = (
                (HERE / "test-readme.sh")
                .read_text()
                .replace(
                    "if ((EUID != 0)); then",
                    "if false; then",
                    1,
                )
            )
            (root / "util/test-readme.sh").write_text(runner)
            commands = {
                "extra-container": '''case $1 in
    list) [[ ! -f "$TEST_ROOT/state" ]] || echo demo ;;
    create) cat >/dev/null; touch "$TEST_ROOT/state"; echo create >> "$TEST_ROOT/log" ;;
    destroy) rm -f "$TEST_ROOT/state"; echo destroy >> "$TEST_ROOT/log" ;;
esac
exit 0
''',
                "curl": 'echo "$TEST_RESPONSE"\n',
                "nixos-container": '[[ $1 != status ]] || echo up\nexit 0\n',
            }
            for name, body in commands.items():
                path = root / name
                path.write_text("#!/usr/bin/env bash\n" + body)
                path.chmod(0o755)
            if existing:
                (root / "state").touch()
            environment = dict(
                os.environ,
                PATH=f"{root}:{os.environ['PATH']}",
                TEST_ROOT=str(root),
                TEST_RESPONSE=response,
            )
            result = subprocess.run(
                ["bash", str(root / "util/test-readme.sh")],
                check=False,  # failure cases check exception handling and cleanup
                env=environment,
                text=True,
                capture_output=True,
            )
            log = (root / "log").read_text() if (root / "log").exists() else ""
            return result, log, (root / "state").exists()

    def test_success_checks_and_destroys_container(self):
        result, log, remains = self.run_example()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("README example passed.", result.stdout)
        self.assertEqual(log, "create\ndestroy\n")
        self.assertFalse(remains)

    def test_wrong_response_fails_and_cleans_up(self):
        result, log, remains = self.run_example(response="wrong")
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("Expected 'hello'", result.stderr)
        self.assertEqual(log, "create\ndestroy\n")
        self.assertFalse(remains)

    def test_existing_container_is_untouched(self):
        result, log, remains = self.run_example(existing=True)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("Refusing to overwrite", result.stderr)
        self.assertEqual(log, "")
        self.assertTrue(remains)


if __name__ == "__main__":
    unittest.main()
