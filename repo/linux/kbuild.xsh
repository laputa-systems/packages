use pm.make as make

export error ScriptError = Failed(kind: Str, message: Str)

export type Kconfig = {enabled: Map[Bool], values: Map[Str]}

export type CompositeObject = {object: Path, members: List[Path]}

export type KbuildPlan = {
  dirs: List[Path],
  objects: List[Path],
  lib_objects: List[Path],
  composites: List[CompositeObject],
  unsupported: List[Str],
}

export type BuiltinArchivePlan = {
  tasks: List[make.MakeTask],
  archives: List[Path],
  link_inputs: List[Path],
  missing_sources: List[Path],
  generated_objects: List[Path],
}

export type DiscoverOptions = {progress: Bool, progress_every: Int, jobs: Int}

type DiscoverState = {plan: KbuildPlan, seen: Map[Bool], visited: Int}

type DirScan = {dir: Path, plan: KbuildPlan, child_dirs: List[Path], entries: List[Path]}

type ActiveDirObjects = {dir: Path, objects: List[Path]}

type ArchiveInputs = {objs: List[Path], deps: List[Str]}

type CompositeScan = {dir: Path, composites: List[CompositeObject]}

type ElfSection = {name: Str, offset: Int, size: Int}

type ElfReloc = {section: Str, index: Int, offset: Int, info: Int, typ: Str, symbol: Str, addend: Int}

type ElfRelocTable = {keys: List[ElfReloc], by_offset: Map[ElfReloc]}

type RelocLookup = {found: Bool, reloc: ElfReloc}

type JumpLabelPatchResult = {scanned: Int, objects: Int, patches: Int}

type ParsedAssignment = {lhs: Str, op: Str, rhs: Str}

type ItemResult = {plan: KbuildPlan, dirs: List[Path], entries: List[Path]}

pure regex_captures(text: Str, pattern: Str) -> Result[List[Str]] {
  let re = regex.compile(pattern)?
  return re.captures(text)
}

pure regex_matches(text: Str, pattern: Str) -> Result[Bool] {
  let re = regex.compile(pattern)?
  return re.matches(text)
}

pure empty_plan() -> KbuildPlan {
  return {dirs: [], objects: [], lib_objects: [], composites: [], unsupported: []}
}

pure default_discover_options() -> DiscoverOptions {
  return {progress: false, progress_every: 100, jobs: 1}
}

export pure planner_jobs() -> Int {
  let count = cpu.count()

  if count < 1 {
    return 1
  }

  return count
}

proc root_vars(srcarch: Str) [] -> Map[Str] {
  var vars: Map[Str] = {}
  vars["ARCH_CORE"] = ""
  vars["ARCH_DRIVERS"] = ""
  vars["srctree"] = "."

  if srcarch == "arm64" {
    vars["ARCH_LIB"] = "lib/ arch/arm64/lib/"
  } else {
    vars["ARCH_DRIVERS"] = "arch/x86/pci/ arch/x86/power/ arch/x86/video/"
    vars["ARCH_LIB"] = "lib/ arch/x86/lib/"
    vars["BITS"] = "64"
  }

  return vars
}

proc global_vars(srcarch: Str) [] -> Map[Str] {
  var vars: Map[Str] = {}
  vars["srctree"] = "."

  if srcarch == "x86" {
    vars["BITS"] = "64"
  }

  return vars
}

proc kbuild_vars_for_dir(dir: Path, srcarch: Str) [] -> Map[Str] {
  let dir_key = path_key(dir)
  var vars = if dir_key == "." { root_vars(srcarch) } else { global_vars(srcarch) }
  vars["src"] = dir_key
  vars["obj"] = dir_key
  return vars
}

pure path_key(path_value: Path) -> Str {
  let key = path_value.display()

  if key == "" {
    return "."
  }

  return key
}

pure has_plan_path(paths: List[Path], path_value: Path) -> Bool {
  let key = path_key(path_value)

  for item in paths {
    if path_key(item) == key {
      return true
    }
  }

  return false
}

pure add_dir(plan: KbuildPlan, dir: Path) -> KbuildPlan {
  if has_plan_path(plan.dirs, dir) {
    return plan
  }

  return {...plan, dirs: plan.dirs.push(dir)}
}

pure add_object(plan: KbuildPlan, obj: Path) -> KbuildPlan {
  if has_plan_path(plan.objects, obj) {
    return plan
  }

  return {...plan, objects: plan.objects.push(obj)}
}

pure add_lib_object(plan: KbuildPlan, obj: Path) -> KbuildPlan {
  if has_plan_path(plan.lib_objects, obj) {
    return plan
  }

  return {...plan, lib_objects: plan.lib_objects.push(obj)}
}

pure add_composite(plan: KbuildPlan, composite: CompositeObject) -> KbuildPlan {
  let key = path_key(composite.object)

  for item in plan.composites {
    if path_key(item.object) == key {
      return plan
    }
  }

  return {...plan, composites: plan.composites.push(composite)}
}

pure add_unsupported(plan: KbuildPlan, message: Str) -> KbuildPlan {
  return {...plan, unsupported: plan.unsupported.push(message)}
}

proc merge_plan(base: KbuildPlan, addition: KbuildPlan) [] -> KbuildPlan {
  return {
    dirs: base.dirs.extend(addition.dirs),
    objects: base.objects.extend(addition.objects),
    lib_objects: base.lib_objects.extend(addition.lib_objects),
    composites: base.composites.extend(addition.composites),
    unsupported: base.unsupported.extend(addition.unsupported),
  }
}

pure join_rel(dir: Path, item: Str) -> Path {
  if path_key(dir) == "." {
    return normalize_rel_path(fp"${item}")
  }

  return normalize_rel_path(fp"${dir}/${item}")
}

pure join_root(root: Path, rel: Path) -> Path {
  if path_key(rel) == "." {
    return root
  }

  return fp"${root}/${rel}"
}

pure normalize_rel_path(path_value: Path) -> Path {
  var parts: List[Str] = []

  for part in path_value.display().split("/") {
    continue when part == "" or part == "."

    if part == ".." {
      if parts.len() > 0 {
        parts = parts |> take(parts.len() - 1)
      }

      continue
    }

    parts = parts.push(part)
  }

  if parts.len() == 0 {
    return p"."
  }

  return fp"${parts.join("/")}"
}

export proc write_text_if_changed(path_value: Path, data: Str) [fs, error] {
  path_value.parent.mkdir()?

  if path_value.exists()? and path_value.read_text()? == data {
    return
  }

  fs.write(path_value, data)?
}

export proc copy_text_if_changed(source: Path, dest: Path) [fs, error] {
  write_text_if_changed(dest, source.read_text()?)?
}

pure dirname_for_item(dir: Path, item: Str) -> Path {
  let caps = regex_captures(item, "^(.*)/$") ?? []

  if caps.len() >= 2 {
    return join_rel(dir, caps[1])
  }

  return join_rel(dir, item)
}

pure clean_config_value(raw: Str) -> Str {
  return raw.trim().replace("\"", "")
}

pure config_header_value(value: Str) -> Str {
  if value == "y" or value == "m" {
    return "1"
  }

  match value.parse_int() {
    Ok(_) => return value
    Err(_) => {}
  }

  if value.starts_with("0x") {
    return value
  }

  return f"\"${value}\""
}

pure config_auto_line(name: Str, value: Str) -> Str {
  if value == "y" {
    return f"CONFIG_${name}=y"
  }

  return f"CONFIG_${name}=${value}"
}

export proc load_config(path_value: Path) [fs, error] -> Result[Kconfig] {
  var enabled: Map[Bool] = {}
  var values: Map[Str] = {}

  for raw in path_value.read_text()?.split("\n") {
    let line = raw.trim()

    if line.starts_with("CONFIG_") and "=" in line {
      let parts = line.split("=")
      let name = parts[0].replace("CONFIG_", "")
      let value = clean_config_value(parts.get(1, ""))
      values[name] = value

      if value == "y" {
        enabled[name] = true
      }
    }
  }

  return {enabled: enabled, values: values}
}

export proc write_config_headers(config_path: Path, root: Path, release: Str, arch: Str = "arm64") [fs, error] {
  let config = load_config(config_path)?

  var autoconf = [
    "/*",
    " * Automatically generated file; DO NOT EDIT.",
    f" * Linux/${arch} ${release} Kernel Configuration",
    " */",
  ]

  var auto_conf = [
    "#",
    "# Automatically generated file; DO NOT EDIT.",
    f"# Linux/${arch} ${release} Kernel Configuration",
    "#",
  ]

  for name in config.values.keys() |> sort-by . {
    let value = config.values.get(name, "")
    autoconf = autoconf.push(f"#define CONFIG_${name} ${config_header_value(value)}")
    auto_conf = auto_conf.push(config_auto_line(name, value))
  }

  fs.mkdir(fp"${root}/include/generated")?
  fs.mkdir(fp"${root}/include/config")?

  write_text_if_changed(
    fp"${root}/include/generated/autoconf.h",
    f"""${autoconf.join("\n")}
""",
  )?

  write_text_if_changed(
    fp"${root}/include/config/auto.conf",
    f"""${auto_conf.join("\n")}
""",
  )?
}

export proc write_build_headers(root: Path, release: Str, arch: Str = "arm64") [fs, error] {
  fs.mkdir(fp"${root}/include/generated/uapi/linux")?
  let uts_machine = if arch == "x86" { "x86_64" } else { "aarch64" }

  write_text_if_changed(
    fp"${root}/include/generated/utsrelease.h",
    f"""#define UTS_RELEASE "${release}"
""",
  )?

  write_text_if_changed(
    fp"${root}/include/generated/utsversion.h",
    """#define UTS_VERSION "#1 XSH"
""",
  )?

  write_text_if_changed(
    fp"${root}/init/utsversion-tmp.h",
    """#define UTS_VERSION "#1 XSH"
""",
  )?

  write_text_if_changed(
    fp"${root}/include/generated/compile.h",
    f"""#define UTS_MACHINE "${uts_machine}"
#define LINUX_COMPILE_BY "xsh"
#define LINUX_COMPILE_HOST "xsh"
#define LINUX_COMPILER "clang"
""",
  )?

  if arch == "x86" {
    write_text_if_changed(
      fp"${root}/include/generated/vdso-offsets.h",
      """/* x86 vDSO deferred; no offsets yet */
""",
    )?
  } else {
    write_text_if_changed(
      fp"${root}/include/generated/vdso-offsets.h",
      """#define vdso_offset_sigtramp 0x058c
""",
    )?
  }

  write_text_if_changed(
    fp"${root}/include/generated/uapi/linux/version.h",
    """#define LINUX_VERSION_CODE 458757
#define KERNEL_VERSION(a,b,c) (((a) << 16) + ((b) << 8) + (c))
#define LINUX_VERSION_MAJOR 7
#define LINUX_VERSION_PATCHLEVEL 0
#define LINUX_VERSION_SUBLEVEL 5
""",
  )?
}

export proc write_asm_generic_wrappers(root: Path, srcarch: Str = "arm64") [fs, error] {
  let arch_dir = if srcarch == "x86" { "x86" } else { "arm64" }
  fs.mkdir(fp"${root}/arch/${arch_dir}/include/generated/uapi/asm")?
  fs.mkdir(fp"${root}/arch/${arch_dir}/include/generated/asm")?

  for name in [
    "bpf_perf_event.h",
    "errno-base.h",
    "errno.h",
    "fcntl.h",
    "hugetlb_encode.h",
    "int-l64.h",
    "int-ll64.h",
    "ioctl.h",
    "ioctls.h",
    "ipcbuf.h",
    "kvm_para.h",
    "mman-common.h",
    "msgbuf.h",
    "param.h",
    "poll.h",
    "resource.h",
    "sembuf.h",
    "shmbuf.h",
    "signal-defs.h",
    "siginfo.h",
    "socket.h",
    "sockios.h",
    "stat.h",
    "swab.h",
    "termbits-common.h",
    "termbits.h",
    "termios.h",
    "types.h",
  ] {
    write_text_if_changed(
      fp"${root}/arch/${arch_dir}/include/generated/uapi/asm/${name}",
      f"""#include <asm-generic/${name}>
""",
    )?
  }

  for name in [
    "__ffs.h",
    "__fls.h",
    "access_ok.h",
    "atomic.h",
    "atomic64.h",
    "audit_change_attr.h",
    "audit_dir_write.h",
    "audit_read.h",
    "audit_signal.h",
    "audit_write.h",
    "bitsperlong.h",
    "builtin-__ffs.h",
    "builtin-__fls.h",
    "builtin-ffs.h",
    "builtin-fls.h",
    "cmpxchg-local.h",
    "codetag.lds.h",
    "const_hweight.h",
    "delay.h",
    "div64.h",
    "dma-mapping.h",
    "dma.h",
    "early_ioremap.h",
    "emergency-restart.h",
    "error-injection.h",
    "ext2-atomic-setbit.h",
    "ext2-atomic.h",
    "ffs.h",
    "ffz.h",
    "flat.h",
    "fls.h",
    "fls64.h",
    "fprobe.h",
    "generic-non-atomic.h",
    "getorder.h",
    "hw_irq.h",
    "hweight.h",
    "instrumented-atomic.h",
    "instrumented-lock.h",
    "instrumented-non-atomic.h",
    "int-ll64.h",
    "ioctl.h",
    "irq_regs.h",
    "kdebug.h",
    "kmap_size.h",
    "le.h",
    "local.h",
    "local64.h",
    "lock.h",
    "logic_io.h",
    "mcs_spinlock.h",
    "memory_model.h",
    "mm_hooks.h",
    "mmiowb.h",
    "mmiowb_types.h",
    "mmzone.h",
    "module.lds.h",
    "msi.h",
    "nommu_context.h",
    "non-atomic.h",
    "non-instrumented-non-atomic.h",
    "param.h",
    "parport.h",
    "pci_iomap.h",
    "pgtable-nop4d.h",
    "pgtable-nopmd.h",
    "pgtable-nopud.h",
    "pgtable_uffd.h",
    "qrwlock.h",
    "qrwlock_types.h",
    "qspinlock.h",
    "qspinlock_types.h",
    "resource.h",
    "rwonce.h",
    "serial.h",
    "softirq_stack.h",
    "statfs.h",
    "switch_to.h",
    "thread_info_tif.h",
    "ticket_spinlock.h",
    "trace_clock.h",
    "unwind_user.h",
    "user.h",
    "vga.h",
    "video.h",
    "vmlinux.lds.h",
  ] {
    write_text_if_changed(
      fp"${root}/arch/${arch_dir}/include/generated/asm/${name}",
      f"""#include <asm-generic/${name}>
""",
    )?
  }
}

export proc generate_arm64_cpucap_defs(root: Path) [fs, error] {
  var lines = [
    "#ifndef __ASM_CPUCAP_DEFS_H",
    "#define __ASM_CPUCAP_DEFS_H",
    "",
    "/* Generated file - do not edit */",
    "",
  ]

  var cap = 0

  for raw in fp"${root}/arch/arm64/tools/cpucaps".read_text()?.split("\n") {
    let line = raw.trim()

    if line != "" and ! line.starts_with("#") {
      lines = lines.push(f"#define ARM64_${line} ${cap}")
      cap += 1
    }
  }

  lines = lines.push(f"#define ARM64_NCAPS ${cap}")
  lines = lines.push("")
  lines = lines.push("#endif /* __ASM_CPUCAP_DEFS_H */")
  fs.mkdir(fp"${root}/arch/arm64/include/generated/asm")?

  write_text_if_changed(
    fp"${root}/arch/arm64/include/generated/asm/cpucap-defs.h",
    f"""${lines.join("\n")}
""",
  )?
}

pure config_value(config: Kconfig, name: Str) -> Str {
  return config.values.get(name, "")
}

pure expand_subst(raw: Str, config: Kconfig) -> Str {
  let marker = "$(subst m,y,$(CONFIG_"

  if ! (marker in raw) {
    return raw
  }

  let chunks = raw.split(marker)
  var out = chunks[0]

  for chunk in chunks |> drop(1) {
    let parts = chunk.split("))")

    if parts.len() == 1 {
      out = f"${out}${marker}${chunk}"
    } else {
      let name = parts[0]
      var value = config_value(config, name)

      if value == "m" {
        value = "y"
      }

      out = f"${out}${value}${(parts |> drop(1)).join("))")}"
    }
  }

  return out
}

pure expand_config_refs(raw: Str, config: Kconfig) -> Str {
  let marker = "$(CONFIG_"

  if ! (marker in raw) {
    return raw
  }

  let chunks = raw.split(marker)
  var out = chunks[0]

  for chunk in chunks |> drop(1) {
    let parts = chunk.split(")")

    if parts.len() == 1 {
      out = f"${out}${marker}${chunk}"
    } else {
      out = f"${out}${config_value(config, parts[0])}${(parts |> drop(1)).join(")")}"
    }
  }

  return out
}

pure expand_make_vars(raw: Str, vars: Map[Str]) -> Str {
  let marker = "$("

  if ! (marker in raw) {
    return raw
  }

  let chunks = raw.split(marker)
  var out = chunks[0]

  for chunk in chunks |> drop(1) {
    let parts = chunk.split(")")

    if parts.len() == 1 {
      out = f"${out}${marker}${chunk}"
    } else {
      out = f"${out}${vars.get(parts[0], "")}${(parts |> drop(1)).join(")")}"
    }
  }

  return out
}

pure expand_braced_config_refs(raw: Str, config: Kconfig) -> Str {
  let marker = "\${CONFIG_"

  if ! (marker in raw) {
    return raw
  }

  let chunks = raw.split(marker)
  var out = chunks[0]

  for chunk in chunks |> drop(1) {
    let parts = chunk.split("}")

    if parts.len() == 1 {
      out = f"${out}${marker}${chunk}"
    } else {
      out = f"${out}${config_value(config, parts[0])}${(parts |> drop(1)).join("}")}"
    }
  }

  return out
}

pure expand_vars(raw: Str, vars: Map[Str], config: Kconfig, srcarch: Str) -> Str {
  var out = expand_braced_config_refs(expand_subst(raw, config).replace("$(SRCARCH)", srcarch), config)

  if ! ("$(" in out) {
    return out
  }

  out = expand_config_refs(out, config)
  return expand_make_vars(out, vars)
}

proc logical_lines(body: Str) [] -> List[Str] {
  var lines: List[Str] = []
  var current = ""

  for raw in body.split("\n") {
    let without_comment = raw.split("#")[0]
    let trimmed = without_comment.trim()

    if trimmed == "" {
      if current.trim() != "" {
        lines = lines.push(current.trim())
        current = ""
      }

      continue
    }

    if trimmed.ends_with("\\") {
      current = f"${current} ${trimmed.replace("\\", "")}"
    } else {
      lines = lines.push(f"${current} ${trimmed}".trim())
      current = ""
    }
  }

  if current.trim() != "" {
    lines = lines.push(current.trim())
  }

  return lines
}

proc included_kbuild_lines(
  root: Path,
  line: Str,
  vars: Map[Str],
  config: Kconfig,
  srcarch: Str,
) [fs, error] -> Result[List[Str]] {
  if ! line.starts_with("include ") {
    return []
  }

  let raw_spec = line.split("include ").get(1, "").trim()

  if "$(objtree)" in raw_spec {
    return []
  }

  let spec = expand_vars(raw_spec, vars, config, srcarch)

  if spec == "" or " " in spec or "$(" in spec or spec.starts_with("/") {
    return []
  }

  let rel = normalize_rel_path(fp"${spec}")
  return logical_lines(join_root(root, rel).read_text()?)
}

pure parse_assignment(line: Str) -> Result[ParsedAssignment] {
  if "+=" in line {
    let parts = line.split("+=")
    return {lhs: parts[0].trim(), op: "+=", rhs: parts.get(1, "").trim()}
  }

  if ":=" in line {
    let parts = line.split(":=")
    return {lhs: parts[0].trim(), op: ":=", rhs: parts.get(1, "").trim()}
  }

  if "?=" in line {
    let parts = line.split("?=")
    return {lhs: parts[0].trim(), op: "?=", rhs: parts.get(1, "").trim()}
  }

  if "=" in line {
    let parts = line.split("=")
    return {lhs: parts[0].trim(), op: "=", rhs: parts.get(1, "").trim()}
  }

  return Err(ScriptError.Failed("kbuild-skip-line", line))
}

pure active_obj_lhs(expanded: Str) -> Bool {
  return expanded == "obj-y" or expanded == "lib-y" or expanded == "subdir-y"
}

pure active_var_lhs(expanded: Str) -> Str {
  if expanded == "KVM" {
    return expanded
  }

  if expanded.ends_with("-y") {
    return expanded
  }

  if expanded.ends_with("-objs") {
    return expanded
  }

  if expanded.ends_with("_files") {
    return expanded
  }

  return ""
}

proc conditional_value(raw: Str, vars: Map[Str], config: Kconfig, srcarch: Str) [] -> Str {
  let expanded = expand_vars(raw, vars, config, srcarch)

  if expanded.starts_with("CONFIG_") {
    return config_value(config, expanded.replace("CONFIG_", ""))
  }

  return expanded
}

proc eval_make_compare(line: Str, keyword: Str, vars: Map[Str], config: Kconfig, srcarch: Str) [] -> Result[Bool] {
  let prefix = f"${keyword} ("

  if ! line.starts_with(prefix) {
    return Err(ScriptError.Failed("kbuild-not-conditional", line))
  }

  let rest = line.split(prefix).get(1, "")
  let parts = rest.split(",")

  if parts.len() < 2 {
    return Err(ScriptError.Failed("kbuild-not-conditional", line))
  }

  let left = conditional_value(parts[0].trim(), vars, config, srcarch)
  let right = expand_vars((parts |> drop(1)).join(",").replace(")", "").trim(), vars, config, srcarch)

  if keyword == "ifeq" {
    return left == right
  }

  return left != right
}

proc eval_conditional(line: Str, vars: Map[Str], config: Kconfig, srcarch: Str) [] -> Result[Bool] {
  if line.starts_with("ifeq ($(CONFIG_") or line.starts_with("ifeq ($(SRCARCH)") or line.starts_with("ifeq ($(BITS)") {
    return eval_make_compare(line, "ifeq", vars, config, srcarch)
  }

  if line.starts_with("ifneq ($(CONFIG_") or line.starts_with("ifneq ($(SRCARCH)") or line.starts_with("ifneq ($(BITS)") {
    return eval_make_compare(line, "ifneq", vars, config, srcarch)
  }

  if line.starts_with("ifdef ") {
    let parts = line.fields()

    if parts.len() >= 2 {
      return conditional_value(parts[1], vars, config, srcarch) != ""
    }
  }

  if line.starts_with("ifndef ") {
    let parts = line.fields()

    if parts.len() >= 2 {
      return conditional_value(parts[1], vars, config, srcarch) == ""
    }
  }

  return Err(ScriptError.Failed("kbuild-not-conditional", line))
}

pure active_conditional(stack: List[Bool]) -> Bool {
  return stack[stack.len() - 1]
}

pure object_stem(item: Str) -> Str {
  return item.replace(".o", "")
}

pure object_item_for_dir(dir: Path, item: Str, as_lib: Bool = false) -> Str {
  if ! as_lib and path_key(dir) == "arch/x86/boot/startup" and item.ends_with(".o") {
    return f"${object_stem(item)}.pi.o"
  }

  return item
}

proc composite_members(dir: Path, item: Str, vars: Map[Str]) [] -> List[Path] {
  var members: List[Path] = []
  let stem = object_stem(item)

  for member in vars.get(f"${stem}-y", "").fields() {
    if member.ends_with(".o") {
      members = members.push(join_rel(dir, member))
    }
  }

  for member in vars.get(f"${stem}-objs", "").fields() {
    if member.ends_with(".o") {
      members = members.push(join_rel(dir, member))
    }
  }

  return unique_paths(members)
}

