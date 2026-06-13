use parser_gen

error LinuxLoopError = Failed(kind: Str, message: Str)

pure kconfig_objects() -> List[Str] {
  return [
    "conf",
    "confdata",
    "expr",
    "lexer.lex",
    "menu",
    "parser.tab",
    "preprocess",
    "symbol",
    "util",
  ]
}

pure dtc_objects() -> List[Str] {
  return [
    "dtc",
    "flattree",
    "fstree",
    "data",
    "livetree",
    "treesource",
    "srcpos",
    "checks",
    "util",
    "dtc-lexer.lex",
    "dtc-parser.tab",
  ]
}

proc run_argv(argv: List[Str]) [fs, process, error] {
  let status = process.run(process.command_argv(argv[0], argv, cwd: fs.cwd()?))?

  if ! status.ok {
    return Err(LinuxLoopError.Failed("linux-loop-command", f"command failed: ${argv.join(" ")}"))
  }
}

proc compile_one(src: Path, out: Path, includes: List[Str], defs: List[Str] = []) [fs, process, error] {
  var argv = ["cc"]

  for def in defs {
    argv = argv.push(def)
  }

  for include in includes {
    argv = argv.push("-I")
    argv = argv.push(include)
  }

  run_argv(argv.extend(["-c", src.display(), "-o", out.display()]))?
}

proc compile_generated_parsers() [fs, process, error] {
  compile_one(p"scripts/kconfig/parser.tab.c", /tmp/parser.o, ["scripts/include", "scripts/kconfig"])?
  compile_one(p"scripts/kconfig/lexer.lex.c", /tmp/lexer.o, ["scripts/include", "scripts/kconfig"])?
  compile_one(p"scripts/dtc/dtc-parser.tab.c", /tmp/dtc-parser.o, ["scripts/dtc", "scripts/dtc/libfdt"])?
  compile_one(p"scripts/dtc/dtc-lexer.lex.c", /tmp/dtc-lexer.o, ["scripts/dtc", "scripts/dtc/libfdt"])?
}

proc compile_named_objects(
  names: List[Str],
  tmp: Path,
  dir: Str,
  includes: List[Str],
  defs: List[Str] = [],
) [fs, process, error] -> Result[List[Str]] {
  var objs: List[Str] = []

  for name in names {
    let out = fp"${tmp}/${name}.o"
    compile_one(Path.parse(f"${dir}/${name}.c")?, out, includes, defs)?
    objs = objs.push(out.display())
  }

  return objs
}

proc build_kconfig_conf(tmp: Path) [fs, process, error] -> Result[Path] {
  let objs = compile_named_objects(kconfig_objects(), tmp, "scripts/kconfig", ["scripts/include", "scripts/kconfig"])?
  let out = fp"${tmp}/conf"
  run_argv(["cc"].extend(objs).extend(["-o", out.display()]))?
  return out
}

proc assert_contains(path_value: Path, needle: Str) [fs, error] {
  if ! path_value.read_text()?.contains(needle) {
    return Err(LinuxLoopError.Failed("linux-loop-proof", f"${path_value.display()} does not contain ${needle}"))
  }
}

proc prove_kconfig(generate: Bool = true) [fs, process, env, error] {
  if generate {
    parser_gen.generate_kconfig_parsers()?
  }

  let tmp_root = fs.tempdir()?
  defer fs.close_root(tmp_root)?
  let tmp = fs.root_path(tmp_root)?
  let sub = fp"${tmp}/sub"
  sub.mkdir()
  let conf = build_kconfig_conf(tmp)?
  fs.remove(p".config", missing_ok: true)?

  fs.write(
    fp"${tmp}/Kconfig",
    """source "$(SUBKCONFIG)"
menu "Native subset"
config FOO
	bool "foo"
	default y
config SELECTED
	bool
config SELECTOR
	bool "selector"
	default y
	select SELECTED if FOO
config DEFBOOL
	bool "defbool"
	def_bool y
endmenu
""",
  )?

  fs.write(
    fp"${sub}/Kconfig",
    """config FROM_SOURCE
	bool "from source"
	depends on FOO
	default y
	help
	  this help mentions default n and depends on MISSING but is prose
""",
  )?

  let command = process.command_argv(
    conf,
    [conf.display(), "--defconfig=/dev/null", fp"${tmp}/Kconfig".display()],
    cwd: fs.cwd()?,
    env: {SUBKCONFIG: fp"${sub}/Kconfig".display()},
  )

  let status = process.run(command)?

  if ! status.ok {
    return Err(LinuxLoopError.Failed("linux-loop-kconfig-proof", "conf proof command failed"))
  }

  assert_contains(p".config", "CONFIG_FOO=y")?
  assert_contains(p".config", "CONFIG_FROM_SOURCE=y")?
  assert_contains(p".config", "CONFIG_SELECTOR=y")?
  assert_contains(p".config", "CONFIG_DEFBOOL=y")?
}

