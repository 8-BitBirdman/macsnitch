#!/usr/bin/env python3
"""Generates MacSnitch.xcodeproj/project.pbxproj — complete, authoritative source list."""

import os, hashlib, struct, zlib

ROOT = "/home/claude/macsnitch"

def uid(seed):
    return hashlib.md5(seed.encode()).hexdigest().upper()[:24]

# ── Definitive source file lists ──────────────────────────────────────────────

APP_SOURCES = [
    "MacSnitchApp/App.swift",
    "MacSnitchApp/Models/AppStatsModel.swift",
    "MacSnitchApp/Services/BlockListManager.swift",
    "MacSnitchApp/Services/ConnectionLogger.swift",
    "MacSnitchApp/Services/ConnectionPromptCoordinator.swift",
    "MacSnitchApp/Services/DatabaseMigrator.swift",
    "MacSnitchApp/Services/ExtensionClient.swift",
    "MacSnitchApp/Services/FilterExtensionManager.swift",
    "MacSnitchApp/Services/LaunchAtLoginManager.swift",
    "MacSnitchApp/Services/NotificationManager.swift",
    "MacSnitchApp/Services/RuleImportExport.swift",
    "MacSnitchApp/Services/RuleStore.swift",
    "MacSnitchApp/Services/XPCServer.swift",
    "MacSnitchApp/Views/BlockListView.swift",
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

# ── IDs (all deterministic) ───────────────────────────────────────────────────

PROJECT_ID          = uid("project")
APP_TARGET_ID       = uid("target.app")
EXT_TARGET_ID       = uid("target.ext")
TEST_TARGET_ID      = uid("target.test")

APP_SOURCES_PHASE   = uid("phase.app.sources")
EXT_SOURCES_PHASE   = uid("phase.ext.sources")
TEST_SOURCES_PHASE  = uid("phase.test.sources")
APP_FRAMEWORKS      = uid("phase.app.frameworks")
EXT_FRAMEWORKS      = uid("phase.ext.frameworks")
TEST_FRAMEWORKS     = uid("phase.test.frameworks")
APP_RESOURCES       = uid("phase.app.resources")
APP_EMBED_EXT       = uid("phase.app.embed")

APP_DEBUG_CFG       = uid("cfg.app.debug")
APP_RELEASE_CFG     = uid("cfg.app.release")
EXT_DEBUG_CFG       = uid("cfg.ext.debug")
EXT_RELEASE_CFG     = uid("cfg.ext.release")
TEST_DEBUG_CFG      = uid("cfg.test.debug")
TEST_RELEASE_CFG    = uid("cfg.test.release")
PROJ_DEBUG_CFG      = uid("cfg.proj.debug")
PROJ_RELEASE_CFG    = uid("cfg.proj.release")

APP_CFG_LIST        = uid("cfglist.app")
EXT_CFG_LIST        = uid("cfglist.ext")
TEST_CFG_LIST       = uid("cfglist.test")
PROJ_CFG_LIST       = uid("cfglist.proj")

MAIN_GROUP          = uid("group.main")
APP_GROUP           = uid("group.app")
APP_MODELS_GROUP    = uid("group.app.models")
APP_SERVICES_GROUP  = uid("group.app.services")
APP_VIEWS_GROUP     = uid("group.app.views")
EXT_GROUP           = uid("group.ext")
SHARED_GROUP        = uid("group.shared")
TEST_GROUP          = uid("group.test")
CFG_GROUP           = uid("group.cfg")
PRODUCTS_GROUP      = uid("group.products")

APP_PRODUCT_REF     = uid("product.app")
EXT_PRODUCT_REF     = uid("product.ext")
TEST_PRODUCT_REF    = uid("product.test")
EXT_EMBED_BUILD     = uid("buildfile.embed.ext")

ASSETS_REF          = uid("ref.assets")
ASSETS_BUILD        = uid("bf.assets.app")

GRDB_PKG_REF        = uid("spm.grdb.remote")
GRDB_PROD_DEP       = uid("spm.grdb.product.dep")
GRDB_BUILD          = uid("spm.grdb.buildfile")

def fref(path):  return uid(f"ref.{path}")
def bfid(path, t): return uid(f"bf.{path}.{t}")

# ── Frameworks ────────────────────────────────────────────────────────────────

FRAMEWORKS = {
    "NetworkExtension.framework":    uid("fw.networkextension"),
    "ServiceManagement.framework":   uid("fw.servicemanagement"),
    "SystemExtensions.framework":    uid("fw.systemextensions"),
    "SwiftUI.framework":             uid("fw.swiftui"),
    "UserNotifications.framework":   uid("fw.usernotifications"),
    "AppKit.framework":              uid("fw.appkit"),
    "Foundation.framework":          uid("fw.foundation"),
}

# ── Build section helpers ─────────────────────────────────────────────────────

def section(name, body):
    return f"\n/* Begin {name} section */\n{body}/* End {name} section */\n"

# ── PBXBuildFile ──────────────────────────────────────────────────────────────

def build_files():
    lines = []
    for p in APP_SOURCES:
        n = os.path.basename(p)
        lines.append(f"\t\t{bfid(p,'app')} /* {n} in Sources */ = {{isa = PBXBuildFile; fileRef = {fref(p)}; }};")
    for p in EXT_SOURCES:
        n = os.path.basename(p)
        lines.append(f"\t\t{bfid(p,'ext')} /* {n} in Sources (ext) */ = {{isa = PBXBuildFile; fileRef = {fref(p)}; }};")
    for p in TEST_SOURCES:
        n = os.path.basename(p)
        lines.append(f"\t\t{bfid(p,'test')} /* {n} in Sources (test) */ = {{isa = PBXBuildFile; fileRef = {fref(p)}; }};")
    for fw, fid in FRAMEWORKS.items():
        lines.append(f"\t\t{bfid(fw,'app')} /* {fw} in Frameworks */ = {{isa = PBXBuildFile; fileRef = {fid}; }};")
    lines.append(f"\t\t{EXT_EMBED_BUILD} /* MacSnitchExtension in Embed */ = {{isa = PBXBuildFile; fileRef = {EXT_PRODUCT_REF}; settings = {{ATTRIBUTES = (RemoveHeadersOnCopy, ); }}; }};")
    lines.append(f"\t\t{ASSETS_BUILD} /* Assets.xcassets in Resources */ = {{isa = PBXBuildFile; fileRef = {ASSETS_REF}; }};")
    lines.append(f"\t\t{GRDB_BUILD} /* GRDB in Frameworks */ = {{isa = PBXBuildFile; productRef = {GRDB_PROD_DEP}; }};")
    return section("PBXBuildFile", "\n".join(lines) + "\n")

# ── PBXCopyFilesBuildPhase ────────────────────────────────────────────────────

def copy_files_phase():
    return section("PBXCopyFilesBuildPhase", f"""\
\t\t{APP_EMBED_EXT} /* Embed System Extensions */ = {{
\t\t\tisa = PBXCopyFilesBuildPhase;
\t\t\tbuildActionMask = 2147483647;
\t\t\tdstPath = "";
\t\t\tdstSubfolderSpec = 16;
\t\t\tfiles = ({EXT_EMBED_BUILD} /* MacSnitchExtension in Embed */,);
\t\t\tname = "Embed System Extensions";
\t\t\trunOnlyForDeploymentPostprocessing = 0;
\t\t}};
""")

# ── PBXFileReference ──────────────────────────────────────────────────────────

def file_references():
    lines = []
    for p in ALL_SOURCES:
        n = os.path.basename(p)
        lines.append(f"\t\t{fref(p)} /* {n} */ = {{isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = {n}; sourceTree = \"<group>\"; }};")
    for fw, fid in FRAMEWORKS.items():
        lines.append(f"\t\t{fid} /* {fw} */ = {{isa = PBXFileReference; lastKnownFileType = wrapper.framework; name = {fw}; path = System/Library/Frameworks/{fw}; sourceTree = SDKROOT; }};")
    lines.append(f"\t\t{APP_PRODUCT_REF} /* MacSnitch.app */ = {{isa = PBXFileReference; explicitFileType = wrapper.application; includeInIndex = 0; path = MacSnitch.app; sourceTree = BUILT_PRODUCTS_DIR; }};")
    lines.append(f"\t\t{EXT_PRODUCT_REF} /* MacSnitchExtension.systemextension */ = {{isa = PBXFileReference; explicitFileType = wrapper.system-extension; includeInIndex = 0; path = MacSnitchExtension.systemextension; sourceTree = BUILT_PRODUCTS_DIR; }};")
    lines.append(f"\t\t{TEST_PRODUCT_REF} /* MacSnitchTests.xctest */ = {{isa = PBXFileReference; explicitFileType = wrapper.cfbundle; includeInIndex = 0; path = MacSnitchTests.xctest; sourceTree = BUILT_PRODUCTS_DIR; }};")
    lines.append(f"\t\t{ASSETS_REF} /* Assets.xcassets */ = {{isa = PBXFileReference; lastKnownFileType = folder.assetcatalog; path = Assets.xcassets; sourceTree = \"<group>\"; }};")
    for cfg in ["MacSnitchApp.entitlements","MacSnitchExtension.entitlements","MacSnitchApp-Info.plist","MacSnitchExtension-Info.plist","ExportOptions.plist"]:
        cid = uid(f"ref.cfg.{cfg}")
        t = "text.plist.entitlements" if cfg.endswith(".entitlements") else "text.plist.xml"
        lines.append(f"\t\t{cid} /* {cfg} */ = {{isa = PBXFileReference; lastKnownFileType = {t}; path = {cfg}; sourceTree = \"<group>\"; }};")
    return section("PBXFileReference", "\n".join(lines) + "\n")

# ── PBXFrameworksBuildPhase ───────────────────────────────────────────────────

def frameworks_phases():
    fw_entries = "\n".join(f"\t\t\t\t{bfid(fw,'app')} /* {fw} in Frameworks */," for fw in FRAMEWORKS)
    return section("PBXFrameworksBuildPhase", f"""\
\t\t{APP_FRAMEWORKS} /* Frameworks */ = {{
\t\t\tisa = PBXFrameworksBuildPhase;
\t\t\tbuildActionMask = 2147483647;
\t\t\tfiles = (
{fw_entries}
\t\t\t\t{GRDB_BUILD} /* GRDB in Frameworks */,
\t\t\t);
\t\t\trunOnlyForDeploymentPostprocessing = 0;
\t\t}};
\t\t{EXT_FRAMEWORKS} /* Frameworks (ext) */ = {{
\t\t\tisa = PBXFrameworksBuildPhase;
\t\t\tbuildActionMask = 2147483647;
\t\t\tfiles = ();
\t\t\trunOnlyForDeploymentPostprocessing = 0;
\t\t}};
\t\t{TEST_FRAMEWORKS} /* Frameworks (test) */ = {{
\t\t\tisa = PBXFrameworksBuildPhase;
\t\t\tbuildActionMask = 2147483647;
\t\t\tfiles = ();
\t\t\trunOnlyForDeploymentPostprocessing = 0;
\t\t}};
""")

# ── PBXGroup ──────────────────────────────────────────────────────────────────

def grp(paths):
    return "\n".join(f"\t\t\t\t{fref(p)} /* {os.path.basename(p)} */," for p in paths)

def groups():
    root_app  = [p for p in APP_SOURCES if p.startswith("MacSnitchApp/") and p.count("/") == 1]
    models    = [p for p in APP_SOURCES if p.startswith("MacSnitchApp/Models/")]
    services  = [p for p in APP_SOURCES if p.startswith("MacSnitchApp/Services/")]
    views     = [p for p in APP_SOURCES if p.startswith("MacSnitchApp/Views/")]
    ext_files = [p for p in ALL_SOURCES  if p.startswith("NetworkExtension/")]
    shared    = [p for p in ALL_SOURCES  if p.startswith("Shared/")]
    tests     = [p for p in ALL_SOURCES  if p.startswith("Tests/")]
    cfgs      = ["MacSnitchApp.entitlements","MacSnitchExtension.entitlements",
                 "MacSnitchApp-Info.plist","MacSnitchExtension-Info.plist","ExportOptions.plist"]
    cfg_refs  = "\n".join(f"\t\t\t\t{uid(f'ref.cfg.{c}')} /* {c} */," for c in cfgs)

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
\t\t{PRODUCTS_GROUP} = {{
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
{grp(root_app)}
\t\t\t\t{ASSETS_REF} /* Assets.xcassets */,
\t\t\t\t{APP_MODELS_GROUP} /* Models */,
\t\t\t\t{APP_SERVICES_GROUP} /* Services */,
\t\t\t\t{APP_VIEWS_GROUP} /* Views */,
\t\t\t);
\t\t\tpath = MacSnitchApp;
\t\t\tsourceTree = "<group>";
\t\t}};
\t\t{APP_MODELS_GROUP} /* Models */ = {{
\t\t\tisa = PBXGroup;
\t\t\tchildren = ({grp(models)});
\t\t\tpath = Models;
\t\t\tsourceTree = "<group>";
\t\t}};
\t\t{APP_SERVICES_GROUP} /* Services */ = {{
\t\t\tisa = PBXGroup;
\t\t\tchildren = (
{grp(services)}
\t\t\t);
\t\t\tpath = Services;
\t\t\tsourceTree = "<group>";
\t\t}};
\t\t{APP_VIEWS_GROUP} /* Views */ = {{
\t\t\tisa = PBXGroup;
\t\t\tchildren = (
{grp(views)}
\t\t\t);
\t\t\tpath = Views;
\t\t\tsourceTree = "<group>";
\t\t}};
\t\t{EXT_GROUP} /* NetworkExtension */ = {{
\t\t\tisa = PBXGroup;
\t\t\tchildren = (
{grp(ext_files)}
\t\t\t);
\t\t\tpath = NetworkExtension;
\t\t\tsourceTree = "<group>";
\t\t}};
\t\t{SHARED_GROUP} /* Shared */ = {{
\t\t\tisa = PBXGroup;
\t\t\tchildren = ({grp(shared)});
\t\t\tpath = Shared;
\t\t\tsourceTree = "<group>";
\t\t}};
\t\t{TEST_GROUP} /* Tests */ = {{
\t\t\tisa = PBXGroup;
\t\t\tchildren = ({grp(tests)});
\t\t\tpath = Tests;
\t\t\tsourceTree = "<group>";
\t\t}};
\t\t{CFG_GROUP} /* Configuration */ = {{
\t\t\tisa = PBXGroup;
\t\t\tchildren = (
{cfg_refs}
\t\t\t);
\t\t\tpath = Configuration;
\t\t\tsourceTree = "<group>";
\t\t}};
""")

# ── Build phases: Sources + Resources ────────────────────────────────────────

def source_phases():
    app_bf  = "\n".join(f"\t\t\t\t{bfid(p,'app')} /* {os.path.basename(p)} in Sources */," for p in APP_SOURCES)
    ext_bf  = "\n".join(f"\t\t\t\t{bfid(p,'ext')} /* {os.path.basename(p)} in Sources */," for p in EXT_SOURCES)
    test_bf = "\n".join(f"\t\t\t\t{bfid(p,'test')} /* {os.path.basename(p)} in Sources */," for p in TEST_SOURCES)

    return (section("PBXSourcesBuildPhase", f"""\