stream active_objects_for_dir(dir: Path, vars: Map[Str]) [] -> Stream[Path] {
  var objects: List[Path] = []
  var words = vars.get("obj-y", "").fields()
  words = words.extend(vars.get("lib-y", "").fields())

  for item in words {
    let active_item = object_item_for_dir(dir, item)

    if active_item.ends_with(".o") {
      let obj = join_rel(dir, active_item)

      if ! has_plan_path(objects, obj) {
        objects = objects.push(obj)
        yield obj
      }

      for member in composite_members(dir, active_item, vars) {
        if ! has_plan_path(objects, member) {
          objects = objects.push(member)
          yield member
        }
      }
    }
  }

  for obj in extra_objects_for_dir(dir) {
    if ! has_plan_path(objects, obj) {
      objects = objects.push(obj)
      yield obj
    }
  }
}

pure extra_objects_for_dir(dir: Path) -> List[Path] {
  if path_key(dir) == "arch/x86/entry/vdso/vdso64" {
    return [join_rel(dir, "vdso64-image.o")]
  }

  return []
}

pure plan_objects(plan: KbuildPlan) -> List[Path] {
  return plan.objects.extend(plan.lib_objects)
}

proc vars_for_dir(root: Path, dir: Path, config: Kconfig, srcarch: Str) [fs, error] -> Result[Map[Str]] {
  let file = kbuild_file(join_root(root, dir))?
  var vars = kbuild_vars_for_dir(dir, srcarch)
  var active_stack = [true]
  var lines = logical_lines(file.read_text()?)
  var line_index = 0

  while line_index < lines.len() {
    let line = lines[line_index]
    line_index += 1

    match eval_conditional(line, vars, config, srcarch) {
      Ok(active) => {
        active_stack = active_stack.push(active_conditional(active_stack) and active)
        continue
      }
      Err(_) => {}
    }

    if line == "else" {
      let parent = if active_stack.len() > 1 { active_stack[active_stack.len() - 2] } else { true }
      let current = active_conditional(active_stack)
      active_stack = (active_stack |> take(active_stack.len() - 1)).push(parent and ! current)
      continue
    }

    if line == "endif" {
      if active_stack.len() > 1 {
        active_stack = active_stack |> take(active_stack.len() - 1)
      }

      continue
    }

    continue unless active_conditional(active_stack)

    if line.starts_with("include ") {
      let included = included_kbuild_lines(root, line, vars, config, srcarch)?
      lines = (lines |> take(line_index)).extend(included).extend(lines |> drop(line_index))
      continue
    }

    match parse_assignment(line) {
      Ok(assign) => {
        let expanded_lhs = expand_vars(assign.lhs, vars, config, srcarch)
        let lhs = active_var_lhs(expanded_lhs)

        if lhs != "" {
          if path_key(dir) == "arch/x86/boot/startup" and lhs == "obj-y" and assign.rhs.starts_with(
            "$(patsubst %.o,%.pi.o,$(obj-y))",
          ) {
            var rewritten = [object_item_for_dir(dir, item) for item in vars.get("obj-y", "").fields()]
            vars[lhs] = rewritten.join(" ")
            continue
          }

          let rhs = expand_vars(assign.rhs, vars, config, srcarch)

          if assign.op == "+=" {
            vars[lhs] = f"${vars.get(lhs, "")} ${rhs}".trim()
          } else if assign.op != "?=" or vars.get(lhs, "") == "" {
            vars[lhs] = rhs
          }
        }
      }
      Err(_) => {}
    }
  }

  return vars
}

pure object_cflags_lhs(expanded: Str) -> Str {
  if expanded.starts_with("CFLAGS_") and expanded.ends_with(".o") {
    return expanded.replace("CFLAGS_", "")
  }

  return ""
}

proc kbuild_compile_flags_for_dir(
  root: Path,
  dir: Path,
  config: Kconfig,
  srcarch: Str,
) [fs, error] -> Result[Map[List[Str]]] {
  let file = kbuild_file(join_root(root, dir))?
  var vars = kbuild_vars_for_dir(dir, srcarch)
  var flags: Map[List[Str]] = {}
  var subdir_flags: List[Str] = []
  var active_stack = [true]
  var lines = logical_lines(file.read_text()?)
  var line_index = 0

  while line_index < lines.len() {
    let line = lines[line_index]
    line_index += 1

    match eval_conditional(line, vars, config, srcarch) {
      Ok(active) => {
        active_stack = active_stack.push(active_conditional(active_stack) and active)
        continue
      }
      Err(_) => {}
    }

    if line == "else" {
      let parent = if active_stack.len() > 1 { active_stack[active_stack.len() - 2] } else { true }
      let current = active_conditional(active_stack)
      active_stack = (active_stack |> take(active_stack.len() - 1)).push(parent and ! current)
      continue
    }

    if line == "endif" {
      if active_stack.len() > 1 {
        active_stack = active_stack |> take(active_stack.len() - 1)
      }

      continue
    }

    continue unless active_conditional(active_stack)

    if line.starts_with("include ") {
      let included = included_kbuild_lines(root, line, vars, config, srcarch)?
      lines = (lines |> take(line_index)).extend(included).extend(lines |> drop(line_index))
      continue
    }

    match parse_assignment(line) {
      Ok(assign) => {
        let expanded_lhs = expand_vars(assign.lhs, vars, config, srcarch)
        let rhs = expand_vars(assign.rhs, vars, config, srcarch)

        if expanded_lhs == "subdir-ccflags-y" or expanded_lhs == "ccflags-y" {
          let rhs_flags = rhs.fields()

          if assign.op == "+=" {
            subdir_flags = subdir_flags.extend(rhs_flags)
          } else if assign.op != "?=" or subdir_flags.len() == 0 {
            subdir_flags = rhs_flags
          }

          continue
        }

        let object_name = object_cflags_lhs(expanded_lhs)

        if object_name != "" {
          let key = path_key(join_rel(dir, object_name))
          let current = flags.get(key, [])

          if assign.op == "+=" {
            flags[key] = current.extend(rhs.fields())
          } else if assign.op != "?=" or current.len() == 0 {
            flags[key] = rhs.fields()
          }

          continue
        }

        let lhs = active_var_lhs(expanded_lhs)

        if lhs != "" {
          if assign.op == "+=" {
            vars[lhs] = f"${vars.get(lhs, "")} ${rhs}".trim()
          } else if assign.op != "?=" or vars.get(lhs, "") == "" {
            vars[lhs] = rhs
          }
        }
      }
      Err(_) => {}
    }
  }

  if subdir_flags.len() > 0 {
    flags["*"] = subdir_flags
  }

  return flags
}

proc kbuild_compile_flags_for_dirs(
  root: Path,
  dirs: List[Path],
  config: Kconfig,
  srcarch: Str,
) [fs, error] -> Result[Map[Map[List[Str]]]] {
  var by_dir: Map[Map[List[Str]]] = {}
  var dir_index = 0

  for dir in dirs {
    dir_index += 1

    write_text_if_changed(
      fp"${root}/.xsh-kbuild-progress",
      f"""xsh-kbuild-compile-flags-dir ${dir_index}/${dirs.len()} ${dir.display()}
""",
    )?

    by_dir[path_key(dir)] = kbuild_compile_flags_for_dir(root, dir, config, srcarch)?
  }

  return by_dir
}

pure compile_flags_cache_format() -> Str {
  return "linux-kbuild-compile-flags-v2"
}

pure compile_flags_cache_entries(flags: Map[Map[List[Str]]]) -> List[Record] {
  var entries: List[Record] = []

  for dir_key in flags.keys() {
    let dir_flags = flags.get(dir_key, map.empty())

    for object_key in dir_flags.keys() {
      entries = entries.push({dir: dir_key, object: object_key, flags: dir_flags.get(object_key, [])})
    }
  }

  return entries
}

pure compile_flags_from_cache_entries(entries: List[Record]) -> Result[Map[Map[List[Str]]]] {
  var flags: Map[Map[List[Str]]] = {}

  for entry in entries {
    let dir_key: Str = entry.get("dir")?
    let object_key: Str = entry.get("object")?
    let item_flags: List[Str] = entry.get("flags")?
    let dir_flags = flags.get(dir_key, map.empty()).set(object_key, item_flags)
    flags[dir_key] = dir_flags
  }

  return flags
}

proc compile_flags_fingerprint(
  root: Path,
  dirs: List[Path],
  config_path: Path,
  srcarch: Str,
) [fs, error] -> Result[Str] {
  var dir_fingerprints = [fingerprint_dir_line(root, dir)? for dir in dirs]

  return f"""format ${compile_flags_cache_format()}
srcarch ${srcarch}
config ${hash.sha256(config_path)?.hex()}
dirs ${dirs.len()}
${path_strings(dirs).join("\n")}
kbuild-files
${dir_fingerprints.join("\n")}
"""
}

proc read_compile_flags_cache(path_value: Path, fingerprint: Str) [fs, error] -> Result[Map[Map[List[Str]]]] {
  let stored: Record = json.read(path_value)?
  let format = if stored.has("format") { stored.get("format")? } else { "" }

  if format != compile_flags_cache_format() {
    return Err(ScriptError.Failed("kbuild-compile-flags-cache-stale", "compile flags cache has stale format"))
  }

  let cached_fingerprint: Str = stored.get("fingerprint")?

  if cached_fingerprint.trim() != fingerprint.trim() {
    return Err(ScriptError.Failed("kbuild-compile-flags-cache-stale", "compile flags cache fingerprint mismatch"))
  }

  let entries: List[Record] = stored.get("flags")?
  return compile_flags_from_cache_entries(entries)?
}

proc write_compile_flags_cache(path_value: Path, fingerprint: Str, flags: Map[Map[List[Str]]]) [fs, error] {
  write_text_if_changed(
    path_value,
    json.encode(
      {format: compile_flags_cache_format(), fingerprint: fingerprint, flags: compile_flags_cache_entries(flags)},
    )?,
  )?
}

proc cached_kbuild_compile_flags_for_dirs(
  root: Path,
  dirs: List[Path],
  config: Kconfig,
  srcarch: Str,
) [fs, env, error] -> Result[Map[Map[List[Str]]]] {
  let cache_dir = fp"${env.get("XSH_LINUX_KBUILD_COMPILE_FLAGS_CACHE_DIR") ?? env.get("XSH_LINUX_KBUILD_PLAN_CACHE_DIR") ?? "/var/cache/laputa/linux-kbuild"}"
  let stable_cache_path = fp"${cache_dir.display()}/linux-${srcarch}.compile-flags.json"
  let local_cache_path = fp"${root}/.xsh-kbuild-compile-flags.json"
  let fingerprint = compile_flags_fingerprint(root, dirs, fp"${root}/.config", srcarch)?

  if stable_cache_path.exists()? {
    match read_compile_flags_cache(stable_cache_path, fingerprint) {
      Ok(flags) => {
        write_text_if_changed(
          fp"${root}/.xsh-kbuild-progress",
          f"""xsh-kbuild-compile-flags-cache stable-hit ${dirs.len()} dirs
""",
        )?

        write_compile_flags_cache(local_cache_path, fingerprint, flags)?
        return flags
      }
      Err(err) => {
        match err {
          ScriptError.Failed {kind: kind, message: _} => write_text_if_changed(
            fp"${root}/.xsh-kbuild-progress",
            f"""xsh-kbuild-compile-flags-cache stable-miss ${kind}
""",
          )?
        }
      }
    }
  }

  if local_cache_path.exists()? {
    match read_compile_flags_cache(local_cache_path, fingerprint) {
      Ok(flags) => {
        write_text_if_changed(
          fp"${root}/.xsh-kbuild-progress",
          f"""xsh-kbuild-compile-flags-cache local-hit ${dirs.len()} dirs
""",
        )?

        cache_dir.mkdir()?
        write_compile_flags_cache(stable_cache_path, fingerprint, flags)?
        return flags
      }
      Err(err) => {
        match err {
          ScriptError.Failed {kind: kind, message: _} => write_text_if_changed(
            fp"${root}/.xsh-kbuild-progress",
            f"""xsh-kbuild-compile-flags-cache local-miss ${kind}
""",
          )?
        }
      }
    }
  }

  let flags = kbuild_compile_flags_for_dirs(root, dirs, config, srcarch)?
  write_compile_flags_cache(local_cache_path, fingerprint, flags)?
  cache_dir.mkdir()?
  write_compile_flags_cache(stable_cache_path, fingerprint, flags)?
  return flags
}

pure kbuild_compile_flags_for_object(by_dir: Map[Map[List[Str]]], obj: Path) -> List[Str] {
  let dir_flags = by_dir.get(path_key(object_dir(obj)), map.empty())
  let object_flags = dir_flags.get(path_key(obj), [])
  return dir_flags.get("*", []).extend(object_flags)
}

pure object_cflags(base: List[Str], by_dir: Map[Map[List[Str]]], obj: Path) -> List[Str] {
  return base.extend(kbuild_compile_flags_for_object(by_dir, obj))
}

export proc augment_missing_composites(
  root: Path,
  config: Kconfig,
  plan: KbuildPlan,
  srcarch: Str = "arm64",
) [fs, error] -> Result[KbuildPlan] {
  var composites = plan.composites
  var dirs: List[Path] = []
  var missing_by_dir: Map[List[Path]] = {}

  for obj in plan_objects(plan) {
    match source_for_object(obj) {
      Ok(_) => {}
      Err(err) => {
        match err {
          ScriptError.Failed {kind: kind, message: _} => {
            if kind == "kbuild-missing-source" and ! is_known_generated_object(obj) {
              match composite_for(composites, obj) {
                Ok(_) => {}
                Err(_) => {
                  let dir = object_dir(obj)
                  let dir_key = path_key(dir)
                  let current = missing_by_dir.get(dir_key, [])

                  if current.len() == 0 {
                    dirs = dirs.push(dir)
                  }

                  missing_by_dir[dir_key] = current.push(obj)
                }
              }
            }
          }
        }
      }
    }
  }

  let scans: List[CompositeScan] = dirs
    |> par-map --jobs=planner_jobs() { |dir|
      let vars = vars_for_dir(root, dir, config, srcarch)?
      var found = []

      for obj in missing_by_dir.get(path_key(dir), []) {
        let members = composite_members(dir, obj.name, vars)

        if members.len() > 0 {
          found = found.push({object: obj, members: members})
        }
      }

      {dir: dir, composites: found}
    }

  var composites_by_dir: Map[List[CompositeObject]] = {}

  for scan in scans {
    composites_by_dir[path_key(scan.dir)] = scan.composites
  }

  for dir in dirs {
    composites = composites.extend(composites_by_dir.get(path_key(dir), []))
  }

  return {...plan, composites: composites}
}

export proc prune_inactive_objects(
  root: Path,
  config: Kconfig,
  plan: KbuildPlan,
  srcarch: Str = "arm64",
) [fs, error] -> Result[KbuildPlan] {
  var active: Map[Bool] = {}

  let dir_objects: List[ActiveDirObjects] = plan.dirs
    |> par-map --jobs=planner_jobs() { |dir|
      let vars = vars_for_dir(root, dir, config, srcarch)?
      {dir: dir, objects: active_objects_for_dir(dir, vars).collect()}
    }

  for row in dir_objects {
    for obj in row.objects {
      active[path_key(obj)] = true
    }
  }

  var objects = [obj for obj in plan.objects if active.get(path_key(obj), false)]
  var composites = [composite for composite in plan.composites if active.get(path_key(composite.object), false)]
  var lib_objects = [obj for obj in plan.lib_objects if active.get(path_key(obj), false)]
  return {...plan, objects: objects, lib_objects: lib_objects, composites: composites}
}

export proc refresh_plan_dirs(
  root: Path,
  config: Kconfig,
  plan: KbuildPlan,
  srcarch: Str,
  dirs: List[Path],
) [fs, error] -> Result[KbuildPlan] {
  var next = plan
  let jobs = planner_jobs()

  write_text_if_changed(
    fp"${root}/.xsh-kbuild-progress",
    f"""xsh-kbuild-refresh-plan-dirs start ${dirs.len()} jobs ${jobs}
""",
  )?

  var objects_by_dir: Map[List[Path]] = {}
  var composites_by_dir: Map[List[CompositeObject]] = {}
  var scan_index = 0

  for dir in dirs {
    scan_index += 1

    write_text_if_changed(
      fp"${root}/.xsh-kbuild-progress",
      f"""xsh-kbuild-refresh-plan-dir-scan ${scan_index}/${dirs.len()} ${dir.display()}
""",
    )?

    let vars = vars_for_dir(root, dir, config, srcarch)?
    var objects: List[Path] = []
    var composites = []

    for obj in active_objects_for_dir(dir, vars) {
      objects = objects.push(obj)
      let members = composite_members(dir, obj.name, vars)

      if members.len() > 0 {
        composites = composites.push({object: obj, members: members})
      }
    }

    objects_by_dir[path_key(dir)] = objects
    composites_by_dir[path_key(dir)] = composites
  }

  var dirs_all = next.dirs
  var objects_all = next.objects
  var composites_all = next.composites
  var dir_index = 0

  for dir in dirs {
    dir_index += 1

    write_text_if_changed(
      fp"${root}/.xsh-kbuild-progress",
      f"""xsh-kbuild-refresh-plan-dir-merge ${dir_index}/${dirs.len()} ${dir.display()}
""",
    )?

    dirs_all = dirs_all.push(dir)
    objects_all = objects_all.extend(objects_by_dir.get(path_key(dir), []))
    composites_all = composites_all.extend(composites_by_dir.get(path_key(dir), []))
  }

  return normalize_plan({...next, dirs: dirs_all, objects: objects_all, composites: composites_all})
}

export proc refresh_x86_kernel_config_objects(config: Kconfig, plan: KbuildPlan) [fs, error] -> Result[KbuildPlan] {
  var objects: List[Path] = []
  var dirs: List[Path] = []

  if config_value(config, "UTS_NS") == "y" or config_value(config, "USER_NS") == "y" or config_value(config, "PID_NS") == "y" or config_value(
    config,
    "FREEZER",
  ) == "y" {
    dirs = dirs.push(p"kernel")
  }

  if config_value(config, "TIME_NS") == "y" {
    dirs = dirs.push(p"kernel/time")
  }

  if config_value(config, "MEMCG") == "y" {
    dirs = dirs.push(p"mm")
  }

  if config_value(config, "KVM_GUEST") == "y" {
    objects = objects.push(p"arch/x86/kernel/kvm.o")
    objects = objects.push(p"arch/x86/kernel/kvmclock.o")
  }

  if config_value(config, "PARAVIRT") == "y" {
    objects = objects.push(p"arch/x86/kernel/paravirt.o")
    objects = objects.push(p"arch/x86/kernel/paravirt-spinlocks.o")
  }

  if config_value(config, "PARAVIRT_CLOCK") == "y" {
    objects = objects.push(p"arch/x86/kernel/pvclock.o")
  }

  if config_value(config, "HYPERVISOR_GUEST") == "y" {
    objects = objects.push(p"arch/x86/kernel/cpu/vmware.o")
    objects = objects.push(p"arch/x86/kernel/cpu/hypervisor.o")
    objects = objects.push(p"arch/x86/kernel/cpu/mshyperv.o")
  }

  if config_value(config, "WIRELESS") == "y" {
    dirs = dirs.push(p"net/wireless")
  }

  if config_value(config, "MAC80211") == "y" {
    dirs = dirs.push(p"net/mac80211")
  }

  if config_value(config, "VHOST_MENU") == "y" {
    dirs = dirs.push(p"drivers/vhost")
  }

  if config_value(config, "VSOCKETS") == "y" {
    dirs = dirs.push(p"net/vmw_vsock")
  }

  if config_value(config, "BRIDGE") == "y" {
    dirs = dirs.push(p"net/bridge")
  }

  if config_value(config, "BRIDGE_NETFILTER") == "y" or config_value(config, "NF_TABLES_BRIDGE") == "y" {
    dirs = dirs.push(p"net/bridge/netfilter")
  }

  if config_value(config, "NF_TABLES") == "y" {
    dirs = dirs.push(p"net/netfilter")
    dirs = dirs.push(p"net/ipv4/netfilter")
    dirs = dirs.push(p"net/ipv6/netfilter")
  }

  if config_value(config, "XFRM") == "y" {
    dirs = dirs.push(p"net/xfrm")
    dirs = dirs.push(p"net/ipv4")
    dirs = dirs.push(p"net/ipv6")
  }

  if config_value(config, "MACVLAN") == "y" or config_value(config, "TAP") == "y" or config_value(config, "VETH") == "y" {
    dirs = dirs.push(p"drivers/net")
  }

  if config_value(config, "BT") == "y" {
    dirs = dirs.push(p"net/bluetooth")
    dirs = dirs.push(p"drivers/bluetooth")
  }

  if config_value(config, "NEW_LEDS") == "y" {
    dirs = dirs.push(p"drivers/leds")
    dirs = dirs.push(p"drivers/leds/trigger")
  }

  if config_value(config, "BTRFS_FS") == "y" {
    dirs = dirs.push(p"fs/btrfs")
  }

  if config_value(config, "FS_POSIX_ACL") == "y" {
    dirs = dirs.push(p"fs")
  }

  if config_value(config, "FUSE_FS") == "y" {
    dirs = dirs.push(p"fs/fuse")
  }

  if config_value(config, "OVERLAY_FS") == "y" {
    dirs = dirs.push(p"fs/overlayfs")
  }

  if config_value(config, "BPF_SYSCALL") == "y" {
    dirs = dirs.push(p"kernel/bpf")
  }

  if config_value(config, "BPF_JIT") == "y" {
    dirs = dirs.push(p"arch/x86/net")
  }

  if config_value(config, "BINARY_PRINTF") == "y" {
    dirs = dirs.push(p"lib")
  }

  if config_value(config, "TASKS_RCU") == "y" or config_value(config, "TASKS_TRACE_RCU") == "y" {
    dirs = dirs.push(p"kernel/rcu")
  }

  if config_value(config, "BPF_STREAM_PARSER") == "y" or config_value(config, "NET_SOCK_MSG") == "y" {
    dirs = dirs.push(p"net/core")
    dirs = dirs.push(p"net/ipv4")
    dirs = dirs.push(p"net/ipv6")
  }

  if config_value(config, "CGROUPS") == "y" {
    dirs = dirs.push(p"kernel/cgroup")
  }

  if config_value(config, "PM") == "y" {
    dirs = dirs.push(p"kernel/power")
  }

  if config_value(config, "DMA_OPS_HELPERS") == "y" {
    dirs = dirs.push(p"kernel/dma")
  }

  if config_value(config, "ACPI_SLEEP") == "y" {
    dirs = dirs.push(p"arch/x86/kernel/acpi")
  }

  if config_value(config, "CPU_FREQ") == "y" {
    dirs = dirs.push(p"drivers/cpufreq")
  }

  if config_value(config, "INTEL_IDLE") == "y" {
    dirs = dirs.push(p"drivers/idle")
  }

  if config_value(config, "IOMMU_SUPPORT") == "y" {
    dirs = dirs.push(p"drivers/iommu")
  }

  if config_value(config, "GENERIC_PT") == "y" or config_value(config, "AMD_IOMMU") == "y" or config_value(
    config,
    "INTEL_IOMMU",
  ) == "y" {
    dirs = dirs.push(p"drivers/iommu/generic_pt/fmt")
  }

  if config_value(config, "INTEL_IOMMU") == "y" or config_value(config, "DMAR_TABLE") == "y" or config_value(
    config,
    "IRQ_REMAP",
  ) == "y" {
    dirs = dirs.push(p"drivers/iommu/intel")
  }

  if config_value(config, "AMD_IOMMU") == "y" {
    dirs = dirs.push(p"drivers/iommu/amd")
  }

  if config_value(config, "VFIO") == "y" {
    dirs = dirs.push(p"drivers/vfio")
  }

  if config_value(config, "VFIO_PCI") == "y" {
    dirs = dirs.push(p"drivers/vfio/pci")
  }

  if config_value(config, "INPUT_MOUSEDEV") == "y" or config_value(config, "INPUT_JOYDEV") == "y" {
    dirs = dirs.push(p"drivers/input")
  }

  if config_value(config, "INPUT_UINPUT") == "y" {
    dirs = dirs.push(p"drivers/input/misc")
  }

  if config_value(config, "USB_VIDEO_CLASS") == "y" {
    dirs = dirs.push(p"drivers/media/usb/uvc")
    dirs = dirs.push(p"drivers/media/common")
  }

  if config_value(config, "SND_USB_AUDIO") == "y" {
    dirs = dirs.push(p"sound/usb")
  }

  if config_value(config, "CRYPTO_LIB_ARC4") == "y" {
    dirs = dirs.push(p"lib/crypto")
  }

  if config_value(config, "CRYPTO_ECDH") == "y" {
    dirs = dirs.push(p"crypto")
  }

  if config_value(config, "SND") == "y" {
    dirs = dirs.push(p"sound/core")
  }

  var next = plan

  if objects.len() > 0 {
    next = add_plan_objects(add_dir(next, p"arch/x86/kernel"), objects)
  }

  if dirs.len() > 0 {
    next = refresh_plan_dirs(p".", config, next, "x86", dirs)?
  }

  if config_value(config, "IOMMU_PT_AMDV1") == "y" {
    next = add_object(add_dir(next, p"drivers/iommu/generic_pt/fmt"), p"drivers/iommu/generic_pt/fmt/iommu_amdv1.o")
  }

  if config_value(config, "IOMMU_PT_X86_64") == "y" {
    next = add_object(add_dir(next, p"drivers/iommu/generic_pt/fmt"), p"drivers/iommu/generic_pt/fmt/iommu_x86_64.o")
  }

  if config_value(config, "IOMMU_PT_VTDSS") == "y" {
    next = add_object(add_dir(next, p"drivers/iommu/generic_pt/fmt"), p"drivers/iommu/generic_pt/fmt/iommu_vtdss.o")
  }

  if config_value(config, "ZSTD_DECOMPRESS") == "y" {
    let obj = p"lib/zstd/zstd_decompress.o"

    next = add_composite(
      add_object(next, obj),
      {
        object: obj,
        members: [
          p"lib/zstd/zstd_decompress_module.o",
          p"lib/zstd/decompress/huf_decompress.o",
          p"lib/zstd/decompress/zstd_ddict.o",
          p"lib/zstd/decompress/zstd_decompress.o",
          p"lib/zstd/decompress/zstd_decompress_block.o",
        ],
      },
    )
  }

  if config_value(config, "ZSTD_COMMON") == "y" {
    let obj = p"lib/zstd/zstd_common.o"

    next = add_composite(
      add_object(next, obj),
      {
        object: obj,
        members: [
          p"lib/zstd/zstd_common_module.o",
          p"lib/zstd/common/debug.o",
          p"lib/zstd/common/entropy_common.o",
          p"lib/zstd/common/error_private.o",
          p"lib/zstd/common/fse_decompress.o",
          p"lib/zstd/common/zstd_common.o",
        ],
      },
    )
  }

  return next
}