proc build_dtc(tmp: Path) [fs, process, error] -> Result[Path] {
  let objs = compile_named_objects(
    dtc_objects(),
    tmp,
    "scripts/dtc",
    ["scripts/dtc", "scripts/dtc/libfdt"],
    ["-DNO_YAML"],
  )?

  let out = fp"${tmp}/dtc"
  run_argv(["cc"].extend(objs).extend(["-o", out.display()]))?
  return out
}

proc prove_dtc(generate: Bool = true) [fs, process, env, error] {
  if generate {
    parser_gen.generate_dtc_parsers()?
  }

  let tmp_root = fs.tempdir()?
  defer fs.close_root(tmp_root)?
  let tmp = fs.root_path(tmp_root)?
  let dtc = build_dtc(tmp)?
  let source = fp"${tmp}/t.dts"
  let out_dts = fp"${tmp}/t.out.dts"
  let out_dtb = fp"${tmp}/t.dtb"

  fs.write(
    source,
    """/dts-v1/;
/ {
	compatible = "xsh,test";
	#address-cells = <1>;
	#size-cells = <0>;
	status = "okay";
	child@0 {
		compatible = "xsh,child";
		reg = <0>;
	};
};
""",
  )?

  run_argv(
    [
      dtc.display(),
      "-I",
      "dts",
      "-O",
      "dts",
      "-o",
      out_dts.display(),
      source.display(),
    ],
  )?

  assert_contains(out_dts, "compatible = \"xsh,test\"")?
  assert_contains(out_dts, "child@0")?
  assert_contains(out_dts, "reg = <0x00>")?

  run_argv(
    [
      dtc.display(),
      "-I",
      "dts",
      "-O",
      "dtb",
      "-o",
      out_dtb.display(),
      source.display(),
    ],
  )?

  if ! out_dtb.exists()? or out_dtb.metadata()?.size == 0 {
    return Err(LinuxLoopError.Failed("linux-loop-dtc-proof", "dtc proof did not write a non-empty dtb"))
  }
}

proc parser_loop_all() [fs, process, env, error] {
  parser_gen.generate_linux_parsers()?
  compile_generated_parsers()?
  prove_kconfig(false)?
  prove_dtc(false)?
}

proc usage() [error] {
  return Err(
    LinuxLoopError.Failed(
      "linux-loop-usage",
      "usage: linux-loop.xsh <bison-kconfig|flex-kconfig|bison-dtc|flex-dtc|compile|kconfig-proof|dtc-proof|parser-loop-all>",
    ),
  )
}

proc main(argv: List[Str] = []) [fs, process, env, error] {
  if argv.len() != 1 {
    usage()?
  }

  match argv[0] {
    "bison-kconfig" => parser_gen.generate_parser("bison-kconfig")?
    "flex-kconfig" => parser_gen.generate_parser("flex-kconfig")?
    "bison-dtc" => parser_gen.generate_parser("bison-dtc")?
    "flex-dtc" => parser_gen.generate_parser("flex-dtc")?
    "compile" => compile_generated_parsers()?
    "kconfig-proof" => prove_kconfig()?
    "dtc-proof" => prove_dtc()?
    "parser-loop-all" => parser_loop_all()?
    _ => usage()?
  }
}

main(args)?
