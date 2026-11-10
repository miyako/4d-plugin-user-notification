"""The final publication exemption is smaller than the bundle or build roots."""

import unittest

from helper_support import source
import native


class GeneratedOutputTests(unittest.TestCase):
    def test_exact_native_files_and_controlled_directory_descendants(self):
        expected = (
            *map(str, native.FILES),
            "build/XCBuildData/build.db",
            "build/XCBuildData/build.db-wal",
            "build/XCBuildData/build.db-shm",
            "build/XCBuildData/0123456789abcdef0123456789abcdef.xcbuilddata/build-request.json",
            "build/Notification Center.build/Objects-normal/arm64/main.o",
            "build/Default/Notification Center.build/build.db",
            "Notification Center.4dbase/Plugins/Notification Center.build/Objects/file.o",
            "Notification Center.4dbase/Plugins/Notification Center.build/Objects/file.o",
        )
        for path in expected:
            with self.subTest(path=path):
                self.assertTrue(native.generated(path))

    def test_every_resource_source_or_unproven_output_stays_protected(self):
        excluded = (
            "Notification Center.4dbase/Plugins/Notification Center.bundle/Contents/Windows/Notification Center.4DX",
            "Notification Center.4dbase/Plugins/Notification Center.bundle/Contents/Windows64/Notification Center.4DX",
            "Notification Center.4dbase/Plugins/Notification Center.bundle/Contents/MacOS/runtime.dylib",
            "Notification Center.4dbase/Plugins/Notification Center.bundle/Contents/QuickLook/Thumbnail.png",
            "Notification Center.4dbase/Plugins/Default/Notification Center.bundle/Contents/Info.plist",
            "apr-1.5.2-evil/configure", "apr-arm64-evil/build.mk",
            "out-arm64-evil/include/apr.h", "jsoncpp-build-evil/libjsoncpp.a",
            "Notification Center.4dbase/Plugins/keep", "build/XCBuildData-evil/build.db",
            "build/unexpected-source.cpp",
            "build/XCBuildData/unexpected-source.cpp",
            "build/XCBuildData/build.db-evil",
            "build/XCBuildData/evil.xcbuilddata/build-request.json",
            "build/Notification Center.build-evil/injected.cpp",
            "Notification Center.4dbase/Plugins/Notification Center.bundle/Contents/_CodeSignature-evil/file",
            "Notification Center.4dbase/Plugins/Notification Center.bundle/Contents/Info.plist.backup",
            *map(str, source.SOURCE_PATHS),
        )
        for path in excluded:
            with self.subTest(path=path):
                self.assertFalse(native.generated(path))
