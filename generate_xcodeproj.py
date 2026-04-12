#!/usr/bin/env python3
"""
Generates MacSnitch.xcodeproj/project.pbxproj from scratch.
No Ruby or xcodeproj gem required.
"""

import os, uuid, textwrap

ROOT = "/home/claude/macsnitch"

# ── Deterministic IDs (so the file is stable across re-runs) ─────────────────

def uid(seed: str) -> str:
    """24-char uppercase hex deterministic ID from a seed string."""
    import hashlib
    h = hashlib.md5(seed.encode()).hexdigest().upper()
    return h[:24]

# ── File tree ─────────────────────────────────────────────────────────────────

APP_SOURCES = [
    "MacSnitchApp/App.swift",
    "MacSnitchApp/Models/AppStatsModel.swift",
    "MacSnitchApp/Services/ConnectionLogger.swift",
    "MacSnitchApp/Services/ConnectionPromptCoordinator.swift",
    "MacSnitchApp/Services/DatabaseMigrator.swift",
    "MacSnitchApp/Services/ExtensionClient.swift",
    "MacSnitchApp/Services/FilterExtensionManager.swift",
    "MacSnitchApp/Services/NotificationManager.swift",
    "MacSnitchApp/Services/RuleImportExport.swift",
    "MacSnitchApp/Services/RuleStore.swift",
    "MacSnitchApp/Services/XPCServer.swift",
    "MacSnitchApp/Views/ConnectionLogView.swift",
    "MacSnitchApp/Views/ConnectionPromptView.swift",
    "MacSnitchApp/Views/MainContentView.swift",
    "MacSnitchApp/Views/RuleCreatorView.swift",
    "MacSnitchApp/Views/RulesView.swift",
    "MacSnitchApp/Views/StatusView.swift",
    "Shared/IPCMessages.swift",
]

EXT_SOURCES = [
    "NetworkExtension/main.swift",
    "NetworkExtension/DNSResolver.swift",
    "NetworkExtension/FilterControlProvider.swift",
    "NetworkExtension/FilterProvider.swift",
    "NetworkExtension/RuleCache.swift",
    "Shared/IPCMessages.swift",
]

TEST_SOURCES = [
    "Tests/MacSnitchTests.swift",
    "Shared/IPCMessages.swift",
]

ALL_SOURCES = sorted(set(APP_SOURCES + EXT_SOURCES + TEST_SOURCES))

# ── IDs ───────────────────────────────────────────────────────────────────────

PROJECT_ID         = uid("project")
APP_TARGET_ID      = uid("target.app")
EXT_TARGET_ID      = uid("target.ext")
TEST_TARGET_ID     = uid("target.test")

APP_SOURCES_PHASE  = uid("phase.app.sources")
EXT_SOURCES_PHASE  = uid("phase.ext.sources")
TEST_SOURCES_PHASE = uid("phase.test.sources")
APP_FRAMEWORKS     = uid("phase.app.frameworks")
EXT_FRAMEWORKS     = uid("phase.ext.frameworks")
APP_RESOURCES      = uid("phase.app.resources")
APP_EMBED_EXT      = uid("phase.app.embed")
TEST_FRAMEWORKS    = uid("phase.test.frameworks")

APP_DEBUG_CFG      = uid("cfg.app.debug")
APP_RELEASE_CFG    = uid("cfg.app.release")
EXT_DEBUG_CFG      = uid("cfg.ext.debug")
EXT_RELEASE_CFG    = uid("cfg.ext.release")
TEST_DEBUG_CFG     = uid("cfg.test.debug")
TEST_RELEASE_CFG   = uid("cfg.test.release")
PROJ_DEBUG_CFG     = uid("cfg.proj.debug")
PROJ_RELEASE_CFG   = uid("cfg.proj.release")

APP_CFG_LIST       = uid("cfglist.app")
EXT_CFG_LIST       = uid("cfglist.ext")
TEST_CFG_LIST      = uid("cfglist.test")
PROJ_CFG_LIST      = uid("cfglist.proj")

MAIN_GROUP         = uid("group.main")
APP_GROUP          = uid("group.app")
APP_MODELS_GROUP   = uid("group.app.models")
APP_SERVICES_GROUP = uid("group.app.services")
APP_VIEWS_GROUP    = uid("group.app.views")
EXT_GROUP          = uid("group.ext")
SHARED_GROUP       = uid("group.shared")
TEST_GROUP         = uid("group.test")
CFG_GROUP          = uid("group.cfg")
PRODUCTS_GROUP     = uid("group.products")