\t\t{APP_SOURCES_PHASE} /* Sources */ = {{
\t\t\tisa = PBXSourcesBuildPhase;
\t\t\tbuildActionMask = 2147483647;
\t\t\tfiles = (
{app_bf}
\t\t\t);
\t\t\trunOnlyForDeploymentPostprocessing = 0;
\t\t}};
\t\t{EXT_SOURCES_PHASE} /* Sources (ext) */ = {{
\t\t\tisa = PBXSourcesBuildPhase;
\t\t\tbuildActionMask = 2147483647;
\t\t\tfiles = (
{ext_bf}
\t\t\t);
\t\t\trunOnlyForDeploymentPostprocessing = 0;
\t\t}};
\t\t{TEST_SOURCES_PHASE} /* Sources (test) */ = {{
\t\t\tisa = PBXSourcesBuildPhase;
\t\t\tbuildActionMask = 2147483647;
\t\t\tfiles = (
{test_bf}
\t\t\t);
\t\t\trunOnlyForDeploymentPostprocessing = 0;
\t\t}};
""") + section("PBXResourcesBuildPhase", f"""\
\t\t{APP_RESOURCES} /* Resources */ = {{
\t\t\tisa = PBXResourcesBuildPhase;
\t\t\tbuildActionMask = 2147483647;
\t\t\tfiles = ({ASSETS_BUILD} /* Assets.xcassets in Resources */,);
\t\t\trunOnlyForDeploymentPostprocessing = 0;
\t\t}};
"""))

# ── PBXNativeTarget ───────────────────────────────────────────────────────────

def native_targets():
    return section("PBXNativeTarget", f"""\
