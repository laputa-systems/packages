pure xsh_bin() -> Path {
  return p"xsh"
}

pure m4_script() -> Path {
  return p"files/m4.xsh"
}

proc run_m4(argv: List[Str]) [process, error] -> Result[Str] {
  return run.text (xsh_bin()) (m4_script()) -- @argv ?
}

proc test_prefixed_define_rescans_expansion(ctx: TestContext) [fs, process, error] {
  let input = test.temp_file(ctx, name: "prefix.m4", contents: b"m4_define([GREETING],[hello])GREETING\n")?
  let output = run_m4(["-P", input.display()])?

  test.eq(
    output,
    """hello
""",
  )?
}

proc test_include_path_and_multiple_inputs(ctx: TestContext) [fs, process, error] {
  let root = test.temp_dir(ctx, name: "bison-style")?
  let inc = fp"${root}/m4sugar"
  inc.mkdir()

  fs.write(
    fp"${inc}/helpers.m4",
    """m4_define([b4_token],[$1])
""",
  )?

  let skeleton = test.temp_file(
    ctx,
    name: "skeleton.m4",
    contents: b"m4_include([helpers.m4])m4_divert(0)b4_token([NUMBER])\n",
  )?

  let grammar = test.temp_file(ctx, name: "grammar.m4", contents: b"m4_define([GRAMMAR],[ok])\n")?
  let output = run_m4(["-P", "-I", inc.display(), skeleton.display(), grammar.display()])?
  test.contains(output, "NUMBER")?
}

proc test_prefixed_dnl_is_available_without_prefix_mode(ctx: TestContext) [fs, process, error] {
  let input = test.temp_file(
    ctx,
    name: "flex-guard.m4",
    contents: b"m4_dnl ifdef(`__gnu__', ,`errprint(no) m4exit(2)')\nok\n",
  )?

  let output = run_m4([input.display()])?

  test.eq(
    output,
    """ok
""",
  )?
}

proc test_changequote_applies_to_remaining_stream(ctx: TestContext) [fs, process, error] {
  let input = test.temp_file(ctx, name: "changequote.m4", contents: b"changequote([[,]])[[ok]]\n")?
  let output = run_m4([input.display()])?

  test.eq(
    output,
    """ok
""",
  )?
}

proc test_changecom_without_args_disables_comments(ctx: TestContext) [fs, process, error] {
  let input = test.temp_file(ctx, name: "changecom.m4", contents: b"define(`NAME',`value')changecom`'dnl\n#line NAME\n")?
  let output = run_m4([input.display()])?

  test.eq(
    output,
    """#line value
""",
  )?
}

proc test_prefix_mode_leaves_bare_builtins_literal(ctx: TestContext) [fs, process, error] {
  let input = test.temp_file(ctx, name: "prefix-literal.m4", contents: b"#define X 1\nm4_define([[Y]], [[ok]])Y\n")?
  let output = run_m4(["-P", input.display()])?

  test.eq(
    output,
    """#define X 1
ok
""",
  )?
}

proc test_macro_arg_count_and_quoted_argv(ctx: TestContext) [fs, process, error] {
  let input = test.temp_file(
    ctx,
    name: "macro-argv.m4",
    contents: b"changequote([, ])define([show], [#$# star:$* at:$@])show([a], [b,c])\n",
  )?

  let output = run_m4([input.display()])?

  test.eq(
    output,
    """#2 star:a,b,c at:[a],[b,c]
""",
  )?
}

proc test_indir_calls_user_macro(ctx: TestContext) [fs, process, error] {
  let input = test.temp_file(
    ctx,
    name: "indir-user.m4",
    contents: b"changequote([, ])define([slot(name)], [ok:$1])indir([slot(name)], [value])\n",
  )?

  let output = run_m4([input.display()])?

  test.eq(
    output,
    """ok:value
""",
  )?
}

proc test_separate_define_flag_is_rescanned(ctx: TestContext) [fs, process, error] {
  let input = test.temp_file(ctx, name: "define-flag.m4", contents: b"FEATURE\n")?
  let output = run_m4(["-P", "-D", "FEATURE=m4_define([WORD],[ok])WORD", input.display()])?

  test.eq(
    output,
    """ok
""",
  )?
}

proc test_divert_undivert_and_m4wrap(ctx: TestContext) [fs, process, error] {
  let input = test.temp_file(
    ctx,
    name: "divert.m4",
    contents: b"m4_divert(1)side\nm4_divert(0)main\nm4_undivert(1)m4_m4wrap([tail])\n",
  )?

  let output = run_m4(["-P", input.display()])?
  test.contains(output, "main")?
  test.contains(output, "side")?
  test.contains(output, "tail")?
}
