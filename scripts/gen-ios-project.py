#!/usr/bin/env python3
"""Writes iOS/Orbit.xcodeproj. The iPhone app compiles the Mac app's Models, Design, Services and Views folders directly
(folder references, so new shared files are picked up automatically) plus its own screens in iOS/OrbitPhone.
The home-screen widgets reuse Widgets/OrbitWidgets.swift.

  python3 scripts/gen-ios-project.py               # app + widgets
  python3 scripts/gen-ios-project.py --no-widgets  # app only (Apple doesn't give free accounts the App Group widgets need)
"""
import hashlib, pathlib, sys

ROOT = pathlib.Path(__file__).resolve().parent.parent
OUT = ROOT / "iOS" / "Orbit.xcodeproj" / "project.pbxproj"
VERSION = (ROOT / "VERSION").read_text().strip()
TEAM = "Y2K55S3UA9"
BUNDLE_ID = "com.ahmedwalid.orbit"
WIDGETS = "--no-widgets" not in sys.argv

# Shared Mac files that can't run on iPhone (Mac-only windows, hotkeys, updater).
MAC_ONLY_SERVICES = ["Capture.swift", "Updater.swift", "VoiceCapture.swift"]
MAC_ONLY_VIEWS = ["RootView.swift", "CaptureAndMenuViews.swift"]


def oid(name):
    return hashlib.md5(name.encode()).hexdigest()[:24].upper()


def q(v):
    v = str(v)
    return v if v and all(c.isalnum() or c in "_./" for c in v) else '"' + v.replace('"', '\\"') + '"'


def settings_text(d, indent=4):
    pad = "\t" * indent
    return "\n".join(f"{pad}{k} = {q(v)};" for k, v in d.items())


T_APP, T_WID = oid("target.app"), oid("target.widgets")
P_APP, P_WID = oid("product.app"), oid("product.widgets")
G_MAIN, G_PRODUCTS = oid("group.main"), oid("group.products")
F_SUPABASE, B_SUPABASE = oid("file.supabase"), oid("build.supabase")
B_EMBED = oid("build.embed.widgets")
PROJECT = oid("project")

# name: (path, source tree, target, files excluded from that target)
SYNC = {
    "OrbitPhone": ("OrbitPhone", '"<group>"', T_APP, []),
    "Models": ("../Sources/Orbit/Models", "SOURCE_ROOT", T_APP, []),
    "Design": ("../Sources/Orbit/Design", "SOURCE_ROOT", T_APP, []),
    "Services": ("../Sources/Orbit/Services", "SOURCE_ROOT", T_APP, MAC_ONLY_SERVICES),
    "Views": ("../Sources/Orbit/Views", "SOURCE_ROOT", T_APP, MAC_ONLY_VIEWS),
}
if WIDGETS:
    SYNC["Widgets"] = ("../Widgets", "SOURCE_ROOT", T_WID, ["Info.plist", "OrbitWidgets.entitlements"])

project_common = {
    "ALWAYS_SEARCH_USER_PATHS": "NO", "CLANG_ENABLE_MODULES": "YES", "CLANG_ENABLE_OBJC_ARC": "YES", "COPY_PHASE_STRIP": "NO",
    "ENABLE_STRICT_OBJC_MSGSEND": "YES", "ENABLE_USER_SCRIPT_SANDBOXING": "YES", "GCC_C_LANGUAGE_STANDARD": "gnu17",
    "IPHONEOS_DEPLOYMENT_TARGET": "18.0", "LOCALIZATION_PREFERS_STRING_CATALOGS": "YES", "SDKROOT": "iphoneos", "SWIFT_VERSION": "5.0",
}
project_debug = {**project_common, "DEBUG_INFORMATION_FORMAT": "dwarf", "ENABLE_TESTABILITY": "YES", "GCC_OPTIMIZATION_LEVEL": "0",
                 "ONLY_ACTIVE_ARCH": "YES", "SWIFT_ACTIVE_COMPILATION_CONDITIONS": "DEBUG $(inherited)", "SWIFT_OPTIMIZATION_LEVEL": "-Onone"}
project_release = {**project_common, "DEBUG_INFORMATION_FORMAT": "dwarf-with-dsym", "ENABLE_NS_ASSERTIONS": "NO",
                   "SWIFT_COMPILATION_MODE": "wholemodule", "VALIDATE_PRODUCT": "YES"}