\t\t{APP_TARGET_ID} /* MacSnitchApp */ = {{
\t\t\tisa = PBXNativeTarget;
\t\t\tbuildConfigurationList = {APP_CFG_LIST};
\t\t\tbuildPhases = (
\t\t\t\t{APP_SOURCES_PHASE} /* Sources */,
\t\t\t\t{APP_FRAMEWORKS} /* Frameworks */,
\t\t\t\t{APP_RESOURCES} /* Resources */,
\t\t\t\t{APP_EMBED_EXT} /* Embed System Extensions */,
\t\t\t);
\t\t\tbuildRules = ();
\t\t\tdependencies = ();
\t\t\tname = MacSnitchApp;
\t\t\tpackageProductDependencies = ({GRDB_PROD_DEP} /* GRDB */,);
\t\t\tproductName = MacSnitchApp;
\t\t\tproductReference = {APP_PRODUCT_REF};
\t\t\tproductType = "com.apple.product-type.application";
\t\t}};
\t\t{EXT_TARGET_ID} /* MacSnitchExtension */ = {{
\t\t\tisa = PBXNativeTarget;
\t\t\tbuildConfigurationList = {EXT_CFG_LIST};
\t\t\tbuildPhases = (
\t\t\t\t{EXT_SOURCES_PHASE} /* Sources */,
\t\t\t\t{EXT_FRAMEWORKS} /* Frameworks */,
\t\t\t);
\t\t\tbuildRules = ();
\t\t\tdependencies = ();
\t\t\tname = MacSnitchExtension;
\t\t\tproductName = MacSnitchExtension;
\t\t\tproductReference = {EXT_PRODUCT_REF};
\t\t\tproductType = "com.apple.product-type.system-extension";
\t\t}};
\t\t{TEST_TARGET_ID} /* MacSnitchTests */ = {{
\t\t\tisa = PBXNativeTarget;
\t\t\tbuildConfigurationList = {TEST_CFG_LIST};
\t\t\tbuildPhases = (
\t\t\t\t{TEST_SOURCES_PHASE} /* Sources */,
\t\t\t\t{TEST_FRAMEWORKS} /* Frameworks */,
\t\t\t);
\t\t\tbuildRules = ();
\t\t\tdependencies = ();
\t\t\tname = MacSnitchTests;
\t\t\tproductName = MacSnitchTests;
\t\t\tproductReference = {TEST_PRODUCT_REF};
\t\t\tproductType = "com.apple.product-type.bundle.unit-test";
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
\t\t\t\t\t{APP_TARGET_ID}  = {{ CreatedOnToolsVersion = 15.0; }};
\t\t\t\t\t{EXT_TARGET_ID}  = {{ CreatedOnToolsVersion = 15.0; }};
\t\t\t\t\t{TEST_TARGET_ID} = {{ CreatedOnToolsVersion = 15.0; TestTargetID = {APP_TARGET_ID}; }};
\t\t\t\t}};
\t\t\t}};
\t\t\tbuildConfigurationList = {PROJ_CFG_LIST};
\t\t\tcompatibilityVersion = "Xcode 15.0";
\t\t\tdevelopmentRegion = en;
\t\t\thasScannedForEncodings = 0;
\t\t\tknownRegions = (en, Base,);
\t\t\tmainGroup = {MAIN_GROUP};
\t\t\tpackageReferences = ({GRDB_PKG_REF} /* XCRemoteSwiftPackageReference "GRDB.swift" */,);
\t\t\tproductRefGroup = {PRODUCTS_GROUP};
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

