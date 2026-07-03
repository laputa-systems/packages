use PKGBUILD-shared as PKGBUILD_shared
use kbuild
use pm.make as make

pure native_kbuild_cflags() -> List[Str] {
  return [
    "-D__KERNEL__",
    "-DCONFIG_CC_HAS_K_CONSTRAINT=1",
    "-std=gnu11",
    "-Wall",
    "-Wundef",
    "-Werror=strict-prototypes",
    "-Wno-trigraphs",
    "-fno-strict-aliasing",
    "-fno-common",
    "-fshort-wchar",
    "-funsigned-char",
    "-fno-PIE",
    "-fms-extensions",
    "-fno-asynchronous-unwind-tables",
    "-fno-unwind-tables",
    "-fno-delete-null-pointer-checks",
    "-O2",
    "-fno-stack-protector",
    "-fno-omit-frame-pointer",
    "-fno-optimize-sibling-calls",
    "-ftrivial-auto-var-init=zero",
    "-fno-stack-clash-protection",
    "-fstrict-flex-arrays=3",
    "-fno-strict-overflow",
    "-fno-stack-check",
    "-fno-builtin-wcslen",
    "-falign-functions=4",
    "-fno-function-sections",
    "-fno-data-sections",
    "-mlittle-endian",
    "-mgeneral-regs-only",
    "-mbranch-protection=none",
    "-Wa,-march=armv8.5-a",
    "-DARM64_ASM_ARCH=\"armv8.5-a\"",
    "-Wno-psabi",
    "-Wno-address-of-packed-member",
    "-Wno-pointer-sign",
    "-Wno-microsoft-anon-tag",
    "-Wno-gnu-variable-sized-type-not-at-end",
    "-Wno-initializer-overrides",
  ]
}

pure native_kbuild_includes() -> List[Str] {
  return [
    "-nostdinc",
    "-I./arch/arm64/include",
    "-I./arch/arm64/include/generated",
    "-I./include",
    "-I./include",
    "-I./arch/arm64/include/uapi",
    "-I./arch/arm64/include/generated/uapi",
    "-I./include/uapi",
    "-I./include/generated/uapi",
    "-include",
    "./include/linux/compiler-version.h",
    "-include",
    "./include/linux/kconfig.h",
    "-include",
    "./include/linux/compiler_types.h",
  ]
}

proc write_native_asm_offsets(cc: Path) [fs, process, env, error] {
  let asm_out = p".xsh-kbuild/generated/asm-offsets.s"
  fs.mkdir(asm_out.parent)?
  var argv = [cc.display(), "-target", "aarch64-linux-gnu", "-Wno-unused-command-line-argument"]
  argv = argv.extend(native_kbuild_cflags()).extend(native_kbuild_includes())
  argv = argv.extend(["-S", "-o", asm_out.display(), "arch/arm64/kernel/asm-offsets.c"])
  PKGBUILD_shared.run_native_command(argv)?
  kbuild.generate_offsets_header(asm_out, p"include/generated/asm-offsets.h", "__ASM_OFFSETS_H__")?
}

proc write_native_hyp_constants(cc: Path) [fs, process, env, error] {
  let asm_out = p".xsh-kbuild/generated/hyp-constants.s"
  fs.mkdir(asm_out.parent)?
  var argv = [cc.display(), "-target", "aarch64-linux-gnu", "-Wno-unused-command-line-argument"]
  argv = argv.extend(native_kbuild_cflags()).extend(native_kbuild_includes())
  argv = argv.push("-I./arch/arm64/kvm/hyp/include")
  argv = argv.extend(["-S", "-o", asm_out.display(), "arch/arm64/kvm/hyp/hyp-constants.c"])
  PKGBUILD_shared.run_native_command(argv)?
  kbuild.generate_offsets_header(asm_out, p"arch/arm64/kvm/hyp_constants.h", "__HYP_CONSTANTS_H__")?
}

pure native_vdso_cflags() -> List[Str] {
  return (native_kbuild_cflags() |> where . != "-mgeneral-regs-only").extend(
    ["-fno-builtin", "-ffixed-x18", "-DDISABLE_BRANCH_PROFILING", "-DBUILD_VDSO"],
  )
}