common_target = {
    "CODE_SIGN_STYLE": "Automatic", "CURRENT_PROJECT_VERSION": "1", "DEVELOPMENT_TEAM": TEAM, "MARKETING_VERSION": VERSION,
    "SUPPORTED_PLATFORMS": "iphoneos iphonesimulator", "SUPPORTS_MACCATALYST": "NO", "SWIFT_EMIT_LOC_STRINGS": "NO", "TARGETED_DEVICE_FAMILY": "1",
}
app = {
    **common_target,
    "ASSETCATALOG_COMPILER_APPICON_NAME": "AppIcon",
    "ENABLE_PREVIEWS": "YES",
    "GENERATE_INFOPLIST_FILE": "YES",
    "INFOPLIST_FILE": "Support/OrbitPhone-Info.plist",
    "INFOPLIST_KEY_CFBundleDisplayName": "Orbit",
    "INFOPLIST_KEY_LSApplicationCategoryType": "public.app-category.productivity",
    "INFOPLIST_KEY_NSCalendarsFullAccessUsageDescription": "Orbit shows your calendar events alongside your tasks and plans.",
    "INFOPLIST_KEY_NSRemindersFullAccessUsageDescription": "Orbit shows and completes your Apple Reminders next to your tasks.",
    "INFOPLIST_KEY_NSMicrophoneUsageDescription": "Orbit listens when you tap the mic, so you can talk to your assistant and plan by voice.",
    "INFOPLIST_KEY_NSSpeechRecognitionUsageDescription": "Orbit turns what you say into text on your iPhone, so your assistant can understand you.",
    "INFOPLIST_KEY_NSCameraUsageDescription": "Take a photo of a receipt or document to send to your assistant.",
    "INFOPLIST_KEY_UIApplicationSceneManifest_Generation": "YES",
    "INFOPLIST_KEY_UILaunchScreen_Generation": "YES",
    "INFOPLIST_KEY_UISupportedInterfaceOrientations_iPhone": "UIInterfaceOrientationPortrait",
    "LD_RUNPATH_SEARCH_PATHS": "$(inherited) @executable_path/Frameworks",
    "PRODUCT_BUNDLE_IDENTIFIER": BUNDLE_ID,
    "PRODUCT_NAME": "Orbit",
}
if WIDGETS:
    app["CODE_SIGN_ENTITLEMENTS"] = "Support/OrbitPhone.entitlements"
widgets = {
    **common_target,
    "GENERATE_INFOPLIST_FILE": "YES",
    "INFOPLIST_FILE": "Support/OrbitWidgets-Info.plist",
    "INFOPLIST_KEY_CFBundleDisplayName": "Orbit",
    "CODE_SIGN_ENTITLEMENTS": "Support/OrbitWidgets.entitlements",
    "LD_RUNPATH_SEARCH_PATHS": "$(inherited) @executable_path/Frameworks @executable_path/../../Frameworks",
    "PRODUCT_BUNDLE_IDENTIFIER": BUNDLE_ID + ".widgets",
    "PRODUCT_NAME": "OrbitWidgets",
    "SKIP_INSTALL": "YES",
}

configs = {
    oid("cfg.project.debug"): ("Debug", project_debug), oid("cfg.project.release"): ("Release", project_release),
    oid("cfg.app.debug"): ("Debug", app), oid("cfg.app.release"): ("Release", app),
}
if WIDGETS:
    configs[oid("cfg.wid.debug")] = ("Debug", widgets)
    configs[oid("cfg.wid.release")] = ("Release", widgets)

exceptions = sync_groups = ""
for name, (path, tree, target, excl) in SYNC.items():
    gid = oid("sync." + name)
    exc_ref = ""
    if excl:
        xid = oid("exc." + name)
        exceptions += (f'\t\t{xid} = {{\n\t\t\tisa = PBXFileSystemSynchronizedBuildFileExceptionSet;\n\t\t\tmembershipExceptions = (\n'
                       + "".join(f"\t\t\t\t{e},\n" for e in excl) + f"\t\t\t);\n\t\t\ttarget = {target};\n\t\t}};\n")
        exc_ref = f"exceptions = ({xid}, ); "
    label = "" if name == path else f"name = {name}; "
    sync_groups += f"\t\t{gid} /* {name} */ = {{isa = PBXFileSystemSynchronizedRootGroup; {exc_ref}{label}path = {path}; sourceTree = {tree}; }};\n"


def groups_for(target):
    return ", ".join(oid("sync." + n) for n, v in SYNC.items() if v[2] == target)


def phase(kind, pid, files="", extra=""):
    return f"\t\t{pid} = {{\n\t\t\tisa = {kind};\n\t\t\tbuildActionMask = 2147483647;\n{extra}\t\t\tfiles = (\n{files}\t\t\t);\n\t\t\trunOnlyForDeploymentPostprocessing = 0;\n\t\t}};\n"