BASE_DEBUG = """\
\t\t\t\tALWAYS_SEARCH_USER_PATHS = NO;
\t\t\t\tCLANG_ENABLE_MODULES = YES;
\t\t\t\tCLANG_ENABLE_OBJC_ARC = YES;
\t\t\t\tCOPY_PHASE_STRIP = NO;
\t\t\t\tDEBUG_INFORMATION_FORMAT = dwarf;
\t\t\t\tENABLE_TESTABILITY = YES;
\t\t\t\tGCC_DYNAMIC_NO_PIC = NO;
\t\t\t\tGCC_OPTIMIZATION_LEVEL = 0;
\t\t\t\tGCC_PREPROCESSOR_DEFINITIONS = ("DEBUG=1", "$(inherited)");
\t\t\t\tGCC_WARN_ABOUT_RETURN_TYPE = YES_ERROR;
\t\t\t\tGCC_WARN_UNINITIALIZED_AUTOS = YES_AGGRESSIVE;
\t\t\t\tGCC_WARN_UNUSED_FUNCTION = YES;
\t\t\t\tGCC_WARN_UNUSED_VARIABLE = YES;
\t\t\t\tMACOSX_DEPLOYMENT_TARGET = 13.0;
\t\t\t\tONLY_ACTIVE_ARCH = YES;
\t\t\t\tSDKROOT = macosx;
\t\t\t\tSWIFT_ACTIVE_COMPILATION_CONDITIONS = DEBUG;
\t\t\t\tSWIFT_OPTIMIZATION_LEVEL = "-Onone";
\t\t\t\tSWIFT_VERSION = 5.9;
"""

