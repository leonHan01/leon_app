from pathlib import Path
import hashlib,json,re,os
root=Path(__file__).resolve().parents[1]
# Keep the team selected in Xcode when adding UI source files regenerates the
# project. LEON_IOS_TEAM explicitly overrides it for another developer.
project_path=root/'Leon.xcodeproj/project.pbxproj'
existing=project_path.read_text() if project_path.exists() else ''
selected_team=re.search(r'\bDEVELOPMENT_TEAM\s*=\s*"?([A-Z0-9]{10})"?;',existing)
team=os.environ.get('LEON_IOS_TEAM') or (selected_team.group(1) if selected_team else None)
def uid(value): return hashlib.sha1(value.encode()).hexdigest()[:24].upper()
def quote(value): return json.dumps(str(value),ensure_ascii=False)
objects=[]
def obj(key,text): objects.append(f'\t\t{uid(key)} = {{ {text} }};')
sources=sorted((root/'Sources').rglob('*.swift'))
for p in sources:
 rel=p.relative_to(root).as_posix();obj('file:'+rel,f'isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = {quote(rel)}; sourceTree = "<group>";')
 obj('build:'+rel,f'isa = PBXBuildFile; fileRef = {uid("file:"+rel)};')
for name,type_ in [('Resources/Markdown','folder'),('Resources/Assets.xcassets','folder.assetcatalog')]:
 obj('file:'+name,f'isa = PBXFileReference; lastKnownFileType = {quote(type_)}; path = {quote(name)}; sourceTree = "<group>";')
 obj('build:'+name,f'isa = PBXBuildFile; fileRef = {uid("file:"+name)};')
obj('product','isa = PBXFileReference; explicitFileType = wrapper.application; includeInIndex = 0; path = Leon.app; sourceTree = BUILT_PRODUCTS_DIR;')
obj('info','isa = PBXFileReference; lastKnownFileType = text.plist.xml; path = Info.plist; sourceTree = "<group>";')
obj('zlib','isa = PBXFileReference; lastKnownFileType = sourcecode.text-based-dylib-definition; name = libz.tbd; path = usr/lib/libz.tbd; sourceTree = SDKROOT;')
obj('build-zlib',f'isa = PBXBuildFile; fileRef = {uid("zlib")};')
children=[uid('file:'+p.relative_to(root).as_posix()) for p in sources]+[uid('file:Resources/Markdown'),uid('file:Resources/Assets.xcassets'),uid('info'),uid('zlib'),uid('products')]
obj('main',f'isa = PBXGroup; children = ({", ".join(children)},); sourceTree = "<group>";')
obj('products',f'isa = PBXGroup; children = ({uid("product")},); name = Products; sourceTree = "<group>";')
obj('sources',f'isa = PBXSourcesBuildPhase; buildActionMask = 2147483647; files = ({", ".join(uid("build:"+p.relative_to(root).as_posix()) for p in sources)},); runOnlyForDeploymentPostprocessing = 0;')
obj('resources',f'isa = PBXResourcesBuildPhase; buildActionMask = 2147483647; files = ({uid("build:Resources/Markdown")}, {uid("build:Resources/Assets.xcassets")},); runOnlyForDeploymentPostprocessing = 0;')
obj('frameworks',f'isa = PBXFrameworksBuildPhase; buildActionMask = 2147483647; files = ({uid("build-zlib")},); runOnlyForDeploymentPostprocessing = 0;')
obj('target',f'isa = PBXNativeTarget; buildConfigurationList = {uid("target-config")}; buildPhases = ({uid("sources")}, {uid("frameworks")}, {uid("resources")},); buildRules = (); dependencies = (); name = Leon; productName = Leon; productReference = {uid("product")}; productType = "com.apple.product-type.application";')
project_settings={'CLANG_ENABLE_MODULES':'YES','CLANG_ENABLE_OBJC_ARC':'YES','SDKROOT':'iphoneos','IPHONEOS_DEPLOYMENT_TARGET':'16.0','SWIFT_VERSION':'5.0','ENABLE_USER_SCRIPT_SANDBOXING':'YES','SWIFT_STRICT_CONCURRENCY':'minimal'}
target_settings={'PRODUCT_BUNDLE_IDENTIFIER':'com.leon.ios','PRODUCT_NAME':'Leon','INFOPLIST_FILE':'Info.plist','GENERATE_INFOPLIST_FILE':'NO','CODE_SIGN_STYLE':'Automatic','CURRENT_PROJECT_VERSION':'3','MARKETING_VERSION':'0.12.2','TARGETED_DEVICE_FAMILY':'1,2','SUPPORTED_PLATFORMS':'iphoneos iphonesimulator','SUPPORTS_MACCATALYST':'NO','ASSETCATALOG_COMPILER_APPICON_NAME':'AppIcon','LD_RUNPATH_SEARCH_PATHS':'$(inherited) @executable_path/Frameworks','SWIFT_EMIT_LOC_STRINGS':'YES'}
if team:target_settings['DEVELOPMENT_TEAM']=team
for scope,settings in [('project',project_settings),('target',target_settings)]:
 for config in ['Debug','Release']:
  data=dict(settings)
  if config=='Debug': data.update({'SWIFT_OPTIMIZATION_LEVEL':'-Onone','SWIFT_ACTIVE_COMPILATION_CONDITIONS':'DEBUG $(inherited)','DEBUG_INFORMATION_FORMAT':'dwarf'})
  else: data.update({'SWIFT_OPTIMIZATION_LEVEL':'-O','DEBUG_INFORMATION_FORMAT':'dwarf-with-dsym'})
  obj(scope+'-'+config,'isa = XCBuildConfiguration; buildSettings = {'+' '.join(f'{k} = {quote(v)};' for k,v in data.items())+'}; name = '+config+';')
 obj(scope+'-config',f'isa = XCConfigurationList; buildConfigurations = ({uid(scope+"-Debug")}, {uid(scope+"-Release")},); defaultConfigurationIsVisible = 0; defaultConfigurationName = Release;')
