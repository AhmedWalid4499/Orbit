#!/usr/bin/env python3
"""Writes iOS/Orbit.xcodeproj. The iPhone app compiles the Mac app's Models, Design, Services and Views folders directly
(folder references, so new shared files are picked up automatically) plus its own screens in iOS/OrbitPhone.
The home-screen widgets reuse Widgets/OrbitWidgets.swift.

  python3 scripts/gen-ios-project.py               # app + widgets
  python3 scripts/gen-ios-project.py --no-widgets  # app only (Apple doesn't give free accounts the App Group widgets need)
  python3 scripts/gen-ios-project.py --no-watch    # leave out the Apple Watch app

The Apple Watch app (iOS/OrbitWatch, with complications in iOS/OrbitWatchWidgets) is embedded in the iPhone app and
talks to it over WatchConnectivity; iOS/Shared holds the types both sides use.
"""
import hashlib, os, pathlib, subprocess, sys

ROOT = pathlib.Path(__file__).resolve().parent.parent
OUT = ROOT / "iOS" / "Orbit.xcodeproj" / "project.pbxproj"
VERSION = (ROOT / "VERSION").read_text().strip()
# The build number must go up with every App Store upload: the number of commits does, on its own.
BUILD = os.environ.get("ORBIT_BUILD_NUMBER") or subprocess.run(["git", "-C", str(ROOT), "rev-list", "--count", "HEAD"],
                                                               capture_output=True, text=True).stdout.strip() or "1"
TEAM = os.environ.get("ORBIT_TEAM_ID", "Y2K55S3UA9")  # the paid team for the App Store build (scripts/upload-ios.sh)
BUNDLE_ID = "com.ahmedwalid.orbit"
WIDGETS = "--no-widgets" not in sys.argv
HEALTH = "--no-health" not in sys.argv  # Apple Health (read-only); install-iphone.sh drops it if the account can't sign it
WATCH = "--no-watch" not in sys.argv
# The App Store build (scripts/upload-ios.sh): your paid team's signing, with Sign in with Apple, which free accounts can't use.
APP_STORE = "--app-store" in sys.argv

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
T_WATCH, T_WWID = oid("target.watch"), oid("target.watchwidgets")
P_WATCH, P_WWID = oid("product.watch"), oid("product.watchwidgets")
B_EMBED_WATCH, B_EMBED_WWID = oid("build.embed.watch"), oid("build.embed.watchwidgets")
G_MAIN, G_PRODUCTS = oid("group.main"), oid("group.products")
F_SUPABASE, B_SUPABASE = oid("file.supabase"), oid("build.supabase")
# The signed Shortcuts the app shares (scripts/make-shortcuts.py), copied in as a folder.
F_SHORTCUTS, B_SHORTCUTS = oid("file.shortcuts"), oid("build.shortcuts")
# Screenshots for the first-launch tour (TourView), copied in as a folder.
F_TOUR, B_TOUR = oid("file.tour"), oid("build.tour")
B_EMBED = oid("build.embed.widgets")
PROJECT = oid("project")

# name: (path, source tree, targets, files excluded from the first target)
SYNC = {
    "OrbitPhone": ("OrbitPhone", '"<group>"', [T_APP], []),
    "Models": ("../Sources/Orbit/Models", "SOURCE_ROOT", [T_APP], []),
    "Design": ("../Sources/Orbit/Design", "SOURCE_ROOT", [T_APP], []),
    "Services": ("../Sources/Orbit/Services", "SOURCE_ROOT", [T_APP], MAC_ONLY_SERVICES),
    "Views": ("../Sources/Orbit/Views", "SOURCE_ROOT", [T_APP], MAC_ONLY_VIEWS),
    "Shared": ("Shared", '"<group>"', [T_APP] + ([T_WATCH, T_WWID] if WATCH else []), []),
}
if WIDGETS:
    SYNC["Widgets"] = ("../Widgets", "SOURCE_ROOT", [T_WID], ["Info.plist", "OrbitWidgets.entitlements"])