BASE_RELEASE = """\
\t\t\t\tALWAYS_SEARCH_USER_PATHS = NO;
\t\t\t\tCLANG_ENABLE_MODULES = YES;
\t\t\t\tCLANG_ENABLE_OBJC_ARC = YES;
\t\t\t\tCOPY_PHASE_STRIP = NO;
\t\t\t\tDEBUG_INFORMATION_FORMAT = "dwarf-with-dsym";
\t\t\t\tENABLE_NS_ASSERTIONS = NO;
\t\t\t\tGCC_WARN_ABOUT_RETURN_TYPE = YES_ERROR;
\t\t\t\tGCC_WARN_UNINITIALIZED_AUTOS = YES_AGGRESSIVE;
\t\t\t\tMACOSX_DEPLOYMENT_TARGET = 13.0;
\t\t\t\tSDKROOT = macosx;
\t\t\t\tSWIFT_COMPILATION_MODE = wholemodule;
\t\t\t\tSWIFT_OPTIMIZATION_LEVEL = "-O";
\t\t\t\tSWIFT_VERSION = 5.9;
\t\t\t\tVALIDATE_PRODUCT = YES;
"""

def cfg_block(cid, name, base, extra=""):
    return f"""\
\t\t{cid} /* {name} */ = {{
\t\t\tisa = XCBuildConfiguration;
\t\t\tbuildSettings = {{
{base}{extra}\t\t\t}};
\t\t\tname = {name};
\t\t}};
"""

