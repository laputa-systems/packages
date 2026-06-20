# Generates a config.h from a config.h.in by processing autoconf #undef lines.
#
# defines maps variable name → C token (e.g. "1", "0", "\"pkgconf\"").
# Lines of the form '#undef VAR' are replaced:
#   - VAR in defines → '#define VAR value'
#   - VAR not in defines → '/* #undef VAR */'
# All other lines (comments, '/* #undef */' commented forms, blank) pass through.
export proc config_h(in_path: Path, out_path: Path, defines: Map[Str]) [fs, error] -> Result[Unit] {
  let content = fs.read_text(in_path)?
  let lines = content.split("\n")
  var out_lines: List[Str] = []

  for line in lines {
    if line.starts_with("#undef ") {
      let varname = line.replace("#undef ", "").trim()

      if defines.has(varname) {
        let value: Str = defines.get(varname)?
        out_lines = out_lines.push(f"#define ${varname} ${value}")
      } else {
        out_lines = out_lines.push(f"/* #undef ${varname} */")
      }
    } else {
      out_lines = out_lines.push(line)
    }
  }

  fs.mkdir(out_path.parent)?
  fs.write(out_path, out_lines.join("\n"))?
}

# Substitutes @VAR@ placeholders in an autoconf .in file and writes the result.
# vars is a list of [name, value] pairs; name is the placeholder without @.
# Unknown @VAR@ tokens are left as-is.
export proc substitute(in_path: Path, out_path: Path, vars: List[List[Str]]) [fs, error] -> Result[Unit] {
  var content = fs.read_text(in_path)?

  for pair in vars {
    let key = pair[0]
    let value = pair[1]
    content = content.replace(f"@${key}@", value)
  }

  fs.mkdir(out_path.parent)?
  fs.write(out_path, content)?
}
