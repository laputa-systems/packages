##! XSH module `PKGBUILD` package and build operations.
use pm.configure as configure
use pm.make as make
use pm.util as pm_util

error ScriptError = Failed(kind: Str, message: Str)

## Exported declaration `name`.
export let name = "cmake"

## Explicit payload or metapackage classification.
export let package_kind = "payload"

## Exported declaration `ver`.
export let ver = "4.3.1"

## Exported declaration `rel`.
export let rel = "18"

## Exported declaration `deps`.
export let deps = ["musl", "llvm-toolchain"]

## Exported declaration `mkdeps_host`.
export let mkdeps_host = ["llvm-toolchain", "samurai"]

## Exported declaration `upstream_sources`.
export let upstream_sources = [
  {
    source: p"https://cmake.org/files/vMAJOR.MINOR/cmake-VERSION.tar.gz",
    kind: "auto",
    architectures: [
      "all",
    ],
    checksums: [
      {
        arch: "all",
        sha256: "0798f4be7a1a406a419ac32db90c2956936fecbf50db3057d7af47d69a2d7edb",
      },
    ],
  },
  {
    source: p"patches/cmake-no-execinfo.patch",
    kind: "auto",
    architectures: [
      "all",
    ],
    checksums: [
      {
        arch: "all",
        sha256: "d6ebd2eb89ded4e1e12afccfabc9bcac4220c920f424118d411062ea23ece2cb",
      },
    ],
  },
  {
    source: p"patches/cmake-musl-ioctl-fallbacks.patch",
    kind: "auto",
    architectures: [
      "all",
    ],
    checksums: [
      {
        arch: "all",
        sha256: "eaba0ffc090bf877775e6d94ce63fdd702477962d5366d3f0e260ea2446e4aac",
      },
    ],
  },
  {
    source: p"patches/cmake-libarchive-no-closefrom.patch",
    kind: "auto",
    architectures: [
      "all",
    ],
    checksums: [
      {
        arch: "all",
        sha256: "b334fe4e1718220cd3a0110759575a91e10028d1959959941e198ce90a0e1f4d",
      },
    ],
  },
]

## Exported declaration `filetree`.
export let filetree = [
  {
    path: p"usr",
    kind: "tree",
  },
  {
    path: p"usr/bin/cmake",
    kind: "binary",
  },
  {
    path: p"usr/bin/cpack",
    kind: "binary",
  },
  {
    path: p"usr/bin/ctest",
    kind: "binary",
  },
]