pure native_vdso_cc_base(cc: Path) -> List[Str] {
  let with_flags = [cc.display(), "-target", "aarch64-linux-gnu", "-Wno-unused-command-line-argument"].extend(
    native_vdso_cflags(),
  )

  return with_flags.extend(native_kbuild_includes())
}

proc write_native_vdso_offsets(nm: Path) [fs, process, env, error] {
  let symbol_re = regex.compile("^([0-9a-fA-F]*) . VDSO_([a-zA-Z0-9_]*)$")?
  let leading_zero_re = regex.compile("^00*")?
  let symbols = run.text $nm "arch/arm64/kernel/vdso/vdso.so.dbg" ?
  var out = ""

  for raw in symbols.lines() {
    let line = leading_zero_re.replace(raw, "0")
    let caps = symbol_re.captures(line)

    if caps.len() >= 3 {
      out = f"""${out}#define vdso_offset_${caps[2]} 0x${caps[1]}
"""
    }
  }

  kbuild.write_text_if_changed(p"include/generated/vdso-offsets.h", out)?
}

proc build_native_vdso(cc: Path) [fs, process, env, error] {
  let base = native_vdso_cc_base(cc)

  PKGBUILD_shared.run_native_command(
    base.extend(
      [
        "-D__ASSEMBLY__",
        "-E",
        "-P",
        "-C",
        "-Uarm64",
        "arch/arm64/kernel/vdso/vdso.lds.S",
        "-o",
        "arch/arm64/kernel/vdso/vdso.lds",
      ],
    ),
  )?

  for asm in [
    {source: "note.S", object: "note.o"},
    {source: "sigreturn.S", object: "sigreturn.o"},
    {source: "vgetrandom-chacha.S", object: "vgetrandom-chacha.o"},
  ] {
    PKGBUILD_shared.run_native_command(
      base.extend(
        ["-D__ASSEMBLY__", "-c", f"arch/arm64/kernel/vdso/${asm.source}", "-o", f"arch/arm64/kernel/vdso/${asm.object}"],
      ),
    )?
  }

  let c_base = base.extend(["-O2", "-mcmodel=tiny", "-fasynchronous-unwind-tables"])

  PKGBUILD_shared.run_native_command(
    c_base.extend(
      [
        "-include",
        "lib/vdso/gettimeofday.c",
        "-c",
        "arch/arm64/kernel/vdso/vgettimeofday.c",
        "-o",
        "arch/arm64/kernel/vdso/vgettimeofday.o",
      ],
    ),
  )?

  PKGBUILD_shared.run_native_command(
    c_base.extend(
      [
        "-include",
        "lib/vdso/getrandom.c",
        "-c",
        "arch/arm64/kernel/vdso/vgetrandom.c",
        "-o",
        "arch/arm64/kernel/vdso/vgetrandom.o",
      ],
    ),
  )?

  let ld = PKGBUILD_shared.native_tool("ld.lld")?

  PKGBUILD_shared.run_native_command(
    [
      ld.display(),
      "-shared",
      "-soname=linux-vdso.so.1",
      "-Bsymbolic",
      "--build-id=sha1",
      "-n",
      "-T",
      "arch/arm64/kernel/vdso/vdso.lds",
      "arch/arm64/kernel/vdso/vgettimeofday.o",
      "arch/arm64/kernel/vdso/note.o",
      "arch/arm64/kernel/vdso/sigreturn.o",
      "arch/arm64/kernel/vdso/vgetrandom.o",
      "arch/arm64/kernel/vdso/vgetrandom-chacha.o",
      "-o",
      "arch/arm64/kernel/vdso/vdso.so.dbg",
    ],
  )?

  let objcopy = PKGBUILD_shared.native_tool("llvm-objcopy")?

  PKGBUILD_shared.run_native_command(
    [objcopy.display(), "-S", "arch/arm64/kernel/vdso/vdso.so.dbg", "arch/arm64/kernel/vdso/vdso.so"],
  )?

  write_native_vdso_offsets(PKGBUILD_shared.native_tool("llvm-nm")?)?
}

pure native_nvhe_cflags() -> List[Str] {
  return native_kbuild_cflags().extend(
    [
      "-D__KVM_NVHE_HYPERVISOR__",
      "-D__DISABLE_EXPORTS",
      "-D__DISABLE_TRACE_MMIO__",
      "-DDISABLE_BRANCH_PROFILING",
      "-D__NO_FORTIFY",
      "-fno-asynchronous-unwind-tables",
      "-fno-unwind-tables",
    ],
  )
}