# Product references
APP_PRODUCT_REF    = uid("product.app")
EXT_PRODUCT_REF    = uid("product.ext")
TEST_PRODUCT_REF   = uid("product.test")
EXT_EMBED_BUILD    = uid("buildfile.embed.ext")

def file_ref_id(path): return uid(f"ref.{path}")
def build_file_id(path, target): return uid(f"bf.{path}.{target}")

# ── Framework IDs ─────────────────────────────────────────────────────────────

FRAMEWORKS = {
    "NetworkExtension.framework": uid("fw.networkextension"),
    "SystemExtensions.framework": uid("fw.systemextensions"),
    "SwiftUI.framework":          uid("fw.swiftui"),
    "UserNotifications.framework":uid("fw.usernotifications"),
    "AppKit.framework":           uid("fw.appkit"),
    "Foundation.framework":       uid("fw.foundation"),
}

# ── Helpers ───────────────────────────────────────────────────────────────────

def indent(text, n=2):
    return textwrap.indent(text, "\t" * n)

def section(name, content):
    return f"\n/* Begin {name} section */\n{content}/* End {name} section */\n"

# ── PBXBuildFile ──────────────────────────────────────────────────────────────

def build_files():
    lines = []
    for path in APP_SOURCES:
        bid = build_file_id(path, "app")
        rid = file_ref_id(path)
        name = os.path.basename(path)
        lines.append(f"\t\t{bid} /* {name} in Sources */ = {{isa = PBXBuildFile; fileRef = {rid} /* {name} */; }};")
    for path in EXT_SOURCES:
        if path in APP_SOURCES:
            continue  # shared files get separate build file entries
        bid = build_file_id(path, "ext")
        rid = file_ref_id(path)
        name = os.path.basename(path)
        lines.append(f"\t\t{bid} /* {name} in Sources */ = {{isa = PBXBuildFile; fileRef = {rid} /* {name} */; }};")
    # Shared in ext
    bid = build_file_id("Shared/IPCMessages.swift", "ext")
    rid = file_ref_id("Shared/IPCMessages.swift")
    lines.append(f"\t\t{bid} /* IPCMessages.swift in Sources (ext) */ = {{isa = PBXBuildFile; fileRef = {rid} /* IPCMessages.swift */; }};")
    # Tests
    for path in TEST_SOURCES:
        bid = build_file_id(path, "test")
        rid = file_ref_id(path)
        name = os.path.basename(path)
        lines.append(f"\t\t{bid} /* {name} in Sources (test) */ = {{isa = PBXBuildFile; fileRef = {rid} /* {name} */; }};")
    # Frameworks (app)
    for fw, fid in FRAMEWORKS.items():
        bid = build_file_id(fw, "app")
        lines.append(f"\t\t{bid} /* {fw} in Frameworks */ = {{isa = PBXBuildFile; fileRef = {fid} /* {fw} */; }};")
    # Extension embed
    lines.append(f"\t\t{EXT_EMBED_BUILD} /* MacSnitchExtension.systemextension in Embed */ = {{isa = PBXBuildFile; fileRef = {EXT_PRODUCT_REF}; settings = {{ATTRIBUTES = (RemoveHeadersOnCopy, ); }}; }};")
    return section("PBXBuildFile", "\n".join(lines) + "\n")

# ── PBXCopyFilesBuildPhase ────────────────────────────────────────────────────

def copy_files_phase():
    return section("PBXCopyFilesBuildPhase", f"""\
\t\t{APP_EMBED_EXT} /* Embed System Extensions */ = {{
\t\t\tisa = PBXCopyFilesBuildPhase;
\t\t\tbuildActionMask = 2147483647;
\t\t\tdstPath = "";
\t\t\tdstSubfolderSpec = 16;
\t\t\tfiles = (
\t\t\t\t{EXT_EMBED_BUILD} /* MacSnitchExtension.systemextension in Embed */,
\t\t\t);
\t\t\tname = "Embed System Extensions";
\t\t\trunOnlyForDeploymentPostprocessing = 0;
\t\t}};
""")

# ── PBXFileReference ──────────────────────────────────────────────────────────