if WATCH:
    SYNC["OrbitWatch"] = ("OrbitWatch", '"<group>"', [T_WATCH], [])
    SYNC["OrbitWatchWidgets"] = ("OrbitWatchWidgets", '"<group>"', [T_WWID], [])

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
    "CODE_SIGN_STYLE": "Automatic", "CURRENT_PROJECT_VERSION": BUILD, "DEVELOPMENT_TEAM": TEAM, "MARKETING_VERSION": VERSION,
    "SUPPORTED_PLATFORMS": "iphoneos iphonesimulator", "SUPPORTS_MACCATALYST": "NO", "SWIFT_EMIT_LOC_STRINGS": "NO", "TARGETED_DEVICE_FAMILY": "1",
}
app = {
    **common_target,
    "ASSETCATALOG_COMPILER_APPICON_NAME": "AppIcon", "ASSETCATALOG_COMPILER_ALTERNATE_APPICON_NAMES": "AppIconPro",  # the Joshu Pro icon
    "ENABLE_PREVIEWS": "YES",
    "GENERATE_INFOPLIST_FILE": "YES",
    "INFOPLIST_FILE": "Support/OrbitPhone-Info.plist", "ENABLE_USER_SCRIPT_SANDBOXING": "NO",  # the shared Google sign-in step reads from your Library
    "INFOPLIST_KEY_CFBundleDisplayName": "Joshu",
    "INFOPLIST_KEY_LSApplicationCategoryType": "public.app-category.productivity",
    "INFOPLIST_KEY_NSCalendarsFullAccessUsageDescription": "Joshu shows your calendar events alongside your tasks and plans.",
    "INFOPLIST_KEY_NSRemindersFullAccessUsageDescription": "Joshu shows and completes your Apple Reminders next to your tasks.",
    "INFOPLIST_KEY_NSMicrophoneUsageDescription": "Joshu listens when you tap the mic, so you can talk to your assistant and plan by voice.",
    "INFOPLIST_KEY_NSSpeechRecognitionUsageDescription": "Joshu turns what you say into text on your iPhone, so your assistant can understand you.",
    "INFOPLIST_KEY_NSCameraUsageDescription": "Take a photo of a receipt or document to send to your assistant.",
    "INFOPLIST_KEY_NSLocationWhenInUseUsageDescription": "Joshu uses your location when you ask for food or places nearby, to find what's close to you.",
    "INFOPLIST_KEY_NSHealthShareUsageDescription": "Joshu reads your steps, sleep, workouts and heart rate to show them next to your habits and day, and to tick off workout habits. It never writes to Health.",
    "INFOPLIST_KEY_UIApplicationSceneManifest_Generation": "YES",
    "INFOPLIST_KEY_UILaunchScreen_Generation": "YES",
    "INFOPLIST_KEY_UISupportedInterfaceOrientations_iPhone": "UIInterfaceOrientationPortrait",
    "LD_RUNPATH_SEARCH_PATHS": "$(inherited) @executable_path/Frameworks",
    "PRODUCT_BUNDLE_IDENTIFIER": BUNDLE_ID,
    "PRODUCT_NAME": "Orbit",
    "JOSHU_SIGN_IN_WITH_APPLE": "YES" if APP_STORE else "NO",
}
if APP_STORE:
    app["CODE_SIGN_ENTITLEMENTS"] = "Support/OrbitPhone-AppStore.entitlements"
elif WIDGETS and HEALTH:
    app["CODE_SIGN_ENTITLEMENTS"] = "Support/OrbitPhone.entitlements"
elif WIDGETS:
    app["CODE_SIGN_ENTITLEMENTS"] = "Support/OrbitPhone-NoHealth.entitlements"
elif HEALTH:
    app["CODE_SIGN_ENTITLEMENTS"] = "Support/OrbitPhone-Health.entitlements"
