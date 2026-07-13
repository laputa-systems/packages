use PKGBUILD-shared as PKGBUILD_shared
use kbuild

pure x86_kbuild_cflags() -> List[Str] {
  return [
    "-D__KERNEL__",
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
    "-fno-function-sections",
    "-fno-data-sections",
    "-mcmodel=kernel",
    "-mno-mmx",
    "-mno-sse",
    "-mno-sse2",
    "-mno-3dnow",
    "-mno-red-zone",
    "-Wno-address-of-packed-member",
    "-Wno-pointer-sign",
    "-Wno-microsoft-anon-tag",
    "-Wno-gnu-variable-sized-type-not-at-end",
    "-Wno-initializer-overrides",
    "-Wno-sometimes-uninitialized",
    "-Wno-ignored-attributes",
  ]
}

pure x86_kbuild_includes() -> List[Str] {
  return [
    "-nostdinc",
    "-I./arch/x86/include",
    "-I./arch/x86/include/generated",
    "-I./include",
    "-I./include",
    "-I./arch/x86/include/uapi",
    "-I./arch/x86/include/generated/uapi",
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

pure x86_vdso_cflags() -> List[Str] {
  return [
    "-D__KERNEL__",
    "-std=gnu11",
    "-Wall",
    "-Wundef",
    "-Werror=strict-prototypes",
    "-Wno-trigraphs",
    "-fno-strict-aliasing",
    "-fno-common",
    "-fshort-wchar",
    "-funsigned-char",
    "-fno-asynchronous-unwind-tables",
    "-fno-unwind-tables",
    "-fno-delete-null-pointer-checks",
    "-O2",
    "-fno-stack-protector",
    "-fno-omit-frame-pointer",
    "-foptimize-sibling-calls",
    "-fasynchronous-unwind-tables",
    "-fpic",
    "-m64",
    "-mcmodel=small",
    "-DDISABLE_BRANCH_PROFILING",
    "-DBUILD_VDSO",
    "-DBUILD_VDSO64",
    "-D__DISABLE_EXPORTS",
    "-fno-strict-overflow",
    "-fno-stack-check",
    "-fno-builtin-wcslen",
    "-fcf-protection=none",
  ]
}

pure x86_vdso_base(cc: Path) -> List[Str] {
  let with_flags = [cc.display(), "-target", "x86_64-linux-gnu", "-Wno-unused-command-line-argument"].extend(
    x86_vdso_cflags(),
  )

  let with_includes = with_flags.extend(x86_kbuild_includes())
  return with_includes.extend(["-I./arch/x86/entry/vdso", "-I."])
}

proc write_x86_vdso_offsets(nm: Path) [fs, process, env, error] {
  let symbol_re = regex.compile("^([0-9a-fA-F]*) . VDSO_([a-zA-Z0-9_]*)$")?
  let leading_zero_re = regex.compile("^00*")?
  let symbols = run.text $nm "arch/x86/entry/vdso/vdso64/vdso64.so.dbg" ?
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

proc build_x86_vdso(cc: Path) [fs, process, env, error] {
  let vdso_dir = p"arch/x86/entry/vdso/vdso64"
  fs.mkdir(vdso_dir)?
  fs.mkdir(p".xsh-kbuild/host/arch/x86/tools")?
  let vdso2c = p".xsh-kbuild/host/arch/x86/tools/vdso2c"
  PKGBUILD_shared.emit_kbuild_progress("xsh-kbuild-x86-vdso build-host-vdso2c")?

  PKGBUILD_shared.run_native_command(
    [
      cc.display(),
      "-O2",
      "-std=gnu11",
      "-Wall",
      "-I./tools/include",
      "-I./arch/x86/include/uapi",
      "-I./arch/x86/include/generated/uapi",
      "-I./include/uapi",
      "-I./include/generated/uapi",
      "-I./include",
      "-o",
      vdso2c.display(),
      "arch/x86/tools/vdso2c.c",
    ],
  )?

  let base = x86_vdso_base(cc)
  let lds = p"arch/x86/entry/vdso/vdso64/vdso64.lds"
  PKGBUILD_shared.emit_kbuild_progress("xsh-kbuild-x86-vdso preprocess-lds")?

  PKGBUILD_shared.run_native_command(
    base.extend(["-D__ASSEMBLY__", "-E", "-P", "-C", "arch/x86/entry/vdso/vdso64/vdso64.lds.S", "-o", lds.display()]),
  )?

  let objects = [
    {
      source: p"arch/x86/entry/vdso/vdso64/note.S",
      object: p"arch/x86/entry/vdso/vdso64/note.o",
      asm: true,
    },
    {
      source: p"arch/x86/entry/vdso/vdso64/vclock_gettime.c",
      object: p"arch/x86/entry/vdso/vdso64/vclock_gettime.o",
      asm: false,
    },
    {
      source: p"arch/x86/entry/vdso/vdso64/vgetcpu.c",
      object: p"arch/x86/entry/vdso/vdso64/vgetcpu.o",
      asm: false,
    },
    {
      source: p"arch/x86/entry/vdso/vdso64/vgetrandom.c",
      object: p"arch/x86/entry/vdso/vdso64/vgetrandom.o",
      asm: false,
    },
    {
      source: p"arch/x86/entry/vdso/vdso64/vgetrandom-chacha.S",
      object: p"arch/x86/entry/vdso/vdso64/vgetrandom-chacha.o",
      asm: true,
    },
  ]

  for item in objects {
    let asm_args = if item.asm { ["-D__ASSEMBLY__"] } else { [] }
    PKGBUILD_shared.emit_kbuild_progress(f"xsh-kbuild-x86-vdso compile ${item.object.display()}")?

    PKGBUILD_shared.run_native_command(
      base.extend(asm_args).extend(["-c", item.source.display(), "-o", item.object.display()]),
    )?
  }

  let config = kbuild.load_config(p".config")?

  var linked_objects = [
    "arch/x86/entry/vdso/vdso64/note.o",
    "arch/x86/entry/vdso/vdso64/vclock_gettime.o",
    "arch/x86/entry/vdso/vdso64/vgetcpu.o",
    "arch/x86/entry/vdso/vdso64/vgetrandom.o",
    "arch/x86/entry/vdso/vdso64/vgetrandom-chacha.o",
  ]

  if config.values.get("X86_SGX", "") == "y" {
    PKGBUILD_shared.emit_kbuild_progress("xsh-kbuild-x86-vdso compile arch/x86/entry/vdso/vdso64/vsgx.o")?

    PKGBUILD_shared.run_native_command(
      base.extend(
        ["-D__ASSEMBLY__", "-c", "arch/x86/entry/vdso/vdso64/vsgx.S", "-o", "arch/x86/entry/vdso/vdso64/vsgx.o"],
      ),
    )?

    linked_objects = linked_objects.push("arch/x86/entry/vdso/vdso64/vsgx.o")
  }

  PKGBUILD_shared.emit_kbuild_progress("xsh-kbuild-x86-vdso link vdso64.so.dbg")?

  PKGBUILD_shared.run_native_command(
    [
      "ld.lld",
      "-shared",
      "--hash-style=both",
      "--build-id=sha1",
      "--no-undefined",
      "--eh-frame-hdr",
      "-Bsymbolic",
      "-z",
      "noexecstack",
      "-m",
      "elf_x86_64",
      "-soname",
      "linux-vdso.so.1",
      "-z",
      "max-page-size=4096",
      "-T",
      lds.display(),
    ].extend(linked_objects)
      .extend(["-o", "arch/x86/entry/vdso/vdso64/vdso64.so.dbg"]),
  )?

  PKGBUILD_shared.emit_kbuild_progress("xsh-kbuild-x86-vdso strip vdso64.so")?

  PKGBUILD_shared.run_native_command(
    [
      "llvm-objcopy",
      "-S",
      "--remove-section",
      "__ex_table",
      "arch/x86/entry/vdso/vdso64/vdso64.so.dbg",
      "arch/x86/entry/vdso/vdso64/vdso64.so",
    ],
  )?

  PKGBUILD_shared.emit_kbuild_progress("xsh-kbuild-x86-vdso convert vdso64-image.c")?

  PKGBUILD_shared.run_native_command(
    [
      vdso2c.display(),
      "arch/x86/entry/vdso/vdso64/vdso64.so.dbg",
      "arch/x86/entry/vdso/vdso64/vdso64.so",
      "arch/x86/entry/vdso/vdso64/vdso64-image.c",
    ],
  )?

  PKGBUILD_shared.emit_kbuild_progress("xsh-kbuild-x86-vdso offsets")?
  write_x86_vdso_offsets(PKGBUILD_shared.native_tool("llvm-nm")?)?
  PKGBUILD_shared.emit_kbuild_progress("xsh-kbuild-x86-vdso generated vdso64-image.c")?
}

proc write_x86_bounds_header() [fs, error] {
  kbuild.write_text_if_changed(
    p"include/generated/bounds.h",
    """#ifndef __LINUX_BOUNDS_H__
#define __LINUX_BOUNDS_H__
/*
 * DO NOT MODIFY.
 *
 * This file was generated by Kbuild
 */

#define NR_PAGEFLAGS 21 /* __NR_PAGEFLAGS */
#define MAX_NR_ZONES 3 /* __MAX_NR_ZONES */
#define NR_CPUS_BITS 8 /* order_base_2(CONFIG_NR_CPUS) */
#define SPINLOCK_SIZE 4 /* sizeof(spinlock_t) */
#define LRU_GEN_WIDTH 0 /* 0 */
#define __LRU_REFS_WIDTH 0 /* 0 */

#endif
""",
  )?
}

proc generate_x86_asm_offsets_header(cc: Path) [fs, process, env, error] {
  fs.mkdir(p".xsh-kbuild")?
  fs.mkdir(p".xsh-kbuild/generated")?
  let asm_out = p".xsh-kbuild/generated/asm-offsets.s"
  let base = [cc.display(), "-target", "x86_64-linux-gnu", "-Wno-unused-command-line-argument", "-S"]
  let with_flags = base.extend(x86_kbuild_cflags())
  let with_includes = with_flags.extend(x86_kbuild_includes())

  let argv = with_includes.extend(
    [
      "-DKBUILD_BASENAME=\"asm_offsets\"",
      "-DKBUILD_MODNAME=\"asm_offsets\"",
      "-D__KBUILD_MODNAME=asm_offsets",
      "arch/x86/kernel/asm-offsets.c",
      "-o",
      asm_out.display(),
    ],
  )

  PKGBUILD_shared.run_native_command(argv)?
  kbuild.generate_offsets_header(asm_out, p"include/generated/asm-offsets.h", "__ASM_OFFSETS_H__")?
}

proc generate_x86_kvm_asm_offsets_header(cc: Path) [fs, process, env, error] {
  fs.mkdir(p".xsh-kbuild")?
  fs.mkdir(p".xsh-kbuild/generated")?
  let asm_out = p".xsh-kbuild/generated/kvm-asm-offsets.s"
  let base = [cc.display(), "-target", "x86_64-linux-gnu", "-Wno-unused-command-line-argument", "-S"]
  let with_flags = base.extend(x86_kbuild_cflags())
  let with_includes = with_flags.extend(x86_kbuild_includes()).extend(["-I./arch/x86/kvm"])

  let argv = with_includes.extend(
    [
      "-DKBUILD_BASENAME=\"kvm_asm_offsets\"",
      "-DKBUILD_MODNAME=\"kvm_asm_offsets\"",
      "-D__KBUILD_MODNAME=kvm_asm_offsets",
      "arch/x86/kvm/kvm-asm-offsets.c",
      "-o",
      asm_out.display(),
    ],
  )

  PKGBUILD_shared.run_native_command(argv)?
  kbuild.generate_offsets_header(asm_out, p"arch/x86/kvm/kvm-asm-offsets.h", "__KVM_ASM_OFFSETS_H__")?
}

proc write_x86_orc_hash_header() [fs, error] {
  kbuild.write_text_if_changed(
    p"arch/x86/include/generated/asm/orc_hash.h",
    """#define ORC_HASH 0xfe,0x5d,0x32,0xbf,0x58,0x1b,0xd6,0x3b,0x2c,0xa9,0xa5,0xc6,0x5b,0xa5,0xa6,0x25,0xea,0xb3,0xfe,0x24,
""",
  )?
}

proc x86_capflag_array(array: Str, size: Str, prefix: Str, postfix: Str, input: Path) [fs, error] -> Result[List[Str]] {
  var lines = [f"const char * const ${array}[${size}] = {"]

  for raw in input.read_text()?.split("\n") {
    let line = raw.replace("\t", " ").trim()
    continue unless line.starts_with(f"#define ${prefix}")
    let rest = line.split(f"#define ${prefix}").get(1, "").trim()
    let fields = rest.fields()
    continue when fields.len() == 0
    let quote_parts = line.split("\"")
    continue when quote_parts.len() < 3
    let name = fields[0]
    let value = quote_parts[1]
    let index = if postfix == "" { f"${prefix}${name}" } else { f"${prefix}${name} - ${postfix}" }
    lines = lines.push(f"\t[${index}] = \"${value}\",")
  }

  return lines.push("};")
}

proc generate_x86_capflags_source() [fs, error] {
  let cpufeature = p"arch/x86/include/asm/cpufeatures.h"
  let vmxfeature = p"arch/x86/include/asm/vmxfeatures.h"
  var lines = ["#ifndef _ASM_X86_CPUFEATURES_H", "#include <asm/cpufeatures.h>", "#endif", ""]
  lines = lines.extend(x86_capflag_array("x86_cap_flags", "NCAPINTS*32", "X86_FEATURE_", "", cpufeature)?)
  lines = lines.push("")
  lines = lines.extend(x86_capflag_array("x86_bug_flags", "NBUGINTS*32", "X86_BUG_", "NCAPINTS*32", cpufeature)?)
  lines = lines.push("")
  lines = lines.push("#ifdef CONFIG_X86_VMX_FEATURE_NAMES")
  lines = lines.push("#ifndef _ASM_X86_VMXFEATURES_H")
  lines = lines.push("#include <asm/vmxfeatures.h>")
  lines = lines.push("#endif")
  lines = lines.extend(x86_capflag_array("x86_vmx_flags", "NVMXINTS*32", "VMX_FEATURE_", "", vmxfeature)?)
  lines = lines.push("#endif /* CONFIG_X86_VMX_FEATURE_NAMES */")

  kbuild.write_text_if_changed(
    p"arch/x86/kernel/cpu/capflags.c",
    f"""${lines.join("\n")}
""",
  )?
}

proc generate_x86_inat_tables() [fs, error] {
  var source = p"inat-tables-x86.c"

  if ! source.exists()? {
    source = ../pkg/files/generated/inat-tables-x86.c
  }

  kbuild.copy_text_if_changed(source, p"arch/x86/lib/inat-tables.c")?
}

pure realmode_object_paths(objects: List[Str]) -> List[Str] {
  [fp"arch/x86/realmode/rm/${obj}".display() for obj in objects]
}

proc write_x86_realmode_pasyms(nm: Path, objects: List[Str]) [fs, process, env, error] {
  let symbol_re = regex.compile("^([0-9a-fA-F]+) [ABCDGRSTVW] (.+)$")?
  let paths = realmode_object_paths(objects)
  let symbols = run.text $nm @paths ?
  var lines: List[Str] = []

  for raw in symbols.lines() {
    let caps = symbol_re.captures(raw)

    if caps.len() >= 3 {
      let name = caps[2]
      lines = lines.push(f"pa_${name} = ${name};")
    }
  }

  let sorted = lines |> sort-by .
  var unique: List[Str] = []
  var previous = ""

  for line in sorted {
    if line != previous {
      unique = unique.push(line)
      previous = line
    }
  }

  if unique.len() == 0 {
    return Err(ScriptError.Failed("linux-x86-realmode-pasyms", "llvm-nm did not report realmode symbols"))
  }

  kbuild.write_text_if_changed(
    p"arch/x86/realmode/rm/pasyms.h",
    f"""${unique.join("\n")}
""",
  )?
}

proc build_x86_realmode_payload(cc: Path) [fs, process, env, error] {
  let realmode_dir = p"arch/x86/realmode/rm"
  let relocs = p"arch/x86/tools/relocs"
  let ld = PKGBUILD_shared.native_tool("ld.lld")?
  let objcopy = PKGBUILD_shared.native_tool("llvm-objcopy")?
  let nm = PKGBUILD_shared.native_tool("llvm-nm")?
  fs.mkdir(realmode_dir)?

  PKGBUILD_shared.run_native_command(
    [
      cc.display(),
      "-O2",
      "-Itools/include",
      "-Iinclude/uapi",
      "-Iarch/x86/include/uapi",
      "-Iarch/x86/tools",
      "-o",
      relocs.display(),
      "arch/x86/tools/relocs_32.c",
      "arch/x86/tools/relocs_64.c",
      "arch/x86/tools/relocs_common.c",
    ],
  )?

  var realmode_objects = ["header.o", "trampoline_64.o", "stack.o", "reboot.o"]
  let acpi_sleep = p".config".read_text()?.contains("CONFIG_ACPI_SLEEP=y")

  if acpi_sleep {
    realmode_objects = realmode_objects.extend(
      [
        "wakeup_asm.o",
        "wakemain.o",
        "video-mode.o",
        "copy.o",
        "bioscall.o",
        "regs.o",
        "video-vga.o",
        "video-vesa.o",
        "video-bios.o",
      ],
    )
  }

  let realmode_cflags = [
    cc.display(),
    "-target",
    "x86_64-linux-gnu",
    "-std=gnu11",
    "-fms-extensions",
    "-m16",
    "-g",
    "-Os",
    "-ffreestanding",
    "-fno-pic",
    "-fno-pie",
    "-fno-stack-protector",
    "-Wno-address-of-packed-member",
    "-Wno-gnu",
    "-Wno-microsoft-anon-tag",
    "-D__KERNEL__",
    "-D_SETUP",
    "-D_WAKEUP",
    "-D__DISABLE_EXPORTS",
    "-nostdinc",
    "-Iarch/x86/boot",
    "-Iarch/x86/realmode/rm",
    "-Iarch/x86/include",
    "-Iarch/x86/include/generated",
    "-Iinclude",
    "-Iarch/x86/include/uapi",
    "-Iarch/x86/include/generated/uapi",
    "-Iinclude/uapi",
    "-Iinclude/generated/uapi",
    "-include",
    "include/linux/compiler-version.h",
    "-include",
    "include/linux/kconfig.h",
    "-include",
    "include/linux/compiler_types.h",
    "-fno-asynchronous-unwind-tables",
  ]

  let realmode_asm_cflags = realmode_cflags.extend(["-D__ASSEMBLY__"])

  for asm in [
    {
      source: "header.S",
      object: "header.o",
    },
    {
      source: "trampoline_64.S",
      object: "trampoline_64.o",
    },
    {
      source: "stack.S",
      object: "stack.o",
    },
    {
      source: "reboot.S",
      object: "reboot.o",
    },
  ] {
    PKGBUILD_shared.run_native_command(
      realmode_asm_cflags.extend(
        ["-c", fp"${realmode_dir}/${asm.source}".display(), "-o", fp"${realmode_dir}/${asm.object}".display()],
      ),
    )?
  }

  if acpi_sleep {
    for asm in [
      {
        source: "wakeup_asm.S",
        object: "wakeup_asm.o",
      },
      {
        source: "copy.S",
        object: "copy.o",
      },
      {
        source: "bioscall.S",
        object: "bioscall.o",
      },
    ] {
      PKGBUILD_shared.run_native_command(
        realmode_asm_cflags.extend(
          ["-c", fp"${realmode_dir}/${asm.source}".display(), "-o", fp"${realmode_dir}/${asm.object}".display()],
        ),
      )?
    }

    for source in ["wakemain.c", "video-mode.c", "regs.c", "video-vga.c", "video-vesa.c", "video-bios.c"] {
      PKGBUILD_shared.run_native_command(
        realmode_cflags.extend(
          [
            "-c",
            fp"${realmode_dir}/${source}".display(),
            "-o",
            fp"${realmode_dir}/${source.replace(".c", ".o")}".display(),
          ],
        ),
      )?
    }
  }

  write_x86_realmode_pasyms(nm, realmode_objects)?

  PKGBUILD_shared.run_native_command(
    [
      cc.display(),
      "-E",
      "-P",
      "-C",
      "-D__ASSEMBLY__",
      "-D__ASSEMBLER__",
      "-nostdinc",
      "-Iarch/x86/realmode/rm",
      "-Iarch/x86/include",
      "-Iarch/x86/include/generated",
      "-Iinclude",
      "-Iarch/x86/include/uapi",
      "-Iarch/x86/include/generated/uapi",
      "-Iinclude/uapi",
      "-Iinclude/generated/uapi",
      "-include",
      "include/linux/kconfig.h",
      "arch/x86/realmode/rm/realmode.lds.S",
      "-o",
      "arch/x86/realmode/rm/realmode.lds",
    ],
  )?

  PKGBUILD_shared.run_native_command(
    [
      ld.display(),
      "-m",
      "elf_i386",
      "--emit-relocs",
      "-T",
      "arch/x86/realmode/rm/realmode.lds",
      "-o",
      "arch/x86/realmode/rm/realmode.elf",
    ].extend(realmode_object_paths(realmode_objects)),
  )?

  let relocs_out = run.capture --bytes $relocs "--realmode" "arch/x86/realmode/rm/realmode.elf" ?

  if ! relocs_out.status.ok {
    return Err(ScriptError.Failed("linux-x86-realmode-relocs", "relocs --realmode failed"))
  }

  fs.write(p"arch/x86/realmode/rm/realmode.relocs", relocs_out.stdout)?

  PKGBUILD_shared.run_native_command(
    [objcopy.display(), "-O", "binary", "arch/x86/realmode/rm/realmode.elf", "arch/x86/realmode/rm/realmode.bin"],
  )?
}

export proc build_x86_64_scratch(cc: Path, srcarch: Str, ver: Str) [fs, process, env, time, error] {
  let prepare_start = PKGBUILD_shared.timing_start("prepare")
  kbuild.write_config_headers(p".config", p".", ver, srcarch)?
  kbuild.write_build_headers(p".", ver, srcarch)?
  kbuild.copy_text_if_changed(p"timeconst.h", p"include/generated/timeconst.h")?
  write_x86_bounds_header()?
  kbuild.write_asm_generic_wrappers(p".", srcarch)?
  kbuild.copy_text_if_changed(p"cpufeaturemasks-x86.h", p"arch/x86/include/generated/asm/cpufeaturemasks.h")?
  kbuild.generate_x86_syscall_tables(p".")?
  generate_x86_asm_offsets_header(cc)?
  generate_x86_kvm_asm_offsets_header(cc)?
  write_x86_orc_hash_header()?
  kbuild.copy_text_if_changed(p"rq-offsets.h", p"include/generated/rq-offsets.h")?
  generate_x86_capflags_source()?
  generate_x86_inat_tables()?
  kbuild.generate_empty_root_dtb_asm(p".")?
  kbuild.generate_crc32table_header(p".", cc)?
  kbuild.generate_raid6_sources(p".", cc)?
  PKGBUILD_shared.write_default_builtin_initramfs(cc)?
  build_x86_realmode_payload(cc)?
  build_x86_vdso(cc)?
  PKGBUILD_shared.timing_done("prepare", prepare_start)
  PKGBUILD_shared.stop_after("prepare")?
  let config = kbuild.load_config(p".config")?
  let discover_start = PKGBUILD_shared.timing_start("discover")
  let cached_plan = PKGBUILD_shared.add_extra_objects_from_env(PKGBUILD_shared.cached_package_plan(srcarch)?)?
  let trust_plan_cache = (env.get("XSH_LINUX_KBUILD_TRUST_PLAN_CACHE") ?? "") == "1"

  let refreshed_plan = if trust_plan_cache {
    cached_plan
  } else {
    kbuild.refresh_x86_kernel_config_objects(config, cached_plan)?
  }

  let plan = if trust_plan_cache {
    refreshed_plan
  } else {
    kbuild.augment_missing_composites(p".", config, refreshed_plan, srcarch)?
  }

  PKGBUILD_shared.timing_done("discover", discover_start)
  PKGBUILD_shared.stop_after("discover")?
  let plan_start = PKGBUILD_shared.timing_start("plan")

  let archive_plan_start = PKGBUILD_shared.timing_start("archive-plan")
  let archive_plan = PKGBUILD_shared.cached_archive_plan(
    plan,
    cc,
    srcarch,
    "x86_64-linux-gnu",
    x86_kbuild_cflags(),
    x86_kbuild_includes(),
  )?
  PKGBUILD_shared.timing_done("archive-plan", archive_plan_start)

  let only = env.get("XSH_LINUX_KBUILD_ONLY") ?? ""

  if only != "" {
    PKGBUILD_shared.run_targeted_kbuild_outputs(archive_plan, only)?
  }

  PKGBUILD_shared.timing_done("plan", plan_start)
  PKGBUILD_shared.require_complete_x86_archive_plan(archive_plan)?
  PKGBUILD_shared.stop_after("plan")?
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
    kbuild.patch_x86_jump_label_archive_plan(archive_plan, jobs_count)?
    archives = archive_plan.archives
  } else {
    archives = kbuild.run_x86_builtin_archive_plan(archive_plan, jobs_count)?
  }

  PKGBUILD_shared.timing_done("compile", compile_start)
  PKGBUILD_shared.stop_after("compile")?
  let link_start = PKGBUILD_shared.timing_start("link")

  kbuild.build_scratch_x86_final(
    cc,
    x86_kbuild_cflags(),
    [],
    x86_kbuild_includes(),
    archive_plan.link_inputs,
    jobs_count,
  )?

  PKGBUILD_shared.timing_done("link", link_start)
  PKGBUILD_shared.stop_after("link")?
  print "linux-native-kbuild-complete" archives.len() "archives" "linked" "arch/x86/boot/bzImage"
}