def file_references():
    lines = []
    for path in ALL_SOURCES:
        rid = file_ref_id(path)
        name = os.path.basename(path)
        lines.append(f"\t\t{rid} /* {name} */ = {{isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = {name}; sourceTree = \"<group>\"; }};")
    # Framework refs
    for fw, fid in FRAMEWORKS.items():
        lines.append(f"\t\t{fid} /* {fw} */ = {{isa = PBXFileReference; lastKnownFileType = wrapper.framework; name = {fw}; path = System/Library/Frameworks/{fw}; sourceTree = SDKROOT; }};")
    # Products
    lines.append(f"\t\t{APP_PRODUCT_REF} /* MacSnitch.app */ = {{isa = PBXFileReference; explicitFileType = wrapper.application; includeInIndex = 0; path = MacSnitch.app; sourceTree = BUILT_PRODUCTS_DIR; }};")
    lines.append(f"\t\t{EXT_PRODUCT_REF} /* MacSnitchExtension.systemextension */ = {{isa = PBXFileReference; explicitFileType = wrapper.system-extension; includeInIndex = 0; path = MacSnitchExtension.systemextension; sourceTree = BUILT_PRODUCTS_DIR; }};")
    lines.append(f"\t\t{TEST_PRODUCT_REF} /* MacSnitchTests.xctest */ = {{isa = PBXFileReference; explicitFileType = wrapper.cfbundle; includeInIndex = 0; path = MacSnitchTests.xctest; sourceTree = BUILT_PRODUCTS_DIR; }};")
    # Config files
    for cfg in ["MacSnitchApp.entitlements", "MacSnitchExtension.entitlements",
                "MacSnitchApp-Info.plist", "MacSnitchExtension-Info.plist", "ExportOptions.plist"]:
        cid = uid(f"ref.cfg.{cfg}")
        ext = "text.plist.entitlements" if cfg.endswith(".entitlements") else "text.plist.xml"
        lines.append(f"\t\t{cid} /* {cfg} */ = {{isa = PBXFileReference; lastKnownFileType = {ext}; path = {cfg}; sourceTree = \"<group>\"; }};")
    return section("PBXFileReference", "\n".join(lines) + "\n")

# ── PBXFrameworksBuildPhase ───────────────────────────────────────────────────

def frameworks_phases():
    fw_lines = "\n".join(
        f"\t\t\t\t{build_file_id(fw,'app')} /* {fw} in Frameworks */,"
        for fw in FRAMEWORKS
    )
    return section("PBXFrameworksBuildPhase", f"""\
\t\t{APP_FRAMEWORKS} /* Frameworks */ = {{
\t\t\tisa = PBXFrameworksBuildPhase;
\t\t\tbuildActionMask = 2147483647;
\t\t\tfiles = (
{fw_lines}
\t\t\t);
\t\t\trunOnlyForDeploymentPostprocessing = 0;
\t\t}};
\t\t{EXT_FRAMEWORKS} /* Frameworks (ext) */ = {{
\t\t\tisa = PBXFrameworksBuildPhase;
\t\t\tbuildActionMask = 2147483647;
\t\t\tfiles = (
\t\t\t);
\t\t\trunOnlyForDeploymentPostprocessing = 0;
\t\t}};
\t\t{TEST_FRAMEWORKS} /* Frameworks (test) */ = {{
\t\t\tisa = PBXFrameworksBuildPhase;
\t\t\tbuildActionMask = 2147483647;
\t\t\tfiles = (
\t\t\t);
\t\t\trunOnlyForDeploymentPostprocessing = 0;
\t\t}};
""")

# ── PBXGroup ─────────────────────────────────────────────────────────────────

