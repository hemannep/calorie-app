#!/usr/bin/env python3
"""Prepare local iOS output; retain at most one unused previous build under 2 GiB.

Only recognized generated-build directories are candidates. Source backups,
symlinks, current output, and files referenced by running processes are retained.
"""
import argparse
import fcntl
import hashlib
import os
from pathlib import Path
import re
import shutil
import stat
import subprocess
import sys
import tempfile
import time
import uuid
from contextlib import contextmanager

PROJECT = Path(__file__).resolve().parent.parent
BACKUP_NAME = re.compile(r"(?:build-before-ios-\d{8}-\d{6}(?:-\d+)?|desktop-build-before-ios-fix)")
CACHE_NAME = re.compile(r"build(?:-\d{8}-\d{6}-\d+(?:-[a-f0-9]+)?)?")
SOURCE_MARKERS = (".git", "pubspec.yaml", "pubspec.lock", "package.json", "lib", "Runner.xcodeproj")
PREVIOUS_BUDGET_BYTES = 2 * 1024 ** 3
OUTPUT_MARKERS = ("ios", "macos", "app", "test_cache", "unit_test_assets", "native_assets", ".kayleo-generated-build")


def cache_root(project):
    key = hashlib.sha1(str(project).encode()).hexdigest()[:12]
    return Path(os.environ.get("TMPDIR") or tempfile.gettempdir()) / "Kayleo" / key


def is_generated(path):
    return (path.is_dir() and not path.is_symlink()
            and path.stat().st_uid == os.getuid()
            and not any((path / name).exists() for name in SOURCE_MARKERS)
            and (any((path / name).exists() for name in OUTPUT_MARKERS) or not any(path.iterdir())))


@contextmanager
def locked(root):
    root.mkdir(parents=True, exist_ok=True)
    if root.is_symlink():
        raise RuntimeError("Refusing a symlinked cache root")
    with (root / ".prepare-ios.lock").open("a") as handle:
        try:
            fcntl.flock(handle, fcntl.LOCK_EX | fcntl.LOCK_NB)
        except BlockingIOError:
            raise RuntimeError("Another iOS preparation or cleanup is running; retry after it finishes")
        yield


def candidates(project, root):
    found = []
    for parent, pattern in ((project / ".codex-backups", BACKUP_NAME), (root, CACHE_NAME)):
        if not parent.is_dir() or parent.is_symlink():
            continue
        for path in parent.iterdir():
            if pattern.fullmatch(path.name) and is_generated(path):
                found.append(path)
    return found


def live_references():
    """Fail closed when the OS cannot provide a snapshot of open files."""
    files = subprocess.run(["/usr/sbin/lsof", "-nP", "-u", str(os.getuid()), "-Fn"],
                           capture_output=True, text=True, timeout=30)
    if files.returncode not in (0, 1) or not files.stdout.strip():
        raise RuntimeError("Could not verify open files; generated builds were retained")
    paths = []
    for line in files.stdout.splitlines():
        if line.startswith("n/"):
            paths.append(os.path.realpath(line[1:].removesuffix(" (deleted)")))
    processes = subprocess.run(["/bin/ps", "-axo", "pid=,args="],
                               capture_output=True, text=True, check=True, timeout=15)
    # Process arguments are examined locally and are never printed or saved.
    args = [line.split(None, 1)[1] for line in processes.stdout.splitlines()
            if len(line.split(None, 1)) == 2 and line.split(None, 1)[0] != str(os.getpid())]
    return paths, args


def referenced(path, paths, args):
    name = str(path.resolve())
    prefixes = {name, str(path)}
    # A path named "build" must not match a sibling named "build-2026...".
    boundary = r"(?=$|[/\s'\"])"
    return (any(os.path.realpath(p) == name or os.path.realpath(p).startswith(name + os.sep) for p in paths)
            or any(re.search(re.escape(prefix) + boundary, command)
                   for prefix in prefixes for command in args))


def remove_generated(path):
    """rmtree does not follow child symlinks; retry read-only owned build files."""
    base = path.resolve()
    def writable(operation, name, error):
        child = Path(name)
        if not isinstance(error[1], PermissionError):
            raise error[1]
        parent = child.parent
        if parent.resolve().is_relative_to(base) and not parent.is_symlink():
            if parent.stat().st_uid != os.getuid():
                raise error[1]
            parent.chmod(parent.stat().st_mode | stat.S_IRUSR | stat.S_IWUSR | stat.S_IXUSR)
        if not child.is_symlink():
            if not child.resolve().is_relative_to(base) or child.stat().st_uid != os.getuid():
                raise error[1]
            mode = child.stat().st_mode | stat.S_IRUSR | stat.S_IWUSR
            if child.is_dir():
                mode |= stat.S_IXUSR
            child.chmod(mode)
        operation(name)
    shutil.rmtree(path, onerror=writable)


