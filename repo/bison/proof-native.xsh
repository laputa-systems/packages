error ScriptError = Failed(kind: Str, message: Str)

proc ensure(condition: Bool, kind: Str, message: Str) [error] {
  if ! condition {
    Err(ScriptError.Failed(kind, message))?
  }
}

proc read_if_exists(file_path: Path) [fs, error] -> Result[Str] {
  if fs.exists(file_path)? {
    return fs.read_text(file_path)?
  }

  return ""
}

proc ensure_status_ok(status: Status, label: Str, err_path: Path, artifacts: Path) [fs, error] {
  if ! status.ok {
    let err = read_if_exists(err_path)?.trim()
    Err(ScriptError.Failed(label, f"failed; artifacts=${artifacts.display()} stderr=${err}"))?
  }
}

proc ensure_output_contains(file_path: Path, needle: Str, label: Str, artifacts: Path) [fs, error] {
  let body = read_if_exists(file_path)?

  if needle not in body {
    Err(ScriptError.Failed(label, f"missing '${needle}'; artifacts=${artifacts.display()} output=${body.trim()}"))?
  }
}

proc run_m4sugar_case(
  label: Str,
  m4_bin: Path,
  bison_data: Path,
  artifacts: Path,
  input_text: Str,
  expected: Str,
) [fs, process, error] {
  let input = fp"${artifacts}/${label}.m4"
  let out = fp"${artifacts}/${label}.out"
  let err = fp"${artifacts}/${label}.err"
  fs.write(input, input_text)?
  let status = run.status $m4_bin "--gnu" "-I" $bison_data fp"${bison_data}/m4sugar/m4sugar.m4" $input > $out 2> $err
  ensure_status_ok(status, label, err, artifacts)?
  ensure_output_contains(out, expected, label, artifacts)?
}

proc run_m4_case(label: Str, m4_bin: Path, artifacts: Path, input_text: Str, expected: Str) [fs, process, error] {
  let input = fp"${artifacts}/${label}.m4"
  let out = fp"${artifacts}/${label}.out"
  let err = fp"${artifacts}/${label}.err"
  fs.write(input, input_text)?
  let status = run.status $m4_bin "--gnu" $input > $out 2> $err
  ensure_status_ok(status, label, err, artifacts)?
  ensure_output_contains(out, expected, label, artifacts)?
}

proc run_tiny_bison(build_env: Path, bison_data: Path, artifacts: Path) [fs, process, env, error] {
  let bison = fp"${build_env}/usr/bin/bison"
  let grammar = fp"${artifacts}/tiny.y"
  let out = fp"${artifacts}/tiny-bison.out"
  let err = fp"${artifacts}/tiny-bison.err"

  fs.write(
    grammar,
    """%define api.prefix {proof}
%token WORD
%%
start:
  WORD
;
%%
""",
  )?

  env {
    BISON_PKGDATADIR = bison_data.display()
    PATH = f"${build_env}/usr/bin:/usr/bin:/bin"
  } {
    let status = run.status --timeout=10s $bison "--feature=syntax-only" $grammar > $out 2> $err
    ensure_status_ok(status, "tiny-bison", err, artifacts)?
  } ?
}

proc main(build_env: Path = /build-env, artifacts: Path = /tmp/laputa-native-m4-bison-proof) [fs, process, env, error] {
  let m4_bin = /usr/bin/m4
  let packaged_m4 = fp"${build_env}/usr/bin/m4"
  let bison_data = fp"${build_env}/usr/share/bison"
  ensure(fs.exists(m4_bin)?, "native-m4-bison", "missing /usr/bin/m4")?
  ensure(fs.exists(packaged_m4)?, "native-m4-bison", f"missing packaged m4: ${packaged_m4.display()}")?
  ensure(fs.exists(bison_data)?, "native-m4-bison", f"missing bison data: ${bison_data.display()}")?
  artifacts.remove(missing_ok: true)?
  fs.mkdir(artifacts)?

  run_m4sugar_case(
    "m4sugar-copy-rename",
    m4_bin,
    bison_data,
    artifacts,
    """m4_divert(0)dnl
m4_copy([m4_define], [define_alias])
define_alias([WORD], [copy-ok])
m4_rename([WORD], [RENAMED])
RENAMED
""",
    "copy-ok",
  )?

  run_m4_case(
    "bison-percent-define",
    m4_bin,
    artifacts,
    """changequote([,])dnl
define([b4_percent_define_default], [])dnl
define([b4_percent_define_flag_if], [])dnl
b4_percent_define_default([parse.trace], [false])
b4_percent_define_flag_if([parse.trace], [yes], [no])
b4_percent_define_default([api.token.raw], [true])
b4_percent_define_flag_if([api.token.raw], [raw], [cooked])
""",
    "raw",
  )?

  run_m4_case(
    "bison-cat-syscmd",
    m4_bin,
    artifacts,
    """changequote([,])dnl
define([b4_cat], [syscmd([cat <<'_m4eof'
$1@
_m4eof
])])dnl
b4_cat([[hello from b4_cat]])
""",
    "[hello from b4_cat]@",
  )?

  run_tiny_bison(build_env, bison_data, artifacts)?
  print f"native m4/bison ok: artifacts=${artifacts.display()}"
}

main(@args)?