obj('project',f'isa = PBXProject; attributes = {{ LastUpgradeCheck = 1600; TargetAttributes = {{ {uid("target")} = {{ CreatedOnToolsVersion = 16.0; }}; }}; }}; buildConfigurationList = {uid("project-config")}; compatibilityVersion = "Xcode 14.0"; developmentRegion = zh_CN; hasScannedForEncodings = 0; knownRegions = (en, zh_CN, Base,); mainGroup = {uid("main")}; productRefGroup = {uid("products")}; projectDirPath = ""; projectRoot = ""; targets = ({uid("target")},);')
(root/'Leon.xcodeproj/project.pbxproj').write_text('// !$*UTF8*$!\n{\n\tarchiveVersion = 1;\n\tclasses = {};\n\tobjectVersion = 56;\n\tobjects = {\n'+'\n'.join(objects)+'\n\t};\n\trootObject = '+uid('project')+';\n}\n')
scheme=f'''<?xml version="1.0" encoding="UTF-8"?>
<Scheme LastUpgradeVersion="1600" version="1.3">
<BuildAction parallelizeBuildables="YES" buildImplicitDependencies="YES"><BuildActionEntries><BuildActionEntry buildForTesting="YES" buildForRunning="YES" buildForProfiling="YES" buildForArchiving="YES" buildForAnalyzing="YES"><BuildableReference BuildableIdentifier="primary" BlueprintIdentifier="{uid('target')}" BuildableName="Leon.app" BlueprintName="Leon" ReferencedContainer="container:Leon.xcodeproj"/></BuildActionEntry></BuildActionEntries></BuildAction>
<TestAction buildConfiguration="Debug" selectedDebuggerIdentifier="Xcode.DebuggerFoundation.Debugger.LLDB" selectedLauncherIdentifier="Xcode.IDEFoundation.Launcher.LLDB" shouldUseLaunchSchemeArgsEnv="YES"/>
<LaunchAction buildConfiguration="Debug" selectedDebuggerIdentifier="Xcode.DebuggerFoundation.Debugger.LLDB" selectedLauncherIdentifier="Xcode.IDEFoundation.Launcher.LLDB" launchStyle="0" useCustomWorkingDirectory="NO" ignoresPersistentStateOnLaunch="NO" debugDocumentVersioning="YES" debugServiceExtension="internal" allowLocationSimulation="YES"><BuildableProductRunnable runnableDebuggingMode="0"><BuildableReference BuildableIdentifier="primary" BlueprintIdentifier="{uid('target')}" BuildableName="Leon.app" BlueprintName="Leon" ReferencedContainer="container:Leon.xcodeproj"/></BuildableProductRunnable></LaunchAction>
<ProfileAction buildConfiguration="Release" shouldUseLaunchSchemeArgsEnv="YES" savedToolIdentifier="" useCustomWorkingDirectory="NO" debugDocumentVersioning="YES"><BuildableProductRunnable runnableDebuggingMode="0"><BuildableReference BuildableIdentifier="primary" BlueprintIdentifier="{uid('target')}" BuildableName="Leon.app" BlueprintName="Leon" ReferencedContainer="container:Leon.xcodeproj"/></BuildableProductRunnable></ProfileAction>
<AnalyzeAction buildConfiguration="Debug"/><ArchiveAction buildConfiguration="Release" revealArchiveInOrganizer="YES"/>
</Scheme>'''
(root/'Leon.xcodeproj/xcshareddata/xcschemes/Leon.xcscheme').write_text(scheme)
print('Generated native Xcode project with',len(sources),'Swift sources.')
