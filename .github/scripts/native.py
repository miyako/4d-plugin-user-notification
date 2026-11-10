"""Rebuild exact Default outputs while preserving the committed cross-platform bundle."""

import argparse
from pathlib import Path, PurePosixPath
import re
import shutil

from repository import is_link


PRODUCT = "Notification Center"
BASE = Path(PRODUCT + ".4dbase/Plugins")
BUNDLE = BASE / (PRODUCT + ".bundle")
FILES = tuple(BUNDLE / relative for relative in (
    f"Contents/MacOS/{PRODUCT}", "Contents/Info.plist",
    "Contents/Resources/English.lproj/InfoPlist.strings",
    "Contents/Resources/constants.xlf", "Contents/Resources/manifest.json",
    "Contents/_CodeSignature/CodeResources",
))
XCODE_DATA = Path("build/XCBuildData")
DIRECTORIES = (
    Path("build") / (PRODUCT + ".build"),
    Path("build/Default") / (PRODUCT + ".build"),
    BASE / (PRODUCT + ".build"),
    BASE / "Default" / (PRODUCT + ".build"),
)


def generated(path):
    if "\\" in path or PurePosixPath(path).as_posix() != path \
            or PurePosixPath(path).is_absolute() or ".." in PurePosixPath(path).parts:
        return False
    return (path in set(map(str, FILES))
            or bool(re.fullmatch(
                r"build/XCBuildData/(?:build\.db(?:-wal|-shm)?|"
                r"[0-9a-f]{32}\.xcbuilddata/.+)", path))
            or any(path.startswith(str(directory) + "/") for directory in DIRECTORIES))


def validate_paths(paths):
    root = Path.cwd().resolve()
    for path in paths:
        for parent in (path, *path.parents):
            if parent == Path("."):
                break
            if is_link(parent):
                raise ValueError(f"Refusing symlink output: {parent}")
        if not path.resolve().is_relative_to(root):
            raise ValueError(f"Output escapes checkout: {path}")
        if path.is_dir():
            for descendant in path.rglob("*"):
                if is_link(descendant):
                    raise ValueError(f"Refusing symlink output: {descendant}")


def prepare():
    validate_paths((*FILES, *DIRECTORIES, XCODE_DATA))
    for path in FILES:
        path.unlink(missing_ok=True)
    for path in DIRECTORIES:
        if path.exists():
            shutil.rmtree(path)


def require_file(path):
    validate_paths((path,))
    if not path.is_file() or path.stat().st_size == 0:
        raise ValueError(f"Missing or empty native output: {path}")


def validate_outputs(*, signed=True):
    validate_paths((BUNDLE, *DIRECTORIES, XCODE_DATA))
    for path in FILES if signed else FILES[:-1]:
        require_file(path)
    for path in BUNDLE.rglob("*"):
        if not path.is_dir():
            require_file(path)


def verify_resources():
    for name in ("manifest.json", "constants.xlf"):
        copied = BUNDLE / "Contents/Resources" / name
        require_file(copied)
        if copied.read_bytes() != Path(name).read_bytes():
            raise ValueError(f"Copied resource differs from source: {copied}")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("phase", choices=("clean-macos", "verify-unsigned", "verify-resources"))
    phase = parser.parse_args().phase
    if phase == "clean-macos":
        prepare()
    elif phase == "verify-unsigned":
        validate_outputs(signed=False)
    else:
        verify_resources()