def cfglist_block(lid, target_name, dbg, rel):
    return f"""\
\t\t{lid} /* Build configuration list for PBXNativeTarget "{target_name}" */ = {{
\t\t\tisa = XCConfigurationList;
\t\t\tbuildConfigurations = ({dbg} /* Debug */, {rel} /* Release */,);
\t\t\tdefaultConfigurationIsVisible = 0;
\t\t\tdefaultConfigurationName = Release;
\t\t}};
"""

APP_EXTRA = """\
\t\t\t\tAPPLE_SILICON_ARCH = arm64;
\t\t\t\tCODE_SIGN_ENTITLEMENTS = "Configuration/MacSnitchApp.entitlements";
\t\t\t\tCODE_SIGN_STYLE = Automatic;
\t\t\t\tDEVELOPMENT_TEAM = "";
\t\t\t\tINFOPLIST_FILE = "Configuration/MacSnitchApp-Info.plist";
\t\t\t\tPRODUCT_BUNDLE_IDENTIFIER = com.macsnitch;
\t\t\t\tPRODUCT_NAME = MacSnitch;
"""

EXT_EXTRA = """\
\t\t\t\tCODE_SIGN_ENTITLEMENTS = "Configuration/MacSnitchExtension.entitlements";
\t\t\t\tCODE_SIGN_STYLE = Automatic;
\t\t\t\tDEVELOPMENT_TEAM = "";
\t\t\t\tINFOPLIST_FILE = "Configuration/MacSnitchExtension-Info.plist";
\t\t\t\tPRODUCT_BUNDLE_IDENTIFIER = com.macsnitch.extension;
\t\t\t\tPRODUCT_NAME = MacSnitchExtension;
"""