def allocated_bytes(path):
    result = subprocess.run(["/usr/bin/du", "-sk", str(path)], capture_output=True,
                            text=True, check=True, timeout=120)
    return int(result.stdout.split()[0]) * 1024


def cleanup(project, root, dry_run=False, refs=None, duplicate=None):
    dynamic_refs = refs is None
    paths, args = live_references() if dynamic_refs else refs
    current = (project / "build").resolve()
    unused = []
    removed = []
    for path in candidates(project, root):
        if path.resolve() == current or referenced(path, paths, args):
            print("Keeping current or in-use build:", path, flush=True)
            continue
        unused.append(path)
    # A successfully copied original is redundant with the current cache. It
    # need not displace the one older build retained for convenience.
    redundant = [p for p in unused if duplicate is not None and p == duplicate]
    previous = sorted((p for p in unused if p not in redundant),
                      key=lambda p: (p.stat().st_mtime_ns, p.name), reverse=True)
    keep = 1 if previous and allocated_bytes(previous[0]) <= PREVIOUS_BUDGET_BYTES else 0
    deleting = redundant + previous[keep:]
    # Sizing a large old tree can take time. Refresh references after it.
    if dynamic_refs and deleting:
        paths, args = live_references()
    for path in deleting:
        # Recheck guards immediately before mutation.
        if (not is_generated(path) or path.resolve() == (project / "build").resolve()
                or referenced(path, paths, args)):
            continue
        print("Would remove:" if dry_run else "Removing obsolete generated build:", path, flush=True)
        if not dry_run:
            remove_generated(path)
        removed.append(path)
    return removed


def prepare(project, root):
    build = project / "build"
    duplicate = None
    if build.is_symlink():
        target = build.resolve()
        if not target.exists():
            if not target.is_relative_to(root.resolve()):
                raise RuntimeError("Refusing to recreate a build link outside this project's cache")
            target.mkdir(parents=True)
        elif not target.is_dir():
            raise RuntimeError("The build link does not point to a directory")
    else:
        if build.exists() and not is_generated(build):
            raise RuntimeError("Build contains unexpected/source files; leaving it unchanged")
        # Recover space before copying; currently referenced output is retained.
        cleanup(project, root)
        name = "build-" + time.strftime("%Y%m%d-%H%M%S") + "-" + str(os.getpid()) + "-" + uuid.uuid4().hex[:8]
        target = root / name
        target.mkdir()
        try:
            if build.exists():
                subprocess.run(["/usr/bin/rsync", "-a", str(build) + "/", str(target) + "/"], check=True)
                subprocess.run(["/bin/chmod", "-R", "u+w", str(target)], check=True)
                for attribute in ("com.apple.FinderInfo", "com.apple.ResourceFork"):
                    subprocess.run(["/usr/bin/xattr", "-dr", attribute, str(target)], check=True)
            (target / ".kayleo-generated-build").touch()
            if build.exists():
                backups = project / ".codex-backups"
                if backups.is_symlink():
                    raise RuntimeError("Refusing a symlinked backup directory")
                backups.mkdir(exist_ok=True)
                duplicate = backups / ("build-before-ios-" + time.strftime("%Y%m%d-%H%M%S") + "-" + str(os.getpid()))
                if duplicate.exists():
                    raise RuntimeError("Backup name already exists; leaving the original unchanged")
                build.rename(duplicate)
            try:
                build.symlink_to(target, target_is_directory=True)
            except OSError:
                if duplicate is not None:
                    duplicate.rename(build)
                raise
        except Exception:
            # Until the new link is installed, the original build remains the
            # source of truth. Remove only this attempt's partial cache copy.
            if not build.is_symlink() or build.resolve() != target.resolve():
                remove_generated(target)
            raise
        print("Current generated build:", target, flush=True)
    try:
        cleanup(project, root, duplicate=duplicate)
    except (OSError, RuntimeError, subprocess.SubprocessError) as error:
        # A cleanup failure must not destroy or block a successfully prepared build.
        print("Build is ready; cleanup retained extra copies:", error, file=sys.stderr)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--cleanup-only", action="store_true")
    parser.add_argument("--dry-run", action="store_true", help="inspect cleanup without changing builds")
    options = parser.parse_args()
    root = cache_root(PROJECT)
    with locked(root):
        if options.cleanup_only or options.dry_run:
            cleanup(PROJECT, root, dry_run=options.dry_run)
        else:
            prepare(PROJECT, root)


if __name__ == "__main__":
    try:
        main()
    except (OSError, RuntimeError, subprocess.SubprocessError) as error:
        print("iOS build preparation:", error, file=sys.stderr)
        sys.exit(1)