def native(tid, name, cl, phases, groups, product, ptype, deps=""):
    return (f"\t\t{tid} /* {name} */ = {{\n\t\t\tisa = PBXNativeTarget;\n\t\t\tbuildConfigurationList = {cl};\n\t\t\tbuildPhases = (\n"
            + "".join(f"\t\t\t\t{p},\n" for p in phases) + f"\t\t\t);\n\t\t\tbuildRules = (\n\t\t\t);\n\t\t\tdependencies = (\n{deps}\t\t\t);\n"
            f"\t\t\tfileSystemSynchronizedGroups = (\n\t\t\t\t{groups},\n\t\t\t);\n\t\t\tname = {name};\n\t\t\tpackageProductDependencies = (\n\t\t\t);\n"
            f"\t\t\tproductName = {name};\n\t\t\tproductReference = {product};\n\t\t\tproductType = \"{ptype}\";\n\t\t}};\n")


def cfg_list(lid, comment, a, b):
    return (f"\t\t{lid} /* {comment} */ = {{\n\t\t\tisa = XCConfigurationList;\n\t\t\tbuildConfigurations = (\n\t\t\t\t{a} /* Debug */,\n\t\t\t\t{b} /* Release */,\n"
            "\t\t\t);\n\t\t\tdefaultConfigurationIsVisible = 0;\n\t\t\tdefaultConfigurationName = Release;\n\t\t};\n")


app_phases = [oid("app.sources"), oid("app.frameworks"), oid("app.resources")]
phases_text = (phase("PBXSourcesBuildPhase", app_phases[0]) + phase("PBXFrameworksBuildPhase", app_phases[1])
               + phase("PBXResourcesBuildPhase", app_phases[2], f"\t\t\t\t{B_SUPABASE} /* Supabase.json in Resources */,\n"))
build_files = f"\t\t{B_SUPABASE} /* Supabase.json in Resources */ = {{isa = PBXBuildFile; fileRef = {F_SUPABASE}; }};\n"
products = f"\t\t\t\t{P_APP} /* Orbit.app */,\n"
file_refs = (f"\t\t{F_SUPABASE} /* Supabase.json */ = {{isa = PBXFileReference; lastKnownFileType = text.json; name = Supabase.json; path = ../Support/Supabase.json; sourceTree = SOURCE_ROOT; }};\n"
             f"\t\t{P_APP} /* Orbit.app */ = {{isa = PBXFileReference; explicitFileType = wrapper.application; includeInIndex = 0; path = Orbit.app; sourceTree = BUILT_PRODUCTS_DIR; }};\n")
targets = ""
extra_sections = ""
app_deps = ""
if WIDGETS:
    wid_phases = [oid("wid.sources"), oid("wid.frameworks"), oid("wid.resources")]
    embed = oid("app.embed")
    app_phases.append(embed)
    phases_text += (phase("PBXSourcesBuildPhase", wid_phases[0]) + phase("PBXFrameworksBuildPhase", wid_phases[1])
                    + phase("PBXResourcesBuildPhase", wid_phases[2])
                    + phase("PBXCopyFilesBuildPhase", embed, f"\t\t\t\t{B_EMBED} /* OrbitWidgets.appex in Embed Foundation Extensions */,\n",
                            '\t\t\tdstPath = "";\n\t\t\tdstSubfolderSpec = 13;\n\t\t\tname = "Embed Foundation Extensions";\n'))
    build_files += f"\t\t{B_EMBED} /* OrbitWidgets.appex */ = {{isa = PBXBuildFile; fileRef = {P_WID}; settings = {{ATTRIBUTES = (RemoveHeadersOnCopy, ); }}; }};\n"
    products += f"\t\t\t\t{P_WID} /* OrbitWidgets.appex */,\n"
    file_refs += f"\t\t{P_WID} /* OrbitWidgets.appex */ = {{isa = PBXFileReference; explicitFileType = \"wrapper.app-extension\"; includeInIndex = 0; path = OrbitWidgets.appex; sourceTree = BUILT_PRODUCTS_DIR; }};\n"
    proxy, dep = oid("proxy.widgets"), oid("dep.widgets")
    extra_sections += (f"/* Begin PBXContainerItemProxy section */\n\t\t{proxy} = {{\n\t\t\tisa = PBXContainerItemProxy;\n\t\t\tcontainerPortal = {PROJECT};\n"
                       f"\t\t\tproxyType = 1;\n\t\t\tremoteGlobalIDString = {T_WID};\n\t\t\tremoteInfo = OrbitWidgets;\n\t\t}};\n/* End PBXContainerItemProxy section */\n\n"
                       f"/* Begin PBXTargetDependency section */\n\t\t{dep} = {{\n\t\t\tisa = PBXTargetDependency;\n\t\t\ttarget = {T_WID};\n\t\t\ttargetProxy = {proxy};\n\t\t}};\n"
                       "/* End PBXTargetDependency section */\n\n")
    app_deps = f"\t\t\t\t{dep},\n"
    targets += native(T_WID, "OrbitWidgets", oid("cl.wid"), wid_phases, groups_for(T_WID), P_WID, "com.apple.product-type.app-extension")
