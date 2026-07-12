error ParserGenError = Failed(kind: Str, message: Str)

export type ParserGen = {name: Str, tool: Path, argv: List[Str], outputs: List[Path]}

export proc bison_tool() [env, error] -> Result[Path] {
  let root = env.get("XSH_PM_BUILD_ROOT") ?? env.get("LAPUTA_ROOT") ?? ""

  if root != "" {
    return fp"${root}/usr/lib/pm/repo/bison/files/bison.xsh"
  }

  return /usr/lib/pm/repo/bison/files/bison.xsh
}

export proc flex_tool() [env, error] -> Result[Path] {
  let root = env.get("XSH_PM_BUILD_ROOT") ?? env.get("LAPUTA_ROOT") ?? ""

  if root != "" {
    return fp"${root}/usr/lib/pm/repo/flex/files/flex.xsh"
  }

  return /usr/lib/pm/repo/flex/files/flex.xsh
}

export proc parser_generators() [env, error] -> Result[List[ParserGen]] {
  return [
    {
      name: "bison-kconfig",
      tool: bison_tool()?,
      argv: [
        "-o",
        "scripts/kconfig/parser.tab.c",
        "--defines=scripts/kconfig/parser.tab.h",
        "-t",
        "-l",
        "scripts/kconfig/parser.y",
      ],
      outputs: [
        p"scripts/kconfig/parser.tab.c",
        p"scripts/kconfig/parser.tab.h",
      ],
    },
    {
      name: "flex-kconfig",
      tool: flex_tool()?,
      argv: [
        "-oscripts/kconfig/lexer.lex.c",
        "-L",
        "scripts/kconfig/lexer.l",
      ],
      outputs: [
        p"scripts/kconfig/lexer.lex.c",
      ],
    },
    {
      name: "bison-dtc",
      tool: bison_tool()?,
      argv: [
        "-o",
        "scripts/dtc/dtc-parser.tab.c",
        "--defines=scripts/dtc/dtc-parser.tab.h",
        "-t",
        "-l",
        "scripts/dtc/dtc-parser.y",
      ],
      outputs: [
        p"scripts/dtc/dtc-parser.tab.c",
        p"scripts/dtc/dtc-parser.tab.h",
      ],
    },
    {
      name: "flex-dtc",
      tool: flex_tool()?,
      argv: [
        "-oscripts/dtc/dtc-lexer.lex.c",
        "-L",
        "scripts/dtc/dtc-lexer.l",
      ],
      outputs: [
        p"scripts/dtc/dtc-lexer.lex.c",
      ],
    },
  ]
}

export proc parser_generator(name: Str) [env, error] -> Result[ParserGen] {
  for spec in parser_generators()? {
    if spec.name == name {
      return spec
    }
  }

  return Err(ParserGenError.Failed("linux-parser-generator", f"unknown parser generator '${name}'"))
}

export proc remove_outputs(spec: ParserGen) [fs, error] {
  for out in spec.outputs {
    fs.remove(out, missing_ok: true)?
  }

  match spec.name {
    "bison-kconfig" => fs.remove(p"scripts/kconfig/.parser.tab.h.cmd", missing_ok: true)?
    "bison-dtc" => fs.remove(p"scripts/dtc/.dtc-parser.tab.h.cmd", missing_ok: true)?
    _ => {}
  }
}

export proc run_generator(spec: ParserGen) [fs, process, error] {
  let command = process.command_argv(
    /bin/xsh,
    ["/bin/xsh", spec.tool.display(), "--"].extend(spec.argv),
    cwd: fs.cwd()?,
    env: {XSH_BISON_NO_UPSTREAM: "1", XSH_FLEX_NO_UPSTREAM: "1"},
  )

  let status = process.run(command)?

  if ! status.ok {
    return Err(
      ParserGenError.Failed(
        "linux-parser-generator",
        f"generator failed for ${spec.name}: ${spec.tool.display()} ${spec.argv.join(" ")}",
      ),
    )
  }

  for out in spec.outputs {
    if ! out.exists()? {
      return Err(ParserGenError.Failed("linux-parser-generator", f"${spec.name} did not write ${out.display()}"))
    }
  }
}

export proc generate_parser(name: Str, clean: Bool = true) [fs, process, env, error] {
  let spec = parser_generator(name)?

  if clean {
    remove_outputs(spec)?
  }

  run_generator(spec)?
}

export proc generate_kconfig_parsers(clean: Bool = true) [fs, process, env, error] {
  generate_parser("bison-kconfig", clean)?
  generate_parser("flex-kconfig", clean)?
}

export proc generate_dtc_parsers(clean: Bool = true) [fs, process, env, error] {
  generate_parser("bison-dtc", clean)?
  generate_parser("flex-dtc", clean)?
}

export proc generate_linux_parsers(clean: Bool = true) [fs, process, env, error] {
  for spec in parser_generators()? {
    if clean {
      remove_outputs(spec)?
    }

    run_generator(spec)?
  }
}