widgets = {
    **common_target,
    "GENERATE_INFOPLIST_FILE": "YES",
    "INFOPLIST_FILE": "Support/OrbitWidgets-Info.plist",
    "INFOPLIST_KEY_CFBundleDisplayName": "Joshu",
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

watch_common = {
    "CODE_SIGN_STYLE": "Automatic", "CURRENT_PROJECT_VERSION": BUILD, "DEVELOPMENT_TEAM": TEAM, "MARKETING_VERSION": VERSION,
    "SDKROOT": "watchos", "SUPPORTED_PLATFORMS": "watchos watchsimulator", "TARGETED_DEVICE_FAMILY": "4",
    "WATCHOS_DEPLOYMENT_TARGET": "10.0", "SWIFT_EMIT_LOC_STRINGS": "NO", "GENERATE_INFOPLIST_FILE": "YES",
    "INFOPLIST_KEY_CFBundleDisplayName": "Joshu", "SKIP_INSTALL": "YES",
}
watch_app = {
    **watch_common,
    "ASSETCATALOG_COMPILER_APPICON_NAME": "AppIcon",
    "INFOPLIST_KEY_WKCompanionAppBundleIdentifier": BUNDLE_ID,
    "INFOPLIST_KEY_WKRunsIndependentlyOfCompanionApp": "NO",
    "INFOPLIST_KEY_UISupportedInterfaceOrientations": "UIInterfaceOrientationPortrait UIInterfaceOrientationPortraitUpsideDown",
    "LD_RUNPATH_SEARCH_PATHS": "$(inherited) @executable_path/Frameworks",
    "PRODUCT_BUNDLE_IDENTIFIER": BUNDLE_ID + ".watchkitapp",
    "PRODUCT_NAME": "OrbitWatch",
}
watch_widgets = {
    **watch_common,
    "INFOPLIST_FILE": "Support/OrbitWidgets-Info.plist",
    "LD_RUNPATH_SEARCH_PATHS": "$(inherited) @executable_path/Frameworks @executable_path/../../Frameworks",
    "PRODUCT_BUNDLE_IDENTIFIER": BUNDLE_ID + ".watchkitapp.widgets",
    "PRODUCT_NAME": "OrbitWatchWidgets",
}
if WIDGETS:  # the complications read the watch app's data through the app group
    watch_app["CODE_SIGN_ENTITLEMENTS"] = "Support/OrbitWatch.entitlements"
    watch_widgets["CODE_SIGN_ENTITLEMENTS"] = "Support/OrbitWatchWidgets.entitlements"
if WATCH:
    for key, (n, cfg) in {"watch": ("OrbitWatch", watch_app), "wwid": ("OrbitWatchWidgets", watch_widgets)}.items():
        configs[oid(f"cfg.{key}.debug")] = ("Debug", cfg)
        configs[oid(f"cfg.{key}.release")] = ("Release", cfg)

exceptions = sync_groups = ""
for name, (path, tree, targets_, excl) in SYNC.items():
    target = targets_[0]
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
    return ", ".join(oid("sync." + n) for n, v in SYNC.items() if target in v[2])


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


app_phases = [oid("app.sources"), oid("app.frameworks"), oid("app.resources"), oid("app.google")]
phases_text = (phase("PBXSourcesBuildPhase", app_phases[0]) + phase("PBXFrameworksBuildPhase", app_phases[1])
               + phase("PBXResourcesBuildPhase", app_phases[2], f"\t\t\t\t{B_SUPABASE} /* Supabase.json in Resources */,\n\t\t\t\t{B_SHORTCUTS} /* Shortcuts in Resources */,\n\t\t\t\t{B_TOUR} /* Tour in Resources */,\n")
               # If the owner chose (in Joshu's Mac Settings) to share their Google setup, build it in, as build-app.sh does on the Mac.
               + phase("PBXShellScriptBuildPhase", oid("app.google"), "",
                       "\t\t\talwaysOutOfDate = 1;\n\t\t\tname = \"Shared Google sign-in\";\n\t\t\tshellPath = /bin/sh;\n"
                       "\t\t\tshellScript = \"F=\\\"$HOME/Library/Application Support/Orbit/shared-google-client.json\\\"; "
                       "if [ -f \\\"$F\\\" ]; then cp \\\"$F\\\" \\\"$TARGET_BUILD_DIR/$UNLOCALIZED_RESOURCES_FOLDER_PATH/GoogleClient.json\\\"; fi\\n\";\n"))
build_files = (f"\t\t{B_SUPABASE} /* Supabase.json in Resources */ = {{isa = PBXBuildFile; fileRef = {F_SUPABASE}; }};\n"
               f"\t\t{B_SHORTCUTS} /* Shortcuts in Resources */ = {{isa = PBXBuildFile; fileRef = {F_SHORTCUTS}; }};\n"
               f"\t\t{B_TOUR} /* Tour in Resources */ = {{isa = PBXBuildFile; fileRef = {F_TOUR}; }};\n")
products = f"\t\t\t\t{P_APP} /* Orbit.app */,\n"
file_refs = (f"\t\t{F_TOUR} /* Tour */ = {{isa = PBXFileReference; lastKnownFileType = folder; name = Tour; path = ../Support/Tour; sourceTree = SOURCE_ROOT; }};\n"
             f"\t\t{F_SHORTCUTS} /* Shortcuts */ = {{isa = PBXFileReference; lastKnownFileType = folder; name = Shortcuts; path = Support/Shortcuts; sourceTree = SOURCE_ROOT; }};\n"
             f"\t\t{F_SUPABASE} /* Supabase.json */ = {{isa = PBXFileReference; lastKnownFileType = text.json; name = Supabase.json; path = ../Support/Supabase.json; sourceTree = SOURCE_ROOT; }};\n"
             f"\t\t{P_APP} /* Orbit.app */ = {{isa = PBXFileReference; explicitFileType = wrapper.application; includeInIndex = 0; path = Orbit.app; sourceTree = BUILT_PRODUCTS_DIR; }};\n")
targets = ""
proxies = deps_text = ""
app_deps = ""


def depend(name, target):
    """A target dependency on `target`; returns the line for the dependent target's list."""
    global proxies, deps_text
    proxy, dep = oid("proxy." + name), oid("dep." + name)
    proxies += (f"\t\t{proxy} = {{\n\t\t\tisa = PBXContainerItemProxy;\n\t\t\tcontainerPortal = {PROJECT};\n"
                f"\t\t\tproxyType = 1;\n\t\t\tremoteGlobalIDString = {target};\n\t\t\tremoteInfo = {name};\n\t\t}};\n")
    deps_text += f"\t\t{dep} = {{\n\t\t\tisa = PBXTargetDependency;\n\t\t\ttarget = {target};\n\t\t\ttargetProxy = {proxy};\n\t\t}};\n"
    return f"\t\t\t\t{dep},\n"


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
    app_deps += depend("OrbitWidgets", T_WID)
    targets += native(T_WID, "OrbitWidgets", oid("cl.wid"), wid_phases, groups_for(T_WID), P_WID, "com.apple.product-type.app-extension")
if WATCH:
    w_phases = [oid("watch.sources"), oid("watch.frameworks"), oid("watch.resources"), oid("watch.embed")]
    ww_phases = [oid("wwid.sources"), oid("wwid.frameworks"), oid("wwid.resources")]
    embed_watch = oid("app.embed.watch")
    app_phases.append(embed_watch)
    phases_text += (phase("PBXSourcesBuildPhase", w_phases[0]) + phase("PBXFrameworksBuildPhase", w_phases[1])
                    + phase("PBXResourcesBuildPhase", w_phases[2])
                    + phase("PBXCopyFilesBuildPhase", w_phases[3], f"\t\t\t\t{B_EMBED_WWID} /* OrbitWatchWidgets.appex in Embed Foundation Extensions */,\n",
                            '\t\t\tdstPath = "";\n\t\t\tdstSubfolderSpec = 13;\n\t\t\tname = "Embed Foundation Extensions";\n')
                    + phase("PBXSourcesBuildPhase", ww_phases[0]) + phase("PBXFrameworksBuildPhase", ww_phases[1])
                    + phase("PBXResourcesBuildPhase", ww_phases[2])
                    + phase("PBXCopyFilesBuildPhase", embed_watch, f"\t\t\t\t{B_EMBED_WATCH} /* OrbitWatch.app in Embed Watch Content */,\n",
                            '\t\t\tdstPath = "$(CONTENTS_FOLDER_PATH)/Watch";\n\t\t\tdstSubfolderSpec = 16;\n\t\t\tname = "Embed Watch Content";\n'))
    build_files += (f"\t\t{B_EMBED_WATCH} /* OrbitWatch.app */ = {{isa = PBXBuildFile; fileRef = {P_WATCH}; settings = {{ATTRIBUTES = (RemoveHeadersOnCopy, ); }}; }};\n"
                    f"\t\t{B_EMBED_WWID} /* OrbitWatchWidgets.appex */ = {{isa = PBXBuildFile; fileRef = {P_WWID}; settings = {{ATTRIBUTES = (RemoveHeadersOnCopy, ); }}; }};\n")
    products += f"\t\t\t\t{P_WATCH} /* OrbitWatch.app */,\n\t\t\t\t{P_WWID} /* OrbitWatchWidgets.appex */,\n"
    file_refs += (f"\t\t{P_WATCH} /* OrbitWatch.app */ = {{isa = PBXFileReference; explicitFileType = wrapper.application; includeInIndex = 0; path = OrbitWatch.app; sourceTree = BUILT_PRODUCTS_DIR; }};\n"
                  f"\t\t{P_WWID} /* OrbitWatchWidgets.appex */ = {{isa = PBXFileReference; explicitFileType = \"wrapper.app-extension\"; includeInIndex = 0; path = OrbitWatchWidgets.appex; sourceTree = BUILT_PRODUCTS_DIR; }};\n")
    watch_deps = depend("OrbitWatchWidgets", T_WWID)
    app_deps += depend("OrbitWatch", T_WATCH)
    targets += native(T_WATCH, "OrbitWatch", oid("cl.watch"), w_phases, groups_for(T_WATCH), P_WATCH, "com.apple.product-type.application", watch_deps)
    targets += native(T_WWID, "OrbitWatchWidgets", oid("cl.wwid"), ww_phases, groups_for(T_WWID), P_WWID, "com.apple.product-type.app-extension")
extra_sections = ""
if proxies:
    extra_sections = (f"/* Begin PBXContainerItemProxy section */\n{proxies}/* End PBXContainerItemProxy section */\n\n"
                      f"/* Begin PBXTargetDependency section */\n{deps_text}/* End PBXTargetDependency section */\n\n")
targets = native(T_APP, "OrbitPhone", oid("cl.app"), app_phases, groups_for(T_APP), P_APP, "com.apple.product-type.application", app_deps) + targets

cfg_text = "".join(f"\t\t{k} /* {n} */ = {{\n\t\t\tisa = XCBuildConfiguration;\n\t\t\tbuildSettings = {{\n{settings_text(s)}\n\t\t\t}};\n\t\t\tname = {n};\n\t\t}};\n"
                   for k, (n, s) in configs.items())
cfg_lists = cfg_list(oid("cl.project"), "Build configuration list for PBXProject", oid("cfg.project.debug"), oid("cfg.project.release"))
cfg_lists += cfg_list(oid("cl.app"), "OrbitPhone", oid("cfg.app.debug"), oid("cfg.app.release"))
if WIDGETS:
    cfg_lists += cfg_list(oid("cl.wid"), "OrbitWidgets", oid("cfg.wid.debug"), oid("cfg.wid.release"))
if WATCH:
    cfg_lists += cfg_list(oid("cl.watch"), "OrbitWatch", oid("cfg.watch.debug"), oid("cfg.watch.release"))
    cfg_lists += cfg_list(oid("cl.wwid"), "OrbitWatchWidgets", oid("cfg.wwid.debug"), oid("cfg.wwid.release"))
target_ids = [(T_APP, "OrbitPhone")] + ([(T_WID, "OrbitWidgets")] if WIDGETS else []) + ([(T_WATCH, "OrbitWatch"), (T_WWID, "OrbitWatchWidgets")] if WATCH else [])
all_targets = "".join(f"\t\t\t\t{t} /* {n} */,\n" for t, n in target_ids)
attrs = "".join(f"\t\t\t\t\t{t} = {{\n\t\t\t\t\t\tCreatedOnToolsVersion = 27.1;\n\t\t\t\t\t}};\n" for t, _ in target_ids)
main_children = "".join(f"\t\t\t\t{oid('sync.' + n)} /* {n} */,\n" for n in SYNC) + f"\t\t\t\t{F_SUPABASE} /* Supabase.json */,\n\t\t\t\t{F_SHORTCUTS} /* Shortcuts */,\n\t\t\t\t{F_TOUR} /* Tour */,\n\t\t\t\t{G_PRODUCTS} /* Products */,\n"

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