pure native_nvhe_includes() -> List[Str] {
  return native_kbuild_includes().extend(
    ["-I./arch/arm64/kvm", "-I./arch/arm64/kvm/hyp", "-I./arch/arm64/kvm/hyp/include", "-I./arch/arm64/kvm/hyp/nvhe"],
  )
}

pure native_nvhe_objects() -> List[Record] {
  return [
    {source: p"arch/arm64/kvm/hyp/nvhe/timer-sr.c", out: p".xsh-kbuild/obj/arch/arm64/kvm/hyp/nvhe/timer-sr.nvhe.o"},
    {source: p"arch/arm64/kvm/hyp/nvhe/sysreg-sr.c", out: p".xsh-kbuild/obj/arch/arm64/kvm/hyp/nvhe/sysreg-sr.nvhe.o"},
    {source: p"arch/arm64/kvm/hyp/nvhe/debug-sr.c", out: p".xsh-kbuild/obj/arch/arm64/kvm/hyp/nvhe/debug-sr.nvhe.o"},
    {source: p"arch/arm64/kvm/hyp/nvhe/switch.c", out: p".xsh-kbuild/obj/arch/arm64/kvm/hyp/nvhe/switch.nvhe.o"},
    {source: p"arch/arm64/kvm/hyp/nvhe/tlb.c", out: p".xsh-kbuild/obj/arch/arm64/kvm/hyp/nvhe/tlb.nvhe.o"},
    {source: p"arch/arm64/kvm/hyp/nvhe/hyp-init.S", out: p".xsh-kbuild/obj/arch/arm64/kvm/hyp/nvhe/hyp-init.nvhe.o"},
    {source: p"arch/arm64/kvm/hyp/nvhe/host.S", out: p".xsh-kbuild/obj/arch/arm64/kvm/hyp/nvhe/host.nvhe.o"},
    {source: p"arch/arm64/kvm/hyp/nvhe/hyp-main.c", out: p".xsh-kbuild/obj/arch/arm64/kvm/hyp/nvhe/hyp-main.nvhe.o"},
    {source: p"arch/arm64/kvm/hyp/nvhe/hyp-smp.c", out: p".xsh-kbuild/obj/arch/arm64/kvm/hyp/nvhe/hyp-smp.nvhe.o"},
    {source: p"arch/arm64/kvm/hyp/nvhe/psci-relay.c", out: p".xsh-kbuild/obj/arch/arm64/kvm/hyp/nvhe/psci-relay.nvhe.o"},
    {
      source: p"arch/arm64/kvm/hyp/nvhe/early_alloc.c",
      out: p".xsh-kbuild/obj/arch/arm64/kvm/hyp/nvhe/early_alloc.nvhe.o",
    },
    {source: p"arch/arm64/kvm/hyp/nvhe/page_alloc.c", out: p".xsh-kbuild/obj/arch/arm64/kvm/hyp/nvhe/page_alloc.nvhe.o"},
    {source: p"arch/arm64/kvm/hyp/nvhe/cache.S", out: p".xsh-kbuild/obj/arch/arm64/kvm/hyp/nvhe/cache.nvhe.o"},
    {source: p"arch/arm64/kvm/hyp/nvhe/setup.c", out: p".xsh-kbuild/obj/arch/arm64/kvm/hyp/nvhe/setup.nvhe.o"},
    {source: p"arch/arm64/kvm/hyp/nvhe/mm.c", out: p".xsh-kbuild/obj/arch/arm64/kvm/hyp/nvhe/mm.nvhe.o"},
    {
      source: p"arch/arm64/kvm/hyp/nvhe/mem_protect.c",
      out: p".xsh-kbuild/obj/arch/arm64/kvm/hyp/nvhe/mem_protect.nvhe.o",
    },
    {source: p"arch/arm64/kvm/hyp/nvhe/sys_regs.c", out: p".xsh-kbuild/obj/arch/arm64/kvm/hyp/nvhe/sys_regs.nvhe.o"},
    {source: p"arch/arm64/kvm/hyp/nvhe/pkvm.c", out: p".xsh-kbuild/obj/arch/arm64/kvm/hyp/nvhe/pkvm.nvhe.o"},
    {source: p"arch/arm64/kvm/hyp/nvhe/stacktrace.c", out: p".xsh-kbuild/obj/arch/arm64/kvm/hyp/nvhe/stacktrace.nvhe.o"},
    {source: p"arch/arm64/kvm/hyp/nvhe/ffa.c", out: p".xsh-kbuild/obj/arch/arm64/kvm/hyp/nvhe/ffa.nvhe.o"},
    {source: p"arch/arm64/kvm/hyp/nvhe/list_debug.c", out: p".xsh-kbuild/obj/arch/arm64/kvm/hyp/nvhe/list_debug.nvhe.o"},
    {source: p"arch/arm64/kvm/hyp/vgic-v3-sr.c", out: p".xsh-kbuild/obj/arch/arm64/kvm/hyp/vgic-v3-sr.nvhe.o"},
    {source: p"arch/arm64/kvm/hyp/aarch32.c", out: p".xsh-kbuild/obj/arch/arm64/kvm/hyp/aarch32.nvhe.o"},
    {
      source: p"arch/arm64/kvm/hyp/vgic-v2-cpuif-proxy.c",
      out: p".xsh-kbuild/obj/arch/arm64/kvm/hyp/vgic-v2-cpuif-proxy.nvhe.o",
    },
    {source: p"arch/arm64/kvm/hyp/entry.S", out: p".xsh-kbuild/obj/arch/arm64/kvm/hyp/entry.nvhe.o"},
    {source: p"arch/arm64/kvm/hyp/fpsimd.S", out: p".xsh-kbuild/obj/arch/arm64/kvm/hyp/fpsimd.nvhe.o"},
    {source: p"arch/arm64/kvm/hyp/hyp-entry.S", out: p".xsh-kbuild/obj/arch/arm64/kvm/hyp/hyp-entry.nvhe.o"},
    {source: p"arch/arm64/kvm/hyp/exception.c", out: p".xsh-kbuild/obj/arch/arm64/kvm/hyp/exception.nvhe.o"},
    {source: p"arch/arm64/kvm/hyp/pgtable.c", out: p".xsh-kbuild/obj/arch/arm64/kvm/hyp/pgtable.nvhe.o"},
    {source: p"arch/arm64/kernel/smccc-call.S", out: p".xsh-kbuild/obj/arch/arm64/kernel/smccc-call.nvhe.o"},
    {source: p"arch/arm64/lib/clear_page.S", out: p".xsh-kbuild/obj/arch/arm64/lib/clear_page.nvhe.o"},
    {source: p"arch/arm64/lib/copy_page.S", out: p".xsh-kbuild/obj/arch/arm64/lib/copy_page.nvhe.o"},
    {source: p"arch/arm64/lib/memcpy.S", out: p".xsh-kbuild/obj/arch/arm64/lib/memcpy.nvhe.o"},
    {source: p"arch/arm64/lib/memset.S", out: p".xsh-kbuild/obj/arch/arm64/lib/memset.nvhe.o"},
  ]
}