export proc refresh_plan_composite_members(
  root: Path,
  config: Kconfig,
  plan: KbuildPlan,
  srcarch: Str,
  objects: List[Path],
) [fs, error] -> Result[KbuildPlan] {
  var refreshed: Map[CompositeObject] = {}
  var member_paths: Map[Bool] = {}

  for obj in objects {
    let dir = object_dir(obj)
    let vars = vars_for_dir(root, dir, config, srcarch)?
    let members = composite_members(dir, obj.name, vars)

    if members.len() > 0 {
      refreshed[path_key(obj)] = {object: obj, members: members}

      for member in members {
        member_paths[path_key(member)] = true
      }
    }
  }

  var composites: List[CompositeObject] = []
  var seen: Map[Bool] = {}

  for composite in plan.composites {
    let key = path_key(composite.object)

    if refreshed.has(key) {
      composites = composites.push(refreshed.get(key)?)
      seen[key] = true
    } else {
      composites = composites.push(composite)
    }
  }

  for obj in objects {
    let key = path_key(obj)

    if refreshed.has(key) and ! seen.get(key, false) {
      composites = composites.push(refreshed.get(key)?)
    }
  }

  var top_objects = [obj for obj in plan.objects if ! member_paths.get(path_key(obj), false)]
  return normalize_plan({...plan, objects: top_objects, composites: composites})
}

export proc refresh_arm64_kernel_config_objects(config: Kconfig, plan: KbuildPlan) [fs, error] -> Result[KbuildPlan] {
  var objects: List[Path] = []

  if config_value(config, "VFIO") == "y" {
    objects = objects.push(p"drivers/vfio/vfio.o")
  }

  if config_value(config, "VFIO_PCI_CORE") == "y" {
    objects = objects.push(p"drivers/vfio/pci/vfio-pci-core.o")
  }

  if config_value(config, "VFIO_PCI") == "y" {
    objects = objects.push(p"drivers/vfio/pci/vfio-pci.o")
  }

  if objects.len() == 0 {
    return plan
  }

  return refresh_plan_composite_members(p".", config, plan, "arm64", objects)?
}

export proc add_plan_objects(plan: KbuildPlan, objects: List[Path]) [] -> KbuildPlan {
  var next = plan

  for obj in objects {
    next = add_object(next, obj)
  }

  return next
}

proc apply_item(plan: KbuildPlan, dir: Path, item: Str, vars: Map[Str], as_lib: Bool = false) [] -> ItemResult {
  if item == "" {
    return {plan: plan, dirs: [], entries: []}
  }

  if "$(" in item {
    return {plan: add_unsupported(plan, f"${path_key(dir)}: unresolved token ${item}"), dirs: [], entries: []}
  }

  if item.ends_with("/") {
    let child = dirname_for_item(dir, item)
    return {plan: add_dir(plan, child), dirs: [child], entries: [child]}
  }

  if item.ends_with(".o") {
    let active_item = object_item_for_dir(dir, item, as_lib)
    let obj = join_rel(dir, active_item)
    let members = composite_members(dir, active_item, vars)
    var next = if as_lib { add_lib_object(plan, obj) } else { add_object(plan, obj) }

    if members.len() > 0 {
      next = add_composite(next, {object: obj, members: members})
    }

    return {plan: next, dirs: [], entries: [obj]}
  }

  return {plan: add_unsupported(plan, f"${path_key(dir)}: unsupported token ${item}"), dirs: [], entries: []}
}

proc apply_words(plan: KbuildPlan, dir: Path, words: List[Str], vars: Map[Str], as_lib: Bool = false) [] -> ItemResult {
  var current = plan
  var dirs: List[Path] = []
  var entries: List[Path] = []

  for item in words {
    let applied = apply_item(current, dir, item, vars, as_lib)
    current = applied.plan
    dirs = dirs.extend(applied.dirs)
    entries = entries.extend(applied.entries)
  }

  return {plan: current, dirs: dirs, entries: entries}
}

proc kbuild_file(dir_abs: Path) [fs, error] -> Result[Path] {
  let kbuild = fp"${dir_abs}/Kbuild"

  if kbuild.exists()? {
    return kbuild
  }

  let makefile = fp"${dir_abs}/Makefile"

  if makefile.exists()? {
    return makefile
  }

  return Err(ScriptError.Failed("kbuild-missing", f"missing Kbuild or Makefile in ${dir_abs.display()}"))
}

proc emit_discover_progress(root: Path, options: DiscoverOptions, state: DiscoverState, rel: Path) [fs, error] {
  if options.progress and options.progress_every > 0 {
    let count = state.visited

    if count == 1 or count % options.progress_every == 0 {
      let message = f"xsh-kbuild-discover ${count} visited ${state.plan.dirs.len()} dirs ${state.plan.objects.len()} objects current=${path_key(
        rel,
      )}"

      fs.write(
        fp"${root}/.xsh-kbuild-progress",
        f"""${message}
""",
      )?

      print $message
    }
  }
}

proc emit_stage_progress(root: Path, options: DiscoverOptions, message: Str) [fs, error] {
  if options.progress {
    fs.write(
      fp"${root}/.xsh-kbuild-progress",
      f"""${message}
""",
    )?

    print $message
  }
}

proc emit_merge_progress(root: Path, options: DiscoverOptions, state: DiscoverState, rel: Path) [fs, error] {
  if options.progress and options.progress_every > 0 {
    let count = state.visited

    if count == 1 or count % options.progress_every == 0 {
      emit_stage_progress(
        root,
        options,
        f"xsh-kbuild-merge ${count} merged ${state.plan.dirs.len()} dirs ${state.plan.objects.len()} objects current=${path_key(
          rel,
        )}",
      )?
    }
  }
}

proc emit_line_progress(root: Path, options: DiscoverOptions, rel: Path, line_no: Int, line: Str) [fs, error] {
  if options.progress and options.progress_every == 1 {
    fs.write(
      fp"${root}/.xsh-kbuild-progress",
      f"""xsh-kbuild-line current=${path_key(rel)} line=${line_no} text=${line}
""",
    )?
  }
}

proc emit_batch_progress(root: Path, options: DiscoverOptions, pending: List[Path]) [fs, error] {
  if options.progress {
    fs.write(
      fp"${root}/.xsh-kbuild-progress",
      f"""xsh-kbuild-batch count=${pending.len()} sample=${path_strings(pending |> take(16)).join(",")}
""",
    )?
  }
}

proc scan_discover_dir(
  root: Path,
  rel: Path,
  config: Kconfig,
  srcarch: Str,
  options: DiscoverOptions,
) [fs, error] -> Result[DirScan] {
  let rel_key = path_key(rel)
  let dir_abs = join_root(root, rel)
  let file_result = kbuild_file(dir_abs)

  match file_result {
    Err(err) => {
      let plan = add_unsupported(add_dir(empty_plan(), rel), err.message)
      return {dir: rel, plan: plan, child_dirs: [], entries: []}
    }
    Ok(_) => {}
  }

  let file = file_result?
  var plan = add_dir(empty_plan(), rel)
  var vars = kbuild_vars_for_dir(rel, srcarch)
  var child_dirs: List[Path] = []
  var entries: List[Path] = []
  var object_rhs: List[Str] = []
  var lib_rhs: List[Str] = []
  var active_stack = [true]
  var line_no = 0

  if options.progress and options.progress_every == 1 {
    emit_stage_progress(root, options, f"xsh-kbuild-scan-start current=${rel_key}")?
  }

  var lines = logical_lines(file.read_text()?)
  var line_index = 0

  while line_index < lines.len() {
    let line = lines[line_index]
    line_index += 1
    line_no += 1
    emit_line_progress(root, options, rel, line_no, line)?

    match eval_conditional(line, vars, config, srcarch) {
      Ok(active) => {
        active_stack = active_stack.push(active_conditional(active_stack) and active)
        continue
      }
      Err(_) => {}
    }

    if line == "else" {
      let parent = if active_stack.len() > 1 { active_stack[active_stack.len() - 2] } else { true }
      let current = active_conditional(active_stack)
      active_stack = (active_stack |> take(active_stack.len() - 1)).push(parent and ! current)
      continue
    }

    if line == "endif" {
      if active_stack.len() > 1 {
        active_stack = active_stack |> take(active_stack.len() - 1)
      }

      continue
    }

    continue unless active_conditional(active_stack)

    if line.starts_with("include ") {
      let included = included_kbuild_lines(root, line, vars, config, srcarch)?
      lines = (lines |> take(line_index)).extend(included).extend(lines |> drop(line_index))
      continue
    }

    match parse_assignment(line) {
      Ok(assign) => {
        let expanded_lhs = expand_vars(assign.lhs, vars, config, srcarch)
        let lhs = active_var_lhs(expanded_lhs)

        if active_obj_lhs(expanded_lhs) {
          let rhs = expand_vars(assign.rhs, vars, config, srcarch)

          if expanded_lhs == "lib-y" {
            lib_rhs = lib_rhs.push(rhs)
          } else {
            object_rhs = object_rhs.push(rhs)
          }
        } else if lhs != "" {
          let rhs = expand_vars(assign.rhs, vars, config, srcarch)

          if assign.op == "+=" {
            vars[lhs] = f"${vars.get(lhs, "")} ${rhs}".trim()
          } else if assign.op != "?=" or vars.get(lhs, "") == "" {
            vars[lhs] = rhs
          }
        }
      }
      Err(_) => {}
    }
  }

  for rhs in object_rhs {
    let applied = apply_words(plan, rel, rhs.fields(), vars)
    plan = applied.plan
    child_dirs = child_dirs.extend(applied.dirs)
    entries = entries.extend(applied.entries)
  }

  if srcarch == "x86" {
    for obj in extra_objects_for_dir(rel) {
      plan = add_object(plan, obj)
      entries = entries.push(obj)
    }
  }

  for rhs in lib_rhs {
    let applied = apply_words(plan, rel, rhs.fields(), vars, true)
    plan = applied.plan
    child_dirs = child_dirs.extend(applied.dirs)
  }

  return {dir: rel, plan: plan, child_dirs: child_dirs, entries: entries}
}

proc unique_unseen_paths(paths: List[Path], seen: Map[Bool]) [] -> List[Path] {
  var unique: List[Path] = []
  var local_seen = seen

  for path_value in paths {
    let key = path_key(path_value)

    if ! local_seen.get(key, false) {
      local_seen[key] = true
      unique = unique.push(path_value)
    }
  }

  return unique
}

proc discover_scans(
  root: Path,
  config: Kconfig,
  srcarch: Str,
  options: DiscoverOptions,
) [fs, error] -> Result[Map[DirScan]] {
  var scans: Map[DirScan] = {}
  var seen: Map[Bool] = {}
  var frontier = [p"."]
  var aggregate = empty_plan()
  var visited = 0

  while frontier.len() > 0 {
    emit_stage_progress(root, options, f"xsh-kbuild-frontier-start frontier=${frontier.len()}")?
    let pending = unique_unseen_paths(frontier, seen)
    emit_stage_progress(root, options, f"xsh-kbuild-frontier-pending pending=${pending.len()}")?
    frontier = []

    for dir in pending {
      seen[path_key(dir)] = true
    }

    emit_batch_progress(root, options, pending)?
    var batch: List[DirScan] = []

    # Parallel discovery currently clones the large Kconfig/runtime context into
    # each worker and can burn CPU for minutes without returning a batch. Keep
    # compile/link parallelism, but make discovery deterministic and bounded.
    for dir in pending {
      emit_stage_progress(root, options, f"xsh-kbuild-scan ${path_key(dir)}")?
      batch = batch.push(scan_discover_dir(root, dir, config, srcarch, options)?)
    }

    var batch_by_dir: Map[DirScan] = {}

    for scan in batch {
      batch_by_dir[path_key(scan.dir)] = scan
    }

    for dir in pending {
      let scan = batch_by_dir.get(path_key(dir))?
      scans[path_key(dir)] = scan
      aggregate = merge_plan(aggregate, scan.plan)
      visited += 1
      emit_discover_progress(root, options, {plan: aggregate, seen: seen, visited: visited}, dir)?

      for child in scan.child_dirs {
        if ! seen.get(path_key(child), false) {
          frontier = frontier.push(child)
        }
      }
    }
  }

  return scans
}

proc merge_discovered_scans(
  scan_by_dir: Map[DirScan],
  rel: Path,
  state: DiscoverState,
) [error] -> Result[DiscoverState] {
  let rel_key = path_key(rel)

  if state.seen.get(rel_key, false) {
    return state
  }

  let scan = scan_by_dir.get(rel_key)?

  var next: DiscoverState = {
    plan: merge_plan(state.plan, scan.plan),
    seen: state.seen.set(rel_key, true),
    visited: state.visited + 1,
  }

  for child in scan.child_dirs {
    next = merge_discovered_scans(scan_by_dir, child, next)?
  }

  return next
}

proc merge_discovered_scans_with_options(
  root: Path,
  options: DiscoverOptions,
  scan_by_dir: Map[DirScan],
  rel: Path,
  state: DiscoverState,
) [fs, error] -> Result[DiscoverState] {
  let rel_key = path_key(rel)

  if state.seen.get(rel_key, false) {
    return state
  }

  let scan = scan_by_dir.get(rel_key)?

  var next: DiscoverState = {
    plan: merge_plan(state.plan, scan.plan),
    seen: state.seen.set(rel_key, true),
    visited: state.visited + 1,
  }

  emit_merge_progress(root, options, next, rel)?

  for child in scan.child_dirs {
    let child_next: DiscoverState = merge_discovered_scans_with_options(root, options, scan_by_dir, child, next)?
    next = child_next
  }

  return next
}

export proc discover_plan(root: Path, config: Kconfig, srcarch: Str = "arm64") [fs, error] -> Result[KbuildPlan] {
  return discover_plan_with_options(root, config, srcarch, default_discover_options())
}

export proc discover_plan_with_options(
  root: Path,
  config: Kconfig,
  srcarch: Str,
  options: DiscoverOptions,
) [fs, error] -> Result[KbuildPlan] {
  let scans = discover_scans(root, config, srcarch, options)?
  emit_stage_progress(root, options, "xsh-kbuild-discover-scans complete")?

  let state = merge_discovered_scans_with_options(
    root,
    options,
    scans,
    p".",
    {plan: empty_plan(), seen: map.empty(), visited: 0},
  )?

  emit_stage_progress(
    root,
    options,
    f"xsh-kbuild-discover-complete ${state.plan.dirs.len()} dirs ${state.plan.objects.len()} objects ${state.plan.composites.len()} composites",
  )?

  return normalize_plan(state.plan)
}

pure path_strings(paths: List[Path]) -> List[Str] {
  return [path_key(path_value) for path_value in paths]
}

pure argv_strings(argv: List[Any]) -> List[Str] {
  return [f"${arg}" for arg in argv]
}

proc paths_from_strings(items: List[Str]) [error] -> Result[List[Path]] {
  [path_from_string(item)? for item in items]
}

proc unique_paths(paths: List[Path]) [] -> List[Path] {
  var unique: List[Path] = []
  var seen: Map[Bool] = {}

  for path_value in paths {
    let key = path_key(path_value)

    if ! seen.get(key, false) {
      seen[key] = true
      unique = unique.push(path_value)
    }
  }

  return unique
}

proc unique_composites(composites: List[CompositeObject]) [] -> List[CompositeObject] {
  var unique: List[CompositeObject] = []
  var seen: Map[Bool] = {}

  for composite in composites {
    let key = path_key(composite.object)

    if ! seen.get(key, false) {
      seen[key] = true
      unique = unique.push(composite)
    }
  }

  return unique
}

proc normalize_plan(plan: KbuildPlan) [] -> KbuildPlan {
  return {
    dirs: unique_paths(plan.dirs),
    objects: unique_paths(plan.objects),
    lib_objects: unique_paths(plan.lib_objects),
    composites: unique_composites(plan.composites),
    unsupported: plan.unsupported,
  }
}

proc sorted_paths(paths: List[Path]) [] -> List[Path] {
  var sorted: List[Path] = []

  for path_value in paths {
    var next: List[Path] = []
    var inserted = false
    let key = path_key(path_value)

    for item in sorted {
      if ! inserted and key < path_key(item) {
        next = next.push(path_value)
        inserted = true
      }

      next = next.push(item)
    }

    if ! inserted {
      next = next.push(path_value)
    }

    sorted = next
  }

  return sorted
}

pure composite_records(composites: List[CompositeObject]) -> List[Record] {
  return [{object: path_key(item.object), members: path_strings(item.members)} for item in composites]
}

proc composites_from_records(items: List[Record]) [error] -> Result[List[CompositeObject]] {
  var composites: List[CompositeObject] = []

  for item in items {
    let object_key: Str = item.get("object")?
    let members: List[Str] = item.get("members")?
    composites = composites.push({object: fp"${object_key}", members: paths_from_strings(members)?})
  }

  return composites
}

pure plan_record(plan: KbuildPlan) -> Record {
  return {
    dirs: path_strings(plan.dirs),
    objects: path_strings(plan.objects),
    lib_objects: path_strings(plan.lib_objects),
    composites: composite_records(plan.composites),
    unsupported: plan.unsupported,
  }
}

pure discovered_plan_text(plan: KbuildPlan) -> Str {
  var out = ""

  for dir in plan.dirs {
    out = f"""${out}dir	${path_key(dir)}
"""
  }

  for obj in plan.objects {
    out = f"""${out}obj	${path_key(obj)}
"""
  }

  for obj in plan.lib_objects {
    out = f"""${out}lib	${path_key(obj)}
"""
  }

  for composite in plan.composites {
    out = f"""${out}composite	${path_key(composite.object)}	${path_strings(composite.members).join("\t")}
"""
  }

  for item in plan.unsupported {
    out = f"""${out}unsupported	${item}
"""
  }

  return out
}

export proc write_discovered_plan(plan: KbuildPlan, out: Path) [fs, error] {
  write_text_if_changed(out, discovered_plan_text(plan))?
}

export proc read_discovered_plan(path_value: Path) [fs, error] -> Result[KbuildPlan] {
  let text = path_value.read_text()?

  if ! text.trim().starts_with("{") {
    return read_discovered_plan_text(path_value)
  }

  let stored: Record = json.read(path_value)?
  let dirs: List[Str] = stored.get("dirs")?
  let objects: List[Str] = stored.get("objects")?
  let no_composites: List[Record] = []
  let no_strings: List[Str] = []
  let lib_objects = if stored.has("lib_objects") { stored.get("lib_objects")? } else { no_strings }
  let composites = if stored.has("composites") { stored.get("composites")? } else { no_composites }
  let unsupported = if stored.has("unsupported") { stored.get("unsupported")? } else { no_strings }

  return {
    dirs: unique_paths(paths_from_strings(dirs)?),
    objects: unique_paths(paths_from_strings(objects)?),
    lib_objects: unique_paths(paths_from_strings(lib_objects)?),
    composites: composites_from_records(composites)?,
    unsupported: unsupported,
  }
}

export proc parse_discovered_plan_text(text: Str) [error] -> Result[KbuildPlan] {
  var dirs: List[Str] = []
  var objects: List[Str] = []
  var lib_objects: List[Str] = []
  var composites: List[CompositeObject] = []
  var unsupported: List[Str] = []

  for raw in text.split("\n") {
    let line = raw.trim()
    continue when line == ""
    let parts = line.split("\t")
    let kind = parts[0]

    match kind {
      "dirs" => dirs = parts |> drop(1)
      "dir" => dirs = dirs.push(parts.get(1, ""))
      "objects" => objects = parts |> drop(1)
      "obj" => objects = objects.push(parts.get(1, ""))
      "lib_objects" => lib_objects = parts |> drop(1)
      "lib" => lib_objects = lib_objects.push(parts.get(1, ""))
      "composite" => composites = composites.push(
        {object: fp"${parts.get(1, "")}", members: paths_from_strings(parts |> drop(2))?},
      )
      "unsupported" => unsupported = unsupported.push(parts.get(1, ""))
      _ => {}
    }
  }

  return {
    dirs: paths_from_strings(dirs)?,
    objects: paths_from_strings(objects)?,
    lib_objects: paths_from_strings(lib_objects)?,
    composites: composites,
    unsupported: unsupported,
  }
}

export proc read_discovered_plan_text(path_value: Path) [fs, error] -> Result[KbuildPlan] {
  return parse_discovered_plan_text(path_value.read_text()?)
}

proc fingerprint_dir_line(root: Path, dir: Path) [fs, error] -> Result[Str] {
  var line = ""

  match kbuild_file(join_root(root, dir)) {
    Ok(file) => {
      let rel = file.strip_prefix(root)?
      line = f"${path_key(rel)} ${hash.sha256(file)?.hex()}"
    }
    Err(err) => line = f"${path_key(dir)} missing ${err.message}"
  }

  return line
}

