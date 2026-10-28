#!/usr/bin/env python3
"""Regenerates PencilHive.xcodeproj from the files on disk.

Run from the project folder after adding or removing Swift files:

    python3 tools/generate_xcodeproj.py

The project is plain Xcode (no third-party dependencies); this script only saves hand-editing
project.pbxproj. Identifiers are derived from file paths so the output is stable between runs.
"""
import hashlib
import os
import re
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
PROJECT_NAME = "PencilHive"
BUNDLE_ID = "dev.pencilhive.PencilHive"
DEPLOYMENT_TARGET = "16.0"


def pbx_quote(value):
    return value if re.fullmatch(r"[A-Za-z0-9_./]+", value) else '"' + value + '"'


def oid(*parts):
    return hashlib.md5("/".join(parts).encode()).hexdigest()[:24].upper()


def swift_files(folder):
    found = []
    for base, _dirs, files in os.walk(os.path.join(ROOT, folder)):
        for name in sorted(files):
            if name.endswith(".swift"):
                found.append(os.path.relpath(os.path.join(base, name), ROOT))
    return sorted(found)


app_files = swift_files("PencilHive")
test_files = swift_files("PencilHiveTests")
objects = []  # (id, comment, body)


def add(identifier, comment, body):
    objects.append((identifier, comment, body))


# --- File references -------------------------------------------------------------------------
file_ref = {}
for path in app_files + test_files:
    file_ref[path] = oid("fileref", path)
    name = os.path.basename(path)
    add(file_ref[path], name, f'{{isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = {pbx_quote(name)}; sourceTree = "<group>"; }}')

assets_ref = oid("fileref", "Assets.xcassets")
levels_ref = oid("fileref", "Levels")
add(assets_ref, "Assets.xcassets", '{isa = PBXFileReference; lastKnownFileType = folder.assetcatalog; path = Assets.xcassets; sourceTree = "<group>"; }')
add(levels_ref, "Levels", '{isa = PBXFileReference; lastKnownFileType = folder; path = Levels; sourceTree = "<group>"; }')
privacy_ref = oid("fileref", "PrivacyInfo.xcprivacy")
add(privacy_ref, "PrivacyInfo.xcprivacy", '{isa = PBXFileReference; lastKnownFileType = text.xml; path = PrivacyInfo.xcprivacy; sourceTree = "<group>"; }')

app_product = oid("product", "app")
test_product = oid("product", "tests")
add(app_product, f"{PROJECT_NAME}.app", f'{{isa = PBXFileReference; explicitFileType = wrapper.application; includeInIndex = 0; path = {PROJECT_NAME}.app; sourceTree = BUILT_PRODUCTS_DIR; }}')
add(test_product, f"{PROJECT_NAME}Tests.xctest", f'{{isa = PBXFileReference; explicitFileType = wrapper.cfbundle; includeInIndex = 0; path = {PROJECT_NAME}Tests.xctest; sourceTree = BUILT_PRODUCTS_DIR; }}')

# --- Groups ----------------------------------------------------------------------------------
def group(identifier, name, children, path=None):
    kids = ",\n".join(f"\t\t\t\t{c}," for c in children).replace(",,", ",")
    kids = "\n".join(f"\t\t\t\t{c}," for c in children)
    path_line = f"path = {path}; " if path else ""
    name_line = f"name = {name}; " if (name and not path) else ""
    add(identifier, name or path, f'{{\n\t\t\tisa = PBXGroup;\n\t\t\tchildren = (\n{kids}\n\t\t\t);\n\t\t\t{path_line}{name_line}sourceTree = "<group>";\n\t\t}}')


def folder_group(folder, subfolders):
    """Builds nested groups for one top-level source folder; returns the group id."""
    children = []
    for sub in subfolders:
        sub_path = f"{folder}/{sub}"
        ids = [file_ref[p] for p in app_files + test_files if os.path.dirname(p) == sub_path]
        gid = oid("group", sub_path)
        group(gid, None, ids, path=sub)
        children.append(gid)
    return children


app_subs = ["App", "Core", "Game", "UI"]
app_children = folder_group("PencilHive", app_subs)
resources_group = oid("group", "PencilHive/Resources")
group(resources_group, None, [assets_ref, levels_ref, privacy_ref], path="Resources")
app_children.append(resources_group)
app_group = oid("group", "PencilHive")
group(app_group, None, app_children, path="PencilHive")