## Exported declaration `build`.
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
    let build_root = fp"${env.get("XSH_PM_BUILD_ROOT") ?? ""}"
    bootstrap_cc = fp"${build_root}/usr/bin/cc"
    bootstrap_triple = build_triple
    bootstrap_ld_library_path = f"${build_root}/usr/lib:${build_root}/usr/lib/llvm23/lib"

    bootstrap_task_env = {
      XSH_MAKE_NATIVE_CROSS: "0",
      PATH: f"${build_root}/usr/bin:${build_root}/usr/lib/llvm-toolchain/bin:${env.get("PATH") ?? ""}",
      LD_LIBRARY_PATH: f"${build_root}/usr/lib:${build_root}/usr/lib/llvm23/lib",
    }
  }

  # Step 1: apply musl compatibility patches in XSH (no `patch` binary required).
  for patch_file in [
    p"cmake-no-execinfo.patch",
    p"cmake-musl-ioctl-fallbacks.patch",
    p"cmake-libarchive-no-closefrom.patch",
  ] {
    let _ = patch.apply(p".", fs.read_text(patch_file)?, 1)?
  }

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
    [
      "KWSYS_NAMESPACE",
      "cmsys",
    ],
    [
      "KWSYS_BUILD_SHARED",
      "0",
    ],
    [
      "KWSYS_LFS_AVAILABLE",
      "1",
    ],
    [
      "KWSYS_LFS_REQUESTED",
      "1",
    ],
    [
      "KWSYS_NAME_IS_KWSYS",
      "0",
    ],
    [
      "KWSYS_CXX_HAS_EXT_STDIO_FILEBUF_H",
      "0",
    ],
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

  # cmake CXX sources: Source/cm*.cxx (list from CMAKE_CXX_SOURCES in bootstrap)
  let cmake_cxx_sources = [
    fp"Source/${s}.cxx"
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
    ]
  ]

  # Ninja generator sources (bootstrap uses Ninja so samu can drive the full build).
  let ninja_cxx_sources = [
    fp"Source/${s}.cxx"
    for s in [
      "cmFortranParserImpl",
      "cmGlobalNinjaGenerator",
      "cmLocalNinjaGenerator",
      "cmNinjaLinkLineComputer",
      "cmNinjaLinkLineDeviceComputer",
      "cmNinjaNormalTargetGenerator",
      "cmNinjaTargetGenerator",
      "cmNinjaUtilityTargetGenerator",
    ]
  ]

  # Fortran LexerParser sources needed by the Ninja generator.
  let fortran_lexer_sources = [fp"Source/LexerParser/${s}.cxx" for s in ["cmFortranLexer", "cmFortranParser"]]

  # Utilities/std: fs_path.cxx, string_view.cxx
  let std_cxx_sources = [fp"Utilities/std/cm/bits/${s}.cxx" for s in ["fs_path", "string_view"]]

  # LexerParser CXX
  let lexer_parser_cxx_sources = [
    fp"Source/LexerParser/${s}.cxx"
    for s in ["cmExprLexer", "cmExprParser", "cmGccDepfileLexer"]
  ]

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

  let kwsys_c_sources = [fp"Source/kwsys/${s}.c" for s in ["EncodingC", "ProcessUNIX", "System"]]

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

  # kwsys CXX (KWSYS_CXX_SOURCES from bootstrap)
  let kwsys_cxx_sources = [
    fp"Source/kwsys/${s}.cxx"
    for s in ["Directory", "EncodingCXX", "FStream", "Glob", "RegularExpression", "Status"]
  ]

  # libuv C sources (unix branch, bundled)
  let uv_sources = [
    fp"Utilities/cmlibuv/${s}"
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
    ]
  ]

  # librhash C sources (bundled)
  let rhash_sources = [
    fp"Utilities/cmlibrhash/${s}"
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
    ]
  ]

  # jsoncpp CXX sources (bundled)
  let jsoncpp_sources = [
    fp"Utilities/cmjsoncpp/${s}"
    for s in ["src/lib_json/json_reader.cpp", "src/lib_json/json_value.cpp", "src/lib_json/json_writer.cpp"]
  ]

  # Step 4: link the bootstrap cmake binary (C++ program needs C++ compiler driver).
  let bootstrap_cmake = fp"${bsdir}/cmake"

  let bootstrap_target = make.c_multi_program(
    {
      cc: bootstrap_cc,
      triple: bootstrap_triple,
      cflags: [],
      defs: [],
      includes: [],
      root: p".",
      out_dir: fp"${bsdir}/obj",
      groups: [
        {
          name: "cmake-cxx",
          cflags: cxx_all,
          defs: [],
          includes: [],
          root: p".",
          sources: cmake_cxx_sources,
          out_dir: p"",
          deps: [],
        },
        {
          name: "ninja-cxx",
          cflags: cxx_all,
          defs: [],
          includes: [],
          root: p".",
          sources: ninja_cxx_sources,
          out_dir: p"",
          deps: [],
        },
        {
          name: "fortran-lexer",
          cflags: cxx_all,
          defs: [],
          includes: [],
          root: p".",
          sources: fortran_lexer_sources,
          out_dir: p"",
          deps: [],
        },
        {
          name: "cmake-c",
          cflags: c_all,
          defs: [],
          includes: [],
          root: p".",
          sources: [
            p"Source/cm_utf8.c",
          ],
          out_dir: p"",
          deps: [],
        },
        {
          name: "std-cxx",
          cflags: cxx_all,
          defs: [],
          includes: [],
          root: p".",
          sources: std_cxx_sources,
          out_dir: p"",
          deps: [],
        },
        {
          name: "lexer-parser-cxx",
          cflags: cxx_all,
          defs: [],
          includes: [],
          root: p".",
          sources: lexer_parser_cxx_sources,
          out_dir: p"",
          deps: [],
        },
        {
          name: "lexer-parser-c",
          cflags: c_all,
          defs: [],
          includes: [],
          root: p".",
          sources: [
            p"Source/LexerParser/cmListFileLexer.c",
          ],
          out_dir: p"",
          deps: [],
        },
        {
          name: "kwsys-c",
          cflags: kwsys_c_base,
          defs: [],
          includes: [],
          root: p".",
          sources: kwsys_c_sources,
          out_dir: p"",
          deps: [],
        },
        {
          name: "kwsys-string",
          cflags: string_flags,
          defs: [],
          includes: [],
          root: p".",
          sources: [
            p"Source/kwsys/String.c",
          ],
          out_dir: p"",
          deps: [],
        },
        {
          name: "kwsys-cxx",
          cflags: kwsys_all,
          defs: [],
          includes: [],
          root: p".",
          sources: kwsys_cxx_sources,
          out_dir: p"",
          deps: [],
        },
        {
          name: "kwsys-system-tools",
          cflags: kwsys_st,
          defs: [],
          includes: [],
          root: p".",
          sources: [
            p"Source/kwsys/SystemTools.cxx",
          ],
          out_dir: p"",
          deps: [],
        },
        {
          name: "uv",
          cflags: uv_all,
          defs: [],
          includes: [],
          root: p".",
          sources: uv_sources,
          out_dir: p"",
          deps: [],
        },
        {
          name: "rhash",
          cflags: rhash_all,
          defs: [],
          includes: [],
          root: p".",
          sources: rhash_sources,
          out_dir: p"",
          deps: [],
        },
        {
          name: "jsoncpp",
          cflags: jsoncpp_all,
          defs: [],
          includes: [],
          root: p".",
          sources: jsoncpp_sources,
          out_dir: p"",
          deps: [],
        },
      ],
      targets: [
        {
          name: "cmake",
          groups: [
            "cmake-cxx",
            "ninja-cxx",
            "fortran-lexer",
            "cmake-c",
            "std-cxx",
            "lexer-parser-cxx",
            "lexer-parser-c",
            "kwsys-c",
            "kwsys-string",
            "kwsys-cxx",
            "kwsys-system-tools",
            "uv",
            "rhash",
            "jsoncpp",
          ],
          sources: [],
          libs: [],
          ldflags: [
            "-ldl",
            "-lrt",
            "-Wl,--unresolved-symbols=ignore-all",
          ],
          out: bootstrap_cmake,
          deps: [],
        },
      ],
    },
  )?

  var tasks = bootstrap_target.tasks

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
set (CMAKE_C_COMPILER "/usr/bin/cc" CACHE FILEPATH "C compiler." FORCE)
set (CMAKE_CXX_COMPILER "/usr/bin/c++" CACHE FILEPATH "C++ compiler." FORCE)
set (CMAKE_EXE_LINKER_FLAGS "-Wl,--unresolved-symbols=ignore-all" CACHE STRING "Executable linker flags." FORCE)
set (CMAKE_INSTALL_PREFIX "/usr" CACHE PATH "Install prefix." FORCE)
set (CMAKE_DOC_DIR "share/doc/cmake" CACHE PATH "Doc dir." FORCE)
set (CMAKE_MAN_DIR "share/man" CACHE PATH "Man dir." FORCE)
set (CMAKE_BIN_DIR "bin" CACHE PATH "Bin dir." FORCE)
set (CMAKE_DATA_DIR "share/cmake" CACHE PATH "Data dir." FORCE)
set (CMAKE_XDGDATA_DIR "share" CACHE PATH "XDG data dir." FORCE)
set (CMAKE_USE_OPENSSL OFF CACHE BOOL "Use OpenSSL." FORCE)
set (CMAKE_USE_SYSTEM_LIBRARIES OFF CACHE BOOL "Use system libs." FORCE)
set (BUILD_TESTING OFF CACHE BOOL "Build tests." FORCE)
set (BUILD_DOCS OFF CACHE BOOL "Build documentation." FORCE)
set (BUILD_MAN_PAGES OFF CACHE BOOL "Build man pages." FORCE)
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

      var cmake_args = [
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
        "-DBUILD_DOCS=OFF",
        "-DBUILD_MAN_PAGES=OFF",
        "-DCMAKE_DISABLE_FIND_PACKAGE_Curses=ON",
        "-DCMAKE_Fortran_COMPILER=NOTFOUND",
      ]

      let cmake_proc = process.command_argv(cmake_args[0], cmake_args)
      let cmake_status = process.run(cmake_proc)?

      if ! cmake_status.ok {
        let err_log = fp"CMakeFiles/CMakeError.log"

        if fs.exists(err_log)? {
          print (fs.read_text(err_log)?)
        }

        Err(ScriptError.Failed("cmake-configure-failed", "bootstrap cmake configure failed"))?
      }

      run $samu $jobs_flag ?

      env {
        DESTDIR = dest
      } {
        run $bc "-P" "cmake_install.cmake" ?
      } ?
    } ?
  } ?
}