export proc plan_fingerprint(root: Path, config_path: Path, plan: KbuildPlan) [fs, error] -> Result[Str] {
  let _ = root

  return f"""format linux-kbuild-plan-fingerprint-v9
config ${hash.sha256(config_path)?.hex()}
dirs ${plan.dirs.len()}
objects ${plan.objects.len()}
lib_objects ${plan.lib_objects.len()}
composites ${plan.composites.len()}
"""
}

pure task_record(task: Record) -> Record {
  return {
    name: task.name,
    outputs: path_strings(task.outputs),
    inputs: path_strings(task.inputs),
    deps: task.deps,
    argv: argv_strings(task.argv),
    env: task.env,
    cwd: task.cwd.display(),
    depfile: task.depfile.display(),
    stamp: task.stamp.display(),
  }
}

pure task_records(tasks: List[make.MakeTask]) -> List[Record] {
  return [task_record(task) for task in tasks]
}

pure archive_plan_report_format() -> Str {
  return "linux-archive-plan-v4"
}

export pure archive_plan_summary_path(report_path: Path) -> Path {
  return fp"${report_path.display()}.summary"
}

pure duplicate_task_outputs(tasks: List[make.MakeTask]) -> List[Path] {
  var outputs: Map[Bool] = {}
  var duplicates: List[Path] = []

  for task in tasks {
    for output in task.outputs {
      let key = path_key(output)
      continue when key == ""

      if outputs.get(key, false) {
        if ! has_plan_path(duplicates, output) {
          duplicates = duplicates.push(output)
        }
      } else {
        outputs[key] = true
      }
    }
  }

  return duplicates
}

export proc write_archive_plan_summary(archive_plan: Record, out: Path) [fs, error] {
  write_text_if_changed(
    out,
    json.encode({
      format: archive_plan_report_format(),
      archives: path_strings(archive_plan.archives),
      link_inputs: path_strings(archive_plan.link_inputs),
      generated_objects: path_strings(archive_plan.generated_objects),
      missing_sources: path_strings(archive_plan.missing_sources),
      duplicate_outputs: path_strings(duplicate_task_outputs(archive_plan.tasks)),
      task_count: archive_plan.tasks.len(),
    })?,
  )?
}

export proc write_archive_plan_report(archive_plan: Record, out: Path) [fs, error] {
  write_text_if_changed(
    out,
    json.encode({
      format: archive_plan_report_format(),
      archives: path_strings(archive_plan.archives),
      link_inputs: path_strings(archive_plan.link_inputs),
      generated_objects: path_strings(archive_plan.generated_objects),
      missing_sources: path_strings(archive_plan.missing_sources),
      duplicate_outputs: path_strings(duplicate_task_outputs(archive_plan.tasks)),
      task_count: archive_plan.tasks.len(),
      tasks: task_records(archive_plan.tasks),
    })?,
  )?

  write_archive_plan_summary(archive_plan, archive_plan_summary_path(out))?
}

proc path_from_string(item: Str) [error] -> Result[Path] {
  if item == "" {
    return p""
  }

  return fp"${item}"
}

proc task_from_record(item: Record) [error] -> Result[make.MakeTask] {
  let outputs: List[Str] = item.get("outputs")?
  let inputs: List[Str] = item.get("inputs")?
  let deps: List[Str] = item.get("deps")?
  let argv: List[Str] = item.get("argv")?
  let env_record: Record = item.get("env")?
  let cwd: Str = item.get("cwd")?
  let depfile: Str = item.get("depfile")?
  let stamp: Str = item.get("stamp")?

  return {
    name: item.get("name")?,
    outputs: paths_from_strings(outputs)?,
    inputs: paths_from_strings(inputs)?,
    deps: deps,
    argv: argv,
    cwd: path_from_string(cwd)?,
    env: env_record,
    depfile: path_from_string(depfile)?,
    stamp: path_from_string(stamp)?,
  }
}

proc read_archive_plan_tasks(path_value: Path) [fs, error] -> Result[List[make.MakeTask]] {
  let stored: Record = json.read(path_value)?
  let rows: List[Record] = stored.get("tasks")?
  [task_from_record(row)? for row in rows]
}

export proc read_archive_plan_report(path_value: Path) [fs, error] -> Result[Record] {
  let stored: Record = json.read(path_value)?
  let format = if stored.has("format") { stored.get("format")? } else { "" }

  if format != archive_plan_report_format() {
    return Err(ScriptError.Failed("kbuild-archive-plan-cache-stale", "archive plan cache has stale format"))
  }

  let archives: List[Str] = stored.get("archives")?
  let link_inputs: List[Str] = stored.get("link_inputs")?
  let generated_objects: List[Str] = stored.get("generated_objects")?
  let missing_sources: List[Str] = stored.get("missing_sources")?
  let duplicate_outputs = if stored.has("duplicate_outputs") { stored.get("duplicate_outputs")? } else { [] }
  let task_count = if stored.has("task_count") { stored.get("task_count")? } else { 0 }

  return {
    tasks: read_archive_plan_tasks(path_value)?,
    archives: paths_from_strings(archives)?,
    link_inputs: paths_from_strings(link_inputs)?,
    generated_objects: paths_from_strings(generated_objects)?,
    missing_sources: paths_from_strings(missing_sources)?,
    duplicate_outputs: paths_from_strings(duplicate_outputs)?,
    task_count: task_count,
  }
}

export proc read_archive_plan_summary(path_value: Path) [fs, error] -> Result[Record] {
  let stored: Record = json.read(path_value)?
  let format = if stored.has("format") { stored.get("format")? } else { "" }

  if format != archive_plan_report_format() {
    return Err(ScriptError.Failed("kbuild-archive-plan-cache-stale", "archive plan summary has stale format"))
  }

  let archives: List[Str] = stored.get("archives")?
  let link_inputs: List[Str] = stored.get("link_inputs")?
  let generated_objects: List[Str] = stored.get("generated_objects")?
  let missing_sources: List[Str] = stored.get("missing_sources")?
  let duplicate_outputs = if stored.has("duplicate_outputs") { stored.get("duplicate_outputs")? } else { [] }
  let task_count: Int = stored.get("task_count")?
  let tasks: List[make.MakeTask] = []

  return {
    tasks: tasks,
    archives: paths_from_strings(archives)?,
    link_inputs: paths_from_strings(link_inputs)?,
    generated_objects: paths_from_strings(generated_objects)?,
    missing_sources: paths_from_strings(missing_sources)?,
    duplicate_outputs: paths_from_strings(duplicate_outputs)?,
    task_count: task_count,
  }
}

export proc read_archive_plan_object_outputs(path_value: Path) [fs, error] -> Result[List[Path]] {
  let stored: Record = json.read(path_value)?
  let format = if stored.has("format") { stored.get("format")? } else { "" }

  if format != archive_plan_report_format() {
    return Err(ScriptError.Failed("kbuild-archive-plan-cache-stale", "archive plan cache has stale format"))
  }

  let rows: List[Record] = stored.get("tasks")?
  var outputs: List[Path] = []

  for row in rows {
    let items: List[Str] = row.get("outputs")?

    for item in items {
      if item.ends_with(".o") {
        outputs = outputs.push(path_from_string(item)?)
      }
    }
  }

  return outputs
}

pure task_has_output(task: Record, output: Path) -> Bool {
  let key = path_key(output)

  for item in task.outputs {
    if path_key(item) == key {
      return true
    }
  }

  return false
}

pure find_task_name_by_output(tasks: List[Record], output: Path) -> Result[Str] {
  for task in tasks {
    if task_has_output(task, output) {
      return task.name
    }
  }

  return Err(ScriptError.Failed("kbuild-task-output-missing", f"no archive-plan task produces ${output.display()}"))
}

proc collect_task_closure(task_deps: Map[List[Str]], target: Str, selected: Map[Bool]) [] -> Map[Bool] {
  if selected.get(target, false) {
    return selected
  }

  var next = selected.set(target, true)

  for dep in task_deps.get(target, []) {
    next = collect_task_closure(task_deps, dep, next)
  }

  return next
}

proc archive_task_deps_by_name(tasks: List[Record]) [] -> Map[List[Str]] {
  var by_name: Map[List[Str]] = {}

  for task in tasks {
    by_name[task.name] = task.deps
  }

  return by_name
}

export proc select_archive_tasks_outputs(tasks: List[Record], outputs: List[Path]) [error] -> Result[List[Record]] {
  let task_deps = archive_task_deps_by_name(tasks)
  var selected: Map[Bool] = {}

  for output in outputs {
    let target = find_task_name_by_output(tasks, output)?
    selected = collect_task_closure(task_deps, target, selected)
  }

  [task for task in tasks if selected.get(task.name, false)]
}

export proc run_archive_tasks_output(tasks: List[Record], output: Path, jobs_count: Int = 1) [fs, process, env, error] {
  make.run_tasks(select_archive_tasks_outputs(tasks, [output])?, jobs_count)?
}

export proc run_archive_tasks_outputs(
  tasks: List[Record],
  outputs: List[Path],
  jobs_count: Int = 1,
) [fs, process, env, error] {
  make.run_tasks(select_archive_tasks_outputs(tasks, outputs)?, jobs_count)?
}

export proc run_archive_plan_output(plan_path: Path, output: Path, jobs_count: Int = 1) [fs, process, env, error] {
  let tasks = read_archive_plan_tasks(plan_path)?
  run_archive_tasks_output(tasks, output, jobs_count)?
}

export proc write_plan(
  root: Path,
  config_path: Path,
  out: Path,
  srcarch: Str = "arm64",
) [fs, error] -> Result[KbuildPlan] {
  let config = load_config(config_path)?
  let plan = discover_plan(root, config, srcarch)?
  write_discovered_plan(plan, out)?
  return plan
}

pure obj_out_path(obj: Path) -> Path {
  return fp".xsh-kbuild/obj/${obj}"
}

pure composite_for(composites: List[CompositeObject], obj: Path) -> Result[CompositeObject] {
  let key = path_key(obj)

  for composite in composites {
    if path_key(composite.object) == key {
      return composite
    }
  }

  return Err(ScriptError.Failed("kbuild-not-composite", f"${key} is not a composite object"))
}

proc composite_map(composites: List[CompositeObject]) [] -> Map[CompositeObject] {
  var mapped: Map[CompositeObject] = {}

  for composite in composites {
    mapped[path_key(composite.object)] = composite
  }

  return mapped
}

proc composite_member_map(composites: List[CompositeObject]) [] -> Map[CompositeObject] {
  var mapped: Map[CompositeObject] = {}

  for composite in composites {
    for member in composite.members {
      mapped[path_key(member)] = composite
    }
  }

  return mapped
}

proc composite_for_map(composites: Map[CompositeObject], obj: Path) [error] -> Result[CompositeObject] {
  let key = path_key(obj)

  if composites.has(key) {
    return composites.get(key)?
  }

  return Err(ScriptError.Failed("kbuild-not-composite", f"${key} is not a composite object"))
}

proc source_for_object(obj: Path) [fs, error] -> Result[Path] {
  var candidates = [obj]
  let stem = obj.name.replace(".o", "")

  if stem.ends_with("_") {
    candidates = candidates.push(join_rel(object_dir(obj), f"${stem}64.o"))
  }

  if path_key(obj) == "arch/x86/kernel/head.o" {
    candidates = candidates.push(p"arch/x86/kernel/head_64.o")
  }

  for candidate in candidates {
    let c_src = candidate.with_ext("c")

    if c_src.exists()? {
      return c_src
    }

    let asm_src = candidate.with_ext("S")

    if asm_src.exists()? {
      return asm_src
    }

    let raw_asm_src = candidate.with_ext("s")

    if raw_asm_src.exists()? {
      return raw_asm_src
    }
  }

  return Err(ScriptError.Failed("kbuild-missing-source", f"missing source for ${obj.display()}"))
}

pure is_asm_source(src: Path) -> Bool {
  let name = src.display()
  return name.ends_with(".S") or name.ends_with(".s")
}

pure asm_keeps_forced_include(arg: Str) -> Bool {
  return arg in [
    "include/linux/compiler-version.h",
    "./include/linux/compiler-version.h",
    "include/linux/kconfig.h",
    "./include/linux/kconfig.h",
    "include/linux/compiler_types.h",
    "./include/linux/compiler_types.h",
    "include/generated/asm-offsets.h",
    "./include/generated/asm-offsets.h",
  ]
}

proc asm_includes(args: List[Str]) [] -> List[Str] {
  var filtered: List[Str] = []
  var skip_next = false

  for arg in args {
    if skip_next {
      if asm_keeps_forced_include(arg) {
        filtered = filtered.push("-include").push(arg)
      }

      skip_next = false
      continue
    }

    if arg == "-include" {
      skip_next = true
      continue
    }

    filtered = filtered.push(arg)
  }

  return filtered.push("-include").push("./include/generated/asm-offsets.h")
}

proc asm_cflags(_: List[Str]) [] -> List[Str] {
  return [
    "-D__KERNEL__",
    "-D__ASSEMBLY__",
    "-D__ASSEMBLER__",
    "-fno-PIE",
    "-mlittle-endian",
    "-DKASAN_SHADOW_SCALE_SHIFT=",
    "-fno-asynchronous-unwind-tables",
    "-fno-unwind-tables",
  ]
}

pure object_key_from_out(out: Path) -> Str {
  return out.display().replace(".xsh-kbuild/obj/", "").replace(".o", "")
}

pure object_base_name_from_out(out: Path) -> Str {
  return out.name.replace(".o", "").replace("-", "_")
}

pure kbuild_object_defs(out: Path) -> List[Str] {
  return kbuild_object_defs_for_module(out, out)
}

pure kbuild_object_defs_for_module(out: Path, mod_out: Path) -> List[Str] {
  let modfile = object_key_from_out(mod_out)
  let basename = object_base_name_from_out(out)
  let modname = object_base_name_from_out(mod_out)
  let identifier = modname.replace("-", "_")

  let base = [
    f"-DKBUILD_MODFILE=\"${modfile}\"",
    f"-DKBUILD_BASENAME=\"${basename}\"",
    f"-DKBUILD_MODNAME=\"${modname}\"",
    f"-D__KBUILD_MODNAME=${identifier}",
  ]

  if modfile.starts_with("drivers/acpi/acpica/") {
    return base.extend(["-D_LINUX", "-DBUILDING_ACPICA"])
  }

  if modfile.starts_with("drivers/gpu/drm/i915/") {
    return base.push("-DI915")
  }

  if modfile.starts_with("arch/arm64/kvm/hyp/nvhe/") or modfile.ends_with(".nvhe") {
    return base.extend(["-D__KVM_NVHE_HYPERVISOR__", "-D__DISABLE_EXPORTS", "-D__DISABLE_TRACE_MMIO__"])
  }

  if modfile.starts_with("arch/arm64/kvm/hyp/") {
    return base.push("-D__KVM_VHE_HYPERVISOR__")
  }

  return base
}

pure is_pi_output(out: Path) -> Bool {
  return "/arch/arm64/kernel/pi/" in out.display()
}

pure is_x86_startup_pi_base_output(out: Path) -> Bool {
  return "/arch/x86/boot/startup/" in out.display()
}

proc pi_compile_cflags(args: List[Str], out: Path) [] -> List[Str] {
  if is_x86_startup_pi_base_output(out) {
    var out_args = [arg for arg in args if arg != "-O2" and arg != "-fno-PIE" and arg != "-mcmodel=kernel"]

    return out_args.extend(
      [
        "-D__DISABLE_EXPORTS",
        "-mcmodel=small",
        "-fPIC",
        "-Os",
        "-DDISABLE_BRANCH_PROFILING",
        "-fno-stack-protector",
        "-D__NO_FORTIFY",
        "-fno-jump-tables",
      ],
    )
  }

  if ! is_pi_output(out) {
    return args
  }

  var out_args = [arg for arg in args if arg != "-fno-function-sections" and arg != "-fno-data-sections"]

  out_args = out_args.extend(
    [
      "-fpie",
      "-Os",
      "-DDISABLE_BRANCH_PROFILING",
      "-mbranch-protection=none",
      "-D__DISABLE_EXPORTS",
      "-ffreestanding",
      "-D__NO_FORTIFY",
      "-fno-asynchronous-unwind-tables",
      "-fno-unwind-tables",
      "-fno-addrsig",
    ],
  )

  if out.name == "map_range.o" {
    out_args = out_args.push("-mstrict-align")
  }

  return out_args
}

proc object_compile_cflags(args: List[Str], out: Path) [] -> List[Str] {
  if ! out.display().ends_with("/crypto/jitterentropy.o") {
    return args
  }

  var out_args = args
  return out_args.push("-O0")
}

proc pi_compile_includes(args: List[Str], out: Path) [] -> List[Str] {
  if is_x86_startup_pi_base_output(out) {
    var out_args = args
    out_args = out_args.push("-include")
    return out_args.push("include/linux/hidden.h")
  }

  if ! is_pi_output(out) {
    return args
  }

  var out_args = args
  out_args = out_args.push("-I./scripts/dtc/libfdt")
  out_args = out_args.push("-include")
  return out_args.push("include/linux/hidden.h")
}

proc trace_compile_includes(args: List[Str], src: Path) [] -> List[Str] {
  var out_args = args
  return out_args.push(f"-I./${src.parent}")
}

proc arch_local_compile_includes(args: List[Str], src: Path, triple: Str) [] -> List[Str] {
  let dir = path_key(src.parent)
  var out_args = args

  if triple == "x86_64-linux-gnu" {
    out_args = out_args.push("-I./arch/x86/include/asm/trace")
  }

  if dir.starts_with("arch/x86/kvm/") or dir == "arch/x86/kvm" or dir == "virt/kvm" {
    out_args = out_args.push("-I./arch/x86/kvm")
  }

  if triple == "aarch64-linux-gnu" and (dir.starts_with("arch/arm64/kvm/hyp/") or dir == "arch/arm64/kvm/hyp" or dir == "arch/arm64/kvm") {
    out_args = out_args.push("-I./arch/arm64/kvm/hyp/include")
    out_args = out_args.push("-I./arch/arm64/kvm")
  }

  if dir.starts_with("drivers/gpu/drm/i915/") {
    out_args = out_args.push("-I./drivers/gpu/drm/i915")
    out_args = out_args.push("-I./drivers/gpu/drm/i915/display")
    out_args = out_args.push("-I./drivers/gpu/drm/i915/gem")
    out_args = out_args.push("-I./drivers/gpu/drm/i915/gt")
  }

  if dir == "drivers/media/dvb-frontends" {
    out_args = out_args.push("-I./drivers/media/tuners")
    out_args = out_args.push("-I./drivers/media/usb/dvb-usb-v2")
  }

  if dir == "drivers/media/tuners" {
    out_args = out_args.push("-I./drivers/media/dvb-frontends")
  }

  if dir == "drivers/media/v4l2-core" {
    out_args = out_args.push("-I./drivers/media/dvb-frontends")
    out_args = out_args.push("-I./drivers/media/tuners")
  }

  if dir == "drivers/media/spi" {
    out_args = out_args.push("-I./drivers/media/dvb-frontends/cxd2880")
  }

  if dir != "lib/crypto" and dir != "lib/crc" {
    return out_args
  }

  let local_arch = if triple == "x86_64-linux-gnu" { "x86" } else { "arm64" }
  return out_args.push(f"-I./${dir}/${local_arch}")
}

proc libfdt_compile_includes(args: List[Str], out: Path) [] -> List[Str] {
  let key = object_key_from_out(out)

  if key == "lib/fdt" or key == "lib/fdt_addresses" or key == "lib/fdt_empty_tree" or key == "lib/fdt_ro" or key == "lib/fdt_rw" or key == "lib/fdt_strerror" or key == "lib/fdt_sw" or key == "lib/fdt_wip" {
    var out_args = args
    return out_args.push("-I./scripts/dtc/libfdt")
  }

  return args
}

proc version_compile_includes(args: List[Str], out: Path) [] -> List[Str] {
  if object_key_from_out(out) == "init/version" or path_key(out) == "init/version-timestamp.o" {
    var out_args = args
    out_args = out_args.push("-include")
    return out_args.push("init/utsversion-tmp.h")
  }

  return args
}

export proc compile_kbuild_task(
  cc: Path,
  triple: Str,
  cflags: List[Str],
  defs: List[Str],
  includes: List[Str],
  src: Path,
  out: Path,
  deps: List[Str] = [],
) [] -> make.MakeTask {
  return compile_kbuild_task_for_module(cc, triple, cflags, defs, includes, src, out, out, deps)
}

proc compile_kbuild_task_for_module(
  cc: Path,
  triple: Str,
  cflags: List[Str],
  defs: List[Str],
  includes: List[Str],
  src: Path,
  out: Path,
  mod_out: Path,
  deps: List[Str] = [],
) [] -> make.MakeTask {
  let compile_cflags = object_compile_cflags(pi_compile_cflags(cflags, out), out)

  let object_includes = arch_local_compile_includes(
    trace_compile_includes(
      version_compile_includes(libfdt_compile_includes(pi_compile_includes(includes, out), out), out),
      src,
    ),
    src,
    triple,
  )

  let task_cflags = if is_asm_source(src) { asm_cflags(compile_cflags) } else { compile_cflags }
  let task_defs = defs.extend(kbuild_object_defs_for_module(out, mod_out))
  let task_includes = if is_asm_source(src) { asm_includes(object_includes) } else { object_includes }
  return make.compile_c_task(cc, triple, task_cflags, task_defs, task_includes, src, out, deps)
}

proc relocatable_object_task(cc: Path, inputs: List[Path], out: Path, deps: List[Str] = []) [env] -> make.MakeTask {
  let _ = cc
  let tool_path = host_build_path()
  var argv = ["ld.lld", "-r", "-o", out.display()]
  argv = argv.extend(path_strings(inputs))

  return {
    name: out.display(),
    outputs: [
      out,
    ],
    inputs: inputs,
    deps: deps,
    argv: argv,
    cwd: p".",
    env: {
      PATH: tool_path,
    },
    depfile: p"",
    stamp: fp"${out}.cmd",
  }
}

proc pi_objcopy_task(cc: Path, input: Path, out: Path, deps: List[Str] = []) [env] -> make.MakeTask {
  let _ = cc
  let tool_path = host_build_path()
  var argv = ["llvm-objcopy", "--prefix-symbols=__pi_", "--remove-section=.note.gnu.property"]

  if out.name.starts_with("lib-") {
    argv = argv.push("--prefix-alloc-sections=.init")
  }

  argv = argv.extend([input.display(), out.display()])

  return {
    name: out.display(),
    outputs: [
      out,
    ],
    inputs: [
      input,
    ],
    deps: deps,
    argv: argv,
    cwd: p".",
    env: {
      PATH: tool_path,
    },
    depfile: p"",
    stamp: fp"${out}.cmd",
  }
}

pure pi_relacheck_path() -> Path {
  return p".xsh-kbuild/host/arch/arm64/kernel/pi/relacheck"
}

proc host_build_cc() [env] -> Path {
  let root = env.get("XSH_PM_BUILD_ROOT") ?? ""

  if root != "" {
    return fp"${root}/usr/bin/cc"
  }

  return p"cc"
}

proc host_build_path() [env] -> Str {
  let root = env.get("XSH_PM_BUILD_ROOT") ?? ""
  let current = env.get("PATH") ?? ""

  if root != "" {
    return f"${root}/usr/lib/llvm-toolchain/bin:${root}/usr/bin:${current}"
  }

  return current
}

proc host_build_ld_library_path() [env] -> Str {
  let root = env.get("XSH_PM_BUILD_ROOT") ?? ""
  let current = env.get("LD_LIBRARY_PATH") ?? ""

  if root == "" {
    return current
  }

  if current == "" {
    return f"${root}/usr/lib:${root}/usr/lib/llvm22/lib"
  }

  return f"${root}/usr/lib:${root}/usr/lib/llvm22/lib:${current}"
}

