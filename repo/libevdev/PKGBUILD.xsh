use pm.meson as pm_meson

export let name: Str = "libevdev"

export let ver: Str = "1.13.6"

export let rel: Str = "3"

export let deps: List[Str] = ["musl", "linux"]

export let mkdeps: List[Str] = ["llvm-toolchain", "linux", "muon", "pkgconf"]

export let sources: List[Path] = [p"https://gitlab.freedesktop.org/libevdev/libevdev/-/archive/libevdev-VERSION/libevdev-libevdev-VERSION.tar.gz"]

export let checksums: List[Str] = ["54748fded25633399a8418d7c4c123fe365037c901b4389e0bf3dd7688fb1c7e"]

type EventDef = {attr: Str, value: Int, name: Str}

pure event_prefixes() -> List[Str] {
  [
    "EV_",
    "REL_",
    "ABS_",
    "KEY_",
    "BTN_",
    "LED_",
    "SND_",
    "MSC_",
    "SW_",
    "FF_",
    "SYN_",
    "REP_",
    "INPUT_PROP_",
    "MT_TOOL_",
  ]
}

pure code_prefixes() -> List[Str] {
  [
    "ABS_",
    "BTN_",
    "FF_",
    "KEY_",
    "LED_",
    "MSC_",
    "REL_",
    "REP_",
    "SND_",
    "SW_",
    "SYN_",
  ]
}

pure duplicate_defines() -> List[Str] {
  [
    "EV_VERSION",
    "BTN_MISC",
    "BTN_MOUSE",
    "BTN_JOYSTICK",
    "BTN_GAMEPAD",
    "BTN_DIGI",
    "BTN_WHEEL",
    "BTN_TRIGGER_HAPPY",
    "SW_MAX",
    "REP_MAX",
  ]
}

pure attr_name(prefix: Str) -> Str {
  prefix.replace("_", "").replace("INPUTPROP", "input_prop").replace("MTTOOL", "mt_tool").replace("EV", "ev").replace(
    "REL",
    "rel",
  ).replace("ABS", "abs").replace("KEY", "key").replace("BTN", "btn").replace("LED", "led").replace("SND", "snd").replace(
    "MSC",
    "msc",
  ).replace("SW", "sw").replace("FF", "ff").replace("SYN", "syn").replace("REP", "rep")
}

pure lookup_prefix(event_name: Str) -> Str {
  event_name.replace("EV_", "")
}

pure has_event_prefix(prefix: Str) -> Bool {
  f"${prefix}_" in event_prefixes()
}

proc c_lines_for_bits(defs: List[EventDef], attr: Str, max_name: Str, include_buttons: Bool) [] -> Result[List[Str]] {
  var lines = [f"static const char * const ${attr}_map[${max_name} + 1] = {"]

  for item in defs
    |> where .attr == attr
    |> sort-by .value {
    lines = lines.push(f"    [${item.name}] = \"${item.name}\",")
  }

  if include_buttons {
    for item in defs
      |> where .attr == "btn"
      |> sort-by .value {
      lines = lines.push(f"    [${item.name}] = \"${item.name}\",")
    }
  }

  return lines.push("};").push("")
}

proc c_lookup_lines(
  defs: List[EventDef],
  attr: Str,
  include_button_aliases: Bool,
  max_codes: Map[Int],
) [] -> Result[List[Str]] {
  var lookups = [{name: item.name, value: item.name} for item in defs
    |> where .attr == attr
    |> sort-by .name]

  if include_button_aliases {
    lookups = lookups.push({name: "BTN_A", value: "BTN_A"})
    lookups = lookups.push({name: "BTN_B", value: "BTN_B"})
    lookups = lookups.push({name: "BTN_X", value: "BTN_X"})
    lookups = lookups.push({name: "BTN_Y", value: "BTN_Y"})
  }

  let max_name = f"${attr.replace("input_prop", "INPUT_PROP").replace("mt_tool", "MT_TOOL").replace("ev", "EV").replace(
    "rel",
    "REL",
  ).replace("abs", "ABS").replace("key", "KEY").replace("btn", "BTN").replace("led", "LED").replace("snd", "SND").replace(
    "msc",
    "MSC",
  ).replace("sw", "SW").replace("ff", "FF").replace("syn", "SYN").replace("rep", "REP")}_MAX"

  if max_name in duplicate_defines() and max_codes.has(max_name) {
    lookups = lookups.push({name: max_name, value: max_name})
  }

  [f"    { .name = \"${item.name}\", .value = ${item.value} }," for item in lookups |> sort-by .name]
}