tests_group = oid("group", "PencilHiveTests")
group(tests_group, None, [file_ref[p] for p in test_files], path="PencilHiveTests")
products_group = oid("group", "Products")
group(products_group, "Products", [app_product, test_product])
main_group = oid("group", "main")
group(main_group, None, [app_group, tests_group, products_group])

# --- Build files and phases ------------------------------------------------------------------
def build_file(path_key, ref, comment, phase):
    identifier = oid("buildfile", phase, path_key)
    add(identifier, f"{comment} in {phase}", f"{{isa = PBXBuildFile; fileRef = {ref}; }}")
    return identifier


app_sources = [build_file(p, file_ref[p], os.path.basename(p), "Sources") for p in app_files]
test_sources = [build_file(p, file_ref[p], os.path.basename(p), "TestSources") for p in test_files]
app_resources = [
    build_file("Assets", assets_ref, "Assets.xcassets", "Resources"),
    build_file("Levels", levels_ref, "Levels", "Resources"),
    build_file("Privacy", privacy_ref, "PrivacyInfo.xcprivacy", "Resources"),
]


def phase(kind, identifier, files, comment):
    body = "\n".join(f"\t\t\t\t{f}," for f in files)
    add(identifier, comment, f"{{\n\t\t\tisa = {kind};\n\t\t\tbuildActionMask = 2147483647;\n\t\t\tfiles = (\n{body}\n\t\t\t);\n\t\t\trunOnlyForDeploymentPostprocessing = 0;\n\t\t}}")


app_sources_phase, app_frameworks_phase, app_resources_phase = (oid("phase", n) for n in ("app-src", "app-fw", "app-res"))
test_sources_phase, test_frameworks_phase, test_resources_phase = (oid("phase", n) for n in ("test-src", "test-fw", "test-res"))
phase("PBXSourcesBuildPhase", app_sources_phase, app_sources, "Sources")
phase("PBXFrameworksBuildPhase", app_frameworks_phase, [], "Frameworks")
phase("PBXResourcesBuildPhase", app_resources_phase, app_resources, "Resources")
phase("PBXSourcesBuildPhase", test_sources_phase, test_sources, "Sources")
phase("PBXFrameworksBuildPhase", test_frameworks_phase, [], "Frameworks")
phase("PBXResourcesBuildPhase", test_resources_phase, [], "Resources")

# --- Build configurations --------------------------------------------------------------------
def quote(value):
    return value if re.fullmatch(r"[A-Za-z0-9_]+", value) else '"' + value.replace('"', '\\"') + '"'


def settings(items):
    lines = []
    for key in sorted(items):
        value = items[key]
        if isinstance(value, list):
            value = "(" + ", ".join(quote(v) for v in value) + ")"
        else:
            value = quote(value)
        lines.append(f"\t\t\t\t{key} = {value};")
    return "\n".join(lines)


def config(identifier, name, items):
    add(identifier, name, f"{{\n\t\t\tisa = XCBuildConfiguration;\n\t\t\tbuildSettings = {{\n{settings(items)}\n\t\t\t}};\n\t\t\tname = {name};\n\t\t}}")