targets = native(T_APP, "OrbitPhone", oid("cl.app"), app_phases, groups_for(T_APP), P_APP, "com.apple.product-type.application", app_deps) + targets

cfg_text = "".join(f"\t\t{k} /* {n} */ = {{\n\t\t\tisa = XCBuildConfiguration;\n\t\t\tbuildSettings = {{\n{settings_text(s)}\n\t\t\t}};\n\t\t\tname = {n};\n\t\t}};\n"
                   for k, (n, s) in configs.items())
cfg_lists = cfg_list(oid("cl.project"), "Build configuration list for PBXProject", oid("cfg.project.debug"), oid("cfg.project.release"))
cfg_lists += cfg_list(oid("cl.app"), "OrbitPhone", oid("cfg.app.debug"), oid("cfg.app.release"))
if WIDGETS:
    cfg_lists += cfg_list(oid("cl.wid"), "OrbitWidgets", oid("cfg.wid.debug"), oid("cfg.wid.release"))
all_targets = f"\t\t\t\t{T_APP} /* OrbitPhone */,\n" + (f"\t\t\t\t{T_WID} /* OrbitWidgets */,\n" if WIDGETS else "")
attrs = f"\t\t\t\t\t{T_APP} = {{\n\t\t\t\t\t\tCreatedOnToolsVersion = 27.1;\n\t\t\t\t\t}};\n"
if WIDGETS:
    attrs += f"\t\t\t\t\t{T_WID} = {{\n\t\t\t\t\t\tCreatedOnToolsVersion = 27.1;\n\t\t\t\t\t}};\n"
main_children = "".join(f"\t\t\t\t{oid('sync.' + n)} /* {n} */,\n" for n in SYNC) + f"\t\t\t\t{F_SUPABASE} /* Supabase.json */,\n\t\t\t\t{G_PRODUCTS} /* Products */,\n"

text = f"""// !$*UTF8*$!
{{
	archiveVersion = 1;
	classes = {{
	}};
	objectVersion = 77;
	objects = {{

/* Begin PBXBuildFile section */
{build_files}/* End PBXBuildFile section */

{extra_sections}/* Begin PBXFileReference section */
{file_refs}/* End PBXFileReference section */

/* Begin PBXFileSystemSynchronizedBuildFileExceptionSet section */
{exceptions}/* End PBXFileSystemSynchronizedBuildFileExceptionSet section */

/* Begin PBXFileSystemSynchronizedRootGroup section */
{sync_groups}/* End PBXFileSystemSynchronizedRootGroup section */

/* Begin build phases */
{phases_text}/* End build phases */

/* Begin PBXGroup section */
		{G_MAIN} = {{
			isa = PBXGroup;
			children = (
{main_children}			);
			sourceTree = "<group>";
		}};
		{G_PRODUCTS} /* Products */ = {{
			isa = PBXGroup;
			children = (
{products}			);
			name = Products;
			sourceTree = "<group>";
		}};
/* End PBXGroup section */

/* Begin PBXNativeTarget section */
{targets}/* End PBXNativeTarget section */

/* Begin PBXProject section */
		{PROJECT} /* Project object */ = {{
			isa = PBXProject;
			attributes = {{
				BuildIndependentTargetsInParallel = 1;
				LastSwiftUpdateCheck = 2710;
				LastUpgradeCheck = 2710;
				TargetAttributes = {{
{attrs}				}};
			}};
			buildConfigurationList = {oid("cl.project")};
			developmentRegion = en;
			hasScannedForEncodings = 0;
			knownRegions = (
				en,
				Base,
			);
			mainGroup = {G_MAIN};
			minimizedProjectReferenceProxies = 1;
			preferredProjectObjectVersion = 77;
			productRefGroup = {G_PRODUCTS} /* Products */;
			projectDirPath = "";
			projectRoot = "";
			targets = (
{all_targets}			);
		}};
/* End PBXProject section */

/* Begin XCBuildConfiguration section */
{cfg_text}/* End XCBuildConfiguration section */

/* Begin XCConfigurationList section */
{cfg_lists}/* End XCConfigurationList section */
	}};
	rootObject = {PROJECT} /* Project object */;
}}
"""
OUT.parent.mkdir(parents=True, exist_ok=True)
OUT.write_text(text)
print(f"Wrote {OUT.relative_to(ROOT)} (version {VERSION}{', with widgets' if WIDGETS else ', no widgets'})")