proc collect_event_defs(path_value: Path) [fs, error] -> Result[Record] {
  var defs: List[EventDef] = []
  var max_codes: Map[Int] = {}

  for line in path_value.read_text()?.split("\n") {
    let words = line.words()

    if words.len() >= 3 and words[0] == "#define" {
      let event_name = words[1]
      let value = words[2].parse_int() ?? -1

      if value >= 0 {
        for prefix in event_prefixes() {
          if event_name.starts_with(prefix) {
            if event_name.ends_with("_MAX") {
              max_codes[event_name] = value
            }

            if ! (event_name in duplicate_defines()) {
              defs = defs.push({attr: attr_name(prefix), value, name: event_name})
            }
          }
        }
      }
    }
  }

  {defs, max_codes}
}

proc write_event_names() [fs, error] {
  let input_h = p"include/linux/linux/input.h"
  let input_event_codes_h = p"include/linux/linux/input-event-codes.h"
  let first: Record = collect_event_defs(input_h)?
  let second: Record = collect_event_defs(input_event_codes_h)?
  let first_defs: List[EventDef] = first.defs
  let second_defs: List[EventDef] = second.defs
  var defs = first_defs.extend(second_defs)
  var max_codes: Map[Int] = first.max_codes
  let second_max: Map[Int] = second.max_codes

  for key in [
    "EV_MAX",
    "REL_MAX",
    "ABS_MAX",
    "KEY_MAX",
    "LED_MAX",
    "SND_MAX",
    "MSC_MAX",
    "SW_MAX",
    "FF_MAX",
    "SYN_MAX",
    "REP_MAX",
    "INPUT_PROP_MAX",
    "MT_TOOL_MAX",
  ] {
    if second_max.has(key) {
      max_codes[key] = second_max.get(key)?
    }
  }

  var lines: List[Str] = [
    "/* THIS FILE IS GENERATED, DO NOT EDIT */",
    "",
    "#ifndef EVENT_NAMES_H",
    "#define EVENT_NAMES_H",
    "",
  ]

  lines = lines.extend(c_lines_for_bits(defs, "ev", "EV_MAX", false)?)
  lines = lines.extend(c_lines_for_bits(defs, "rel", "REL_MAX", false)?)
  lines = lines.extend(c_lines_for_bits(defs, "abs", "ABS_MAX", false)?)
  lines = lines.extend(c_lines_for_bits(defs, "key", "KEY_MAX", true)?)
  lines = lines.extend(c_lines_for_bits(defs, "led", "LED_MAX", false)?)
  lines = lines.extend(c_lines_for_bits(defs, "snd", "SND_MAX", false)?)
  lines = lines.extend(c_lines_for_bits(defs, "msc", "MSC_MAX", false)?)
  lines = lines.extend(c_lines_for_bits(defs, "sw", "SW_MAX", false)?)
  lines = lines.extend(c_lines_for_bits(defs, "ff", "FF_MAX", false)?)
  lines = lines.extend(c_lines_for_bits(defs, "syn", "SYN_MAX", false)?)
  lines = lines.extend(c_lines_for_bits(defs, "rep", "REP_MAX", false)?)
  lines = lines.extend(c_lines_for_bits(defs, "input_prop", "INPUT_PROP_MAX", false)?)
  lines = lines.extend(c_lines_for_bits(defs, "mt_tool", "MT_TOOL_MAX", false)?)
  lines = lines.push("static const char * const * const event_type_map[EV_MAX + 1] = {")

  for prefix in event_prefixes() {
    if ! (prefix == "BTN_" or prefix == "EV_" or prefix == "INPUT_PROP_" or prefix == "MT_TOOL_") {
      let key = prefix.replace("_", "")

      let map_name = prefix.replace("_", "").replace("REL", "rel").replace("ABS", "abs").replace("KEY", "key").replace(
        "LED",
        "led",
      ).replace("SND", "snd").replace("MSC", "msc").replace("SW", "sw").replace("FF", "ff").replace("SYN", "syn").replace(
        "REP",
        "rep",
      )

      lines = lines.push(f"    [EV_${key}] = ${map_name}_map,")
    }
  }

  lines = lines.push("};").push("")
  lines = lines.push("#if __clang__")
  lines = lines.push("#pragma clang diagnostic push")
  lines = lines.push("#pragma clang diagnostic ignored \"-Winitializer-overrides\"")
  lines = lines.push("#elif __GNUC__")
  lines = lines.push("#pragma GCC diagnostic push")
  lines = lines.push("#pragma GCC diagnostic ignored \"-Woverride-init\"")
  lines = lines.push("#endif")
  lines = lines.push("static const int ev_max[EV_MAX + 1] = {")
  var index = 0
  let ev_max = max_codes.get("EV_MAX", 31)

  while index <= ev_max {
    var emitted = false

    for item in defs |> where .attr == "ev" {
      if item.value == index {
        let prefix = lookup_prefix(item.name)

        if has_event_prefix(prefix) {
          lines = lines.push(f"    ${prefix}_MAX,")
          emitted = true
        }
      }
    }

    if ! emitted {
      lines = lines.push("    -1,")
    }

    index += 1
  }

  lines = lines.push("};")
  lines = lines.push("#if __clang__")
  lines = lines.push("#pragma clang diagnostic pop /* \"-Winitializer-overrides\" */")
  lines = lines.push("#elif __GNUC__")
  lines = lines.push("#pragma GCC diagnostic pop /* \"-Winitializer-overrides\" */")
  lines = lines.push("#endif")
  lines = lines.push("")
  lines = lines.push("struct name_entry {")
  lines = lines.push("    const char *name;")
  lines = lines.push("    unsigned int value;")
  lines = lines.push("};")
  lines = lines.push("")
  lines = lines.push("static const struct name_entry tool_type_names[] = {")
  lines = lines.extend(c_lookup_lines(defs, "mt_tool", false, max_codes)?)
  lines = lines.push("};").push("")
  lines = lines.push("static const struct name_entry ev_names[] = {")
  lines = lines.extend(c_lookup_lines(defs, "ev", false, max_codes)?)
  lines = lines.push("};").push("")
  lines = lines.push("static const struct name_entry code_names[] = {")

  for prefix in code_prefixes() {
    lines = lines.extend(c_lookup_lines(defs, attr_name(prefix), prefix == "BTN_", max_codes)?)
  }

  lines = lines.push("};").push("")
  lines = lines.push("static const struct name_entry prop_names[] = {")
  lines = lines.extend(c_lookup_lines(defs, "input_prop", false, max_codes)?)
  lines = lines.push("};").push("")
  lines = lines.push("#endif /* EVENT_NAMES_H */")
  fs.write(p"event-names.h", lines.join("\n"))?
}

