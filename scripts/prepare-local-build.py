#!/usr/bin/env python3
"""Generate a public-checkout Xcode project without editing the upstream project."""

import json
import os
import plistlib
import shutil
import subprocess
import xml.etree.ElementTree as ET
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
UPSTREAM = ROOT / "Sapphire.xcodeproj"
OUTPUT = ROOT / "build" / "Local" / "Sapphire.xcodeproj"


def main():
    data = subprocess.check_output([
        "/usr/bin/plutil", "-convert", "json", "-o", "-",
        str(UPSTREAM / "project.pbxproj"),
    ])
    project = json.loads(data)
    objects = project["objects"]
    root = objects[project["rootObject"]]
    root["projectDirPath"] = str(ROOT)
    root.pop("projectReferences", None)
    # Upstream contains a reference to itself; retaining it loads unmodified targets.
    nested_project = "DA262AE22EA484A70027CA69"
    objects.pop(nested_project, None)
    for obj in objects.values():
        if "children" in obj:
            obj["children"] = [x for x in obj["children"] if x != nested_project]

    for obj in objects.values():
        if obj["isa"] == "PBXShellScriptBuildPhase":
            if isinstance(obj.get("shellScript"), list):
                obj["shellScript"] = "\n".join(obj["shellScript"])
        if obj["isa"] == "PBXFileReference":
            path = obj.get("path", "")
            if "/System/Library/" in path and path.startswith("../"):
                obj["path"] = "System/Library/" + path.split("/System/Library/", 1)[1]
                obj["sourceTree"] = "SDKROOT"
            if "MacOSX10.7.sdk/System/Library/" in path:
                obj["path"] = "System/Library/" + path.split("/System/Library/", 1)[1]
                obj["sourceTree"] = "SDKROOT"

    # The public app relies on the provided stubs for private features.
    app = objects["DA46CF752DCBCA0000F00EC5"]
    app["buildPhases"] = [
        phase for phase in app["buildPhases"]
        if objects[phase].get("name") != "Upload Crashlytics Symbols"
    ]
    # Public Services only advertise implemented selectors. Preserve the upstream
    # plist for private builds, whose camera/document services are separate.
    public_info = plistlib.loads((ROOT / "Sapphire/App/Info.plist").read_bytes())
    public_info["NSFocusStatusUsageDescription"] = "Sapphire uses your shared Focus status to evaluate menu-bar profiles and show Focus indicators."
    public_info["NSServices"] = plistlib.loads((ROOT / "scripts/public-services.plist").read_bytes())
    public_info_path = ROOT / "build/Local/Sapphire-Public-Info.plist"
    public_info_path.parent.mkdir(parents=True, exist_ok=True)
    public_info_path.write_bytes(plistlib.dumps(public_info, sort_keys=False))
    configs = objects[app["buildConfigurationList"]]["buildConfigurations"]
    for config in configs:
        objects[config]["buildSettings"]["INFOPLIST_FILE"] = str(public_info_path)
        objects[config]["buildSettings"]["EXCLUDED_SOURCE_FILE_NAMES"] = "GeminiLiveManagerStub.swift"
        for key in ("NSLocationUsageDescription", "NSLocationWhenInUseUsageDescription"):
            objects[config]["buildSettings"]["INFOPLIST_KEY_" + key] = "Sapphire uses Location access to find and join your phone’s Wi-Fi hotspot, and for local weather."
        if os.environ.get("SAPPHIRE_FAST_BUILD") == "1":
            # Keep package dependencies cached; disable optimization only in the app
            # while iterating on device interoperability. Default builds stay optimized.
            objects[config]["buildSettings"]["SWIFT_OPTIMIZATION_LEVEL"] = "-Onone"
            objects[config]["buildSettings"]["SWIFT_COMPILATION_MODE"] = "wholemodule"

    # Point the File Provider target at its public placeholder implementation.
    provider_file = objects["F2DE000000000000000002BB"]
    provider_file["path"] = "PublicExtensionStubs/FileProvider/FileProviderExtension.swift"
    provider_file["sourceTree"] = "SOURCE_ROOT"
    objects["F2DE00000000000000000EBB"]["files"] = ["F2DE000000000000000013BB"]
    objects["F2DE000000000000000010BB"]["files"] = []
    provider = objects["F2DE00000000000000000ABB"]
    for config in objects[provider["buildConfigurationList"]]["buildConfigurations"]:
        settings = objects[config]["buildSettings"]
        settings["INFOPLIST_FILE"] = "PublicExtensionStubs/FileProvider/Info.plist"
        settings["CODE_SIGN_ENTITLEMENTS"] = ""

    # Local ad-hoc signing needs no Apple account or the author's provisioning profiles.
    for obj in objects.values():
        if obj["isa"] == "XCBuildConfiguration":
            settings = obj["buildSettings"]
            settings.update({
                "CODE_SIGN_IDENTITY": "-",
                "CODE_SIGN_STYLE": "Manual",
                "DEVELOPMENT_TEAM": "",
                "PROVISIONING_PROFILE_SPECIFIER": "",
                "OTHER_CODE_SIGN_FLAGS": "--timestamp=none",
                "REGISTER_APP_GROUPS": "NO",
            })
            settings["CODE_SIGN_ENTITLEMENTS"] = ""

    OUTPUT.mkdir(parents=True, exist_ok=True)
    entitlements = OUTPUT.parent / "Local.entitlements"
    entitlements.write_bytes(plistlib.dumps({
        "com.apple.security.automation.apple-events": True,
        "com.apple.security.personal-information.photos-library": True,
        "com.apple.security.cs.disable-library-validation": True,
    }))
    for config in configs:
        objects[config]["buildSettings"]["CODE_SIGN_ENTITLEMENTS"] = str(entitlements)

    (OUTPUT / "project.pbxproj").write_bytes(plistlib.dumps(project, sort_keys=False))
    for relative in [
        "xcshareddata/xcschemes",
        "project.xcworkspace/xcshareddata/swiftpm",
    ]:
        source = UPSTREAM / relative
        if source.exists():
            shutil.copytree(source, OUTPUT / relative, dirs_exist_ok=True)
    # projectDirPath points at the source checkout, so use explicit scheme containers.
    for scheme in (OUTPUT / "xcshareddata/xcschemes").glob("*.xcscheme"):
        tree = ET.parse(scheme)
        for reference in tree.iter("BuildableReference"):
            reference.set("ReferencedContainer", "container:" + str(OUTPUT))
        tree.write(scheme, encoding="UTF-8", xml_declaration=True)
    print(OUTPUT)


if __name__ == "__main__":
    main()