proc pi_relacheck_build_task(cc: Path) [env] -> make.MakeTask {
  let _ = cc
  let host_cc = host_build_cc()
  let host_path = host_build_path()
  let host_ld_library_path = host_build_ld_library_path()
  let src = p"arch/arm64/kernel/pi/relacheck.c"
  let out = pi_relacheck_path()

  return {
    name: out.display(),
    outputs: [
      out,
    ],
    inputs: [
      src,
    ],
    deps: [],
    argv: [
      host_cc.display(),
      "-Wall",
      "-Wmissing-prototypes",
      "-Wstrict-prototypes",
      "-O2",
      "-fomit-frame-pointer",
      "-std=gnu11",
      "-I",
      "./scripts/include",
      "-o",
      out.display(),
      src.display(),
    ],
    cwd: p".",
    env: {
      TMPDIR: out.parent.display(),
      PATH: host_path,
      LD_LIBRARY_PATH: host_ld_library_path,
      XSH_MAKE_NATIVE_CROSS: "0",
    },
    depfile: p"",
    stamp: fp"${out}.cmd",
  }
}

proc pi_relacheck_task(relacheck: Path, input: Path, original: Path, deps: List[Str]) [] -> make.MakeTask {
  let stamp = fp"${input}.relacheck.cmd"

  return {
    name: f"${input.display()}:relacheck",
    outputs: [
      stamp,
    ],
    inputs: [
      relacheck,
      input,
      original,
    ],
    deps: deps,
    argv: [
      relacheck.display(),
      input.display(),
      original.display(),
    ],
    cwd: p".",
    env: {},
    depfile: p"",
    stamp: stamp,
  }
}

export proc generate_empty_root_dtb_asm(root: Path) [fs, error] {
  write_text_if_changed(
    fp"${root}/drivers/of/empty_root.dtb.S",
    """#include <asm-generic/vmlinux.lds.h>
.section .rodata,"a"
.balign STRUCT_ALIGNMENT
.global __dtb_empty_root_begin
__dtb_empty_root_begin:
.byte 0xd0,0x0d,0xfe,0xed,0x00,0x00,0x00,0x83,0x00,0x00,0x00,0x38
.byte 0x00,0x00,0x00,0x68,0x00,0x00,0x00,0x28,0x00,0x00,0x00,0x11
.byte 0x00,0x00,0x00,0x10,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x1b
.byte 0x00,0x00,0x00,0x30,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00
.byte 0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x01
.byte 0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x03,0x00,0x00,0x00,0x04
.byte 0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x02,0x00,0x00,0x00,0x03
.byte 0x00,0x00,0x00,0x04,0x00,0x00,0x00,0x0f,0x00,0x00,0x00,0x02
.byte 0x00,0x00,0x00,0x02,0x00,0x00,0x00,0x09,0x23,0x61,0x64,0x64
.byte 0x72,0x65,0x73,0x73,0x2d,0x63,0x65,0x6c,0x6c,0x73,0x00,0x23
.byte 0x73,0x69,0x7a,0x65,0x2d,0x63,0x65,0x6c,0x6c,0x73,0x00
.global __dtb_empty_root_end
__dtb_empty_root_end:
.balign STRUCT_ALIGNMENT
""",
  )?
}

export proc generate_crc32table_header(root: Path, cc: Path) [fs, process, env, error] {
  let gen = fp"${root}/lib/crc/gen_crc32table"
  let source = fp"${root}/lib/crc/gen_crc32table.c"
  let argv = [cc.display(), "-Iinclude", "-Iinclude/generated", "-o", gen.display(), source.display()]
  let build_root = env.get("XSH_PM_BUILD_ROOT") ?? ""
  let build_env = {PATH: f"${build_root}/usr/bin:${env.get("PATH") ?? ""}"}

  let compile_command = if build_root != "" {
    process.command_argv(argv[0], argv, env: build_env)
  } else {
    process.command_argv(argv[0], argv)
  }

  let compile_status = process.run(compile_command)?

  if ! compile_status.ok {
    return Err(ScriptError.Failed("linux-crc32table-compile", f"command failed: ${argv.join(" ")}"))
  }

  let output = run.text $gen ?
  write_text_if_changed(fp"${root}/lib/crc/crc32table.h", output)?
}

export proc generate_raid6_sources(root: Path, cc: Path) [fs, process, env, error] {
  let int_uc = fp"${root}/lib/raid6/int.uc".read_text()?

  for n in [1, 2, 4, 8] {
    var lines: List[Str] = []

    for line in int_uc.split("\n") {
      let reps = if "$$" in line { n } else { 1 }
      var i = 0

      while i < reps {
        lines = lines.push(line.replace("$$", f"${i}").replace("$#", f"${n}").replace("$*", "$"))
        i += 1
      }
    }

    write_text_if_changed(
      fp"${root}/lib/raid6/int${n}.c",
      f"""${lines.join("\n")}
""",
    )?
  }

  let gen = fp"${root}/lib/raid6/mktables"
  let source = fp"${root}/lib/raid6/mktables.c"

  let argv = [
    cc.display(),
    "-O2",
    "-std=gnu11",
    "-Wall",
    "-I./tools/include",
    "-o",
    gen.display(),
    source.display(),
  ]

  let build_root = env.get("XSH_PM_BUILD_ROOT") ?? ""
  let build_env = {PATH: f"${build_root}/usr/bin:${env.get("PATH") ?? ""}"}

  let compile_command = if build_root != "" {
    process.command_argv(argv[0], argv, env: build_env)
  } else {
    process.command_argv(argv[0], argv)
  }

  let compile_status = process.run(compile_command)?

  if ! compile_status.ok {
    return Err(ScriptError.Failed("linux-raid6-mktables-compile", f"command failed: ${argv.join(" ")}"))
  }

  let tables = run.text $gen ?
  write_text_if_changed(fp"${root}/lib/raid6/tables.c", tables)?
}

pure dir_archive(dir: Path) -> Path {
  if path_key(dir) == "." {
    return p".xsh-kbuild/built-in.a"
  }

  return fp".xsh-kbuild/${dir}/built-in.a"
}

pure dir_lib_archive(dir: Path) -> Path {
  if path_key(dir) == "." {
    return p".xsh-kbuild/lib.a"
  }

  return fp".xsh-kbuild/${dir}/lib.a"
}

proc insert_archive_before(
  objs: List[Path],
  deps: List[Str],
  archive_path: Path,
  dep: Str,
  marker: Path,
) [] -> ArchiveInputs {
  var out_objs: List[Path] = []
  var out_deps: List[Str] = []
  var inserted = false
  var index = 0
  let marker_key = path_key(marker)

  for obj in objs {
    if ! inserted and path_key(obj) == marker_key {
      out_objs = out_objs.push(archive_path)
      out_deps = out_deps.push(dep)
      inserted = true
    }

    out_objs = out_objs.push(obj)
    out_deps = out_deps.push(deps[index])
    index += 1
  }

  if ! inserted {
    out_objs = out_objs.push(archive_path)
    out_deps = out_deps.push(dep)
  }

  return {objs: out_objs, deps: out_deps}
}

pure object_dir(obj: Path) -> Path {
  if ! ("/" in obj.display()) {
    return p"."
  }

  return obj.parent
}

pure parent_dir(dir: Path) -> Path {
  if path_key(dir) == "." or ! ("/" in dir.display()) {
    return p"."
  }

  return dir.parent
}

pure archive_parent_dir(dir: Path) -> Path {
  let key = path_key(dir)

  if regex_matches(key, "^arch/[^/]+$") ?? false {
    return p"."
  }

  return parent_dir(dir)
}

pure is_known_generated_object(obj: Path) -> Bool {
  let key = path_key(obj)
  return key.ends_with(".pi.o") or key.ends_with(".dtb.o") or key == "lib/crypto/powerpc/aesp8-ppc.o" or key == "lib/crypto/arm/sha256-core.o" or key == "lib/crypto/arm64/sha256-core.o" or key == "lib/crypto/arm/sha512-core.o" or key == "lib/crypto/arm64/sha512-core.o"
}

pure is_pi_object(obj: Path) -> Bool {
  return path_key(obj).ends_with(".pi.o")
}

pure pi_base_name(obj: Path) -> Str {
  return obj.name.replace(".pi.o", "")
}

pure pi_base_object(obj: Path) -> Path {
  return join_rel(object_dir(obj), f"${pi_base_name(obj)}.o")
}

pure pi_source(obj: Path) -> Path {
  let base = pi_base_name(obj)

  if base.starts_with("lib-") {
    return fp"lib/${base.replace("lib-", "")}.c"
  }

  return join_rel(object_dir(obj), f"${base}.c")
}

pure abi_enabled(abi: Str, abis: List[Str]) -> Bool {
  if abis.len() == 0 {
    return true
  }

  return abi in abis
}

pure syscall_line(nr: Int, native: Str, compat: Str, noreturn: Str) -> Result[Str] {
  if compat != "" and noreturn == "noreturn" {
    return f"__SYSCALL_COMPAT_NORETURN(${nr}, ${native}, ${compat})"
  }

  if noreturn == "noreturn" {
    return f"__SYSCALL_NORETURN(${nr}, ${native})"
  }

  if compat != "" {
    return f"__SYSCALL_WITH_COMPAT(${nr}, ${native}, ${compat})"
  }

  if native != "" {
    return f"__SYSCALL(${nr}, ${native})"
  }

  return f"__SYSCALL(${nr}, sys_ni_syscall)"
}

export proc generate_syscall_table(table: Path, out: Path, abis: List[Str] = []) [fs, error] {
  var lines: List[Str] = []
  var next_nr = 0

  for raw in table.read_text()?.split("\n") {
    let line = raw.split("#")[0].trim()

    if line != "" {
      let fields = line.fields()
      let nr = fields[0].parse_int()?
      let abi = fields[1]

      if abi_enabled(abi, abis) {
        if next_nr > nr {
          return Err(ScriptError.Failed("kbuild-syscall-order", f"${table.display()} is not sorted at syscall ${nr}"))
        }

        while next_nr < nr {
          lines = lines.push(f"__SYSCALL(${next_nr}, sys_ni_syscall)")
          next_nr += 1
        }

        let native = fields.get(3, "")
        let compat = if fields.get(4, "") == "-" { "" } else { fields.get(4, "") }
        let noreturn = fields.get(5, "")

        if noreturn != "" and noreturn != "noreturn" {
          return Err(ScriptError.Failed("kbuild-syscall-noreturn", f"invalid noreturn marker '${noreturn}'"))
        }

        lines = lines.push(syscall_line(nr, native, compat, noreturn)?)
        next_nr = nr + 1
      }
    }
  }

  write_text_if_changed(
    out,
    f"""${lines.join("\n")}
""",
  )?
}

export proc generate_syscall_numbers(
  table: Path,
  out: Path,
  header_guard: Str,
  syscall_count_name: Str,
  prefix: Str = "",
  abis: List[Str] = [],
) [fs, error] {
  var lines = [f"#ifndef ${header_guard}", f"#define ${header_guard}", ""]
  var max_nr = -1

  for raw in table.read_text()?.split("\n") {
    let line = raw.split("#")[0].trim()

    if line != "" {
      let fields = line.fields()
      let nr = fields[0].parse_int()?
      let abi = fields[1]

      if abi_enabled(abi, abis) {
        lines = lines.push(f"#define __NR_${prefix}${fields[2]} ${nr}")

        if nr > max_nr {
          max_nr = nr
        }
      }
    }
  }

  lines = lines.extend(
    [
      "",
      "#ifdef __KERNEL__",
      f"#define ${syscall_count_name} ${max_nr + 1}",
      "#endif",
      "",
      f"#endif /* ${header_guard} */",
    ],
  )

  write_text_if_changed(
    out,
    f"""${lines.join("\n")}
""",
  )?
}

export proc generate_arm64_syscall_tables(root: Path) [fs, error] {
  generate_syscall_table(
    fp"${root}/arch/arm64/tools/syscall_64.tbl",
    fp"${root}/arch/arm64/include/generated/asm/syscall_table_64.h",
    ["common", "64", "renameat", "rlimit", "memfd_secret"],
  )?

  generate_syscall_table(
    fp"${root}/arch/arm64/tools/syscall_32.tbl",
    fp"${root}/arch/arm64/include/generated/asm/syscall_table_32.h",
    ["common", "32", "renameat", "rlimit", "memfd_secret"],
  )?

  generate_syscall_numbers(
    fp"${root}/arch/arm64/tools/syscall_64.tbl",
    fp"${root}/arch/arm64/include/generated/uapi/asm/unistd_64.h",
    "_UAPI_ASM_UNISTD_64_H",
    "__NR_syscalls",
    "",
    ["common", "64", "renameat", "rlimit", "memfd_secret"],
  )?

  generate_syscall_numbers(
    fp"${root}/arch/arm64/tools/syscall_32.tbl",
    fp"${root}/arch/arm64/include/generated/asm/unistd_32.h",
    "_UAPI_ASM_UNISTD_32_H",
    "__NR_syscalls",
    "",
    ["common", "32", "renameat", "rlimit", "memfd_secret"],
  )?

  generate_syscall_numbers(
    fp"${root}/arch/arm64/tools/syscall_32.tbl",
    fp"${root}/arch/arm64/include/generated/asm/unistd_compat_32.h",
    "_UAPI_ASM_UNISTD_COMPAT_32_H",
    "__NR_compat32_syscalls",
    "compat32_",
    ["common", "32", "renameat", "rlimit", "memfd_secret"],
  )?
}

export proc generate_x86_syscall_tables(root: Path) [fs, error] {
  generate_syscall_table(
    fp"${root}/arch/x86/entry/syscalls/syscall_64.tbl",
    fp"${root}/arch/x86/include/generated/asm/syscalls_64.h",
    ["common", "64", "renameat", "rlimit", "memfd_secret"],
  )?

  generate_syscall_numbers(
    fp"${root}/arch/x86/entry/syscalls/syscall_64.tbl",
    fp"${root}/arch/x86/include/generated/uapi/asm/unistd_64.h",
    "_UAPI_ASM_UNISTD_64_H",
    "__NR_syscalls",
    "",
    ["common", "64", "renameat", "rlimit", "memfd_secret"],
  )?

  generate_syscall_numbers(
    fp"${root}/arch/x86/entry/syscalls/syscall_64.tbl",
    fp"${root}/arch/x86/include/generated/asm/unistd_64_x32.h",
    "_ASM_X86_UNISTD_64_X32_H",
    "__NR_x32_syscalls",
    "x32_",
    ["common", "x32", "renameat", "rlimit", "memfd_secret"],
  )?

  generate_syscall_numbers(
    fp"${root}/arch/x86/entry/syscalls/syscall_32.tbl",
    fp"${root}/arch/x86/include/generated/asm/unistd_32_ia32.h",
    "_ASM_X86_UNISTD_32_IA32_H",
    "__NR_ia32_syscalls",
    "ia32_",
    ["i386"],
  )?
}

export proc generate_offsets_header(asm_path: Path, out: Path, header_guard: Str) [fs, error] {
  var lines = [
    f"#ifndef ${header_guard}",
    f"#define ${header_guard}",
    "/*",
    " * DO NOT MODIFY.",
    " *",
    " * This file was generated by Kbuild",
    " */",
    "",
  ]

  for raw in asm_path.read_text()?.split("\n") {
    let line = raw.trim()

    match regex_captures(line, "\\.ascii\\s+\"->([^\"]*)\"") {
      Ok(caps) => {
        if caps.len() >= 2 {
          let body = caps[1].trim()

          if body == "" {
            lines = lines.push("")
          } else {
            let parts = body.fields()
            let name = parts.get(0, "")
            let value = parts.get(1, "").replace("$", "")
            let comment = parts |> drop(2)

            if name != "" and value != "" {
              lines = lines.push(f"#define ${name} ${value} /* ${comment.join(" ")} */")
            }
          }
        }
      }
      Err(_) => {}
    }
  }

  lines = lines.push("")
  lines = lines.push("#endif")

  write_text_if_changed(
    out,
    f"""${lines.join("\n")}
""",
  )?
}

export proc image_argv_task(
  objcopy_argv: List[Str],
  vmlinux: Path,
  image: Path,
  deps: List[Str] = [],
) [env] -> make.MakeTask {
  let tool_path = host_build_path()

  return {
    name: image.display(),
    outputs: [
      image,
    ],
    inputs: [
      vmlinux,
    ],
    deps: deps,
    argv: objcopy_argv.extend(
      [
        "-O",
        "binary",
        "-R",
        ".note",
        "-R",
        ".note.gnu.build-id",
        "-R",
        ".comment",
        "-S",
        vmlinux.display(),
        image.display(),
      ],
    ),
    cwd: p".",
    env: {
      PATH: tool_path,
    },
    depfile: p"",
    stamp: fp"${image}.cmd",
  }
}

export proc image_task(objcopy: Path, vmlinux: Path, image: Path, deps: List[Str] = []) [env] -> make.MakeTask {
  return image_argv_task([objcopy.display()], vmlinux, image, deps)
}

proc x86_compressed_vmlinux_bin_task(
  objcopy: Path,
  vmlinux: Path,
  out: Path,
  deps: List[Str] = [],
) [] -> make.MakeTask {
  return {
    name: out.display(),
    outputs: [
      out,
    ],
    inputs: [
      vmlinux,
    ],
    deps: deps,
    argv: [
      objcopy.display(),
      "-R",
      ".comment",
      "-S",
      vmlinux.display(),
      out.display(),
    ],
    cwd: p".",
    env: {},
    depfile: p"",
    stamp: fp"${out}.cmd",
  }
}

export proc vmlinux_archive_argv_task(
  ar_argv: List[Str],
  inputs: List[Path],
  out: Path,
  deps: List[Str] = [],
) [env] -> make.MakeTask {
  var argv = ar_argv.extend(["cDPrST", out.display()])
  let tool_path = host_build_path()

  for input in inputs {
    argv = argv.push(input.display())
  }

  return {
    name: out.display(),
    outputs: [
      out,
    ],
    inputs: inputs,
    deps: deps,
    argv: argv,
    cwd: p".",
    env: {
      PATH: tool_path,
    },
    depfile: p"",
    stamp: fp"${out}.cmd",
  }
}

export proc vmlinux_archive_task(ar: Path, inputs: List[Path], out: Path, deps: List[Str] = []) [env] -> make.MakeTask {
  return vmlinux_archive_argv_task([ar.display()], inputs, out, deps)
}

export proc vmlinux_o_task(
  ld: Path,
  kbuild_ldflags: List[Str],
  kernel_archive: Path,
  libs: List[Path],
  out: Path,
  deps: List[Str] = [],
) [env] -> make.MakeTask {
  return vmlinux_o_argv_task([ld.display()], kbuild_ldflags, kernel_archive, libs, out, deps)
}

export proc vmlinux_o_argv_task(
  ld_argv: List[Str],
  kbuild_ldflags: List[Str],
  kernel_archive: Path,
  libs: List[Path],
  out: Path,
  deps: List[Str] = [],
) [env] -> make.MakeTask {
  let tool_path = host_build_path()
  var argv = ld_argv
  argv = argv.extend(kbuild_ldflags)

  argv = argv.extend(
    ["-r", "-o", out.display(), "--whole-archive", kernel_archive.display(), "--no-whole-archive", "--start-group"],
  )

  for lib in libs {
    argv = argv.push(lib.display())
  }

  argv = argv.push("--end-group")

  return {
    name: out.display(),
    outputs: [
      out,
    ],
    inputs: [
      kernel_archive,
    ].extend(libs),
    deps: deps,
    argv: argv,
    cwd: p".",
    env: {
      PATH: tool_path,
    },
    depfile: p"",
    stamp: fp"${out}.cmd",
  }
}

export proc vmlinux_unstripped_task(
  ld: Path,
  kbuild_ldflags: List[Str],
  ldflags_vmlinux: List[Str],
  linker_script: Path,
  kernel_archive: Path,
  libs: List[Path],
  export_obj: Path,
  version_obj: Path,
  out: Path,
  deps: List[Str] = [],
) [env] -> make.MakeTask {
  return vmlinux_unstripped_argv_task(
    [ld.display()],
    kbuild_ldflags,
    ldflags_vmlinux,
    linker_script,
    kernel_archive,
    libs,
    export_obj,
    version_obj,
    out,
    deps,
  )
}

export proc vmlinux_unstripped_argv_task(
  ld_argv: List[Str],
  kbuild_ldflags: List[Str],
  ldflags_vmlinux: List[Str],
  linker_script: Path,
  kernel_archive: Path,
  libs: List[Path],
  export_obj: Path,
  version_obj: Path,
  out: Path,
  deps: List[Str] = [],
) [env] -> make.MakeTask {
  let tool_path = host_build_path()
  var argv = ld_argv
  argv = argv.extend(kbuild_ldflags).extend(ldflags_vmlinux)
  argv = argv.extend(["--script", linker_script.display(), "-o", out.display()])

  argv = argv.extend(
    [
      "--whole-archive",
      kernel_archive.display(),
      export_obj.display(),
      version_obj.display(),
      "--no-whole-archive",
      "--start-group",
    ],
  )

  for lib in libs {
    argv = argv.push(lib.display())
  }

  argv = argv.push("--end-group")

  return {
    name: out.display(),
    outputs: [
      out,
    ],
    inputs: [
      kernel_archive,
      linker_script,
      export_obj,
      version_obj,
    ].extend(libs),
    deps: deps,
    argv: argv,
    cwd: p".",
    env: {
      PATH: tool_path,
    },
    depfile: p"",
    stamp: fp"${out}.cmd",
  }
}

export pure arm64_vmlinux_ldflags(config: Kconfig) -> List[Str] {
  let base = ["--no-undefined", "-X", "--pic-veneer"]

  let relocatable = if config_value(config, "RELOCATABLE") == "y" {
    base.extend(["-shared", "-Bsymbolic", "-z", "notext", "--no-apply-dynamic-relocs"])
  } else {
    base
  }

  let with_build_id = relocatable.push("--build-id=sha1")

  let with_relr = if config_value(config, "RELR") == "y" {
    with_build_id.push("--pack-dyn-relocs=relr")
  } else {
    with_build_id
  }

  return with_relr.push("--orphan-handling=warn")
}

export proc vmlinux_strip_argv_task(
  objcopy_argv: List[Str],
  unstripped: Path,
  out: Path,
  deps: List[Str] = [],
) [env] -> make.MakeTask {
  let tool_path = host_build_path()

  return {
    name: out.display(),
    outputs: [
      out,
    ],
    inputs: [
      unstripped,
    ],
    deps: deps,
    argv: objcopy_argv.extend(
      [
        "--remove-section=.modinfo",
        "-w",
        "--strip-unneeded-symbol=__mod_device_table__*",
        unstripped.display(),
        out.display(),
      ],
    ),
    cwd: p".",
    env: {
      PATH: tool_path,
    },
    depfile: p"",
    stamp: fp"${out}.cmd",
  }
}

export proc vmlinux_strip_task(
  objcopy: Path,
  unstripped: Path,
  out: Path,
  deps: List[Str] = [],
) [env] -> make.MakeTask {
  return vmlinux_strip_argv_task([objcopy.display()], unstripped, out, deps)
}

proc x86_vmlinux_strip_argv_task(
  objcopy_argv: List[Str],
  unstripped: Path,
  out: Path,
  deps: List[Str] = [],
) [] -> make.MakeTask {
  return {
    name: out.display(),
    outputs: [
      out,
    ],
    inputs: [
      unstripped,
    ],
    deps: deps,
    argv: objcopy_argv.extend(
      [
        "--remove-section=.modinfo",
        "--remove-section=.rel*",
        "--remove-section=!.rel*.dyn",
        "--remove-section=.rel.*",
        "-w",
        "--strip-unneeded-symbol=__mod_device_table__*",
        unstripped.display(),
        out.display(),
      ],
    ),
    cwd: p".",
    env: {},
    depfile: p"",
    stamp: fp"${out}.cmd",
  }
}

export proc write_image(objcopy: Path, vmlinux: Path, image: Path) [fs, process, env, error] {
  make.run_tasks([image_task(objcopy, vmlinux, image)], 1)?
}

