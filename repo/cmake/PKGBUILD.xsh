use pm.configure as configure
use pm.make as make
use pm.util as pm_util

error ScriptError = Failed(kind: Str, message: Str)

export let name: Str = "cmake"

export let ver: Str = "4.3.1"

export let rel: Str = "10"

export let deps: List[Str] = ["musl", "llvm-toolchain", "libunwind"]

export let mkdeps: List[Str] = ["llvm-toolchain", "samurai"]

export let sources: List[Path] = [
  p"https://cmake.org/files/vMAJOR.MINOR/cmake-VERSION.tar.gz",
  p"patches/cmake-no-execinfo.patch",
]

export let checksums: List[Str] = [
  "0798f4be7a1a406a419ac32db90c2956936fecbf50db3057d7af47d69a2d7edb",
  "93f5582efd076673f9bcb3e639bd594e378954a5a3130e5921027ede23c3325c",
]

pure regex_replace(text: Str, pattern: Str, replacement: Str) -> Result[Str] {
  let re = regex.compile(pattern)?
  return re.replace(text, replacement)
}

export proc build(dest: Path) [fs, process, env, error] {
  let cc = process.which("cc")?
  let target_arch = pm_util.target_arch()?
  let build_arch = pm_util.build_arch()?
  let triple = f"${target_arch}-linux-musl"
  let build_triple = f"${build_arch}-linux-musl"
  let cross_build = build_arch != target_arch
  let tool_prefix = cc.parent.parent
  let tool_lib = fp"${tool_prefix}/lib"
  var bootstrap_cc = cc
  var bootstrap_triple = triple
  var bootstrap_task_env: Record = {}
  var bootstrap_ld_library_path = tool_lib.display()

  if cross_build {
    let build_root = Path.parse((env.get("XSH_PM_BUILD_ROOT") ?? "").trim())?
    bootstrap_cc = fp"${build_root}/usr/bin/cc"
    bootstrap_triple = build_triple
    bootstrap_ld_library_path = f"${build_root}/usr/lib:${build_root}/usr/lib/llvm22/lib"
    bootstrap_task_env = {
      XSH_MAKE_NATIVE_CROSS: "0",
      PATH: f"${build_root}/usr/bin:${build_root}/usr/lib/llvm-toolchain/bin:${env.get("PATH") ?? ""}",
      LD_LIBRARY_PATH: f"${build_root}/usr/lib:${build_root}/usr/lib/llvm22/lib",
    }
  }

  # Step 1: apply musl compatibility patch in XSH (no `patch` binary required).
  let si_path = p"Source/kwsys/SystemInformation.cxx"
  var si = fs.read_text(si_path)?

  si = si.replace(
    """#if defined(KWSYS_SYSTEMINFORMATION_HAS_BACKTRACE)
#  include <execinfo.h>
#  if defined(KWSYS_SYSTEMINFORMATION_HAS_CPP_DEMANGLE)
#    include <cxxabi.h>
#  endif
#  if defined(KWSYS_SYSTEMINFORMATION_HAS_SYMBOL_LOOKUP)
#    include <dlfcn.h>
#  endif
#else
""",
    "",
  )

  si = si.replace(
    """#  undef KWSYS_SYSTEMINFORMATION_HAS_CPP_DEMANGLE
#  undef KWSYS_SYSTEMINFORMATION_HAS_SYMBOL_LOOKUP
#endif
""",
    """#  undef KWSYS_SYSTEMINFORMATION_HAS_CPP_DEMANGLE
#  undef KWSYS_SYSTEMINFORMATION_HAS_SYMBOL_LOOKUP
""",
  )

  fs.write_atomic(si_path, si)?
  let pt_path = p"Source/kwsys/kwsysPlatformTestsCXX.cxx"
  var pt = fs.read_text(pt_path)?

  let pt_patched = regex_replace(
    pt,
    """#ifdef TEST_KWSYS_CXX_HAS_BACKTRACE
(?:[^
]*
)*?#endif

""",
    "",
  )?

  fs.write_atomic(pt_path, pt_patched)?
  let st_path = p"Source/cmSystemTools.cxx"
  var st = fs.read_text(st_path)?

  st = st.replace(
    """#ifdef __linux__
#  include <linux/fs.h>

#  include <sys/ioctl.h>
#endif
""",
    """#ifdef __linux__
#  include <sys/ioctl.h>
#  ifndef FS_IOC_GETFLAGS
#    define FS_IOC_GETFLAGS _IOR('f', 1, long)
#  endif
#endif
""",
  )

  fs.write_atomic(st_path, st)?
  let kwst_path = p"Source/kwsys/SystemTools.cxx"
  var kwst = fs.read_text(kwst_path)?

  kwst = kwst.replace(
    """#ifdef __linux
#  include <linux/fs.h>
#endif
""",
    """#ifdef __linux
#  ifndef FICLONE
#    define FICLONE _IOW(0x94, 9, int)
#  endif
#endif
""",
  )

  fs.write_atomic(kwst_path, kwst)?

  # Step 2: generate bootstrap headers — replaces cmake's bootstrap shell script.
  # All values are precomputed for Clang + musl on aarch64 and x86_64.
  let bsdir = p"Bootstrap.cmk"
  fs.mkdir(bsdir)?

  fs.write(
    fp"${bsdir}/cmVersionConfig.h",
    """#define CMake_VERSION_MAJOR 4
#define CMake_VERSION_MINOR 3
#define CMake_VERSION_PATCH 1
#define CMake_VERSION "4.3.1"
""",
  )?

  let src_dir = fs.cwd()?

  fs.write(
    fp"${bsdir}/cmConfigure.h",
    f"""#define CMAKE_BOOTSTRAP_SOURCE_DIR "${src_dir.display()}"
#define CMAKE_BOOTSTRAP_BINARY_DIR "${src_dir.display()}/Bootstrap.cmk"
#define CMake_DEFAULT_RECURSION_LIMIT 400
#define CMAKE_BIN_DIR "/bootstrap-not-installed"
#define CMAKE_DATA_DIR "/bootstrap-not-installed"
#define CM_FALLTHROUGH
#define CMAKE_BOOTSTRAP_NINJA
""",
  )?

  fs.write(fp"${bsdir}/cmSTL.hxx", "")?

  # cmThirdParty.h: only #pragma once when using bundled libs (no system libs).
  # cmake's bootstrap only adds #define CMAKE_USE_SYSTEM_* when system libs are found.
  fs.write(
    fp"${bsdir}/cmThirdParty.h",
    """#pragma once
""",
  )?

  # Generate kwsys headers from *.in templates (cmake's bootstrap processes these
  # with sed; we use configure.substitute). All values precomputed for Clang + musl.
  let kwsys_subs = [
    ["KWSYS_NAMESPACE", "cmsys"],
    ["KWSYS_BUILD_SHARED", "0"],
    ["KWSYS_LFS_AVAILABLE", "1"],
    ["KWSYS_LFS_REQUESTED", "1"],
    ["KWSYS_NAME_IS_KWSYS", "0"],
    ["KWSYS_CXX_HAS_EXT_STDIO_FILEBUF_H", "0"],
  ]

  fs.mkdir(fp"${bsdir}/cmsys")?

  for hdr in [
    "Configure.h",
    "Configure.hxx",
    "Directory.hxx",
    "Encoding.h",
    "Encoding.hxx",
    "FStream.hxx",
    "Glob.hxx",
    "Process.h",
    "RegularExpression.hxx",
    "Status.hxx",
    "String.h",
    "System.h",
    "SystemTools.hxx",
  ] {
    configure.substitute(fp"Source/kwsys/${hdr}.in", fp"${bsdir}/cmsys/${hdr}", kwsys_subs)?
  }

  # Step 3: compile bootstrap cmake from source. No sh, no configure, no make.
  # Source categories from CMAKE_*_SOURCES in cmake's bootstrap script.
  fs.mkdir(fp"${bsdir}/obj")?

  # Pre-combined flag lists (XSH has no list concat, so build them explicitly).
  # Linux system flags + cmake bootstrap flags + includes
  let cxx_all = [
    "-D_FILE_OFFSET_BITS=64",
    "-D_TIME_BITS=64",
    "-DCMAKE_BOOTSTRAP",
    "-DCMake_HAVE_CXX_MAKE_UNIQUE=1",
    "-DCMake_HAVE_CXX_FILESYSTEM=1",
    f"-I${bsdir.display()}",
    "-ISource",
    "-ISource/LexerParser",
    "-IUtilities/std",
    "-IUtilities",
  ]

  let c_all = [
    "-D_FILE_OFFSET_BITS=64",
    "-D_TIME_BITS=64",
    "-DCMAKE_BOOTSTRAP",
    f"-I${bsdir.display()}",
    "-ISource",
    "-ISource/LexerParser",
    "-IUtilities",
  ]

  # kwsys feature flags for Clang + musl (captured from cmake's bootstrap log).
  # setenv=1, unsetenv=1: musl has them. environ_in_stdlib=0: musl doesn't expose it.
  # utimensat=1, utimes=1: musl has both. backtrace/demangle/symbol_lookup=0: patched out.
  let kwsys_all = [
    "-D_FILE_OFFSET_BITS=64",
    "-D_TIME_BITS=64",
    "-DCMAKE_BOOTSTRAP",
    "-DCMake_HAVE_CXX_MAKE_UNIQUE=1",
    "-DCMake_HAVE_CXX_FILESYSTEM=1",
    "-DKWSYS_NAMESPACE=cmsys",
    "-DKWSYS_CXX_HAS_SETENV=1",
    "-DKWSYS_CXX_HAS_UNSETENV=1",
    "-DKWSYS_CXX_HAS_ENVIRON_IN_STDLIB_H=0",
    "-DKWSYS_CXX_HAS_UTIMENSAT=1",
    "-DKWSYS_CXX_HAS_UTIMES=1",
    f"-I${bsdir.display()}",
    "-ISource",
    "-ISource/kwsys",
  ]

  # SystemTools also has backtrace/demangle/symbol_lookup flags
  let kwsys_st = [
    "-D_FILE_OFFSET_BITS=64",
    "-D_TIME_BITS=64",
    "-DCMAKE_BOOTSTRAP",
    "-DCMake_HAVE_CXX_MAKE_UNIQUE=1",
    "-DCMake_HAVE_CXX_FILESYSTEM=1",
    "-DKWSYS_NAMESPACE=cmsys",
    "-DKWSYS_CXX_HAS_SETENV=1",
    "-DKWSYS_CXX_HAS_UNSETENV=1",
    "-DKWSYS_CXX_HAS_ENVIRON_IN_STDLIB_H=0",
    "-DKWSYS_CXX_HAS_UTIMENSAT=1",
    "-DKWSYS_CXX_HAS_UTIMES=1",
    "-DKWSYS_SYSTEMINFORMATION_HAS_BACKTRACE=0",
    "-DKWSYS_SYSTEMINFORMATION_HAS_CPP_DEMANGLE=0",
    "-DKWSYS_SYSTEMINFORMATION_HAS_SYMBOL_LOOKUP=0",
    f"-I${bsdir.display()}",
    "-ISource",
    "-ISource/kwsys",
  ]

  let uv_all = [
    "-D_FILE_OFFSET_BITS=64",
    "-D_TIME_BITS=64",
    "-DCMAKE_BOOTSTRAP",
    "-D_GNU_SOURCE",
    f"-I${bsdir.display()}",
    "-IUtilities/cmlibuv/include",
    "-IUtilities/cmlibuv/src",
    "-IUtilities/cmlibuv/src/unix",
  ]

  let rhash_all = [
    "-D_FILE_OFFSET_BITS=64",
    "-D_TIME_BITS=64",
    "-DNO_IMPORT_EXPORT",
    f"-I${bsdir.display()}",
    "-IUtilities/cmlibrhash",
    "-IUtilities",
  ]

  let jsoncpp_all = [
    "-D_FILE_OFFSET_BITS=64",
    "-D_TIME_BITS=64",
    "-DCMAKE_BOOTSTRAP",
    f"-I${bsdir.display()}",
    "-IUtilities/cmjsoncpp/include",
    "-IUtilities",
  ]

  var objs: List[Path] = []
  var tasks: List[make.MakeTask] = []
  var obj_deps: List[Str] = []

  # cmake CXX sources: Source/cm*.cxx (list from CMAKE_CXX_SOURCES in bootstrap)
  for s in [
    "cmAddCompileDefinitionsCommand",
    "cmAddCustomCommandCommand",
    "cmAddCustomTargetCommand",
    "cmAddDefinitionsCommand",
    "cmAddDependenciesCommand",
    "cmAddExecutableCommand",
    "cmAddLibraryCommand",
    "cmAddSubDirectoryCommand",
    "cmAddTestCommand",
    "cmArgumentParser",
    "cmBinUtilsLinker",
    "cmBinUtilsLinuxELFGetRuntimeDependenciesTool",
    "cmBinUtilsLinuxELFLinker",
    "cmBinUtilsLinuxELFObjdumpGetRuntimeDependenciesTool",
    "cmBinUtilsMacOSMachOGetRuntimeDependenciesTool",
    "cmBinUtilsMacOSMachOLinker",
    "cmBinUtilsMacOSMachOOToolGetRuntimeDependenciesTool",
    "cmBinUtilsWindowsPEGetRuntimeDependenciesTool",
    "cmBinUtilsWindowsPEDumpbinGetRuntimeDependenciesTool",
    "cmBinUtilsWindowsPELinker",
    "cmBinUtilsWindowsPEObjdumpGetRuntimeDependenciesTool",
    "cmBlockCommand",
    "cmBreakCommand",
    "cmBuildCommand",
    "cmBuildDatabase",
    "cmCMakeLanguageCommand",
    "cmCMakeMinimumRequired",
    "cmList",
    "cmCMakePath",
    "cmCMakePathCommand",
    "cmCMakePolicyCommand",
    "cmCMakeString",
    "cmCPackPropertiesGenerator",
    "cmCacheManager",
    "cmCommands",
    "cmCommonTargetGenerator",
    "cmComputeComponentGraph",
    "cmComputeLinkDepends",
    "cmComputeLinkInformation",
    "cmComputeTargetDepends",
    "cmConditionEvaluator",
    "cmConfigureFileCommand",
    "cmContinueCommand",
    "cmCoreTryCompile",
    "cmCreateTestSourceList",
    "cmCryptoHash",
    "cmCustomCommand",
    "cmCustomCommandGenerator",
    "cmCustomCommandLines",
    "cmCxxModuleMapper",
    "cmCxxModuleUsageEffects",
    "cmDefinePropertyCommand",
    "cmDefinitions",
    "cmDocumentationFormatter",
    "cmELF",
    "cmEnableLanguageCommand",
    "cmEnableTestingCommand",
    "cmEvaluatedTargetProperty",
    "cmExecProgramCommand",
    "cmExecuteProcessCommand",
    "cmExpandedCommandArgument",
    "cmExperimental",
    "cmExportBuildCMakeConfigGenerator",
    "cmExportBuildFileGenerator",
    "cmExportCMakeConfigGenerator",
    "cmExportFileGenerator",
    "cmExportInstallCMakeConfigGenerator",
    "cmExportInstallFileGenerator",
    "cmExportSet",
    "cmExportTryCompileFileGenerator",
    "cmExprParserHelper",
    "cmExternalMakefileProjectGenerator",
    "cmFileCommand",
    "cmFileCommand_ReadMacho",
    "cmFileCopier",
    "cmFileInstaller",
    "cmFileSet",
    "cmFileTime",
    "cmFileTimeCache",
    "cmFileTimes",
    "cmFindBase",
    "cmFindCommon",
    "cmFindFileCommand",
    "cmFindLibraryCommand",
    "cmFindPackageCommand",
    "cmFindPackageStack",
    "cmFindPathCommand",
    "cmFindProgramCommand",
    "cmForEachCommand",
    "cmFunctionBlocker",
    "cmFunctionCommand",
    "cmFSPermissions",
    "cmGeneratedFileStream",
    "cmGenExContext",
    "cmGenExEvaluation",
    "cmGeneratorExpression",
    "cmGeneratorExpressionDAGChecker",
    "cmGeneratorExpressionEvaluationFile",
    "cmGeneratorExpressionEvaluator",
    "cmGeneratorExpressionLexer",
    "cmGeneratorExpressionNode",
    "cmGeneratorExpressionParser",
    "cmGeneratorTarget",
    "cmGeneratorTarget_CompatibleInterface",
    "cmGeneratorTarget_IncludeDirectories",
    "cmGeneratorTarget_Link",
    "cmGeneratorTarget_LinkDirectories",
    "cmGeneratorTarget_Options",
    "cmGeneratorTarget_Sources",
    "cmGeneratorTarget_TargetPropertyEntry",
    "cmGeneratorTarget_TransitiveProperty",
    "cmGetCMakePropertyCommand",
    "cmGetDirectoryPropertyCommand",
    "cmGetFilenameComponentCommand",
    "cmGetPipes",
    "cmGetPropertyCommand",
    "cmGetSourceFilePropertyCommand",
    "cmGetTargetPropertyCommand",
    "cmGetTestPropertyCommand",
    "cmGlobalCommonGenerator",
    "cmGlobalGenerator",
    "cmGlobVerificationManager",
    "cmHexFileConverter",
    "cmIfCommand",
    "cmImportedCxxModuleInfo",
    "cmIncludeCommand",
    "cmIncludeGuardCommand",
    "cmIncludeDirectoryCommand",
    "cmIncludeRegularExpressionCommand",
    "cmInstallCMakeConfigExportGenerator",
    "cmInstallCommand",
    "cmInstallCommandArguments",
    "cmInstallCxxModuleBmiGenerator",
    "cmInstallDirectoryGenerator",
    "cmInstallExportGenerator",
    "cmInstallFileSetGenerator",
    "cmInstallFilesCommand",
    "cmInstallFilesGenerator",
    "cmInstallGenerator",
    "cmInstallGetRuntimeDependenciesGenerator",
    "cmInstallImportedRuntimeArtifactsGenerator",
    "cmInstallRuntimeDependencySet",
    "cmInstallRuntimeDependencySetGenerator",
    "cmInstallScriptGenerator",
    "cmInstallSubdirectoryGenerator",
    "cmInstallTargetGenerator",
    "cmInstallTargetsCommand",
    "cmInstalledFile",
    "cmJSONHelpers",
    "cmJSONState",
    "cmLDConfigLDConfigTool",
    "cmLDConfigTool",
    "cmLinkDirectoriesCommand",
    "cmLinkItem",
    "cmLinkItemGraphVisitor",
    "cmLinkLineComputer",
    "cmLinkLineDeviceComputer",
    "cmListCommand",
    "cmListFileCache",
    "cmLocalCommonGenerator",
    "cmLocalGenerator",
    "cmMSVC60LinkLineComputer",
    "cmMacroCommand",
    "cmMakeDirectoryCommand",
    "cmMakefile",
    "cmMarkAsAdvancedCommand",
    "cmMathCommand",
    "cmMessageCommand",
    "cmMessenger",
    "cmNewLineStyle",
    "cmOSXBundleGenerator",
    "cmOptionCommand",
    "cmOrderDirectories",
    "cmObjectLocation",
    "cmOutputConverter",
    "cmParseArgumentsCommand",
    "cmPathLabel",
    "cmPathResolver",
    "cmPolicies",
    "cmProcessOutput",
    "cmProjectCommand",
    "cmValue",
    "cmPropertyDefinition",
    "cmPropertyMap",
    "cmGccDepfileLexerHelper",
    "cmGccDepfileReader",
    "cmReturnCommand",
    "cmPackageInfoReader",
    "cmPlaceholderExpander",
    "cmPlistParser",
    "cmRulePlaceholderExpander",
    "cmRuntimeDependencyArchive",
    "cmScriptGenerator",
    "cmSearchPath",
    "cmSeparateArgumentsCommand",
    "cmSetCommand",
    "cmSetDirectoryPropertiesCommand",
    "cmSetPropertyCommand",
    "cmSetSourceFilesPropertiesCommand",
    "cmSetTargetPropertiesCommand",
    "cmSetTestsPropertiesCommand",
    "cmSiteNameCommand",
    "cmSourceFile",
    "cmSourceFileLocation",
    "cmStandardLevelResolver",
    "cmState",
    "cmStateDirectory",
    "cmStateSnapshot",
    "cmStdIoConsole",
    "cmStdIoInit",
    "cmStdIoStream",
    "cmStdIoTerminal",
    "cmString",
    "cmStringAlgorithms",
    "cmStringReplaceHelper",
    "cmStringCommand",
    "cmSubcommandTable",
    "cmSubdirCommand",
    "cmSystemTools",
    "cmTarget",
    "cmTargetCompileDefinitionsCommand",
    "cmTargetCompileFeaturesCommand",
    "cmTargetCompileOptionsCommand",
    "cmTargetIncludeDirectoriesCommand",
    "cmTargetLinkLibrariesCommand",
    "cmTargetLinkOptionsCommand",
    "cmTargetPrecompileHeadersCommand",
    "cmTargetPropCommandBase",
    "cmTargetPropertyComputer",
    "cmTargetSourcesCommand",
    "cmTargetTraceDependencies",
    "cmTest",
    "cmTestGenerator",
    "cmTimestamp",
    "cmTransformDepfile",
    "cmTryCompileCommand",
    "cmTryRunCommand",
    "cmUnsetCommand",
    "cmUVHandlePtr",
    "cmUVProcessChain",
    "cmVersion",
    "cmWhileCommand",
    "cmWindowsRegistry",
    "cmWorkingDirectory",
    "cmXcFramework",
    "cmake",
    "cmakemain",
    "cmcmd",
    "cm_fileno",
  ] {
    let out = fp"${bsdir}/obj/${s}.o"
    let task = make.compile_cxx_task(bootstrap_cc, bootstrap_triple, cxx_all, [], [], fp"Source/${s}.cxx", out)
    tasks = tasks.push(task)
    obj_deps = obj_deps.push(task.name)
    objs = objs.push(out)
  }

  # Ninja generator sources (bootstrap uses Ninja so samu can drive the full build).
  for s in [
    "cmFortranParserImpl",
    "cmGlobalNinjaGenerator",
    "cmLocalNinjaGenerator",
    "cmNinjaLinkLineComputer",
    "cmNinjaLinkLineDeviceComputer",
    "cmNinjaNormalTargetGenerator",
    "cmNinjaTargetGenerator",
    "cmNinjaUtilityTargetGenerator",
  ] {
    let out = fp"${bsdir}/obj/${s}.o"
    let task = make.compile_cxx_task(bootstrap_cc, bootstrap_triple, cxx_all, [], [], fp"Source/${s}.cxx", out)
    tasks = tasks.push(task)
    obj_deps = obj_deps.push(task.name)
    objs = objs.push(out)
  }

  # Fortran LexerParser sources needed by the Ninja generator.
  for s in ["cmFortranLexer", "cmFortranParser"] {
    let out = fp"${bsdir}/obj/${s}.o"
    let task = make.compile_cxx_task(bootstrap_cc, bootstrap_triple, cxx_all, [], [], fp"Source/LexerParser/${s}.cxx", out)
    tasks = tasks.push(task)
    obj_deps = obj_deps.push(task.name)
    objs = objs.push(out)
  }

  # cmake C source: Source/cm_utf8.c
  let utf8_out = fp"${bsdir}/obj/cm_utf8.o"
  let utf8_task = make.compile_c_task(bootstrap_cc, bootstrap_triple, c_all, [], [], p"Source/cm_utf8.c", utf8_out)
  tasks = tasks.push(utf8_task)
  obj_deps = obj_deps.push(utf8_task.name)
  objs = objs.push(utf8_out)

  # Utilities/std: fs_path.cxx, string_view.cxx
  for s in ["fs_path", "string_view"] {
    let out = fp"${bsdir}/obj/${s}.o"
    let task = make.compile_cxx_task(bootstrap_cc, bootstrap_triple, cxx_all, [], [], fp"Utilities/std/cm/bits/${s}.cxx", out)
    tasks = tasks.push(task)
    obj_deps = obj_deps.push(task.name)
    objs = objs.push(out)
  }

  # LexerParser CXX
  for s in ["cmExprLexer", "cmExprParser", "cmGccDepfileLexer"] {
    let out = fp"${bsdir}/obj/${s}.o"
    let task = make.compile_cxx_task(bootstrap_cc, bootstrap_triple, cxx_all, [], [], fp"Source/LexerParser/${s}.cxx", out)
    tasks = tasks.push(task)
    obj_deps = obj_deps.push(task.name)
    objs = objs.push(out)
  }

  # LexerParser C
  let lfl_out = fp"${bsdir}/obj/cmListFileLexer.o"
  let lfl_task = make.compile_c_task(bootstrap_cc, bootstrap_triple, c_all, [], [], p"Source/LexerParser/cmListFileLexer.c", lfl_out)
  tasks = tasks.push(lfl_task)
  obj_deps = obj_deps.push(lfl_task.name)
  objs = objs.push(lfl_out)

  # kwsys C sources (KWSYS_C_SOURCES from bootstrap — unix branch).
  # Per-source flags: String.c requires -DKWSYS_STRING_C to activate its body.
  let kwsys_c_base = [
    "-D_FILE_OFFSET_BITS=64",
    "-D_TIME_BITS=64",
    "-DCMAKE_BOOTSTRAP",
    "-DKWSYS_NAMESPACE=cmsys",
    f"-I${bsdir.display()}",
    "-ISource",
    "-ISource/kwsys",
  ]

  for s in ["EncodingC", "ProcessUNIX", "System"] {
    let out = fp"${bsdir}/obj/kwsys-c-${s}.o"
    let task = make.compile_c_task(bootstrap_cc, bootstrap_triple, kwsys_c_base, [], [], fp"Source/kwsys/${s}.c", out)
    tasks = tasks.push(task)
    obj_deps = obj_deps.push(task.name)
    objs = objs.push(out)
  }

  let string_flags = [
    "-D_FILE_OFFSET_BITS=64",
    "-D_TIME_BITS=64",
    "-DCMAKE_BOOTSTRAP",
    "-DKWSYS_NAMESPACE=cmsys",
    "-DKWSYS_STRING_C",
    f"-I${bsdir.display()}",
    "-ISource",
    "-ISource/kwsys",
  ]

  let string_out = fp"${bsdir}/obj/kwsys-c-String.o"
  let string_task = make.compile_c_task(bootstrap_cc, bootstrap_triple, string_flags, [], [], p"Source/kwsys/String.c", string_out)
  tasks = tasks.push(string_task)
  obj_deps = obj_deps.push(string_task.name)
  objs = objs.push(string_out)

  # kwsys CXX (KWSYS_CXX_SOURCES from bootstrap)
  for s in ["Directory", "EncodingCXX", "FStream", "Glob", "RegularExpression", "Status"] {
    let out = fp"${bsdir}/obj/kwsys-${s}.o"
    let task = make.compile_cxx_task(bootstrap_cc, bootstrap_triple, kwsys_all, [], [], fp"Source/kwsys/${s}.cxx", out)
    tasks = tasks.push(task)
    obj_deps = obj_deps.push(task.name)
    objs = objs.push(out)
  }

  let st_out = fp"${bsdir}/obj/kwsys-SystemTools.o"
  let st_task = make.compile_cxx_task(bootstrap_cc, bootstrap_triple, kwsys_st, [], [], p"Source/kwsys/SystemTools.cxx", st_out)
  tasks = tasks.push(st_task)
  obj_deps = obj_deps.push(st_task.name)
  objs = objs.push(st_out)

  # libuv C sources (unix branch, bundled)
  for s in [
    "src/strscpy.c",
    "src/strtok.c",
    "src/timer.c",
    "src/uv-common.c",
    "src/unix/cmake-bootstrap.c",
    "src/unix/core.c",
    "src/unix/fs.c",
    "src/unix/loop.c",
    "src/unix/loop-watcher.c",
    "src/unix/no-fsevents.c",
    "src/unix/pipe.c",
    "src/unix/poll.c",
    "src/unix/posix-hrtime.c",
    "src/unix/posix-poll.c",
    "src/unix/process.c",
    "src/unix/signal.c",
    "src/unix/stream.c",
    "src/unix/tcp.c",
    "src/unix/tty.c",
  ] {
    let out_name = s.replace("/", "-").replace(".c", ".o")
    let out = fp"${bsdir}/obj/uv-${out_name}"
    let task = make.compile_c_task(bootstrap_cc, bootstrap_triple, uv_all, [], [], fp"Utilities/cmlibuv/${s}", out)
    tasks = tasks.push(task)
    obj_deps = obj_deps.push(task.name)
    objs = objs.push(out)
  }

  # librhash C sources (bundled)
  for s in [
    "librhash/algorithms.c",
    "librhash/byte_order.c",
    "librhash/hex.c",
    "librhash/md5.c",
    "librhash/rhash.c",
    "librhash/sha1.c",
    "librhash/sha256.c",
    "librhash/sha3.c",
    "librhash/sha512.c",
    "librhash/util.c",
  ] {
    let out_name = s.replace("/", "-").replace(".c", ".o")
    let out = fp"${bsdir}/obj/rhash-${out_name}"
    let task = make.compile_c_task(bootstrap_cc, bootstrap_triple, rhash_all, [], [], fp"Utilities/cmlibrhash/${s}", out)
    tasks = tasks.push(task)
    obj_deps = obj_deps.push(task.name)
    objs = objs.push(out)
  }

  # jsoncpp CXX sources (bundled)
  for s in ["src/lib_json/json_reader.cpp", "src/lib_json/json_value.cpp", "src/lib_json/json_writer.cpp"] {
    let out_name = s.replace("/", "-").replace(".cpp", ".o")
    let out = fp"${bsdir}/obj/jsoncpp-${out_name}"
    let task = make.compile_cxx_task(bootstrap_cc, bootstrap_triple, jsoncpp_all, [], [], fp"Utilities/cmjsoncpp/${s}", out)
    tasks = tasks.push(task)
    obj_deps = obj_deps.push(task.name)
    objs = objs.push(out)
  }

  # Step 4: link the bootstrap cmake binary (C++ program needs C++ compiler driver).
  let bootstrap_cmake = fp"${bsdir}/cmake"
  tasks = tasks.push(make.link_executable_cxx_task(bootstrap_cc, bootstrap_triple, objs, [], ["-ldl", "-lrt"], bootstrap_cmake, obj_deps))
  if cross_build {
    tasks = [{...task, env: bootstrap_task_env} for task in tasks]
  }

  make.run_tasks(tasks, make.jobs()?)?


  # Step 5: generate InitialCacheFlags.cmake — passed as -C to bootstrap cmake.
  # The bootstrap script generates this to configure install paths and features.
  fs.write(
    fp"${bsdir}/InitialCacheFlags.cmake",
    """# Generated by cmake PKGBUILD.xsh bootstrap
set (CMAKE_BUILD_TYPE "Release" CACHE STRING "Build type." FORCE)
set (CMAKE_INSTALL_PREFIX "/usr" CACHE PATH "Install prefix." FORCE)
set (CMAKE_DOC_DIR "share/doc/cmake" CACHE PATH "Doc dir." FORCE)
set (CMAKE_MAN_DIR "share/man" CACHE PATH "Man dir." FORCE)
set (CMAKE_BIN_DIR "bin" CACHE PATH "Bin dir." FORCE)
set (CMAKE_DATA_DIR "share/cmake" CACHE PATH "Data dir." FORCE)
set (CMAKE_XDGDATA_DIR "share" CACHE PATH "XDG data dir." FORCE)
set (CMAKE_USE_OPENSSL OFF CACHE BOOL "Use OpenSSL." FORCE)
set (CMAKE_USE_SYSTEM_LIBRARIES OFF CACHE BOOL "Use system libs." FORCE)
set (BUILD_TESTING OFF CACHE BOOL "Build tests." FORCE)
set (CMAKE_BUILD_WITH_INSTALL_RPATH ON CACHE BOOL "Use install rpath in the build tree." FORCE)
set (CMAKE_INSTALL_RPATH "$ORIGIN/../lib" CACHE STRING "Runtime library search path." FORCE)
""",
  )?

  # Step 6: run bootstrap cmake with Ninja generator, then build with samu.
  # No Alpine make required — samu is a mkdep and on PATH via /build-env.
  let samu = process.which("samu")?
  let jobs = make.jobs()?
  let jobs_flag = f"-j${jobs}"
  let build_dir = p"cmake-build"
  fs.mkdir(build_dir)?

  env {
    LD_LIBRARY_PATH = bootstrap_ld_library_path
  } {
    cd cmake-build {
      let bc = fp"../Bootstrap.cmk/cmake"
      let init_cache = fp"../Bootstrap.cmk/InitialCacheFlags.cmake"

      var cmake_args: List[Str] = [
        bc.display(),
        "..",
        f"-C${init_cache.display()}",
        "-G",
        "Ninja",
        f"-DCMAKE_MAKE_PROGRAM=${samu.display()}",
        "-DCMAKE_USE_OPENSSL=OFF",
        "-DCMAKE_USE_SYSTEM_LIBRARIES=OFF",
        "-DBUILD_TESTING=OFF",
        "-DBUILD_CursesDialog=OFF",
        "-DCMAKE_DISABLE_FIND_PACKAGE_Curses=ON",
        "-DCMAKE_Fortran_COMPILER=NOTFOUND",
      ]

      let cmake_proc = process.command_argv(cmake_args[0], cmake_args)
      let cmake_status = process.run(cmake_proc)?

      if ! cmake_status.ok {
        let err_log = fp"CMakeFiles/CMakeError.log"

        if fs.exists(err_log)? {
          print ${fs.read_text(err_log)?}
        }

        Err(ScriptError.Failed("cmake-configure-failed", "bootstrap cmake configure failed"))?
      }

      run $samu $jobs_flag ?

      env {
        DESTDIR = dest.display()
      } {
        run $bc "-P" "cmake_install.cmake" ?
      } ?
    } ?
  } ?
}