project_common = {
    "ALWAYS_SEARCH_USER_PATHS": "NO",
    "CLANG_ENABLE_MODULES": "YES",
    "CLANG_ENABLE_OBJC_ARC": "YES",
    "ENABLE_STRICT_OBJC_MSGSEND": "YES",
    "GCC_NO_COMMON_BLOCKS": "YES",
    "IPHONEOS_DEPLOYMENT_TARGET": DEPLOYMENT_TARGET,
    "SDKROOT": "iphoneos",
    "SWIFT_VERSION": "5.0",
    "MTL_FAST_MATH": "YES",
}
project_debug = dict(project_common, **{
    "DEBUG_INFORMATION_FORMAT": "dwarf",
    "ENABLE_TESTABILITY": "YES",
    "GCC_OPTIMIZATION_LEVEL": "0",
    "GCC_PREPROCESSOR_DEFINITIONS": ["DEBUG=1", "$(inherited)"],
    "MTL_ENABLE_DEBUG_INFO": "INCLUDE_SOURCE",
    "ONLY_ACTIVE_ARCH": "YES",
    "SWIFT_ACTIVE_COMPILATION_CONDITIONS": "DEBUG",
    "SWIFT_OPTIMIZATION_LEVEL": "-Onone",
})
project_release = dict(project_common, **{
    "DEBUG_INFORMATION_FORMAT": "dwarf-with-dsym",
    "ENABLE_NS_ASSERTIONS": "NO",
    "MTL_ENABLE_DEBUG_INFO": "NO",
    "SWIFT_COMPILATION_MODE": "wholemodule",
    "SWIFT_OPTIMIZATION_LEVEL": "-O",
    "VALIDATE_PRODUCT": "YES",
})
app_common = {
    "ASSETCATALOG_COMPILER_APPICON_NAME": "AppIcon",
    "ASSETCATALOG_COMPILER_GLOBAL_ACCENT_COLOR_NAME": "AccentColor",
    "CODE_SIGN_STYLE": "Automatic",
    "CURRENT_PROJECT_VERSION": "1",
    "GENERATE_INFOPLIST_FILE": "YES",
    "INFOPLIST_KEY_CFBundleDisplayName": "Pencil Hive",
    "INFOPLIST_KEY_ITSAppUsesNonExemptEncryption": "NO",
    "INFOPLIST_KEY_LSApplicationCategoryType": "public.app-category.puzzle-games",
    "INFOPLIST_KEY_UIApplicationSceneManifest_Generation": "YES",
    "INFOPLIST_KEY_UIApplicationSupportsIndirectInputEvents": "YES",
    "INFOPLIST_KEY_UILaunchScreen_BackgroundColor": "LaunchBackground",
    "INFOPLIST_KEY_UIRequiresFullScreen": "YES",
    "INFOPLIST_KEY_UISupportedInterfaceOrientations": "UIInterfaceOrientationPortrait",
    "LD_RUNPATH_SEARCH_PATHS": ["$(inherited)", "@executable_path/Frameworks"],
    "MARKETING_VERSION": "1.0",
    "PRODUCT_BUNDLE_IDENTIFIER": BUNDLE_ID,
    "PRODUCT_NAME": "$(TARGET_NAME)",
    "SUPPORTED_PLATFORMS": "iphoneos iphonesimulator",
    "SUPPORTS_MACCATALYST": "NO",
    "SUPPORTS_MAC_DESIGNED_FOR_IPHONE_IPAD": "NO",
    "TARGETED_DEVICE_FAMILY": "1",
}
test_common = {
    "BUNDLE_LOADER": "$(TEST_HOST)",
    "CODE_SIGN_STYLE": "Automatic",
    "CURRENT_PROJECT_VERSION": "1",
    "ENABLE_TESTING_SEARCH_PATHS": "YES",
    "GENERATE_INFOPLIST_FILE": "YES",
    "LD_RUNPATH_SEARCH_PATHS": ["$(inherited)", "@executable_path/Frameworks", "@loader_path/Frameworks"],
    "MARKETING_VERSION": "1.0",
    "PRODUCT_BUNDLE_IDENTIFIER": BUNDLE_ID + "Tests",
    "PRODUCT_NAME": "$(TARGET_NAME)",
    "SUPPORTED_PLATFORMS": "iphoneos iphonesimulator",
    "TARGETED_DEVICE_FAMILY": "1",
    "TEST_HOST": f"$(BUILT_PRODUCTS_DIR)/{PROJECT_NAME}.app/{PROJECT_NAME}",
}

project_cfgs = [oid("cfg", "project", n) for n in ("Debug", "Release")]
app_cfgs = [oid("cfg", "app", n) for n in ("Debug", "Release")]
test_cfgs = [oid("cfg", "test", n) for n in ("Debug", "Release")]
config(project_cfgs[0], "Debug", project_debug)
config(project_cfgs[1], "Release", project_release)
config(app_cfgs[0], "Debug", app_common)
config(app_cfgs[1], "Release", app_common)
config(test_cfgs[0], "Debug", test_common)
config(test_cfgs[1], "Release", test_common)


def config_list(identifier, comment, cfgs):
    body = "\n".join(f"\t\t\t\t{c}," for c in cfgs)
    add(identifier, comment, f"{{\n\t\t\tisa = XCConfigurationList;\n\t\t\tbuildConfigurations = (\n{body}\n\t\t\t);\n\t\t\tdefaultConfigurationIsVisible = 0;\n\t\t\tdefaultConfigurationName = Release;\n\t\t}}")


project_list = oid("cfglist", "project")
app_list = oid("cfglist", "app")
test_list = oid("cfglist", "test")
config_list(project_list, f'Build configuration list for PBXProject "{PROJECT_NAME}"', project_cfgs)
config_list(app_list, f'Build configuration list for PBXNativeTarget "{PROJECT_NAME}"', app_cfgs)
config_list(test_list, f'Build configuration list for PBXNativeTarget "{PROJECT_NAME}Tests"', test_cfgs)