def groups():
    def grp_files(paths):
        return "\n".join(f"\t\t\t\t{file_ref_id(p)} /* {os.path.basename(p)} */," for p in paths)

    # Subfolder groups
    models_paths   = [p for p in APP_SOURCES if p.startswith("MacSnitchApp/Models/")]
    services_paths = [p for p in APP_SOURCES if p.startswith("MacSnitchApp/Services/")]
    views_paths    = [p for p in APP_SOURCES if p.startswith("MacSnitchApp/Views/")]
    root_app_paths = [p for p in APP_SOURCES if p.startswith("MacSnitchApp/") and "/" not in p[len("MacSnitchApp/"):]]
    ext_paths      = [p for p in ALL_SOURCES if p.startswith("NetworkExtension/")]
    shared_paths   = [p for p in ALL_SOURCES if p.startswith("Shared/")]
    test_paths     = [p for p in ALL_SOURCES if p.startswith("Tests/")]
    cfg_files      = ["MacSnitchApp.entitlements", "MacSnitchExtension.entitlements",
                      "MacSnitchApp-Info.plist", "MacSnitchExtension-Info.plist", "ExportOptions.plist"]

    return section("PBXGroup", f"""\
\t\t{MAIN_GROUP} = {{
\t\t\tisa = PBXGroup;
\t\t\tchildren = (
\t\t\t\t{APP_GROUP} /* MacSnitchApp */,
\t\t\t\t{EXT_GROUP} /* NetworkExtension */,
\t\t\t\t{SHARED_GROUP} /* Shared */,
\t\t\t\t{TEST_GROUP} /* Tests */,
\t\t\t\t{CFG_GROUP} /* Configuration */,
\t\t\t\t{PRODUCTS_GROUP} /* Products */,
\t\t\t);
\t\t\tsourceTree = "<group>";
\t\t}};
\t\t{PRODUCTS_GROUP} /* Products */ = {{
\t\t\tisa = PBXGroup;
\t\t\tchildren = (
\t\t\t\t{APP_PRODUCT_REF} /* MacSnitch.app */,
\t\t\t\t{EXT_PRODUCT_REF} /* MacSnitchExtension.systemextension */,
\t\t\t\t{TEST_PRODUCT_REF} /* MacSnitchTests.xctest */,
\t\t\t);
\t\t\tname = Products;
\t\t\tsourceTree = "<group>";
\t\t}};
\t\t{APP_GROUP} /* MacSnitchApp */ = {{
\t\t\tisa = PBXGroup;
\t\t\tchildren = (
{grp_files(root_app_paths)}
\t\t\t\t{APP_MODELS_GROUP} /* Models */,
\t\t\t\t{APP_SERVICES_GROUP} /* Services */,
\t\t\t\t{APP_VIEWS_GROUP} /* Views */,
\t\t\t);
\t\t\tpath = MacSnitchApp;
\t\t\tsourceTree = "<group>";
\t\t}};
\t\t{APP_MODELS_GROUP} /* Models */ = {{
\t\t\tisa = PBXGroup;
\t\t\tchildren = (
{grp_files(models_paths)}
\t\t\t);
\t\t\tpath = Models;
\t\t\tsourceTree = "<group>";
\t\t}};
\t\t{APP_SERVICES_GROUP} /* Services */ = {{
\t\t\tisa = PBXGroup;
\t\t\tchildren = (
{grp_files(services_paths)}
\t\t\t);
\t\t\tpath = Services;
\t\t\tsourceTree = "<group>";
\t\t}};
\t\t{APP_VIEWS_GROUP} /* Views */ = {{
\t\t\tisa = PBXGroup;
\t\t\tchildren = (
{grp_files(views_paths)}
\t\t\t);
\t\t\tpath = Views;
\t\t\tsourceTree = "<group>";
\t\t}};
\t\t{EXT_GROUP} /* NetworkExtension */ = {{
\t\t\tisa = PBXGroup;
\t\t\tchildren = (
{grp_files(ext_paths)}
\t\t\t);
\t\t\tpath = NetworkExtension;
\t\t\tsourceTree = "<group>";
\t\t}};
\t\t{SHARED_GROUP} /* Shared */ = {{
\t\t\tisa = PBXGroup;
\t\t\tchildren = (
{grp_files(shared_paths)}
\t\t\t);
\t\t\tpath = Shared;
\t\t\tsourceTree = "<group>";
\t\t}};
\t\t{TEST_GROUP} /* Tests */ = {{
\t\t\tisa = PBXGroup;
\t\t\tchildren = (
{grp_files(test_paths)}
\t\t\t);
\t\t\tpath = Tests;
\t\t\tsourceTree = "<group>";
\t\t}};
\t\t{CFG_GROUP} /* Configuration */ = {{
\t\t\tisa = PBXGroup;
\t\t\tchildren = (
{chr(10).join(f"            {uid(f'ref.cfg.{c}')} /* {c} */," for c in cfg_files)}
\t\t\t);
\t\t\tpath = Configuration;
\t\t\tsourceTree = "<group>";
\t\t}};
""")

# ── PBXNativeTarget ───────────────────────────────────────────────────────────