pure display_paths(paths: List[Path]) -> List[Str] {
  return [item.display() for item in paths]
}

proc build_native_nvhe_helper(cc: Path) [fs, process, env, error] -> Result[Path] {
  let out = p".xsh-kbuild/host/arch/arm64/kvm/hyp/nvhe/gen-hyprel"
  fs.mkdir(out.parent)?

  PKGBUILD_shared.run_native_command(
    [cc.display(), "-O2", "-I./include", "-o", out.display(), "arch/arm64/kvm/hyp/nvhe/gen-hyprel.c"],
  )?

  return out
}

proc preprocess_native_nvhe_linker_script(cc: Path, out: Path) [fs, process, env, error] {
  fs.mkdir(out.parent)?
  var argv = [cc.display(), "-target", "aarch64-linux-gnu", "-Wno-unused-command-line-argument"]
  argv = argv.extend(native_nvhe_cflags()).extend(native_nvhe_includes())

  argv = argv.extend(
    [
      "-D__ASSEMBLY__",
      "-DLINKER_SCRIPT",
      "-E",
      "-P",
      "-C",
      "-Uarm64",
      "arch/arm64/kvm/hyp/nvhe/hyp.lds.S",
      "-o",
      out.display(),
    ],
  )

  PKGBUILD_shared.run_native_command(argv)?
}

