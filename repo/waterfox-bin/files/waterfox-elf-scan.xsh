export error WaterfoxScanError = UnexpectedExternal(message: Str) | RejectedSoname(message: Str) | PackedRelocations(message: Str)

export type ElfFileReport = {
  path: Path,
  interpreter: Str,
  soname: Str,
  needed: List[Str],
  rpath: Str,
  runpath: Str,
  dynamic_tags: List[ElfDynamicTag],
}

export type ElfScanReport = {
  root: Path,
  private_library_root: Path,
  files: List[ElfFileReport],
  sonames: List[Str],
  external: List[Str],
}

pure is_elf_candidate(name: Str, executable: Bool) -> Bool {
  executable or name.ends_with(".so") or ".so." in name
}

pure clean_lines(text: Str) -> List[Str] {
  text.lines()
    |> map .trim()
    |> where . != ""
    |> sort-by .
}

pure sorted_keys(values: Map[Bool]) -> List[Str] {
  values.keys() |> sort-by .
}

proc private_sonames(root: Path) [fs, error] -> Result[Map[Bool]] {
  var sonames: Map[Bool] = {}

  for entry in fs.walk(root, gitignore: false)? |> where .kind == "file" {
    if is_elf_candidate(entry.name, entry.executable) {
      let info = elf.inspect(entry.path)?

      if info.type != "not-elf" {
        sonames[entry.name] = true

        if info.soname != "" {
          sonames[info.soname] = true
        }
      }
    }
  }

  sonames
}

export proc scan_waterfox_elf(
  root: Path,
  allowed_external_sonames: Path,
  private_library_root: Path,
  reject_pattern: Str,
) [fs, error] -> Result[ElfScanReport] {
  let allowed = clean_lines(allowed_external_sonames.read_text()?)
  let private = private_sonames(private_library_root)?
  let reject = regex.compile(reject_pattern)?
  var files = []
  var all_sonames: Map[Bool] = {}
  var external: Map[Bool] = {}

  for entry in fs.walk(root, gitignore: false)? |> where .kind == "file" {
    if is_elf_candidate(entry.name, entry.executable) {
      let info = elf.inspect(entry.path)?

      if info.type != "not-elf" {
        for tag in info.dynamic_tags {
          if tag.tag == "DT_ANDROID_REL" or tag.tag == "DT_ANDROID_RELSZ" or tag.tag == "DT_ANDROID_RELA" or tag.tag == "DT_ANDROID_RELASZ" {
            return Err(WaterfoxScanError.PackedRelocations(f"${entry.path.display()} contains ${tag.tag}"))
          }
        }

        for soname in info.needed {
          all_sonames[soname] = true

          if reject.matches(soname) {
            return Err(WaterfoxScanError.RejectedSoname(f"${entry.path.display()} needs rejected ${soname}"))
          }

          if ! private.get(soname, false) and soname not in allowed {
            external[soname] = true
          }
        }

        files = files.push({
          path: entry.path,
          interpreter: info.interpreter,
          soname: info.soname,
          needed: info.needed,
          rpath: info.rpath,
          runpath: info.runpath,
          dynamic_tags: info.dynamic_tags,
        })
      }
    }
  }

  let external_names = sorted_keys(external)

  if external_names.len() > 0 {
    return Err(WaterfoxScanError.UnexpectedExternal(f"unexpected external sonames: ${external_names.join(", ")}"))
  }

  let report: ElfScanReport = {
    root,
    private_library_root,
    files,
    sonames: sorted_keys(all_sonames),
    external: external_names,
  }

  let json_files = files
    |> map { |file|
      {
        path: file.path.display(),
        interpreter: file.interpreter,
        soname: file.soname,
        needed: file.needed,
        rpath: file.rpath,
        runpath: file.runpath,
        dynamic_tags: file.dynamic_tags,
      }
    }

  let json_report = {
    root: root.display(),
    private_library_root: private_library_root.display(),
    files: json_files,
    sonames: report.sonames,
    external: report.external,
  }

  print (json.encode(json_report, pretty: true)?)
  report
}