def native_targets():
    app_src_files  = "\n".join(f"\t\t\t\t{build_file_id(p,'app')} /* {os.path.basename(p)} in Sources */," for p in APP_SOURCES)
    ext_src_unique = [p for p in EXT_SOURCES if p != "Shared/IPCMessages.swift"]
    ext_src_files  = "\n".join(f"\t\t\t\t{build_file_id(p,'ext')} /* {os.path.basename(p)} in Sources */," for p in ext_src_unique)
    ext_src_files += f"\n\t\t\t\t{build_file_id('Shared/IPCMessages.swift','ext')} /* IPCMessages.swift in Sources */,"
    test_src_files = "\n".join(f"\t\t\t\t{build_file_id(p,'test')} /* {os.path.basename(p)} in Sources */," for p in TEST_SOURCES)

    return section("PBXNativeTarget", f"""\
\t\t{APP_TARGET_ID} /* MacSnitchApp */ = {{
\t\t\tisa = PBXNativeTarget;
\t\t\tbuildConfigurationList = {APP_CFG_LIST} /* Build configuration list for PBXNativeTarget "MacSnitchApp" */;
\t\t\tbuildPhases = (
\t\t\t\t{APP_SOURCES_PHASE} /* Sources */,
\t\t\t\t{APP_FRAMEWORKS} /* Frameworks */,
\t\t\t\t{APP_RESOURCES} /* Resources */,
\t\t\t\t{APP_EMBED_EXT} /* Embed System Extensions */,
\t\t\t);
\t\t\tbuildRules = (
\t\t\t);
\t\t\tdependencies = (
\t\t\t);
\t\t\tname = MacSnitchApp;
\t\t\tpackageProductDependencies = (
\t\t\t);
\t\t\tproductName = MacSnitchApp;
\t\t\tproductReference = {APP_PRODUCT_REF} /* MacSnitch.app */;
\t\t\tproductType = "com.apple.product-type.application";
\t\t}};
\t\t{EXT_TARGET_ID} /* MacSnitchExtension */ = {{
\t\t\tisa = PBXNativeTarget;
\t\t\tbuildConfigurationList = {EXT_CFG_LIST} /* Build configuration list for PBXNativeTarget "MacSnitchExtension" */;
\t\t\tbuildPhases = (
\t\t\t\t{EXT_SOURCES_PHASE} /* Sources */,
\t\t\t\t{EXT_FRAMEWORKS} /* Frameworks */,
\t\t\t);
\t\t\tbuildRules = (
\t\t\t);
\t\t\tdependencies = (
\t\t\t);
\t\t\tname = MacSnitchExtension;
\t\t\tproductName = MacSnitchExtension;
\t\t\tproductReference = {EXT_PRODUCT_REF} /* MacSnitchExtension.systemextension */;
\t\t\tproductType = "com.apple.product-type.system-extension";
\t\t}};
\t\t{TEST_TARGET_ID} /* MacSnitchTests */ = {{
\t\t\tisa = PBXNativeTarget;
\t\t\tbuildConfigurationList = {TEST_CFG_LIST};
\t\t\tbuildPhases = (
\t\t\t\t{TEST_SOURCES_PHASE} /* Sources */,
\t\t\t\t{TEST_FRAMEWORKS} /* Frameworks */,
\t\t\t);
\t\t\tbuildRules = (
\t\t\t);
\t\t\tdependencies = (
\t\t\t);
\t\t\tname = MacSnitchTests;
\t\t\tproductName = MacSnitchTests;
\t\t\tproductReference = {TEST_PRODUCT_REF} /* MacSnitchTests.xctest */;
\t\t\tproductType = "com.apple.product-type.bundle.unit-test";
\t\t}};
""") + section("PBXSourcesBuildPhase", f"""\
\t\t{APP_SOURCES_PHASE} /* Sources */ = {{
\t\t\tisa = PBXSourcesBuildPhase;
\t\t\tbuildActionMask = 2147483647;
\t\t\tfiles = (
{app_src_files}
\t\t\t);
\t\t\trunOnlyForDeploymentPostprocessing = 0;
\t\t}};
\t\t{EXT_SOURCES_PHASE} /* Sources (ext) */ = {{
\t\t\tisa = PBXSourcesBuildPhase;
\t\t\tbuildActionMask = 2147483647;
\t\t\tfiles = (
{ext_src_files}
\t\t\t);
\t\t\trunOnlyForDeploymentPostprocessing = 0;
\t\t}};
\t\t{TEST_SOURCES_PHASE} /* Sources (test) */ = {{
\t\t\tisa = PBXSourcesBuildPhase;
\t\t\tbuildActionMask = 2147483647;
\t\t\tfiles = (
{test_src_files}
\t\t\t);
\t\t\trunOnlyForDeploymentPostprocessing = 0;
\t\t}};
""") + section("PBXResourcesBuildPhase", f"""\
\t\t{APP_RESOURCES} /* Resources */ = {{
\t\t\tisa = PBXResourcesBuildPhase;
\t\t\tbuildActionMask = 2147483647;
\t\t\tfiles = (
\t\t\t);
\t\t\trunOnlyForDeploymentPostprocessing = 0;
\t\t}};
""")