proc write_native_nvhe_hyprel(gen: Path, input: Path, out: Path) [fs, process, error] {
  let reloc = run.text $gen $input ?
  kbuild.write_text_if_changed(out, reloc)?
}

proc nvhe_ld_task(
  ld: Path,
  out: Path,
  inputs: List[Path],
  deps: List[Str],
  linker_script: Path = p"",
) [] -> make.MakeTask {
  var argv = [ld.display(), "-r"]

  if linker_script.display() != "" {
    argv = argv.extend(["-T", linker_script.display()])
  }

  argv = argv.extend(["-o", out.display()]).extend(display_paths(inputs))

  return {
    name: out.display(),
    outputs: [out],
    inputs: inputs,
    deps: deps,
    argv: argv,
    cwd: p".",
    env: {},
    depfile: p"",
    stamp: fp"${out}.cmd",
  }
}

proc nvhe_objcopy_task(objcopy: Path, input: Path, out: Path, deps: List[Str]) [] -> make.MakeTask {
  return {
    name: out.display(),
    outputs: [out],
    inputs: [input],
    deps: deps,
    argv: [objcopy.display(), "--prefix-symbols=__kvm_nvhe_", input.display(), out.display()],
    cwd: p".",
    env: {},
    depfile: p"",
    stamp: fp"${out}.cmd",
  }
}

proc build_native_nvhe(cc: Path, jobs_count: Int) [fs, process, env, error] {
  let gen = build_native_nvhe_helper(cc)?
  let nvhe_dir = p".xsh-kbuild/obj/arch/arm64/kvm/hyp/nvhe"
  let linker_script = fp"${nvhe_dir}/hyp.lds"
  preprocess_native_nvhe_linker_script(cc, linker_script)?
  let ld = PKGBUILD_shared.native_tool("ld.lld")?
  let objcopy = PKGBUILD_shared.native_tool("llvm-objcopy")?
  var object_tasks: List[make.MakeTask] = []
  var object_outputs: List[Path] = []

  for item in native_nvhe_objects() {
    object_tasks = object_tasks.push(
      kbuild.compile_kbuild_task(
        cc,
        "aarch64-linux-gnu",
        native_nvhe_cflags(),
        [],
        native_nvhe_includes(),
        item.source,
        item.out,
      ),
    )

    object_outputs = object_outputs.push(item.out)
  }

  let tmp = fp"${nvhe_dir}/kvm_nvhe.tmp.o"
  let reloc_asm = fp"${nvhe_dir}/hyp-reloc.S"
  let reloc_o = fp"${nvhe_dir}/hyp-reloc.o"
  let rel = fp"${nvhe_dir}/kvm_nvhe.rel.o"
  let out = fp"${nvhe_dir}/kvm_nvhe.o"
  object_tasks = object_tasks.push(nvhe_ld_task(ld, tmp, object_outputs, display_paths(object_outputs), linker_script))
  make.run_tasks(object_tasks, jobs_count)?
  write_native_nvhe_hyprel(gen, tmp, reloc_asm)?
  var final_tasks: List[make.MakeTask] = []

  final_tasks = final_tasks.push(
    kbuild.compile_kbuild_task(
      cc,
      "aarch64-linux-gnu",
      native_nvhe_cflags(),
      [],
      native_nvhe_includes(),
      reloc_asm,
      reloc_o,
    ),
  )

  final_tasks = final_tasks.push(nvhe_ld_task(ld, rel, [tmp, reloc_o], [reloc_o.display()]))
  final_tasks = final_tasks.push(nvhe_objcopy_task(objcopy, rel, out, [rel.display()]))
  make.run_tasks(final_tasks, jobs_count)?
}

