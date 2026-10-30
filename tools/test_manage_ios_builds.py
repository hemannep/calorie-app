#!/usr/bin/env python3
"""Safety and retention tests using disposable build trees, never the real app."""
import contextlib
import importlib.util
import io
import os
from pathlib import Path
import subprocess
import tempfile
import unittest
from unittest.mock import patch

spec = importlib.util.spec_from_file_location("manage_ios_builds", Path(__file__).with_name("manage_ios_builds.py"))
m = importlib.util.module_from_spec(spec)
spec.loader.exec_module(m)


class RetentionTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.project = Path(self.tmp.name) / "project"
        self.root = Path(self.tmp.name) / "cache"
        self.project.mkdir(); self.root.mkdir()
        self.refs = ([], [])

    def tearDown(self):
        self.tmp.cleanup()

    def output(self, parent, name, when=10):
        p = parent / name
        (p / "ios").mkdir(parents=True)
        (p / "ios" / "compiled.txt").write_text("generated")
        os.utime(p, (when, when))
        return p

    def clean(self, **kw):
        with contextlib.redirect_stdout(io.StringIO()):
            return m.cleanup(self.project, self.root, refs=self.refs, **kw)

    def test_keep_current_one_previous_and_open_build(self):
        old = self.output(self.root, "build-20261008-170000-1", 1)
        previous = self.output(self.root, "build-20261009-170000-2", 2)
        current = self.output(self.root, "build-20261010-170000-3", 3)
        in_use = self.output(self.root, "build", 0)
        (self.project / "build").symlink_to(current)
        self.refs = ([str(in_use / "ios/compiled.txt")], [])
        self.assertEqual(self.clean(), [old])
        self.assertTrue(all(x.exists() for x in (previous, current, in_use)))

    def test_source_backups_unknown_names_and_symlinks_are_never_candidates(self):
        backup = self.project / ".codex-backups"
        saved = self.output(backup, "build-before-ios-20261008-170000-1")
        (saved / "pubspec.yaml").write_text("source")
        model = self.output(backup, "models")
        unknown = self.output(self.root, "my-personal-folder")
        linked = self.root / "build"
        linked.symlink_to(unknown)
        self.assertEqual(self.clean(), [])
        self.assertTrue(all(p.exists() for p in (saved, model, unknown, linked)))

    def test_argument_reference_preserved_and_dry_run_changes_nothing(self):
        old = self.output(self.root, "build", 1)
        latest = self.output(self.root, "build-20261010-170000-3", 3)
        active = self.output(self.root, "build-20261009-170000-2", 2)
        self.refs = ([], ["flutter --build-dir=" + str(active)])
        self.assertEqual(self.clean(dry_run=True), [old])
        self.assertTrue(old.exists())
        self.assertEqual(self.clean(), [old])
        self.assertTrue(latest.exists() and active.exists())

    def test_copy_failure_preserves_original(self):
        original = self.output(self.project, "build")
        with patch.object(m, "live_references", return_value=self.refs), patch.object(m.subprocess, "run", side_effect=subprocess.CalledProcessError(1, "rsync")):
            with self.assertRaises(subprocess.CalledProcessError):
                m.prepare(self.project, self.root)
        self.assertFalse(original.is_symlink())
        self.assertEqual((original / "ios/compiled.txt").read_text(), "generated")
        self.assertEqual(list(self.root.iterdir()), [])

    def test_link_failure_rolls_original_back(self):
        original = self.output(self.project, "build")
        real_symlink = Path.symlink_to
        def fail_link(path, *args, **kwargs):
            if path == original:
                raise OSError("simulated link failure")
            return real_symlink(path, *args, **kwargs)
        with patch.object(m, "live_references", return_value=self.refs), patch.object(Path, "symlink_to", fail_link):
            with self.assertRaises(OSError):
                m.prepare(self.project, self.root)
        self.assertFalse(original.is_symlink())
        self.assertEqual((original / "ios/compiled.txt").read_text(), "generated")
        self.assertEqual(list(self.root.iterdir()), [])

    def test_successful_migration_and_repeated_runs_do_not_accumulate(self):
        previous = self.output(self.root, "build", 1)
        self.output(self.project, "build")
        with patch.object(m, "live_references", return_value=self.refs), contextlib.redirect_stdout(io.StringIO()):
            m.prepare(self.project, self.root)
            current = (self.project / "build").resolve()
            self.assertTrue((current / "ios/compiled.txt").is_file())
            self.assertEqual(list((self.project / ".codex-backups").iterdir()), [])
            # Simulate Flutter replacing its output link with a real build folder.
            (self.project / "build").unlink()
            self.output(self.project, "build", 100)
            m.prepare(self.project, self.root)
            self.assertFalse(previous.exists())
            self.assertTrue(current.exists())
            for _ in range(3):
                m.prepare(self.project, self.root)
        self.assertEqual(len(m.candidates(self.project, self.root)), 2)

    def test_empty_output_is_allowed_but_source_tree_is_refused(self):
        (self.project / "build").mkdir()
        self.assertTrue(m.is_generated(self.project / "build"))
        (self.project / "build/pubspec.yaml").write_text("source")
        with patch.object(m, "live_references", return_value=self.refs):
            with self.assertRaises(RuntimeError):
                m.prepare(self.project, self.root)
        self.assertTrue((self.project / "build/pubspec.yaml").exists())

    def test_cleanup_does_not_follow_child_symlinks(self):
        outside = self.project / "personal.txt"
        outside.write_text("preserve me")
        old = self.output(self.root, "build", 1)
        (old / "ios/link").symlink_to(outside)
        self.output(self.root, "build-20261010-170000-3", 3)
        self.clean()
        self.assertEqual(outside.read_text(), "preserve me")

    def test_readonly_generated_checkout_and_external_link_are_safe(self):
        outside = self.project / "source.txt"
        outside.write_text("preserve")
        old = self.output(self.root, "build", 1)
        (old / "ios/external-link").symlink_to(outside)
        (old / "ios/compiled.txt").chmod(0o444)
        (old / "ios").chmod(0o555)
        self.output(self.root, "build-20261010-170000-3", 3)
        self.clean()
        self.assertFalse(old.exists())
        self.assertEqual(outside.read_text(), "preserve")

    def test_open_file_inventory_failure_retains_everything(self):
        old = self.output(self.root, "build", 1)
        self.output(self.root, "build-20261010-170000-3", 3)
        with patch.object(m.subprocess, "run", return_value=subprocess.CompletedProcess([], 2, "", "error")):
            with self.assertRaises(RuntimeError):
                m.cleanup(self.project, self.root)
        self.assertTrue(old.exists())

    def test_oversized_previous_build_is_removed_but_current_is_kept(self):
        old = self.output(self.root, "build", 1)
        current = self.output(self.root, "build-20261010-170000-3", 3)
        (self.project / "build").symlink_to(current)
        with patch.object(m, "allocated_bytes", return_value=m.PREVIOUS_BUDGET_BYTES + 1):
            self.assertEqual(self.clean(), [old])
        self.assertTrue(current.exists())

    def test_cache_key_matches_existing_shell_preparation_script(self):
        import hashlib
        expected = hashlib.sha1(str(self.project).encode()).hexdigest()[:12]
        self.assertEqual(m.cache_root(self.project).name, expected)

    def test_concurrent_preparation_lock_is_rejected(self):
        with m.locked(self.root):
            with self.assertRaises(RuntimeError):
                with m.locked(self.root):
                    self.fail("lock was not exclusive")


if __name__ == "__main__":
    unittest.main()