# ── PBXProject ────────────────────────────────────────────────────────────────

def project():
    return section("PBXProject", f"""\
\t\t{PROJECT_ID} /* Project object */ = {{
\t\t\tisa = PBXProject;
\t\t\tattributes = {{
\t\t\t\tBuildIndependentTargetsInParallel = 1;
\t\t\t\tLastSwiftUpdateCheck = 1500;
\t\t\t\tLastUpgradeCheck = 1500;
\t\t\t\tTargetAttributes = {{
\t\t\t\t\t{APP_TARGET_ID} = {{
\t\t\t\t\t\tCreatedOnToolsVersion = 15.0;
\t\t\t\t\t}};
\t\t\t\t\t{EXT_TARGET_ID} = {{
\t\t\t\t\t\tCreatedOnToolsVersion = 15.0;
\t\t\t\t\t}};
\t\t\t\t\t{TEST_TARGET_ID} = {{
\t\t\t\t\t\tCreatedOnToolsVersion = 15.0;
\t\t\t\t\t\tTestTargetID = {APP_TARGET_ID};
\t\t\t\t\t}};
\t\t\t\t}};
\t\t\t}};
\t\t\tbuildConfigurationList = {PROJ_CFG_LIST} /* Build configuration list for PBXProject "MacSnitch" */;
\t\t\tcompatibilityVersion = "Xcode 15.0";
\t\t\tdevelopmentRegion = en;
\t\t\thasScannedForEncodings = 0;
\t\t\tknownRegions = (
\t\t\t\ten,
\t\t\t\tBase,
\t\t\t);
\t\t\tmainGroup = {MAIN_GROUP};
\t\t\tproductRefGroup = {PRODUCTS_GROUP} /* Products */;
\t\t\tprojectDirPath = "";
\t\t\tprojectRoot = "";
\t\t\ttargets = (
\t\t\t\t{APP_TARGET_ID} /* MacSnitchApp */,
\t\t\t\t{EXT_TARGET_ID} /* MacSnitchExtension */,
\t\t\t\t{TEST_TARGET_ID} /* MacSnitchTests */,
\t\t\t);
\t\t}};
""")

# ── XCBuildConfiguration ──────────────────────────────────────────────────────