TEST_EXTRA = """\
\t\t\t\tBUNDLE_LOADER = "$(TEST_HOST)";
\t\t\t\tCODE_SIGN_STYLE = Automatic;
\t\t\t\tDEVELOPMENT_TEAM = "";
\t\t\t\tPRODUCT_BUNDLE_IDENTIFIER = com.macsnitch.tests;
\t\t\t\tPRODUCT_NAME = MacSnitchTests;
\t\t\t\tTEST_HOST = "$(BUILT_PRODUCTS_DIR)/MacSnitch.app/Contents/MacOS/MacSnitch";
"""

def build_configurations():
    cfgs = (
        cfg_block(PROJ_DEBUG_CFG,   "Debug",   BASE_DEBUG)   +
        cfg_block(PROJ_RELEASE_CFG, "Release", BASE_RELEASE) +
        cfg_block(APP_DEBUG_CFG,    "Debug",   BASE_DEBUG,   APP_EXTRA) +
        cfg_block(APP_RELEASE_CFG,  "Release", BASE_RELEASE, APP_EXTRA) +
        cfg_block(EXT_DEBUG_CFG,    "Debug",   BASE_DEBUG,   EXT_EXTRA) +
        cfg_block(EXT_RELEASE_CFG,  "Release", BASE_RELEASE, EXT_EXTRA) +
        cfg_block(TEST_DEBUG_CFG,   "Debug",   BASE_DEBUG,   TEST_EXTRA) +
        cfg_block(TEST_RELEASE_CFG, "Release", BASE_RELEASE, TEST_EXTRA)
    )
    lists = (
        f"""\
\t\t{PROJ_CFG_LIST} /* Build configuration list for PBXProject "MacSnitch" */ = {{
\t\t\tisa = XCConfigurationList;
\t\t\tbuildConfigurations = ({PROJ_DEBUG_CFG} /* Debug */, {PROJ_RELEASE_CFG} /* Release */,);
\t\t\tdefaultConfigurationIsVisible = 0;
\t\t\tdefaultConfigurationName = Release;
\t\t}};
""" +
        cfglist_block(APP_CFG_LIST,  "MacSnitchApp",       APP_DEBUG_CFG,  APP_RELEASE_CFG)  +
        cfglist_block(EXT_CFG_LIST,  "MacSnitchExtension", EXT_DEBUG_CFG,  EXT_RELEASE_CFG)  +
        cfglist_block(TEST_CFG_LIST, "MacSnitchTests",     TEST_DEBUG_CFG, TEST_RELEASE_CFG)
    )
    return section("XCBuildConfiguration", cfgs) + section("XCConfigurationList", lists)