proc vmlinux_lds_task(cc: Path, out: Path) [] -> make.MakeTask {
  let depfile = fp"${out}.d"
  let src = p"arch/arm64/kernel/vmlinux.lds.S"

  let argv = [
    cc.display(),
    "-target",
    "aarch64-linux-gnu",
    "-E",
    "-MMD",
    "-MP",
    "-MF",
    depfile.display(),
    "-nostdinc",
    "-I./arch/arm64/include",
    "-I./arch/arm64/include/generated",
    "-I./include",
    "-I./include/generated",
    "-I./arch/arm64/include/uapi",
    "-I./arch/arm64/include/generated/uapi",
    "-I./include/uapi",
    "-I./include/generated/uapi",
    "-include",
    "./include/linux/compiler-version.h",
    "-include",
    "./include/linux/kconfig.h",
    "-D__KERNEL__",
    "-mlittle-endian",
    "-DKASAN_SHADOW_SCALE_SHIFT=",
    "-P",
    "-Uarm64",
    "-D__ASSEMBLY__",
    "-DLINKER_SCRIPT",
    "-o",
    out.display(),
    src.display(),
  ]

  return {
    name: out.display(),
    outputs: [
      out,
    ],
    inputs: [
      src,
    ],
    deps: [],
    argv: argv,
    cwd: p".",
    env: {},
    depfile: depfile,
    stamp: fp"${out}.cmd",
  }
}

proc generate_vmlinux_lds(cc: Path, out: Path) [fs, process, error] {
  let depfile = fp"${out}.d"
  let src = p"arch/arm64/kernel/vmlinux.lds.S"

  run (
    $cc
    "-target"
    "aarch64-linux-gnu"
    "-E"
    "-MMD"
    "-MP"
    "-MF"
    $depfile
    "-nostdinc"
    "-I./arch/arm64/include"
    "-I./arch/arm64/include/generated"
    "-I./include"
    "-I./include/generated"
    "-I./arch/arm64/include/uapi"
    "-I./arch/arm64/include/generated/uapi"
    "-I./include/uapi"
    "-I./include/generated/uapi"
    "-include"
    "./include/linux/compiler-version.h"
    "-include"
    "./include/linux/kconfig.h"
    "-D__KERNEL__"
    "-mlittle-endian"
    "-DKASAN_SHADOW_SCALE_SHIFT="
    "-P"
    "-Uarm64"
    "-D__ASSEMBLY__"
    "-DLINKER_SCRIPT"
    "-o"
    $out
    $src
  ) ?
}

proc generate_vmlinux_lds_x86(cc: Path, out: Path) [fs, process, error] {
  let depfile = fp"${out}.d"
  let src = p"arch/x86/kernel/vmlinux.lds.S"

  run (
    $cc
    "-target"
    "x86_64-linux-gnu"
    "-E"
    "-MMD"
    "-MP"
    "-MF"
    $depfile
    "-nostdinc"
    "-I./arch/x86/include"
    "-I./arch/x86/include/generated"
    "-I./include"
    "-I./include/generated"
    "-I./arch/x86/include/uapi"
    "-I./arch/x86/include/generated/uapi"
    "-I./include/uapi"
    "-I./include/generated/uapi"
    "-include"
    "./include/linux/compiler-version.h"
    "-include"
    "./include/linux/kconfig.h"
    "-D__KERNEL__"
    "-DKASAN_SHADOW_SCALE_SHIFT="
    "-P"
    "-D__ASSEMBLY__"
    "-DLINKER_SCRIPT"
    "-o"
    $out
    $src
  ) ?
}

export pure x86_vmlinux_ldflags(config: Kconfig) -> List[Str] {
  let base = ["--no-undefined", "-X", "-z", "max-page-size=0x200000"]
  let with_relr = if config_value(config, "RELR") == "y" { base.push("--pack-dyn-relocs=relr") } else { base }
  let with_build_id = with_relr.push("--build-id=sha1")

  let with_relocs = if config_value(config, "ARCH_VMLINUX_NEEDS_RELOCS") == "y" {
    with_build_id.extend(["--emit-relocs", "--discard-none"])
  } else {
    with_build_id
  }

  return with_relocs.push("--orphan-handling=warn")
}

proc vmlinux_x86_lds_task(cc: Path, out: Path) [] -> make.MakeTask {
  let depfile = fp"${out}.d"
  let src = p"arch/x86/kernel/vmlinux.lds.S"

  let argv = [
    cc.display(),
    "-target",
    "x86_64-linux-gnu",
    "-E",
    "-MMD",
    "-MP",
    "-MF",
    depfile.display(),
    "-nostdinc",
    "-I./arch/x86/include",
    "-I./arch/x86/include/generated",
    "-I./include",
    "-I./include/generated",
    "-I./arch/x86/include/uapi",
    "-I./arch/x86/include/generated/uapi",
    "-I./include/uapi",
    "-I./include/generated/uapi",
    "-include",
    "./include/linux/compiler-version.h",
    "-include",
    "./include/linux/kconfig.h",
    "-D__KERNEL__",
    "-DKASAN_SHADOW_SCALE_SHIFT=",
    "-P",
    "-D__ASSEMBLY__",
    "-DLINKER_SCRIPT",
    "-o",
    out.display(),
    src.display(),
  ]

  return {
    name: out.display(),
    outputs: [
      out,
    ],
    inputs: [
      src,
    ],
    deps: [],
    argv: argv,
    cwd: p".",
    env: {},
    depfile: depfile,
    stamp: fp"${out}.cmd",
  }
}

proc vmlinux_x86_archive_inputs(link_inputs: List[Path]) [] -> List[Path] {
  if link_inputs.len() > 0 {
    return link_inputs
  }

  return [p".xsh-kbuild/built-in.a", p".xsh-kbuild/arch/x86/lib/lib.a", p".xsh-kbuild/lib/lib.a"]
}

pure efi_libstub_stems_x86() -> List[Str] {
  return [
    "alignedmem",
    "efi-stub-helper",
    "file",
    "gop",
    "lib-cmdline",
    "lib-ctype",
    "mem",
    "pci",
    "printk",
    "random",
    "randomalloc",
    "relocate",
    "secureboot",
    "skip_spaces",
    "smbios",
    "tpm",
    "vsprintf",
    "x86-5lvl",
    "x86-stub",
  ]
}

pure efi_libstub_source_x86(stem: Str) -> Path {
  if stem.starts_with("lib-") {
    return fp"lib/${stem.replace("lib-", "")}.c"
  }

  if stem == "x86-stub" {
    return fp"drivers/firmware/efi/libstub/x86-stub.c"
  }

  return fp"drivers/firmware/efi/libstub/${stem}.c"
}

proc gzip_store_bytes(data: Bytes) [error] -> Result[Bytes] {
  var parts = [
    bytes.from_ints(
      [
        31,
        139,
        8,
        0,
        0,
        0,
        0,
        0,
        0,
        3,
      ],
    )?,
  ]

  var offset = 0

  while offset < data.len() {
    let remaining = data.len() - offset
    let chunk_len = if remaining > 65535 { 65535 } else { remaining }
    let final = if offset + chunk_len >= data.len() { 1 } else { 0 }
    parts = parts.push(bytes.from_ints([final])?)
    parts = parts.push(bytes.pack_le(chunk_len, 2)?)
    parts = parts.push(bytes.pack_le(65535 - chunk_len, 2)?)
    parts = parts.push(data.slice(offset: offset, length: chunk_len))
    offset += chunk_len
  }

  parts = parts.push(bytes.pack_le(hash.crc32(data), 4)?)
  parts = parts.push(bytes.pack_le(data.len() % 4294967296, 4)?)
  return bytes.concat(parts)
}

proc write_gzip_store(input: Path, out: Path) [fs, error] {
  write_text_if_changed(
    fp"${out}.note",
    f"""stored-gzip source=${input.display()} size=${input.metadata()?.size}
""",
  )?

  fs.write(out, gzip_store_bytes(input.read_bytes()?)?)?
}

proc append_x86_relocs(relocs: Path, input: Path, out: Path) [fs, process, error] {
  let input_text = input.display()
  let reloc_data = run.capture --bytes $relocs $input_text ?

  if ! reloc_data.status.ok {
    return Err(ScriptError.Failed("linux-x86-relocs", f"relocs failed for ${input.display()}"))?
  }

  let abs_relocs = run.capture --bytes $relocs "--abs-relocs" $input_text ?

  if ! abs_relocs.status.ok {
    return Err(ScriptError.Failed("linux-x86-relocs", f"relocs --abs-relocs failed for ${input.display()}"))?
  }

  fs.write(out, bytes.concat([p"arch/x86/boot/compressed/vmlinux.bin".read_bytes()?, reloc_data.stdout]))?
}

proc write_x86_voffset_header(nm: Path, input: Path) [fs, process, error] {
  let symbol_re = regex.compile(
    "^([0-9a-fA-F]+) [ABbCDGRSTtVW] (_text|__start_rodata|_sinittext|__inittext_end|__bss_start|_end)$",
  )?

  let symbols = run.text $nm $input ?
  var lines: List[Str] = []

  for raw in symbols.lines() {
    let caps = symbol_re.captures(raw)

    if caps.len() >= 3 {
      lines = lines.push(f"#define VO_${caps[2]} _AC(0x${caps[1]},UL)")
    }
  }

  if lines.len() == 0 {
    return Err(ScriptError.Failed("linux-x86-voffset", f"no voffset symbols found in ${input.display()}"))?
  }

  write_text_if_changed(
    p"arch/x86/boot/voffset.h",
    f"""${lines.join("\n")}
""",
  )?
}

proc write_x86_zoffset_header(nm: Path, input: Path) [fs, process, error] {
  let symbol_re = regex.compile(
    "^([0-9a-fA-F]+) [a-zA-Z] (startup_32|efi.._stub_entry|efi(32)?_pe_entry|input_data|kernel_info|_end|_ehead|_text|_e?data|_e?sbat|z_.*)$",
  )?

  let symbols = run.text $nm $input ?
  var lines: List[Str] = []

  for raw in symbols.lines() {
    let caps = symbol_re.captures(raw)

    if caps.len() >= 3 {
      lines = lines.push(f"#define ZO_${caps[2]} 0x${caps[1]}")
    }
  }

  if lines.len() == 0 {
    return Err(ScriptError.Failed("linux-x86-zoffset", f"no zoffset symbols found in ${input.display()}"))?
  }

  write_text_if_changed(
    p"arch/x86/boot/zoffset.h",
    f"""${lines.join("\n")}
""",
  )?
}

pure x86_compressed_cflags() -> List[Str] {
  return [
    "-D__KERNEL__",
    "-m64",
    "-O2",
    "-std=gnu11",
    "-fms-extensions",
    "-fno-strict-aliasing",
    "-fPIE",
    "-Wundef",
    "-DDISABLE_BRANCH_PROFILING",
    "-mcmodel=small",
    "-mno-red-zone",
    "-mno-mmx",
    "-mno-sse",
    "-ffreestanding",
    "-fshort-wchar",
    "-fno-stack-protector",
    "-Wno-address-of-packed-member",
    "-Wno-gnu",
    "-Wno-microsoft-anon-tag",
    "-Wno-pointer-sign",
    "-fno-asynchronous-unwind-tables",
    "-D__DISABLE_EXPORTS",
    "-include",
    "include/linux/hidden.h",
  ]
}