BASE = """
\t\t\t\tALWAYS_SEARCH_USER_PATHS = NO;
\t\t\t\tCLANG_ANALYZER_NONNULL = YES;
\t\t\t\tCLANG_ANALYZER_NUMBER_OBJECT_CONVERSION = YES_AGGRESSIVE;
\t\t\t\tCLANG_CXX_LANGUAGE_STANDARD = "gnu++20";
\t\t\t\tCLANG_ENABLE_MODULES = YES;
\t\t\t\tCLANG_ENABLE_OBJC_ARC = YES;
\t\t\t\tCLANG_WARN_BLOCK_CAPTURE_AUTORELEASING = YES;
\t\t\t\tCLANG_WARN_BOOL_CONVERSION = YES;
\t\t\t\tCLANG_WARN_COMMA = YES;
\t\t\t\tCLANG_WARN_CONSTANT_CONVERSION = YES;
\t\t\t\tCLANG_WARN_DEPRECATED_OBJC_IMPLEMENTATIONS = YES;
\t\t\t\tCLANG_WARN_DIRECT_OBJC_ISA_USAGE = YES_ERROR;
\t\t\t\tCLANG_WARN_DOCUMENTATION_COMMENTS = YES;
\t\t\t\tCLANG_WARN_EMPTY_BODY = YES;
\t\t\t\tCLANG_WARN_ENUM_CONVERSION = YES;
\t\t\t\tCLANG_WARN_INFINITE_RECURSION = YES;
\t\t\t\tCLANG_WARN_INT_CONVERSION = YES;
\t\t\t\tCLANG_WARN_NON_LITERAL_NULL_CONVERSION = YES;
\t\t\t\tCLANG_WARN_OBJC_IMPLICIT_RETAIN_CYCLE = YES;
\t\t\t\tCLANG_WARN_OBJC_LITERAL_CONVERSION = YES;
\t\t\t\tCLANG_WARN_OBJC_ROOT_CLASS = YES_ERROR;
\t\t\t\tCLANG_WARN_RANGE_LOOP_ANALYSIS = YES;
\t\t\t\tCLANG_WARN_STRICT_PROTOTYPES = YES;
\t\t\t\tCLANG_WARN_SUSPICIOUS_MOVE = YES;
\t\t\t\tCLANG_WARN_UNGUARDED_AVAILABILITY = YES_AGGRESSIVE;
\t\t\t\tCLANG_WARN_UNREACHABLE_CODE = YES;
\t\t\t\tCLANG_WARN__DUPLICATE_METHOD_MATCH = YES;
\t\t\t\tCOPY_PHASE_STRIP = NO;
\t\t\t\tDEBUG_INFORMATION_FORMAT = dwarf;
\t\t\t\tENABLE_STRICT_OBJC_MSGSEND = YES;
\t\t\t\tENABLE_TESTABILITY = YES;
\t\t\t\tGCC_C_LANGUAGE_STANDARD = gnu17;
\t\t\t\tGCC_DYNAMIC_NO_PIC = NO;
\t\t\t\tGCC_NO_COMMON_BLOCKS = YES;
\t\t\t\tGCC_OPTIMIZATION_LEVEL = 0;
\t\t\t\tGCC_PREPROCESSOR_DEFINITIONS = ("DEBUG=1", "$(inherited)");
\t\t\t\tGCC_WARN_64_TO_32_BIT_CONVERSION = YES;
\t\t\t\tGCC_WARN_ABOUT_RETURN_TYPE = YES_ERROR;
\t\t\t\tGCC_WARN_UNDECLARED_SELECTOR = YES;
\t\t\t\tGCC_WARN_UNINITIALIZED_AUTOS = YES_AGGRESSIVE;
\t\t\t\tGCC_WARN_UNUSED_FUNCTION = YES;
\t\t\t\tGCC_WARN_UNUSED_VARIABLE = YES;
\t\t\t\tMACOSX_DEPLOYMENT_TARGET = 13.0;
\t\t\t\tMTL_ENABLE_DEBUG_INFO = INCLUDE_SOURCE;
\t\t\t\tMTL_FAST_MATH = YES;
\t\t\t\tONLY_ACTIVE_ARCH = YES;
\t\t\t\tSDKROOT = macosx;
\t\t\t\tSWIFT_ACTIVE_COMPILATION_CONDITIONS = DEBUG;
\t\t\t\tSWIFT_OPTIMIZATION_LEVEL = "-Onone";
\t\t\t\tSWIFT_VERSION = 5.9;
"""