export proc build_scratch(cc: Path, srcarch: Str, ver: Str) [fs, process, env, error] {
  if srcarch != "arm64" {
    return Err(
      ScriptError.Failed(
        "linux-native-kbuild-unsupported-arch",
        f"native scratch Kbuild final link is only implemented for arm64; ${srcarch} needs x86_64 link/vDSO/generated-header support",
      ),
    )
  }

  let prepare_start = PKGBUILD_shared.timing_start("prepare")
  kbuild.write_config_headers(p".config", p".", ver, srcarch)?
  kbuild.write_build_headers(p".", ver)?
  kbuild.copy_text_if_changed(p"timeconst.h", p"include/generated/timeconst.h")?
  kbuild.copy_text_if_changed(p"bounds.h", p"include/generated/bounds.h")?
  kbuild.write_asm_generic_wrappers(p".")?
  kbuild.generate_arm64_cpucap_defs(p".")?
  kbuild.copy_text_if_changed(p"sysreg-defs.h", p"arch/arm64/include/generated/asm/sysreg-defs.h")?
  kbuild.generate_arm64_syscall_tables(p".")?
  write_native_asm_offsets(cc)?
  kbuild.copy_text_if_changed(p"rq-offsets.h", p"include/generated/rq-offsets.h")?
  write_native_hyp_constants(cc)?
  kbuild.copy_text_if_changed(p"sha256-core.S", p"lib/crypto/arm64/sha256-core.S")?
  kbuild.copy_text_if_changed(p"sha512-core.S", p"lib/crypto/arm64/sha512-core.S")?
  kbuild.generate_empty_root_dtb_asm(p".")?
  kbuild.generate_crc32table_header(p".", cc)?
  PKGBUILD_shared.write_default_builtin_initramfs(cc)?
  build_native_vdso(cc)?
  PKGBUILD_shared.timing_done("prepare", prepare_start)
  PKGBUILD_shared.stop_after("prepare")?
  let discover_start = PKGBUILD_shared.timing_start("discover")
  let plan = PKGBUILD_shared.cached_package_plan(srcarch)?
  PKGBUILD_shared.timing_done("discover", discover_start)
  PKGBUILD_shared.stop_after("discover")?
  let plan_start = PKGBUILD_shared.timing_start("plan")
  let nvhe_jobs_count = PKGBUILD_shared.build_jobs()?
  build_native_nvhe(cc, nvhe_jobs_count)?

  let archive_plan = PKGBUILD_shared.cached_archive_plan(
    plan,
    cc,
    srcarch,
    "aarch64-linux-gnu",
    native_kbuild_cflags(),
    native_kbuild_includes(),
  )?

  let only = env.get("XSH_LINUX_KBUILD_ONLY") ?? ""

  if only != "" {
    PKGBUILD_shared.run_targeted_kbuild_outputs(archive_plan, only)?
  }

  PKGBUILD_shared.timing_done("plan", plan_start)
  PKGBUILD_shared.stop_after("plan")?

  if archive_plan.generated_objects.len() == 0 and archive_plan.missing_sources.len() == 0 {
    let jobs_count = PKGBUILD_shared.build_jobs()?
    var archives: List[Path] = []
    let archive_report = p".xsh-kbuild-archive-plan.json"
    let root_archive = p".xsh-kbuild/built-in.a"
    let reuse_archives = (env.get("XSH_LINUX_KBUILD_REUSE_ARCHIVES") ?? "") == "1"
    let compile_start = PKGBUILD_shared.timing_start("compile")

    if reuse_archives and root_archive.exists()? and archive_report.exists()? and (env.get(
      "XSH_LINUX_KBUILD_FORCE_ARCHIVES",
    ) ?? "") != "1" {
      print "xsh-kbuild-archives" "reuse" archive_plan.archives.len() "archives"
      archives = archive_plan.archives
    } else {
      archives = kbuild.run_builtin_archive_plan(archive_plan, jobs_count)?
    }

    PKGBUILD_shared.timing_done("compile", compile_start)
    PKGBUILD_shared.stop_after("compile")?
    let link_start = PKGBUILD_shared.timing_start("link")
    kbuild.build_scratch_arm64_final(cc, native_kbuild_cflags(), [], native_kbuild_includes(), jobs_count)?
    PKGBUILD_shared.timing_done("link", link_start)
    PKGBUILD_shared.stop_after("link")?
    print "linux-native-kbuild-complete" archives.len() "archives" "linked" "arch/arm64/boot/Image"
    return
  }

  return Err(
    ScriptError.Failed(
      "linux-native-kbuild-compile-incomplete",
      f"native scratch Kbuild generated config/syscall headers, discovered ${plan.dirs.len()} dirs and ${plan.objects.len()} objects, constructed ${archive_plan.tasks.len()} object/archive tasks for archive_plan.archives.len() archives, found ${archive_plan.generated_objects.len()} generated objects and ${archive_plan.missing_sources.len()} objects without direct sources; next step is generated object handling and task execution",
    ),
  )
}
