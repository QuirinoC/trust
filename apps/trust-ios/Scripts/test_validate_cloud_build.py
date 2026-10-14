#!/usr/bin/env python3
"""Focused, host-independent checks for the Xcode Cloud source validator."""

from __future__ import annotations

import json
import os
import re
import shutil
import subprocess
import tempfile
import unittest
from pathlib import Path
import plistlib

import validate_cloud_build as validator


IOS_ROOT = Path(__file__).resolve().parents[1]


class CloudBuildValidatorTests(unittest.TestCase):
    def copied_project(self) -> tuple[tempfile.TemporaryDirectory, Path]:
        temporary_directory = tempfile.TemporaryDirectory()
        root = Path(temporary_directory.name)
        for relative_path in (
            "project.yml",
            "Trust.xcodeproj/project.pbxproj",
            "Trust.xcodeproj/xcshareddata/xcschemes/Trust.xcscheme",
            "Info.plist",
            "Internal-Info.plist",
        ):
            destination = root / relative_path
            destination.parent.mkdir(parents=True, exist_ok=True)
            shutil.copy2(IOS_ROOT / relative_path, destination)
        return temporary_directory, root

    def mutate_configuration(
        self,
        root: Path,
        list_name: str,
        config_name: str,
        setting: str,
        *,
        inside_build_settings: bool = False,
    ) -> None:
        project_path = root / "Trust.xcodeproj/project.pbxproj"
        project = project_path.read_text(encoding="utf-8")
        configuration_list = re.search(
            rf'([A-F0-9]{{24}}) /\* Build configuration list for {re.escape(list_name)} \*/\s*=\s*\{{\s*'
            r"isa = XCConfigurationList;\s*buildConfigurations = \((.*?)\);",
            project,
            re.DOTALL,
        )
        self.assertIsNotNone(configuration_list)
        release_id = re.search(
            rf"([A-F0-9]{{24}}) /\* {re.escape(config_name)} \*/", configuration_list.group(2)
        )
        self.assertIsNotNone(release_id)
        release_config = re.search(
            rf"{release_id.group(1)} /\* {re.escape(config_name)} \*/\s*=\s*\{{(.*?)^\t\t\}};",
            project,
            re.DOTALL | re.MULTILINE,
        )
        self.assertIsNotNone(release_config)
        if inside_build_settings:
            mutated = release_config.group(1).replace(
                "buildSettings = {", f"buildSettings = {{\n\t\t\t\t{setting}", 1
            )
        else:
            mutated = release_config.group(1).replace(
                "buildSettings = {", f"{setting}\n\t\t\tbuildSettings = {{", 1
            )
        self.assertNotEqual(mutated, release_config.group(1))
        project = project[: release_config.start(1)] + mutated + project[release_config.end(1) :]
        project_path.write_text(project, encoding="utf-8")

    def mutate_trust_release_settings(self, root: Path, setting: str) -> None:
        self.mutate_configuration(
            root,
            'PBXNativeTarget "Trust"',
            "Release",
            setting,
            inside_build_settings=True,
        )

    def test_checked_in_project_and_localizations_are_consistent(self) -> None:
        self.assertEqual(validator.project_configuration_errors(IOS_ROOT), [])
        self.assertEqual(validator.localization_freshness_errors(IOS_ROOT), [])

    def test_stale_generated_localization_fails(self) -> None:
        with tempfile.TemporaryDirectory() as temporary_directory:
            root = Path(temporary_directory)
            (root / "Sources/TrustCore").mkdir(parents=True)
            (root / "Scripts/overlays").mkdir(parents=True)
            (root / "Resources/fr.lproj").mkdir(parents=True)
            (root / "project.yml").write_text(
                "CFBundleLocalizations:\n  - en\n  - fr\n", encoding="utf-8"
            )
            (root / "Sources/TrustCore/TrustCopy.swift").write_text(
                'value("hello", defaultValue: "Hello")\n'
                'value("camera_permission", defaultValue: "Camera")\n'
                'value("location_when_in_use", defaultValue: "While using")\n'
                'value("location_always", defaultValue: "Always")\n'
                'value("location_precise", defaultValue: "Precise")\n',
                encoding="utf-8",
            )
            overlay = {
                "hello": "Bonjour",
                "camera_permission": "Caméra",
                "location_when_in_use": "Pendant l’utilisation",
                "location_always": "Toujours",
                "location_precise": "Précise",
            }
            (root / "Scripts/overlays/fr.json").write_text(
                json.dumps(overlay), encoding="utf-8"
            )
            (root / "Resources/fr.lproj/Localizable.strings").write_text(
                validator._render_strings(overlay), encoding="utf-8"
            )
            info_entries = {
                "CFBundleDisplayName": "Trust",
                "NSCameraUsageDescription": overlay["camera_permission"],
                "NSLocationWhenInUseUsageDescription": overlay["location_when_in_use"],
                "NSLocationAlwaysAndWhenInUseUsageDescription": overlay["location_always"],
                "NSLocationAlwaysUsageDescription": overlay["location_always"],
                "PreciseEscrow": overlay["location_precise"],
            }
            (root / "Resources/fr.lproj/InfoPlist.strings").write_text(
                validator._render_strings(info_entries), encoding="utf-8"
            )

            self.assertEqual(validator.localization_freshness_errors(root), [])
            (root / "Resources/fr.lproj/Localizable.strings").write_text(
                '"hello" = "Salut";\n', encoding="utf-8"
            )
            errors = validator.localization_freshness_errors(root)
            self.assertTrue(any("Localizable.strings: stale generated localization" in item for item in errors))

    def test_enabled_phone_verification_bypass_fails_configuration_guard(self) -> None:
        temporary_directory, root = self.copied_project()
        with temporary_directory:
            source_path = root / "project.yml"
            source = source_path.read_text(encoding="utf-8")
            source_path.write_text(
                source.replace("TRUST_SKIP_PHONE_VERIFICATION: false", "TRUST_SKIP_PHONE_VERIFICATION: true", 1),
                encoding="utf-8",
            )

            plist_path = root / "Info.plist"
            with plist_path.open("rb") as plist_file:
                plist = plistlib.load(plist_file)
            plist["TRUST_SKIP_PHONE_VERIFICATION"] = True
            with plist_path.open("wb") as plist_file:
                plistlib.dump(plist, plist_file)

            errors = validator.project_configuration_errors(root)
            self.assertIn(
                "project.yml Trust target must keep phone-verification bypass disabled", errors
            )
            self.assertIn("Info.plist must keep phone-verification bypass disabled", errors)

    def test_internal_target_bypass_and_wrong_plist_mapping_fail(self) -> None:
        temporary_directory, root = self.copied_project()
        with temporary_directory:
            source_path = root / "project.yml"
            source = source_path.read_text(encoding="utf-8")
            source_path.write_text(
                source.replace("TRUST_SKIP_PHONE_VERIFICATION: NO", "TRUST_SKIP_PHONE_VERIFICATION: YES", 1),
                encoding="utf-8",
            )
            project_path = root / "Trust.xcodeproj/project.pbxproj"
            project = project_path.read_text(encoding="utf-8")
            internal_blocks = validator._configuration_blocks(
                project, 'PBXNativeTarget "TrustInternal"'
            )
            release_block = next(block for name, block in internal_blocks if name == "Release")
            project = project.replace(
                release_block,
                release_block.replace("INFOPLIST_FILE = \"Internal-Info.plist\";", "INFOPLIST_FILE = Info.plist;", 1),
                1,
            )
            project_path.write_text(project, encoding="utf-8")

            errors = validator.project_configuration_errors(root)
        self.assertIn(
            "project.yml TrustInternal target must keep phone-verification bypass disabled", errors
        )
        self.assertIn(
            "Xcode Release TrustInternal configuration has an unexpected Internal-Info.plist", errors
        )

    def test_release_target_api_override_fails_configuration_guard(self) -> None:
        temporary_directory, root = self.copied_project()
        with temporary_directory:
            self.mutate_trust_release_settings(
                root, 'TRUST_BASE_URL = "http://127.0.0.1:5088";'
            )
            errors = validator.project_configuration_errors(root)
        self.assertIn(
            "Xcode Release Trust target overrides TRUST_BASE_URL; keep it in the project configuration",
            errors,
        )

    def test_test_action_release_configuration_fails_configuration_guard(self) -> None:
        temporary_directory, root = self.copied_project()
        with temporary_directory:
            scheme_path = root / "Trust.xcodeproj/xcshareddata/xcschemes/Trust.xcscheme"
            scheme = scheme_path.read_text(encoding="utf-8")
            scheme_path.write_text(
                scheme.replace('<TestAction\n      buildConfiguration = "Debug"', '<TestAction\n      buildConfiguration = "Release"', 1),
                encoding="utf-8",
            )
            errors = validator.project_configuration_errors(root)
        self.assertIn("shared Trust scheme TestAction must use Debug configuration", errors)

    def test_xcconfig_inheritance_fails_in_every_app_and_project_configuration(self) -> None:
        cases = (
            ('PBXNativeTarget "Trust"', "Debug", "Xcode Debug Trust target configuration"),
            ('PBXNativeTarget "Trust"', "Release", "Xcode Release Trust target configuration"),
            ('PBXNativeTarget "TrustInternal"', "Debug", "Xcode Debug TrustInternal configuration"),
            ('PBXNativeTarget "TrustInternal"', "Release", "Xcode Release TrustInternal configuration"),
            ('PBXProject "Trust"', "Debug", "Xcode Debug project configuration"),
            ('PBXProject "Trust"', "Release", "Xcode Release project configuration"),
        )
        for list_name, config_name, expected_error in cases:
            with self.subTest(configuration=f"{list_name} {config_name}"):
                temporary_directory, root = self.copied_project()
                with temporary_directory:
                    self.mutate_configuration(
                        root,
                        list_name,
                        config_name,
                        "baseConfigurationReference = ABCDEFABCDEFABCDEFABCDEF;",
                    )
                    errors = validator.project_configuration_errors(root)
                self.assertTrue(any(expected_error in error and "baseConfigurationReference" in error for error in errors))

    def test_injected_phone_verification_build_setting_is_rejected(self) -> None:
        temporary_directory, root = self.copied_project()
        with temporary_directory:
            source_path = root / "project.yml"
            source_path.write_text(
                source_path.read_text(encoding="utf-8")
                + "\n        INFOPLIST_KEY_TRUST_SKIP_PHONE_VERIFICATION: YES\n",
                encoding="utf-8",
            )
            errors = validator.project_configuration_errors(root)
        self.assertTrue(any("INFOPLIST_KEY_TRUST_SKIP_PHONE_VERIFICATION" in error for error in errors))

    def test_post_clone_rejects_wrong_scheme_and_project_environment(self) -> None:
        hook = IOS_ROOT / "ci_scripts/ci_post_clone.sh"
        repository_root = IOS_ROOT.parents[1]
        environment = os.environ.copy()
        environment["CI_PRIMARY_REPOSITORY_PATH"] = str(repository_root)
        environment["CI_XCODE_SCHEME"] = "TrustInternal"
        environment.pop("CI_PROJECT_FILE_PATH", None)
        wrong_scheme = subprocess.run(
            [str(hook)], capture_output=True, text=True, env=environment, check=False
        )
        self.assertNotEqual(wrong_scheme.returncode, 0)
        self.assertIn("expected Trust", wrong_scheme.stderr)

        environment["CI_XCODE_SCHEME"] = "Trust"
        environment["CI_PROJECT_FILE_PATH"] = "apps/trust-ios/Trust.xcodeproj/project.xcworkspace"
        wrong_project = subprocess.run(
            [str(hook)], capture_output=True, text=True, env=environment, check=False
        )
        self.assertNotEqual(wrong_project.returncode, 0)
        self.assertIn("expected Trust.xcodeproj", wrong_project.stderr)

        environment["CI_PROJECT_FILE_PATH"] = "apps/trust-ios/Trust.xcodeproj"
        valid_workflow = subprocess.run(
            [str(hook)], capture_output=True, text=True, env=environment, check=False
        )
        self.assertEqual(valid_workflow.returncode, 0, valid_workflow.stderr)
        self.assertIn("source, project, and localization checks only", valid_workflow.stdout)


if __name__ == "__main__":
    unittest.main()