def build_configurations():
    app_common = f"""\
\t\t\t\tCODE_SIGN_ENTITLEMENTS = "Configuration/MacSnitchApp.entitlements";
\t\t\t\tCODE_SIGN_STYLE = Automatic;
\t\t\t\tDEVELOPMENT_TEAM = "";
\t\t\t\tINFOPLIST_FILE = "Configuration/MacSnitchApp-Info.plist";
\t\t\t\tMACOSX_DEPLOYMENT_TARGET = 13.0;
\t\t\t\tPRODUCT_BUNDLE_IDENTIFIER = com.macsnitch;
\t\t\t\tPRODUCT_NAME = MacSnitch;
\t\t\t\tSDKROOT = macosx;
\t\t\t\tSWIFT_VERSION = 5.9;
"""
    ext_common = f"""\
\t\t\t\tCODE_SIGN_ENTITLEMENTS = "Configuration/MacSnitchExtension.entitlements";
\t\t\t\tCODE_SIGN_STYLE = Automatic;
\t\t\t\tDEVELOPMENT_TEAM = "";
\t\t\t\tINFOPLIST_FILE = "Configuration/MacSnitchExtension-Info.plist";
\t\t\t\tMACOSX_DEPLOYMENT_TARGET = 13.0;
\t\t\t\tPRODUCT_BUNDLE_IDENTIFIER = com.macsnitch.extension;
\t\t\t\tPRODUCT_NAME = MacSnitchExtension;
\t\t\t\tSDKROOT = macosx;
\t\t\t\tSWIFT_VERSION = 5.9;
"""

    def cfg(cid, name, target_settings, is_release=False):
        extra = '\t\t\t\tSWIFT_OPTIMIZATION_LEVEL = "-O";\n' if is_release else ''
        return f"""\
\t\t{cid} /* {name} */ = {{
\t\t\tisa = XCBuildConfiguration;
\t\t\tbuildSettings = {{
{BASE}{target_settings}{extra}\t\t\t}};
\t\t\tname = {"Release" if is_release else "Debug"};
\t\t}};
"""
    def cfglist(lid, target_name, debug_id, release_id):
        return f"""\
\t\t{lid} /* Build configuration list for PBXNativeTarget "{target_name}" */ = {{
\t\t\tisa = XCConfigurationList;
\t\t\tbuildConfigurations = (
\t\t\t\t{debug_id} /* Debug */,
\t\t\t\t{release_id} /* Release */,
\t\t\t);
\t\t\tdefaultConfigurationIsVisible = 0;
\t\t\tdefaultConfigurationName = Release;
\t\t}};
"""

    cfgs = (
        cfg(PROJ_DEBUG_CFG,   "Debug",   "",          False) +
        cfg(PROJ_RELEASE_CFG, "Release", "",          True)  +
        cfg(APP_DEBUG_CFG,    "Debug",   app_common,  False) +
        cfg(APP_RELEASE_CFG,  "Release", app_common,  True)  +
        cfg(EXT_DEBUG_CFG,    "Debug",   ext_common,  False) +
        cfg(EXT_RELEASE_CFG,  "Release", ext_common,  True)  +
        cfg(TEST_DEBUG_CFG,   "Debug",   "\t\t\t\tSDKROOT = macosx;\n\t\t\t\tSWIFT_VERSION = 5.9;\n", False) +
        cfg(TEST_RELEASE_CFG, "Release", "\t\t\t\tSDKROOT = macosx;\n\t\t\t\tSWIFT_VERSION = 5.9;\n", True)
    )

    lists = (
        f"""\
\t\t{PROJ_CFG_LIST} /* Build configuration list for PBXProject "MacSnitch" */ = {{
\t\t\tisa = XCConfigurationList;
\t\t\tbuildConfigurations = (
\t\t\t\t{PROJ_DEBUG_CFG} /* Debug */,
\t\t\t\t{PROJ_RELEASE_CFG} /* Release */,
\t\t\t);
\t\t\tdefaultConfigurationIsVisible = 0;
\t\t\tdefaultConfigurationName = Release;
\t\t}};
""" +
        cfglist(APP_CFG_LIST,  "MacSnitchApp",       APP_DEBUG_CFG,  APP_RELEASE_CFG)  +
        cfglist(EXT_CFG_LIST,  "MacSnitchExtension", EXT_DEBUG_CFG,  EXT_RELEASE_CFG)  +
        cfglist(TEST_CFG_LIST, "MacSnitchTests",     TEST_DEBUG_CFG, TEST_RELEASE_CFG)
    )

    return section("XCBuildConfiguration", cfgs) + section("XCConfigurationList", lists)

# ── Assemble project.pbxproj ──────────────────────────────────────────────────

def generate():
    body = (
        build_files() +
        copy_files_phase() +
        file_references() +
        frameworks_phases() +
        groups() +
        native_targets() +
        project() +
        build_configurations()
    )

    pbxproj = f"""// !$*UTF8*$!
{{
\tarchiveVersion = 1;
\tclasses = {{
\t}};
\tobjectVersion = 77;
\tobjects = {{\n{body}\t}};
\trootObject = {PROJECT_ID} /* Project object */;
}}
"""
    out_dir = os.path.join(ROOT, "MacSnitch.xcodeproj")
    os.makedirs(out_dir, exist_ok=True)
    out_path = os.path.join(out_dir, "project.pbxproj")
    with open(out_path, "w") as f:
        f.write(pbxproj)
    print(f"Written: {out_path}")
    return out_path

if __name__ == "__main__":
    generate()