proc patch_python_generator() [fs, error] {
  write_event_names()?
  let meson = p"meson.build"
  var text = meson.read_text()?

  text = text.replace(
    """# event-names.h
make_event_names = find_program('libevdev/make-event-names.py')
event_names_h = configure_file(input: 'libevdev/libevdev.h',
			       output: 'event-names.h',
			       command: [make_event_names, input_h, input_event_codes_h],
			       capture: true)
""",
    """# event-names.h
event_names_h = files('event-names.h')
""",
  )

  text = text.replace(
    "dep_lm = cc.find_library('m')",
    """# musl packages libm as a libc symlink; link by name instead of recording the build-env path.
dep_lm = declare_dependency(link_args: ['-lm'])""",
  )

  text = text.replace(
    "dep_rt = cc.find_library('rt')",
    """# musl provides realtime interfaces in libc; avoid recording the build-env librt.
dep_rt = declare_dependency()""",
  )

  meson.write_atomic(text)?
}

export proc build(dest: Path) [fs, process, env, error] {
  let muon = process.which("muon")?
  let jobs_flag = f"-j${cpu.count()}"
  let pc = pm_meson.pkg_config_env()?
  patch_python_generator()?

  env {
    LD_LIBRARY_PATH = pc.ld_library_path
    PKG_CONFIG = pc.pkg_config
    PKG_CONFIG_LIBDIR = pc.pkg_config_libdir
    PKG_CONFIG_PATH = pc.pkg_config_path
    PKG_CONFIG_SYSROOT_DIR = pc.pkg_config_sysroot
  } {
    run $muon "setup" "-Dprefix=/usr" "-Dlibdir=lib" "-Ddefault_library=shared" "-Dtests=disabled" "-Dtools=disabled" "-Ddocumentation=disabled" "-Dcoverity=false" "build" ?
    run $muon "-C" "build" samu $jobs_flag ?

    env {
      DESTDIR = dest.display()
    } {
      run $muon "-C" "build" install ?
    } ?
  } ?

  fs.remove(fp"${dest}/usr/share/man", missing_ok: true)?
}