# --- Targets ---------------------------------------------------------------------------------
app_target = oid("target", "app")
test_target = oid("target", "tests")
project_id = oid("project")
proxy = oid("proxy")
dependency = oid("dependency")

add(proxy, "PBXContainerItemProxy", f"{{\n\t\t\tisa = PBXContainerItemProxy;\n\t\t\tcontainerPortal = {project_id};\n\t\t\tproxyType = 1;\n\t\t\tremoteGlobalIDString = {app_target};\n\t\t\tremoteInfo = {PROJECT_NAME};\n\t\t}}")
add(dependency, "PBXTargetDependency", f"{{\n\t\t\tisa = PBXTargetDependency;\n\t\t\ttarget = {app_target};\n\t\t\ttargetProxy = {proxy};\n\t\t}}")
add(app_target, PROJECT_NAME, f"""{{
\t\t\tisa = PBXNativeTarget;
\t\t\tbuildConfigurationList = {app_list};
\t\t\tbuildPhases = (
\t\t\t\t{app_sources_phase},
\t\t\t\t{app_frameworks_phase},
\t\t\t\t{app_resources_phase},
\t\t\t);
\t\t\tbuildRules = (
\t\t\t);
\t\t\tdependencies = (
\t\t\t);
\t\t\tname = {PROJECT_NAME};
\t\t\tproductName = {PROJECT_NAME};
\t\t\tproductReference = {app_product};
\t\t\tproductType = "com.apple.product-type.application";
\t\t}}""")
add(test_target, f"{PROJECT_NAME}Tests", f"""{{
\t\t\tisa = PBXNativeTarget;
\t\t\tbuildConfigurationList = {test_list};
\t\t\tbuildPhases = (
\t\t\t\t{test_sources_phase},
\t\t\t\t{test_frameworks_phase},
\t\t\t\t{test_resources_phase},
\t\t\t);
\t\t\tbuildRules = (
\t\t\t);
\t\t\tdependencies = (
\t\t\t\t{dependency},
\t\t\t);
\t\t\tname = {PROJECT_NAME}Tests;
\t\t\tproductName = {PROJECT_NAME}Tests;
\t\t\tproductReference = {test_product};
\t\t\tproductType = "com.apple.product-type.bundle.unit-test";
\t\t}}""")
add(project_id, "Project object", f"""{{
\t\t\tisa = PBXProject;
\t\t\tattributes = {{
\t\t\t\tBuildIndependentTargetsInParallel = 1;
\t\t\t\tLastSwiftUpdateCheck = 1600;
\t\t\t\tLastUpgradeCheck = 1600;
\t\t\t\tTargetAttributes = {{
\t\t\t\t\t{app_target} = {{
\t\t\t\t\t\tCreatedOnToolsVersion = 16.0;
\t\t\t\t\t}};
\t\t\t\t\t{test_target} = {{
\t\t\t\t\t\tCreatedOnToolsVersion = 16.0;
\t\t\t\t\t\tTestTargetID = {app_target};
\t\t\t\t\t}};
\t\t\t\t}};
\t\t\t}};
\t\t\tbuildConfigurationList = {project_list};
\t\t\tcompatibilityVersion = "Xcode 14.0";
\t\t\tdevelopmentRegion = en;
\t\t\thasScannedForEncodings = 0;
\t\t\tknownRegions = (
\t\t\t\ten,
\t\t\t\tBase,
\t\t\t);
\t\t\tmainGroup = {main_group};
\t\t\tproductRefGroup = {products_group};
\t\t\tprojectDirPath = "";
\t\t\tprojectRoot = "";
\t\t\ttargets = (
\t\t\t\t{app_target},
\t\t\t\t{test_target},
\t\t\t);
\t\t}}""")

# --- Write project.pbxproj -------------------------------------------------------------------
order = {
    "PBXBuildFile": [], "PBXContainerItemProxy": [], "PBXFileReference": [], "PBXFrameworksBuildPhase": [],
    "PBXGroup": [], "PBXNativeTarget": [], "PBXProject": [], "PBXResourcesBuildPhase": [],
    "PBXSourcesBuildPhase": [], "PBXTargetDependency": [], "XCBuildConfiguration": [], "XCConfigurationList": [],
}
for identifier, comment, body in objects:
    isa = body.split("isa = ")[1].split(";")[0]
    order[isa].append((identifier, comment, body))