pure x86_compressed_includes() -> List[Str] {
  return [
    "-nostdinc",
    "-I./arch/x86/boot/compressed",
    "-I./arch/x86/boot",
    "-I./arch/x86/lib",
    "-I./arch/x86/include",
    "-I./arch/x86/include/generated",
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

pure x86_linker_script_includes() -> List[Str] {
  return [
    "-nostdinc",
    "-I./arch/x86/boot/compressed",
    "-I./arch/x86/boot",
    "-I./arch/x86/lib",
    "-I./arch/x86/include",
    "-I./arch/x86/include/generated",
    "-I./include",
    "-I./arch/x86/include/uapi",
    "-I./arch/x86/include/generated/uapi",
    "-I./include/uapi",
    "-I./include/generated/uapi",
    "-include",
    "./include/linux/kconfig.h",
  ]
}

pure x86_setup_cflags() -> List[Str] {
  return [
    "-D__KERNEL__",
    "-std=gnu11",
    "-fms-extensions",
    "-m16",
    "-g",
    "-Os",
    "-DDISABLE_BRANCH_PROFILING",
    "-D__DISABLE_EXPORTS",
    "-Wall",
    "-Wstrict-prototypes",
    "-march=i386",
    "-mregparm=3",
    "-fno-strict-aliasing",
    "-fomit-frame-pointer",
    "-fno-pic",
    "-mno-mmx",
    "-mno-sse",
    "-fcf-protection=none",
    "-ffreestanding",
    "-fno-stack-protector",
    "-Wno-address-of-packed-member",
    "-mstack-alignment=4",
    "-Wno-gnu",
    "-Wno-microsoft-anon-tag",
    "-D_SETUP",
    "-DSVGA_MODE=NORMAL_VGA",
    "-fno-asynchronous-unwind-tables",
  ]
}

pure x86_setup_includes() -> List[Str] {
  return [
    "-nostdinc",
    "-I./arch/x86/boot",
    "-I./arch/x86/include",
    "-I./arch/x86/include/generated",
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

proc preprocess_x86_boot_lds(cc: Path, source: Path, out: Path, includes: List[Str]) [process, error] {
  let argv = [
    cc.display(),
    "-target",
    "x86_64-linux-gnu",
    "-Wno-unused-command-line-argument",
    "-D__ASSEMBLY__",
    "-DLINKER_SCRIPT",
    "-Ux86_64",
    "-E",
    "-P",
  ].extend(includes)
    .extend([source.display(), "-o", out.display()])

  run $cc ${argv |> drop(1)} ?
}

proc build_x86_compressed_kernel(
  cc: Path,
  unstripped: Path,
  vmlinux: Path,
  efi_lib: Path,
  jobs_count: Int,
) [fs, process, env, error] {
  let objcopy = process.which("llvm-objcopy")?
  let nm = process.which("llvm-nm")?
  let ld = process.which("ld.lld")?
  let relocs = p"arch/x86/tools/relocs"
  let compressed = p"arch/x86/boot/compressed"
  fs.mkdir(compressed)?
  fs.mkdir(p".xsh-kbuild/host/arch/x86/boot/compressed")?
  let kernel_bin = fp"${compressed}/vmlinux.bin"
  let kernel_all = fp"${compressed}/vmlinux.bin.all"
  let kernel_gz = fp"${compressed}/vmlinux.bin.gz"
  let piggy_s = fp"${compressed}/piggy.S"
  let mkpiggy = p".xsh-kbuild/host/arch/x86/boot/compressed/mkpiggy"
  let compressed_lds = fp"${compressed}/vmlinux.lds"
  let compressed_vmlinux = fp"${compressed}/vmlinux"
  let boot_vmlinux_bin = p"arch/x86/boot/vmlinux.bin"
  make.run_tasks([x86_compressed_vmlinux_bin_task(objcopy, vmlinux, kernel_bin)], 1)?
  append_x86_relocs(relocs, vmlinux, kernel_all)?
  write_gzip_store(kernel_all, kernel_gz)?
  run $cc "-O2" "-std=gnu11" "-Wall" "-I./tools/include" "-o" $mkpiggy "arch/x86/boot/compressed/mkpiggy.c" ?
  let piggy_text = run.text $mkpiggy $kernel_gz ?
  write_text_if_changed(piggy_s, piggy_text)?
  write_x86_voffset_header(nm, unstripped)?
  preprocess_x86_boot_lds(cc, fp"${compressed}/vmlinux.lds.S", compressed_lds, x86_linker_script_includes())?
  let base_cflags = x86_compressed_cflags()
  let includes = x86_compressed_includes()
  var tasks: List[make.MakeTask] = []
  var objects: List[Path] = []

  for item in [
    {
      source: p"arch/x86/boot/compressed/kernel_info.S",
      object: p"arch/x86/boot/compressed/kernel_info.o",
      asm: true,
    },
    {
      source: p"arch/x86/boot/compressed/head_64.S",
      object: p"arch/x86/boot/compressed/head_64.o",
      asm: true,
    },
    {
      source: p"arch/x86/boot/compressed/misc.c",
      object: p"arch/x86/boot/compressed/misc.o",
      asm: false,
    },
    {
      source: p"arch/x86/boot/compressed/string.c",
      object: p"arch/x86/boot/compressed/string.o",
      asm: false,
    },
    {
      source: p"arch/x86/boot/compressed/cmdline.c",
      object: p"arch/x86/boot/compressed/cmdline.o",
      asm: false,
    },
    {
      source: p"arch/x86/boot/compressed/error.c",
      object: p"arch/x86/boot/compressed/error.o",
      asm: false,
    },
    {
      source: p"arch/x86/boot/compressed/piggy.S",
      object: p"arch/x86/boot/compressed/piggy.o",
      asm: true,
    },
    {
      source: p"arch/x86/boot/compressed/cpuflags.c",
      object: p"arch/x86/boot/compressed/cpuflags.o",
      asm: false,
    },
    {
      source: p"arch/x86/boot/compressed/early_serial_console.c",
      object: p"arch/x86/boot/compressed/early_serial_console.o",
      asm: false,
    },
    {
      source: p"arch/x86/boot/compressed/kaslr.c",
      object: p"arch/x86/boot/compressed/kaslr.o",
      asm: false,
    },
    {
      source: p"arch/x86/boot/compressed/ident_map_64.c",
      object: p"arch/x86/boot/compressed/ident_map_64.o",
      asm: false,
    },
    {
      source: p"arch/x86/boot/compressed/idt_64.c",
      object: p"arch/x86/boot/compressed/idt_64.o",
      asm: false,
    },
    {
      source: p"arch/x86/boot/compressed/idt_handlers_64.S",
      object: p"arch/x86/boot/compressed/idt_handlers_64.o",
      asm: true,
    },
    {
      source: p"arch/x86/boot/compressed/pgtable_64.c",
      object: p"arch/x86/boot/compressed/pgtable_64.o",
      asm: false,
    },
    {
      source: p"arch/x86/boot/compressed/acpi.c",
      object: p"arch/x86/boot/compressed/acpi.o",
      asm: false,
    },
    {
      source: p"arch/x86/boot/compressed/efi.c",
      object: p"arch/x86/boot/compressed/efi.o",
      asm: false,
    },
  ] {
    let item_cflags = if item.asm { base_cflags.push("-D__ASSEMBLY__") } else { base_cflags }
    let item_defs = if item.asm { ["-D__DISABLE_EXPORTS"] } else { [] }
    var task = compile_kbuild_task(cc, "x86_64-linux-gnu", item_cflags, item_defs, includes, item.source, item.object)

    if item.source == p"arch/x86/boot/compressed/piggy.S" {
      task = {...task, inputs: task.inputs.push(kernel_gz)}
    }

    tasks = tasks.push(task)
    objects = objects.push(item.object)
  }

  make.run_tasks(tasks, jobs_count)?

  var argv = [
    ld.display(),
    "-m",
    "elf_x86_64",
    "-pie",
    "--no-dynamic-linker",
    "-z",
    "noexecstack",
    "-u",
    "efi_pe_entry",
    "-T",
    compressed_lds.display(),
    "-o",
    compressed_vmlinux.display(),
  ]

  for object in objects {
    argv = argv.push(object.display())
  }

  argv = argv.push(efi_lib.display())
  argv = argv.push(".xsh-kbuild/arch/x86/boot/startup/lib.a")
  run $ld ${argv |> drop(1)} ?
  write_x86_zoffset_header(nm, compressed_vmlinux)?
  make.run_tasks([image_task(objcopy, compressed_vmlinux, boot_vmlinux_bin)], 1)?
}

proc build_x86_setup_image(cc: Path, jobs_count: Int) [fs, process, env, error] {
  let ld = process.which("ld.lld")?
  let objcopy = process.which("llvm-objcopy")?
  let boot = p"arch/x86/boot"
  fs.mkdir(p".xsh-kbuild/host/arch/x86/boot")?
  let mkcpustr = p".xsh-kbuild/host/arch/x86/boot/mkcpustr"
  run $cc "-O2" "-std=gnu11" "-Wall" "-I./tools/include" "-include" "include/generated/autoconf.h" "-D__EXPORTED_HEADERS__" "-o" $mkcpustr "arch/x86/boot/mkcpustr.c" ?
  write_text_if_changed(fp"${boot}/cpustr.h", run.text $mkcpustr?)?
  let base_cflags = x86_setup_cflags()
  let includes = x86_setup_includes()
  var tasks: List[make.MakeTask] = []
  var objects: List[Path] = []

  for item in [
    {
      source: p"arch/x86/boot/a20.c",
      object: p"arch/x86/boot/a20.o",
      asm: false,
    },
    {
      source: p"arch/x86/boot/bioscall.S",
      object: p"arch/x86/boot/bioscall.o",
      asm: true,
    },
    {
      source: p"arch/x86/boot/cmdline.c",
      object: p"arch/x86/boot/cmdline.o",
      asm: false,
    },
    {
      source: p"arch/x86/boot/copy.S",
      object: p"arch/x86/boot/copy.o",
      asm: true,
    },
    {
      source: p"arch/x86/boot/cpu.c",
      object: p"arch/x86/boot/cpu.o",
      asm: false,
    },
    {
      source: p"arch/x86/boot/cpuflags.c",
      object: p"arch/x86/boot/cpuflags.o",
      asm: false,
    },
    {
      source: p"arch/x86/boot/cpucheck.c",
      object: p"arch/x86/boot/cpucheck.o",
      asm: false,
    },
    {
      source: p"arch/x86/boot/early_serial_console.c",
      object: p"arch/x86/boot/early_serial_console.o",
      asm: false,
    },
    {
      source: p"arch/x86/boot/edd.c",
      object: p"arch/x86/boot/edd.o",
      asm: false,
    },
    {
      source: p"arch/x86/boot/header.S",
      object: p"arch/x86/boot/header.o",
      asm: true,
    },
    {
      source: p"arch/x86/boot/main.c",
      object: p"arch/x86/boot/main.o",
      asm: false,
    },
    {
      source: p"arch/x86/boot/memory.c",
      object: p"arch/x86/boot/memory.o",
      asm: false,
    },
    {
      source: p"arch/x86/boot/pm.c",
      object: p"arch/x86/boot/pm.o",
      asm: false,
    },
    {
      source: p"arch/x86/boot/pmjump.S",
      object: p"arch/x86/boot/pmjump.o",
      asm: true,
    },
    {
      source: p"arch/x86/boot/printf.c",
      object: p"arch/x86/boot/printf.o",
      asm: false,
    },
    {
      source: p"arch/x86/boot/regs.c",
      object: p"arch/x86/boot/regs.o",
      asm: false,
    },
    {
      source: p"arch/x86/boot/string.c",
      object: p"arch/x86/boot/string.o",
      asm: false,
    },
    {
      source: p"arch/x86/boot/tty.c",
      object: p"arch/x86/boot/tty.o",
      asm: false,
    },
    {
      source: p"arch/x86/boot/video.c",
      object: p"arch/x86/boot/video.o",
      asm: false,
    },
    {
      source: p"arch/x86/boot/video-mode.c",
      object: p"arch/x86/boot/video-mode.o",
      asm: false,
    },
    {
      source: p"arch/x86/boot/version.c",
      object: p"arch/x86/boot/version.o",
      asm: false,
    },
    {
      source: p"arch/x86/boot/video-vga.c",
      object: p"arch/x86/boot/video-vga.o",
      asm: false,
    },
    {
      source: p"arch/x86/boot/video-vesa.c",
      object: p"arch/x86/boot/video-vesa.o",
      asm: false,
    },
    {
      source: p"arch/x86/boot/video-bios.c",
      object: p"arch/x86/boot/video-bios.o",
      asm: false,
    },
  ] {
    let item_cflags = if item.asm { base_cflags.push("-D__ASSEMBLY__") } else { base_cflags }
    let item_defs = if item.asm { ["-D__DISABLE_EXPORTS", "-D_SETUP"] } else { [] }
    let item_triple = if item.asm { "i386-linux-gnu" } else { "x86_64-linux-gnu" }
    let task = compile_kbuild_task(cc, item_triple, item_cflags, item_defs, includes, item.source, item.object)
    tasks = tasks.push(task)
    objects = objects.push(item.object)
  }

  make.run_tasks(tasks, jobs_count)?

  var argv = [
    ld.display(),
    "-m",
    "elf_i386",
    "-z",
    "noexecstack",
    "-T",
    "arch/x86/boot/setup.ld",
    "-o",
    "arch/x86/boot/setup.elf",
  ]

  for object in objects {
    argv = argv.push(object.display())
  }

  run $ld ${argv |> drop(1)} ?
  run $objcopy "-O" "binary" "arch/x86/boot/setup.elf" "arch/x86/boot/setup.bin" ?
}

proc write_x86_bzimage(setup: Path, payload: Path, image: Path) [fs, error] {
  let setup_data = setup.read_bytes()?
  let payload_data = payload.read_bytes()?
  let remainder = setup_data.len() % 4096
  let padding_len = if remainder == 0 { 0 } else { 4096 - remainder }
  fs.write(image, bytes.concat([setup_data, bytes.zero(padding_len)?, payload_data]))?
}

export proc build_scratch_x86_final(
  cc: Path,
  cflags: List[Str],
  defs: List[Str],
  includes: List[Str],
  link_inputs: List[Path],
  jobs_count: Int = 1,
) [fs, process, env, error] {
  write_minimal_vmlinux_export(p".")?
  let _ = cc
  let ar_argv = ["llvm-ar"]
  let ld_argv = ["ld.lld"]
  let objcopy_argv = ["llvm-objcopy"]
  let vmlinux_a = p"vmlinux.a"
  let unstripped = p"vmlinux.unstripped"
  let vmlinux = p"vmlinux"
  let image = p"arch/x86/boot/bzImage"
  let efi_lib = p"drivers/firmware/efi/libstub/lib.a"
  let support_lib = p"lib/xsh-final-lib.a"
  let kbuild_ldflags = ["-m", "elf_x86_64", "-z", "norelro", "-z", "noexecstack"]
  let ldflags_vmlinux = x86_vmlinux_ldflags(load_config(p".config")?)
  write_ubsan_stubs(p".")?
  let lds = p"arch/x86/kernel/vmlinux.lds"
  generate_vmlinux_lds_x86(cc, lds)?
  fs.remove(vmlinux_a, missing_ok: true)?
  fs.remove(unstripped, missing_ok: true)?
  fs.remove(vmlinux, missing_ok: true)?
  fs.mkdir(fp"arch/x86/boot")?
  fs.remove(image, missing_ok: true)?
  var tasks: List[make.MakeTask] = []

  let export_task = compile_kbuild_task(
    cc,
    "x86_64-linux-gnu",
    cflags,
    defs,
    includes,
    p".vmlinux.export.c",
    p".vmlinux.export.o",
  )

  tasks = tasks.push(export_task)

  let version_task = compile_kbuild_task(
    cc,
    "x86_64-linux-gnu",
    cflags,
    defs,
    includes,
    p"init/version-timestamp.c",
    p"init/version-timestamp.o",
  )

  tasks = tasks.push(version_task)
  var stub_objs: List[Path] = []
  var stub_deps: List[Str] = []

  for stem in efi_libstub_stems_x86() {
    let obj = fp"drivers/firmware/efi/libstub/${stem}.o"
    let stub = fp"drivers/firmware/efi/libstub/${stem}.stub.o"
    let src = efi_libstub_source_x86(stem)

    let compile_task = compile_kbuild_task(
      cc,
      "x86_64-linux-gnu",
      efi_libstub_cflags_x86(cflags),
      defs,
      includes,
      src,
      obj,
    )

    let copy_task = efi_stubcopy_task_x86(obj, stub, [compile_task.name])
    tasks = tasks.push(compile_task)
    tasks = tasks.push(copy_task)
    stub_objs = stub_objs.push(stub)
    stub_deps = stub_deps.push(copy_task.name)
  }

  let efi_archive = efi_libstub_archive_task(ar_argv, stub_objs, efi_lib, stub_deps)
  tasks = tasks.push(efi_archive)
  var support_objs: List[Path] = []
  var support_deps: List[Str] = []

  for obj in final_support_lib_sources() {
    let src = source_for_object(obj)?
    let task = compile_kbuild_task(cc, "x86_64-linux-gnu", final_support_cflags(cflags, obj), defs, includes, src, obj)
    tasks = tasks.push(task)
    support_objs = support_objs.push(obj)
    support_deps = support_deps.push(task.name)
  }

  let ubsan_stubs = p".xsh-kbuild/obj/lib/xsh-ubsan-stubs.o"

  let ubsan_task = compile_kbuild_task(
    cc,
    "x86_64-linux-gnu",
    cflags.push("-fno-sanitize=undefined"),
    defs,
    includes,
    p".xsh-kbuild/generated/xsh-ubsan-stubs.c",
    ubsan_stubs,
  )

  tasks = tasks.push(ubsan_task)
  support_objs = support_objs.push(ubsan_stubs)
  support_deps = support_deps.push(ubsan_task.name)
  let support_archive = efi_libstub_archive_task(ar_argv, support_objs, support_lib, support_deps)
  tasks = tasks.push(support_archive)
  let archive_inputs = vmlinux_x86_archive_inputs(link_inputs)
  let archive_task = vmlinux_archive_argv_task(ar_argv, archive_inputs, vmlinux_a, [])
  tasks = tasks.push(archive_task)

  let linked_task = vmlinux_unstripped_argv_task(
    ld_argv,
    kbuild_ldflags,
    ldflags_vmlinux,
    lds,
    vmlinux_a,
    [efi_lib, support_lib],
    p".vmlinux.export.o",
    p"init/version-timestamp.o",
    unstripped,
    [export_task.name, version_task.name, efi_archive.name, support_archive.name, archive_task.name],
  )

  let strip_task = x86_vmlinux_strip_argv_task(objcopy_argv, unstripped, vmlinux, [linked_task.name])
  tasks = tasks.push(linked_task)
  tasks = tasks.push(strip_task)
  make.run_tasks(tasks, jobs_count)?
  build_x86_compressed_kernel(cc, unstripped, vmlinux, efi_lib, jobs_count)?
  build_x86_setup_image(cc, jobs_count)?
  write_x86_bzimage(p"arch/x86/boot/setup.bin", p"arch/x86/boot/vmlinux.bin", image)?
}

export proc write_minimal_vmlinux_export(root: Path) [fs, error] {
  write_text_if_changed(
    fp"${root}/.vmlinux.export.c",
    """/* Generated by the scratch-native XSH Linux build. */
""",
  )?
}

pure efi_libstub_stems() -> List[Str] {
  return [
    "alignedmem",
    "arm64-stub",
    "arm64",
    "efi-stub-entry",
    "efi-stub-helper",
    "efi-stub",
    "fdt",
    "file",
    "gop",
    "intrinsics",
    "kaslr",
    "lib-cmdline",
    "lib-ctype",
    "lib-fdt",
    "lib-fdt_empty_tree",
    "lib-fdt_ro",
    "lib-fdt_rw",
    "lib-fdt_sw",
    "lib-fdt_wip",
    "mem",
    "pci",
    "primary_display",
    "printk",
    "random",
    "randomalloc",
    "relocate",
    "secureboot",
    "skip_spaces",
    "smbios",
    "string",
    "systable",
    "tpm",
    "vsprintf",
  ]
}

pure final_support_lib_sources() -> List[Path] {
  return [
    p"lib/fdt.o",
    p"lib/fdt_addresses.o",
    p"lib/fdt_empty_tree.o",
    p"lib/fdt_ro.o",
    p"lib/fdt_rw.o",
    p"lib/fdt_strerror.o",
    p"lib/fdt_sw.o",
    p"lib/fdt_wip.o",
  ]
}

pure efi_libstub_source(stem: Str) -> Path {
  if stem.starts_with("lib-") {
    return fp"lib/${stem.replace("lib-", "")}.c"
  }

  return fp"drivers/firmware/efi/libstub/${stem}.c"
}

pure efi_libstub_cflags(cflags: List[Str]) -> List[Str] {
  return cflags.extend(
    [
      "-fpie",
      "-fno-unwind-tables",
      "-fno-asynchronous-unwind-tables",
      "-I./scripts/dtc/libfdt",
      "-Os",
      "-DDISABLE_BRANCH_PROFILING",
      "-include",
      "include/linux/hidden.h",
      "-D__NO_FORTIFY",
      "-ffreestanding",
      "-fno-stack-protector",
      "-D__DISABLE_EXPORTS",
    ],
  )
}

pure efi_libstub_cflags_x86(cflags: List[Str]) -> List[Str] {
  return cflags.extend(
    [
      "-mcmodel=small",
      "-m64",
      "-fPIC",
      "-fno-strict-aliasing",
      "-mno-red-zone",
      "-mno-mmx",
      "-mno-sse",
      "-fshort-wchar",
      "-Wno-pointer-sign",
      "-Wno-address-of-packed-member",
      "-Wno-gnu",
      "-Wno-microsoft-anon-tag",
      "-fno-unwind-tables",
      "-fno-asynchronous-unwind-tables",
      "-Os",
      "-DDISABLE_BRANCH_PROFILING",
      "-include",
      "include/linux/hidden.h",
      "-D__NO_FORTIFY",
      "-ffreestanding",
      "-fno-stack-protector",
      "-fno-addrsig",
      "-D__DISABLE_EXPORTS",
    ],
  )
}

pure final_support_cflags(cflags: List[Str], out: Path) -> List[Str] {
  let _ = out
  return cflags.extend(["-I./scripts/dtc/libfdt", "-fno-sanitize=undefined"])
}

export proc write_ubsan_stubs(root: Path) [fs, error] {
  write_text_if_changed(
    fp"${root}/.xsh-kbuild/generated/xsh-ubsan-stubs.c",
    """void __ubsan_handle_type_mismatch_v1(void) {}
void __ubsan_handle_type_mismatch_v1_abort(void) {}
void __ubsan_handle_shift_out_of_bounds(void) {}
void __ubsan_handle_shift_out_of_bounds_abort(void) {}
void __ubsan_handle_out_of_bounds(void) {}
void __ubsan_handle_out_of_bounds_abort(void) {}
void __ubsan_handle_add_overflow(void) {}
void __ubsan_handle_add_overflow_abort(void) {}
void __ubsan_handle_sub_overflow(void) {}
void __ubsan_handle_sub_overflow_abort(void) {}
void __ubsan_handle_mul_overflow(void) {}
void __ubsan_handle_mul_overflow_abort(void) {}
void __ubsan_handle_divrem_overflow(void) {}
void __ubsan_handle_divrem_overflow_abort(void) {}
void __ubsan_handle_negate_overflow(void) {}
void __ubsan_handle_negate_overflow_abort(void) {}
void __ubsan_handle_load_invalid_value(void) {}
void __ubsan_handle_load_invalid_value_abort(void) {}
void __ubsan_handle_builtin_unreachable(void) {}
void __ubsan_handle_pointer_overflow(void) {}
void __ubsan_handle_pointer_overflow_abort(void) {}
void __ubsan_handle_invalid_builtin(void) {}
void __ubsan_handle_invalid_builtin_abort(void) {}
void __ubsan_handle_nonnull_arg(void) {}
void __ubsan_handle_nonnull_arg_abort(void) {}
void __ubsan_handle_nullability_arg(void) {}
void __ubsan_handle_nullability_arg_abort(void) {}
void __ubsan_handle_vla_bound_not_positive(void) {}
void __ubsan_handle_vla_bound_not_positive_abort(void) {}
void __ubsan_handle_alignment_assumption(void) {}
void __ubsan_handle_alignment_assumption_abort(void) {}
""",
  )?
}

proc efi_stubcopy_task(input: Path, out: Path, deps: List[Str]) [env] -> make.MakeTask {
  let tool_path = host_build_path()

  return {
    name: out.display(),
    outputs: [
      out,
    ],
    inputs: [
      input,
    ],
    deps: deps,
    argv: [
      "llvm-objcopy",
      "--remove-section=.note.gnu.property",
      "--prefix-alloc-sections=.init",
      "--prefix-symbols=__efistub_",
      input.display(),
      out.display(),
    ],
    cwd: p".",
    env: {
      PATH: tool_path,
    },
    depfile: p"",
    stamp: fp"${out}.cmd",
  }
}

proc efi_stubcopy_task_x86(input: Path, out: Path, deps: List[Str]) [env] -> make.MakeTask {
  let tool_path = host_build_path()

  return {
    name: out.display(),
    outputs: [
      out,
    ],
    inputs: [
      input,
    ],
    deps: deps,
    argv: [
      "llvm-objcopy",
      "--remove-section=.note.gnu.property",
      input.display(),
      out.display(),
    ],
    cwd: p".",
    env: {
      PATH: tool_path,
    },
    depfile: p"",
    stamp: fp"${out}.cmd",
  }
}

proc efi_libstub_archive_task(
  ar_argv: List[Str],
  inputs: List[Path],
  out: Path,
  deps: List[Str],
) [env] -> make.MakeTask {
  let tool_path = host_build_path()
  var argv = ar_argv.extend(["cDPrsT", out.display()])

  for input in inputs {
    argv = argv.push(input.display())
  }

  return {
    name: out.display(),
    outputs: [
      out,
    ],
    inputs: inputs,
    deps: deps,
    argv: argv,
    cwd: p".",
    env: {
      PATH: tool_path,
    },
    depfile: p"",
    stamp: fp"${out}.cmd",
  }
}

proc vmlinux_archive_reorder_task(ar_argv: List[Str], archive_path: Path, deps: List[Str]) [env] -> make.MakeTask {
  let tool_path = host_build_path()

  return {
    name: f"${archive_path.display()}:head-order",
    outputs: [
      fp".xsh-kbuild/${archive_path.name}.head-order",
    ],
    inputs: [
      archive_path,
      p".xsh-kbuild/obj/arch/arm64/kernel/head.o",
    ],
    deps: deps,
    argv: ar_argv.extend(
      [
        "mPiT",
        ".xsh-kbuild/obj/init/main.o",
        archive_path.display(),
        ".xsh-kbuild/obj/arch/arm64/kernel/head.o",
      ],
    ),
    cwd: p".",
    env: {
      PATH: tool_path,
    },
    depfile: p"",
    stamp: fp".xsh-kbuild/${archive_path.name}.head-order.cmd",
  }
}

proc vmlinux_archive_inputs() [] -> List[Path] {
  return [p".xsh-kbuild/built-in.a", p".xsh-kbuild/arch/arm64/lib/lib.a", p".xsh-kbuild/lib/lib.a"]
}

export proc build_scratch_arm64_final(
  cc: Path,
  cflags: List[Str],
  defs: List[Str],
  includes: List[Str],
  jobs_count: Int = 1,
) [fs, process, env, error] {
  write_minimal_vmlinux_export(p".")?
  let _ = cc
  let ar_argv = ["llvm-ar"]
  let ld_argv = ["ld.lld"]
  let objcopy_argv = ["llvm-objcopy"]
  let vmlinux_a = p"vmlinux.a"
  let unstripped = p"vmlinux.unstripped"
  let vmlinux = p"vmlinux"
  let image = p"arch/arm64/boot/Image"
  let efi_lib = p"drivers/firmware/efi/libstub/lib.a"
  let support_lib = p"lib/xsh-final-lib.a"
  let kbuild_ldflags = ["-EL", "-maarch64elf", "-z", "norelro", "-z", "noexecstack"]
  let ldflags_vmlinux = arm64_vmlinux_ldflags(load_config(p".config")?)
  write_ubsan_stubs(p".")?
  let lds = p"arch/arm64/kernel/vmlinux.lds"
  generate_vmlinux_lds(cc, lds)?
  fs.remove(vmlinux_a, missing_ok: true)?
  fs.remove(unstripped, missing_ok: true)?
  fs.remove(vmlinux, missing_ok: true)?
  fs.remove(image, missing_ok: true)?
  var tasks: List[make.MakeTask] = []

  let export_task = compile_kbuild_task(
    cc,
    "aarch64-linux-gnu",
    cflags,
    defs,
    includes,
    p".vmlinux.export.c",
    p".vmlinux.export.o",
  )

  tasks = tasks.push(export_task)

  let version_task = compile_kbuild_task(
    cc,
    "aarch64-linux-gnu",
    cflags,
    defs,
    includes,
    p"init/version-timestamp.c",
    p"init/version-timestamp.o",
  )

  tasks = tasks.push(version_task)
  var stub_objs: List[Path] = []
  var stub_deps: List[Str] = []

  for stem in efi_libstub_stems() {
    let obj = fp"drivers/firmware/efi/libstub/${stem}.o"
    let stub = fp"drivers/firmware/efi/libstub/${stem}.stub.o"
    let src = efi_libstub_source(stem)

    let compile_task = compile_kbuild_task(
      cc,
      "aarch64-linux-gnu",
      efi_libstub_cflags(cflags),
      defs,
      includes,
      src,
      obj,
    )

    let copy_task = efi_stubcopy_task(obj, stub, [compile_task.name])
    tasks = tasks.push(compile_task)
    tasks = tasks.push(copy_task)
    stub_objs = stub_objs.push(stub)
    stub_deps = stub_deps.push(copy_task.name)
  }

  let efi_archive = efi_libstub_archive_task(ar_argv, stub_objs, efi_lib, stub_deps)
  tasks = tasks.push(efi_archive)
  var support_objs: List[Path] = []
  var support_deps: List[Str] = []

  for obj in final_support_lib_sources() {
    let src = source_for_object(obj)?
    let task = compile_kbuild_task(cc, "aarch64-linux-gnu", final_support_cflags(cflags, obj), defs, includes, src, obj)
    tasks = tasks.push(task)
    support_objs = support_objs.push(obj)
    support_deps = support_deps.push(task.name)
  }

  let ubsan_stubs = p".xsh-kbuild/obj/lib/xsh-ubsan-stubs.o"

  let ubsan_task = compile_kbuild_task(
    cc,
    "aarch64-linux-gnu",
    cflags.push("-fno-sanitize=undefined"),
    defs,
    includes,
    p".xsh-kbuild/generated/xsh-ubsan-stubs.c",
    ubsan_stubs,
  )

  tasks = tasks.push(ubsan_task)
  support_objs = support_objs.push(ubsan_stubs)
  support_deps = support_deps.push(ubsan_task.name)
  let support_archive = efi_libstub_archive_task(ar_argv, support_objs, support_lib, support_deps)
  tasks = tasks.push(support_archive)
  let archive_task = vmlinux_archive_argv_task(ar_argv, vmlinux_archive_inputs(), vmlinux_a, [])
  tasks = tasks.push(archive_task)

  let linked_task = vmlinux_unstripped_argv_task(
    ld_argv,
    kbuild_ldflags,
    ldflags_vmlinux,
    lds,
    vmlinux_a,
    [efi_lib, support_lib],
    p".vmlinux.export.o",
    p"init/version-timestamp.o",
    unstripped,
    [export_task.name, version_task.name, efi_archive.name, support_archive.name, archive_task.name],
  )

  let strip_task = vmlinux_strip_argv_task(objcopy_argv, unstripped, vmlinux, [linked_task.name])
  let img_task = image_argv_task(objcopy_argv, vmlinux, image, [strip_task.name])
  tasks = tasks.push(linked_task)
  tasks = tasks.push(strip_task)
  tasks = tasks.push(img_task)
  make.run_tasks(tasks, jobs_count)?
}

export proc relink_existing_arm64(ar: Path, ld: Path, objcopy: Path, jobs_count: Int = 1) [fs, process, env, error] {
  relink_existing_arm64_argv([ar.display()], [ld.display()], [objcopy.display()], jobs_count)?
}

export proc relink_existing_arm64_llvm(jobs_count: Int = 1) [fs, process, env, error] {
  relink_existing_arm64_argv(["llvm-ar"], ["ld.lld"], ["llvm-objcopy"], jobs_count)?
}

export proc relink_existing_arm64_argv(
  ar_argv: List[Str],
  ld_argv: List[Str],
  objcopy_argv: List[Str],
  jobs_count: Int = 1,
) [fs, process, env, error] {
  let vmlinux_a = p"vmlinux.a"
  let vmlinux_o = p"vmlinux.o"
  let unstripped = p"vmlinux.unstripped"
  let vmlinux = p"vmlinux"
  let image = p"arch/arm64/boot/Image"
  let efi_lib = p"drivers/firmware/efi/libstub/lib.a"
  let kbuild_ldflags = ["-EL", "-maarch64elf", "-z", "norelro", "-z", "noexecstack"]
  let ldflags_vmlinux = arm64_vmlinux_ldflags(load_config(p".config")?)
  fs.remove(vmlinux_a, missing_ok: true)?
  fs.remove(vmlinux_o, missing_ok: true)?
  fs.remove(unstripped, missing_ok: true)?
  fs.remove(vmlinux, missing_ok: true)?
  fs.remove(image, missing_ok: true)?

  let archive_task = vmlinux_archive_argv_task(
    ar_argv,
    [p"built-in.a", p"arch/arm64/lib/lib.a", p"lib/lib.a"],
    vmlinux_a,
  )

  let reloc_task = vmlinux_o_argv_task(ld_argv, kbuild_ldflags, vmlinux_a, [efi_lib], vmlinux_o, [archive_task.name])

  let linked_task = vmlinux_unstripped_argv_task(
    ld_argv,
    kbuild_ldflags,
    ldflags_vmlinux,
    p"arch/arm64/kernel/vmlinux.lds",
    vmlinux_a,
    [efi_lib],
    p".vmlinux.export.o",
    p"init/version-timestamp.o",
    unstripped,
    [archive_task.name],
  )

  let strip_task = vmlinux_strip_argv_task(objcopy_argv, unstripped, vmlinux, [linked_task.name])
  let img_task = image_argv_task(objcopy_argv, vmlinux, image, [strip_task.name])
  make.run_tasks([archive_task, reloc_task, linked_task, strip_task, img_task], jobs_count)?
}

export proc build_builtin_archives(
  plan: KbuildPlan,
  cc: Path,
  triple: Str,
  cflags: List[Str],
  defs: List[Str],
  includes: List[Str],
  jobs_count: Int,
) [fs, process, env, error] -> Result[List[Path]] {
  let archive_plan = plan_builtin_archives(plan, cc, triple, cflags, defs, includes)?
  return run_builtin_archive_plan(archive_plan, jobs_count)
}

export proc run_builtin_archive_plan(
  archive_plan: Record,
  jobs_count: Int,
) [fs, process, env, error] -> Result[List[Path]] {
  if archive_plan.missing_sources.len() > 0 {
    print "xsh-kbuild-missing-objects" archive_plan.missing_sources.len() "tolerated"
  }

  if archive_plan.generated_objects.len() > 0 {
    return Err(
      ScriptError.Failed(
        "kbuild-generated-objects",
        f"${archive_plan.generated_objects.len()} generated Kbuild objects need generator tasks",
      ),
    )
  }

  make.run_tasks(archive_plan.tasks, jobs_count)?
  return archive_plan.archives
}

pure empty_reloc() -> ElfReloc {
  return {
    section: "",
    index: 0,
    offset: 0,
    info: 0,
    typ: "",
    symbol: "",
    addend: 0,
  }
}

pure hex_digit(char: Str) -> Result[Int] {
  if char == "0" {
    return 0
  }

  if char == "1" {
    return 1
  }

  if char == "2" {
    return 2
  }

  if char == "3" {
    return 3
  }

  if char == "4" {
    return 4
  }

  if char == "5" {
    return 5
  }

  if char == "6" {
    return 6
  }

  if char == "7" {
    return 7
  }

  if char == "8" {
    return 8
  }

  if char == "9" {
    return 9
  }

  if char == "a" or char == "A" {
    return 10
  }

  if char == "b" or char == "B" {
    return 11
  }

  if char == "c" or char == "C" {
    return 12
  }

  if char == "d" or char == "D" {
    return 13
  }

  if char == "e" or char == "E" {
    return 14
  }

  if char == "f" or char == "F" {
    return 15
  }

  return Err(ScriptError.Failed("kbuild-elf-hex", f"invalid hex digit '${char}'"))
}

pure parse_hex(raw: Str) -> Result[Int] {
  let text = raw.trim().replace("0x", "").replace("0X", "")
  var value = 0

  for char in text.split("") {
    continue when char == ""
    value = value * 16 + hex_digit(char)?
  }

  return value
}

proc parse_elf_sections(text: Str) [error] -> Result[List[ElfSection]] {
  var sections: List[ElfSection] = []

  for raw in text.lines() {
    let words = raw.words()
    continue when words.len() < 6
    continue when words[0] == "[Nr]"

    if words[0] == "[" {
      continue when words.len() < 7 or words[1] == "0]"
      sections = sections.push({name: words[2], offset: parse_hex(words[5])?, size: parse_hex(words[6])?})
      continue
    }

    if words[0].starts_with("[") {
      sections = sections.push({name: words[1], offset: parse_hex(words[4])?, size: parse_hex(words[5])?})
    }
  }

  return sections
}

proc section_offset(sections: List[ElfSection], name: Str) [error] -> Result[Int] {
  for section in sections {
    if section.name == name {
      return section.offset
    }
  }

  return Err(ScriptError.Failed("kbuild-elf-section", f"missing ELF section ${name}"))
}

pure parse_readelf_addend(words: List[Str]) -> Result[Int] {
  var index = 0

  while index < words.len() {
    if words[index] == "+" and index + 1 < words.len() {
      return parse_hex(words[index + 1])
    }

    if words[index] == "-" and index + 1 < words.len() {
      return 0 - parse_hex(words[index + 1])?
    }

    index += 1
  }

  return 0
}

pure elf_reloc_key(section: Str, offset: Int) -> Str {
  return f"${section}@${offset}"
}

proc parse_elf_relocations(text: Str) [error] -> Result[ElfRelocTable] {
  var keys: List[ElfReloc] = []
  var by_offset: Map[ElfReloc] = {}
  var current = ""
  var index = 0

  for raw in text.lines() {
    let line = raw.trim()
    let section_caps = regex_captures(line, "^Relocation section '([^']*)' ")?

    if section_caps.len() >= 2 {
      current = section_caps[1]
      index = 0
      continue
    }

    continue when current == "" or line == "" or line.starts_with("Offset")
    let words = line.words()
    continue when words.len() < 5

    let reloc: ElfReloc = {
      section: current,
      index,
      offset: parse_hex(words[0])?,
      info: parse_hex(words[1])?,
      typ: words[2],
      symbol: words[4],
      addend: parse_readelf_addend(words)?,
    }

    by_offset[elf_reloc_key(reloc.section, reloc.offset)] = reloc

    if reloc.section == ".rela__jump_table" and reloc.offset % 16 == 8 and reloc.addend % 4 >= 2 {
      keys = keys.push(reloc)
    }

    index += 1
  }

  return {keys, by_offset}
}

pure lookup_reloc(relocs: ElfRelocTable, section: Str, offset: Int) -> RelocLookup {
  let key = elf_reloc_key(section, offset)

  if relocs.by_offset.has(key) {
    return {found: true, reloc: relocs.by_offset.get(key, empty_reloc())}
  }

  return {found: false, reloc: empty_reloc()}
}

proc has_bytes_at(data: Bytes, offset: Int, values: List[Int]) [error] -> Result[Bool] {
  var index = 0

  while index < values.len() {
    if offset + index >= data.len() {
      return false
    }

    if bytes.unpack_le(data, 1, offset: offset + index)? != values[index] {
      return false
    }

    index += 1
  }

  return true
}

proc replace_bytes(data: Bytes, offset: Int, replacement: Bytes) [error] -> Result[Bytes] {
  return bytes.concat(
    [
      data.slice(offset: 0, length: offset),
      replacement,
      data.slice(offset: offset + replacement.len(), length: data.len() - offset - replacement.len()),
    ],
  )
}

proc file_has_bytes_at(path_value: Path, offset: Int, values: List[Int]) [error] -> Result[Bool] {
  let data = bytes.read_at(path_value, offset, values.len())?
  return has_bytes_at(data, 0, values)
}

proc patch_x86_jump_label_object(readelf: Path, object: Path) [fs, process, error] -> Result[Int] {
  let section_text = run.text $readelf "-SW" $object ?

  if ! ("__jump_table" in section_text) {
    return 0
  }

  let sections = parse_elf_sections(section_text)?
  let relocs = parse_elf_relocations(run.text $readelf "-rW" $object?)?
  var patched = 0

  for key in relocs.keys {
    let entry_offset = key.offset - 8
    let orig = lookup_reloc(relocs, ".rela__jump_table", entry_offset)

    if ! orig.found {
      return Err(
        ScriptError.Failed("kbuild-x86-jump-label", f"${object.display()} missing jump-table origin relocation"),
      )
    }

    let text_offset = section_offset(sections, orig.reloc.symbol)?
    let insn_offset = orig.reloc.addend
    let file_offset = text_offset + insn_offset
    let opcode = bytes.unpack_le(bytes.read_at(object, file_offset, 1)?, 1, offset: 0)?

    if opcode == 233 {
      bytes.write_at(object, file_offset, bytes.from_ints([15, 31, 68, 0, 0])?)?
      patched += 1
    } else if opcode == 235 {
      bytes.write_at(object, file_offset, bytes.from_ints([102, 144])?)?
      patched += 1
    } else if ! file_has_bytes_at(object, file_offset, [15, 31, 68, 0, 0])? and ! file_has_bytes_at(
      object,
      file_offset,
      [102, 144],
    )? {
      return Err(
        ScriptError.Failed(
          "kbuild-x86-jump-label",
          f"${object.display()} unexpected jump-label opcode ${opcode} at ${orig.reloc.symbol}+${insn_offset}",
        ),
      )
    }

    let branch_rela = lookup_reloc(relocs, f".rela${orig.reloc.symbol}", insn_offset)

    if branch_rela.found {
      let reloc_file_offset = section_offset(sections, branch_rela.reloc.section)? + branch_rela.reloc.index * 24 + 8
      let symbol_index = branch_rela.reloc.info / 4294967296
      bytes.write_at(object, reloc_file_offset, bytes.pack_le(symbol_index * 4294967296, 8)?)?
    }
  }

  return patched
}

proc llvm_tool(names: List[Str], fallback: Path) [fs, process, error] -> Result[Path] {
  for name in names {
    match process.which(name) {
      Ok(tool) => return tool
      Err(_) => {}
    }
  }

  if fallback.exists()? {
    return fallback
  }

  return Err(ScriptError.Failed("kbuild-llvm-tool", f"missing ${names.join("/")}"))
}

proc x86_jump_label_helper_source() [fs, error] -> Result[Path] {
  if p"x86-jump-label-patch.c".exists()? {
    return p"x86-jump-label-patch.c"
  }

  if p"../pkg/files/x86-jump-label-patch.c".exists()? {
    return ../pkg/files/x86-jump-label-patch.c
  }

  return Err(ScriptError.Failed("kbuild-x86-jump-label-helper", "missing x86-jump-label-patch.c"))
}

proc x86_jump_label_helper() [fs, process, error] -> Result[Path] {
  let cc = process.which("cc")?
  let helper = p".xsh-kbuild/host/x86-jump-label-patch"
  let source = x86_jump_label_helper_source()?
  helper.parent.mkdir()?
  run $cc "-O2" "-std=c11" "-Wall" "-Wextra" "-o" $helper $source ?
  return helper
}

pure parse_jump_label_helper_summary(line: Str) -> JumpLabelPatchResult {
  let words = line.words()
  var scanned = 0
  var objects = 0
  var patches = 0
  var index = 0

  while index < words.len() {
    if index > 0 and words[index] == "objects" {
      scanned = words[index - 1].parse_int() ?? scanned
    }

    if index > 0 and words[index] == "patched-objects" {
      objects = words[index - 1].parse_int() ?? objects
    }

    if index > 0 and words[index] == "patches" {
      patches = words[index - 1].parse_int() ?? patches
    }

    index += 1
  }

  return {scanned, objects, patches}
}

export proc patch_x86_jump_label_outputs(outputs: List[Path]) [fs, process, error] -> Result[Record] {
  let helper = x86_jump_label_helper()?
  var argv = [output.display() for output in outputs if output.exists()?]
  archive_plan_progress(f"xsh-kbuild-x86-jump-label-scan start ${argv.len()} objects")?
  let output = run.text $helper @argv ?
  let summary = parse_jump_label_helper_summary(output.trim())

  archive_plan_progress(
    f"xsh-kbuild-x86-jump-label-scan complete ${summary.scanned} objects ${summary.patches} patches",
  )?

  return {scanned: summary.scanned, objects: summary.objects, patches: summary.patches}
}

pure has_archive_output(task: Record) -> Bool {
  for output in task.outputs {
    if output.display().ends_with(".a") {
      return true
    }
  }

  return false
}

pure archive_rerun_tasks(tasks: List[Record]) -> List[Record] {
  var archive_names: Map[Bool] = {}

  for task in tasks {
    if has_archive_output(task) {
      archive_names[task.name] = true
    }
  }

  var rerun: List[Record] = []

  for task in tasks {
    continue unless has_archive_output(task)
    var deps = [dep for dep in task.deps if archive_names.get(dep, false)]
    rerun = rerun.push({...task, deps})
  }

  return rerun
}

proc rerun_x86_jump_label_archives(tasks: List[Record], jobs_count: Int) [fs, process, env, error] {
  let archive_tasks = archive_rerun_tasks(tasks)
  archive_plan_progress(f"xsh-kbuild-x86-jump-label-archive-rerun start ${archive_tasks.len()} archives")?
  make.run_tasks(archive_tasks, jobs_count)?
  archive_plan_progress(f"xsh-kbuild-x86-jump-label-archive-rerun complete ${archive_tasks.len()} archives")?
}

export proc patch_x86_jump_label_archive_plan(archive_plan: Record, jobs_count: Int) [fs, process, env, error] {
  var outputs: List[Path] = []

  for task in archive_plan.tasks {
    for output in task.outputs {
      if output.display().ends_with(".o") {
        outputs = outputs.push(output)
      }
    }
  }

  let result = patch_x86_jump_label_outputs(outputs)?
  let objects: Int = result.get("objects")?
  let patches: Int = result.get("patches")?

  if patches > 0 {
    print "xsh-kbuild-x86-jump-label-nops" $patches "in" $objects "objects"
    rerun_x86_jump_label_archives(archive_plan.tasks, jobs_count)?
  }
}

export proc run_x86_builtin_archive_plan(
  archive_plan: Record,
  jobs_count: Int,
) [fs, process, env, error] -> Result[List[Path]] {
  let archives = run_builtin_archive_plan(archive_plan, jobs_count)?
  patch_x86_jump_label_archive_plan(archive_plan, jobs_count)?
  return archives
}

proc archive_plan_progress(message: Str) [fs, error] {
  write_text_if_changed(
    p".xsh-kbuild-progress",
    f"""${message}
""",
  )?
}

pure skip_planned_object(config: Kconfig, obj: Path) -> Bool {
  let key = path_key(obj)

  if key == "kernel/jump_label.o" and config_value(config, "JUMP_LABEL") != "y" {
    return true
  }

  if key == "arch/x86/kernel/jump_label.o" and config_value(config, "JUMP_LABEL") != "y" {
    return true
  }

  return false
}

export proc plan_builtin_archives(
  plan: KbuildPlan,
  cc: Path,
  triple: Str,
  cflags: List[Str],
  defs: List[Str],
  includes: List[Str],
) [fs, env, error] -> Result[BuiltinArchivePlan] {
  var tasks: List[make.MakeTask] = []
  var objects_by_dir: Map[List[Path]] = {}
  var deps_by_dir: Map[List[Str]] = {}
  var lib_objects_by_dir: Map[List[Path]] = {}
  var lib_deps_by_dir: Map[List[Str]] = {}
  var missing_sources: List[Path] = []
  var generated_objects: List[Path] = []
  var link_inputs: List[Path] = []
  var lib_link_inputs: List[Path] = []
  var pi_relacheck_added = false
  let composites_by_object = composite_map(plan.composites)
  let config = load_config(p".config")?

  let compile_flags_by_dir = cached_kbuild_compile_flags_for_dirs(
    p".",
    plan.dirs,
    config,
    if triple == "x86_64-linux-gnu" {
      "x86"
    } else {
      "arm64"
    },
  )?

  let composite_members_by_object = composite_member_map(plan.composites)
  var object_count = 0

  for obj in plan.objects {
    object_count += 1
    continue when skip_planned_object(config, obj)
    continue when composite_members_by_object.has(path_key(obj))

    if object_count % 100 == 0 {
      archive_plan_progress(
        f"xsh-kbuild-archive-plan objects ${object_count}/${plan.objects.len()} tasks=${tasks.len()}",
      )?
    }

    if is_pi_object(obj) {
      let source = pi_source(obj)

      if source.exists()? {
        if ! pi_relacheck_added {
          tasks = tasks.push(pi_relacheck_build_task(cc))
          pi_relacheck_added = true
        }

        let base_out = obj_out_path(pi_base_object(obj))

        let base_task = compile_kbuild_task(
          cc,
          triple,
          object_cflags(cflags, compile_flags_by_dir, pi_base_object(obj)),
          defs,
          includes,
          source,
          base_out,
        )

        let out = obj_out_path(obj)
        let task = pi_objcopy_task(cc, base_out, out, [base_task.name])

        let check_task = pi_relacheck_task(
          pi_relacheck_path(),
          out,
          base_out,
          [task.name, pi_relacheck_path().display()],
        )

        let dir_key = path_key(object_dir(obj))
        tasks = tasks.push(base_task).push(task).push(check_task)
        link_inputs = link_inputs.push(out)
        objects_by_dir[dir_key] = objects_by_dir.get(dir_key, []).push(out)
        deps_by_dir[dir_key] = deps_by_dir.get(dir_key, []).push(check_task.name)
      } else {
        generated_objects = generated_objects.push(obj)
      }

      continue
    }

    match composite_for_map(composites_by_object, obj) {
      Ok(composite) => {
        var member_outs: List[Path] = []
        var member_deps: List[Str] = []

        for member in composite.members {
          match source_for_object(member) {
            Ok(src) => {
              let member_out = obj_out_path(member)

              let member_task = compile_kbuild_task_for_module(
                cc,
                triple,
                object_cflags(cflags, compile_flags_by_dir, member),
                defs,
                includes,
                src,
                member_out,
                obj_out_path(composite.object),
              )

              tasks = tasks.push(member_task)
              member_outs = member_outs.push(member_out)
              member_deps = member_deps.push(member_task.name)
            }
            Err(err) => {
              match err {
                ScriptError.Failed {kind: kind, message: _} => {
                  if kind == "kbuild-missing-source" {
                    if is_known_generated_object(member) {
                      generated_objects = generated_objects.push(member)
                    } else {
                      missing_sources = missing_sources.push(member)
                    }
                  } else {
                    return Err(err)
                  }
                }
              }
            }
          }
        }

        if member_outs.len() > 0 {
          let dir_key = path_key(object_dir(obj))
          link_inputs = link_inputs.extend(member_outs)
          objects_by_dir[dir_key] = objects_by_dir.get(dir_key, []).extend(member_outs)
          deps_by_dir[dir_key] = deps_by_dir.get(dir_key, []).extend(member_deps)
        }
      }
      Err(_) => {
        match source_for_object(obj) {
          Ok(src) => {
            let out = obj_out_path(obj)

            let task = compile_kbuild_task(
              cc,
              triple,
              object_cflags(cflags, compile_flags_by_dir, obj),
              defs,
              includes,
              src,
              out,
            )

            let dir_key = path_key(object_dir(obj))
            tasks = tasks.push(task)
            link_inputs = link_inputs.push(out)
            objects_by_dir[dir_key] = objects_by_dir.get(dir_key, []).push(out)
            deps_by_dir[dir_key] = deps_by_dir.get(dir_key, []).push(task.name)
          }
          Err(err) => {
            match err {
              ScriptError.Failed {kind: kind, message: _} => {
                if kind == "kbuild-missing-source" {
                  let out = obj_out_path(obj)

                  if out.exists()? {
                    let dir_key = path_key(object_dir(obj))
                    link_inputs = link_inputs.push(out)
                    objects_by_dir[dir_key] = objects_by_dir.get(dir_key, []).push(out)
                  } else if is_known_generated_object(obj) {
                    generated_objects = generated_objects.push(obj)
                  } else {
                    missing_sources = missing_sources.push(obj)
                  }
                } else {
                  return Err(err)
                }
              }
            }
          }
        }
      }
    }
  }

  archive_plan_progress(f"xsh-kbuild-archive-plan objects-complete ${tasks.len()} tasks")?
  var lib_object_count = 0

  for obj in plan.lib_objects {
    lib_object_count += 1
    continue when composite_members_by_object.has(path_key(obj))

    if lib_object_count % 50 == 0 {
      archive_plan_progress(
        f"xsh-kbuild-archive-plan lib-objects ${lib_object_count}/${plan.lib_objects.len()} tasks=${tasks.len()}",
      )?
    }

    match composite_for_map(composites_by_object, obj) {
      Ok(composite) => {
        var member_outs: List[Path] = []
        var member_deps: List[Str] = []

        for member in composite.members {
          match source_for_object(member) {
            Ok(src) => {
              let member_out = obj_out_path(member)

              let member_task = compile_kbuild_task_for_module(
                cc,
                triple,
                object_cflags(cflags, compile_flags_by_dir, member),
                defs,
                includes,
                src,
                member_out,
                obj_out_path(composite.object),
              )

              tasks = tasks.push(member_task)
              member_outs = member_outs.push(member_out)
              member_deps = member_deps.push(member_task.name)
            }
            Err(err) => {
              match err {
                ScriptError.Failed {kind: kind, message: _} => {
                  if kind == "kbuild-missing-source" {
                    if is_known_generated_object(member) {
                      generated_objects = generated_objects.push(member)
                    } else {
                      missing_sources = missing_sources.push(member)
                    }
                  } else {
                    return Err(err)
                  }
                }
              }
            }
          }
        }

        if member_outs.len() > 0 {
          let dir_key = path_key(object_dir(obj))
          lib_link_inputs = lib_link_inputs.extend(member_outs)
          lib_objects_by_dir[dir_key] = lib_objects_by_dir.get(dir_key, []).extend(member_outs)
          lib_deps_by_dir[dir_key] = lib_deps_by_dir.get(dir_key, []).extend(member_deps)
        }
      }
      Err(_) => {
        match source_for_object(obj) {
          Ok(src) => {
            let out = obj_out_path(obj)

            let task = compile_kbuild_task(
              cc,
              triple,
              object_cflags(cflags, compile_flags_by_dir, obj),
              defs,
              includes,
              src,
              out,
            )

            let dir_key = path_key(object_dir(obj))
            tasks = tasks.push(task)
            lib_link_inputs = lib_link_inputs.push(out)
            lib_objects_by_dir[dir_key] = lib_objects_by_dir.get(dir_key, []).push(out)
            lib_deps_by_dir[dir_key] = lib_deps_by_dir.get(dir_key, []).push(task.name)
          }
          Err(err) => {
            match err {
              ScriptError.Failed {kind: kind, message: _} => {
                if kind == "kbuild-missing-source" {
                  let out = obj_out_path(obj)

                  if out.exists()? {
                    let dir_key = path_key(object_dir(obj))
                    lib_link_inputs = lib_link_inputs.push(out)
                    lib_objects_by_dir[dir_key] = lib_objects_by_dir.get(dir_key, []).push(out)
                  } else if is_known_generated_object(obj) {
                    generated_objects = generated_objects.push(obj)
                  } else {
                    missing_sources = missing_sources.push(obj)
                  }
                } else {
                  return Err(err)
                }
              }
            }
          }
        }
      }
    }
  }

  archive_plan_progress(f"xsh-kbuild-archive-plan lib-objects-complete ${tasks.len()} tasks")?
  var archives: List[Path] = []
  var children_by_dir: Map[List[Path]] = {}
  var dir_count = 0

  for dir in plan.dirs {
    dir_count += 1

    if dir_count % 100 == 0 {
      archive_plan_progress(f"xsh-kbuild-archive-plan children ${dir_count}/${plan.dirs.len()}")?
    }

    if path_key(dir) != "." {
      let parent = archive_parent_dir(dir)
      let parent_key = path_key(parent)
      children_by_dir[parent_key] = children_by_dir.get(parent_key, []).push(dir)
    }
  }

  var archive_needed: Map[Bool] = {}
  var dir_index = plan.dirs.len()

  while dir_index > 0 {
    dir_index -= 1
    let dir = plan.dirs[dir_index]
    let dir_key = path_key(dir)
    var needed = objects_by_dir.get(dir_key, []).len() > 0

    for child in children_by_dir.get(dir_key, []) {
      if archive_needed.get(path_key(child), false) {
        needed = true
      }
    }

    archive_needed[dir_key] = needed
  }

  archive_plan_progress("xsh-kbuild-archive-plan needed-complete")?
  var archive_dir_count = 0

  for dir in plan.dirs {
    archive_dir_count += 1

    if archive_dir_count % 100 == 0 {
      archive_plan_progress(
        f"xsh-kbuild-archive-plan archives ${archive_dir_count}/${plan.dirs.len()} tasks=${tasks.len()} archives=${archives.len()}",
      )?
    }

    let dir_key = path_key(dir)
    let lib_objs = lib_objects_by_dir.get(dir_key, [])

    if lib_objs.len() > 0 {
      let sorted_lib_objs = sorted_paths(lib_objs)
      let lib_archive = dir_lib_archive(dir)
      let lib_deps = lib_deps_by_dir.get(dir_key, [])
      tasks = tasks.push(vmlinux_archive_argv_task(["llvm-ar"], sorted_lib_objs, lib_archive, lib_deps))
      archives = archives.push(lib_archive)
    }

    var objs = objects_by_dir.get(dir_key, [])
    var deps = deps_by_dir.get(dir_key, [])

    for child in children_by_dir.get(dir_key, []) {
      if archive_needed.get(path_key(child), false) {
        let child_archive = dir_archive(child)

        let marker = if dir_key == "arch/arm64/kernel" and path_key(child) == "arch/arm64/kernel/pi" {
          p".xsh-kbuild/obj/arch/arm64/kernel/rsi.o"
        } else {
          p"."
        }

        let inserted = insert_archive_before(objs, deps, child_archive, child_archive.display(), marker)
        objs = inserted.objs
        deps = inserted.deps
      }
    }

    if archive_needed.get(dir_key, false) {
      let built_archive = dir_archive(dir)
      tasks = tasks.push(vmlinux_archive_argv_task(["llvm-ar"], objs, built_archive, deps))
      archives = archives.push(built_archive)
    }
  }

  var unique_tasks: List[make.MakeTask] = []
  var task_names: Map[Bool] = {}

  for task in tasks {
    if ! task_names.get(task.name, false) {
      unique_tasks = unique_tasks.push(task)
      task_names[task.name] = true
    }
  }

  archive_plan_progress(f"xsh-kbuild-archive-plan complete ${unique_tasks.len()} tasks ${archives.len()} archives")?

  return {
    tasks: unique_tasks,
    archives: archives,
    link_inputs: unique_paths(link_inputs.extend(lib_link_inputs)),
    missing_sources: missing_sources,
    generated_objects: generated_objects,
  }
}
