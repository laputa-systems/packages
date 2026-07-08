export error PrivateNeededError = MissingPrivate(message: Str)

export type PrivateNeededEntry = {path: Path, soname: Str, resolved: Path}

export type PrivateNeededFile = {path: Path, needed: List[PrivateNeededEntry]}

export type PrivateNeededReport = {
  root: Path,
  private_library_root: Path,
  files: List[PrivateNeededFile],
  private_sonames: List[Str],
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

pure sorted_keys(values: Map[Path]) -> List[Str] {
  values.keys() |> sort-by .
}

proc private_sonames(root: Path) [fs, error] -> Result[Map[Path]] {
  var sonames: Map[Path] = {}

  for entry in fs.walk(root, gitignore: false)? |> where .kind == "file" {
    if is_elf_candidate(entry.name, entry.executable) {
      let info = elf.inspect(entry.path)?

      if info.type != "not-elf" {
        sonames[entry.name] = entry.path

        if info.soname != "" {
          sonames[info.soname] = entry.path
        }
      }
    }
  }

  sonames
}

export proc verify_private_needed(
  root: Path,
  allowed_external_sonames: Path,
  private_library_root: Path,
) [fs, error] -> Result[PrivateNeededReport] {
  let allowed = clean_lines(allowed_external_sonames.read_text()?)
  let private = private_sonames(private_library_root)?
  var files = []

  for entry in fs.walk(root, gitignore: false)? |> where .kind == "file" {
    if is_elf_candidate(entry.name, entry.executable) {
      let info = elf.inspect(entry.path)?

      if info.type != "not-elf" {
        var needed = []

        for soname in info.needed {
          if soname not in allowed {
            if ! private.has(soname) {
              return Err(
                PrivateNeededError.MissingPrivate(
                  f"${entry.path.display()} needs ${soname}, but it is not provided under ${private_library_root.display()}",
                ),
              )
            }

            let resolved: Path = private.get(soname)?
            needed = needed.push({path: entry.path, soname, resolved})
          }
        }

        if needed.len() > 0 {
          files = files.push({path: entry.path, needed})
        }
      }
    }
  }

  let report: PrivateNeededReport = {root, private_library_root, files, private_sonames: sorted_keys(private)}

  let json_files = files
    |> map { |file|
      {
        path: file.path.display(),
        needed: file.needed
          |> map { |item|
            {path: item.path.display(), soname: item.soname, resolved: item.resolved.display()}
          },
      }
    }

  let json_report = {
    root: root.display(),
    private_library_root: private_library_root.display(),
    files: json_files,
    private_sonames: report.private_sonames,
  }

  print (json.encode(json_report, pretty: true)?)
  report
}