out = ["// !$*UTF8*$!", "{", "\tarchiveVersion = 1;", "\tclasses = {", "\t};", "\tobjectVersion = 56;", "\tobjects = {", ""]
for isa, items in order.items():
    if not items:
        continue
    out.append(f"/* Begin {isa} section */")
    for identifier, comment, body in sorted(items):
        out.append(f"\t\t{identifier} /* {comment} */ = {body};")
    out.append(f"/* End {isa} section */")
    out.append("")
out += ["\t};", f"\trootObject = {project_id} /* Project object */;", "}", ""]

proj_dir = os.path.join(ROOT, f"{PROJECT_NAME}.xcodeproj")
os.makedirs(os.path.join(proj_dir, "xcshareddata", "xcschemes"), exist_ok=True)
with open(os.path.join(proj_dir, "project.pbxproj"), "w") as handle:
    handle.write("\n".join(out))

scheme = f"""<?xml version="1.0" encoding="UTF-8"?>
<Scheme LastUpgradeVersion = "1600" version = "1.7">
   <BuildAction parallelizeBuildables = "YES" buildImplicitDependencies = "YES">
      <BuildActionEntries>
         <BuildActionEntry buildForTesting = "YES" buildForRunning = "YES" buildForProfiling = "YES" buildForArchiving = "YES" buildForAnalyzing = "YES">
            <BuildableReference BuildableIdentifier = "primary" BlueprintIdentifier = "{app_target}" BuildableName = "{PROJECT_NAME}.app" BlueprintName = "{PROJECT_NAME}" ReferencedContainer = "container:{PROJECT_NAME}.xcodeproj">
            </BuildableReference>
         </BuildActionEntry>
      </BuildActionEntries>
   </BuildAction>
   <TestAction buildConfiguration = "Debug" selectedDebuggerIdentifier = "Xcode.DebuggerFoundation.Debugger.LLDB" selectedLauncherIdentifier = "Xcode.DebuggerFoundation.Launcher.LLDB" shouldUseLaunchSchemeArgsEnv = "YES">
      <Testables>
         <TestableReference skipped = "NO">
            <BuildableReference BuildableIdentifier = "primary" BlueprintIdentifier = "{test_target}" BuildableName = "{PROJECT_NAME}Tests.xctest" BlueprintName = "{PROJECT_NAME}Tests" ReferencedContainer = "container:{PROJECT_NAME}.xcodeproj">
            </BuildableReference>
         </TestableReference>
      </Testables>
   </TestAction>
   <LaunchAction buildConfiguration = "Debug" selectedDebuggerIdentifier = "Xcode.DebuggerFoundation.Debugger.LLDB" selectedLauncherIdentifier = "Xcode.DebuggerFoundation.Launcher.LLDB" launchStyle = "0" useCustomWorkingDirectory = "NO" ignoresPersistentStateOnLaunch = "NO" debugDocumentVersioning = "YES" debugServiceExtension = "internal" allowLocationSimulation = "YES">
      <BuildableProductRunnable runnableDebuggingMode = "0">
         <BuildableReference BuildableIdentifier = "primary" BlueprintIdentifier = "{app_target}" BuildableName = "{PROJECT_NAME}.app" BlueprintName = "{PROJECT_NAME}" ReferencedContainer = "container:{PROJECT_NAME}.xcodeproj">
         </BuildableReference>
      </BuildableProductRunnable>
   </LaunchAction>
   <ProfileAction buildConfiguration = "Release" shouldUseLaunchSchemeArgsEnv = "YES" savedToolIdentifier = "" useCustomWorkingDirectory = "NO" debugDocumentVersioning = "YES">
      <BuildableProductRunnable runnableDebuggingMode = "0">
         <BuildableReference BuildableIdentifier = "primary" BlueprintIdentifier = "{app_target}" BuildableName = "{PROJECT_NAME}.app" BlueprintName = "{PROJECT_NAME}" ReferencedContainer = "container:{PROJECT_NAME}.xcodeproj">
         </BuildableReference>
      </BuildableProductRunnable>
   </ProfileAction>
   <AnalyzeAction buildConfiguration = "Debug">
   </AnalyzeAction>
   <ArchiveAction buildConfiguration = "Release" revealArchiveInOrganizer = "YES">
   </ArchiveAction>
</Scheme>
"""
with open(os.path.join(proj_dir, "xcshareddata", "xcschemes", f"{PROJECT_NAME}.xcscheme"), "w") as handle:
    handle.write(scheme)
print(f"Wrote {proj_dir} ({len(app_files)} app files, {len(test_files)} test files)")