# ── SPM ───────────────────────────────────────────────────────────────────────

def spm_sections():
    return (
        section("XCRemoteSwiftPackageReference", f"""\
\t\t{GRDB_PKG_REF} /* XCRemoteSwiftPackageReference "GRDB.swift" */ = {{
\t\t\tisa = XCRemoteSwiftPackageReference;
\t\t\trequirement = {{ kind = upToNextMajorVersion; minimumVersion = "6.0.0"; }};
\t\t\trepositoryURL = "https://github.com/groue/GRDB.swift.git";
\t\t}};
""") +
        section("XCSwiftPackageProductDependency", f"""\
\t\t{GRDB_PROD_DEP} /* GRDB */ = {{
\t\t\tisa = XCSwiftPackageProductDependency;
\t\t\tpackage = {GRDB_PKG_REF};
\t\t\tproductName = GRDB;
\t\t}};
"""))

# ── Assemble ──────────────────────────────────────────────────────────────────

def generate():
    body = (
        build_files() +
        copy_files_phase() +
        file_references() +
        frameworks_phases() +
        groups() +
        native_targets() +
        source_phases() +
        project() +
        build_configurations() +
        spm_sections()
    )

    pbxproj = f"""// !$*UTF8*$!
{{
\tarchiveVersion = 1;
\tclasses = {{}};
\tobjectVersion = 77;
\tobjects = {{
{body}
\t}};
\trootObject = {PROJECT_ID} /* Project object */;
}}
"""
    out = os.path.join(ROOT, "MacSnitch.xcodeproj", "project.pbxproj")
    with open(out, "w") as f:
        f.write(pbxproj)

    # Validate
    opens  = pbxproj.count("{")
    closes = pbxproj.count("}")
    lines  = pbxproj.count("\n")

    checks = {
        "All app sources":     all(os.path.basename(p) in pbxproj for p in APP_SOURCES),
        "All ext sources":     all(os.path.basename(p) in pbxproj for p in EXT_SOURCES),
        "ServiceManagement":   "ServiceManagement.framework" in pbxproj,
        "GRDB SPM":            "groue/GRDB" in pbxproj,
        "Assets.xcassets":     "Assets.xcassets" in pbxproj,
        "Embed System Ext":    "Embed System Extensions" in pbxproj,
        "App entitlements":    "MacSnitchApp.entitlements" in pbxproj,
        "Ext entitlements":    "MacSnitchExtension.entitlements" in pbxproj,
        "LaunchAtLogin":       "LaunchAtLoginManager.swift" in pbxproj,
        "BlockListManager":    "BlockListManager.swift" in pbxproj,
        "BlockListView":       "BlockListView.swift" in pbxproj,
        "Braces balanced":     opens == closes,
    }

    print(f"Generated {out}  ({lines} lines)")
    for k, v in checks.items():
        print(f"  {'✓' if v else '✗ FAIL'}  {k}")

if __name__ == "__main__":
    generate()
