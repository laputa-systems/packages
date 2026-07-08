use pm.make as make

export let name: Str = "dropbear"

export let ver: Str = "2025.89"

export let rel: Str = "13"

export let deps: List[Str] = ["musl", "zlib"]

export let mkdeps: List[Str] = ["llvm-toolchain", "xinit"]

# Source is a git commit (no VERSION substitution needed).
export let sources: List[Path] = [
  p"https://github.com/mkj/dropbear/archive/f5d44406ef2952ca69a68d59c6b0f7f0ff777305.tar.gz",
  p"service.xsh",
]

export let checksums: List[Str] = ["ca55783baa7a67e57de4c234d43711349b7b3f8c17b15a04fd58a6e88700572c", "SKIP"]

pure task_names(paths: List[Path]) -> List[Str] {
  return [path_value.display() for path_value in paths]
}

pure dropbear_src(stem: Str) -> Path {
  return fp"src/${stem}.c"
}

pure dropbear_obj(stem: Str) -> Path {
  return fp"obj/dropbear/${stem}.o"
}

pure source_obj(root: Path, prefix: Str, source: Path) -> Path {
  let source_rel = source.relative_to(root).display()
  return fp"obj/${prefix}/${source_rel.replace("/", "_").replace(".c", ".o")}"
}

proc install_manpage(source: Path, dest: Path) [fs, error] {
  if source.exists()? {
    fs.install(source, dest, 0o644, parents: true, overwrite: true)?
  }
}

proc write_config_h() [fs, error] {
  fs.write(
    p"config.h",
    """#ifndef DROPBEAR_CONFIG_H
#define DROPBEAR_CONFIG_H

#define DISABLE_LASTLOG 1
#define DISABLE_UTMP 1
#define DISABLE_UTMPX 1
#define DISABLE_WTMP 1
#define DISABLE_WTMPX 1

#define STDC_HEADERS 1
#define HAVE_BASENAME 1
#define HAVE_CLEARENV 1
#define HAVE_CLOCK_GETTIME 1
#define HAVE_ENDIAN_H 1
#define HAVE_EXPLICIT_BZERO 1
#define HAVE_FCHMOD 1
#define HAVE_FEXECVE 1
#define HAVE_FORK 1
#define HAVE_FREEADDRINFO 1
#define HAVE_GAI_STRERROR 1
#define HAVE_GETADDRINFO 1
#define HAVE_GETNAMEINFO 1
#define HAVE_GETPASS 1
#define HAVE_GETRANDOM 1
#define HAVE_HTOLE32 1
#define HAVE_DECL_HTOLE32 1
#define HAVE_HTOLE64 1
#define HAVE_DECL_HTOLE64 1
#define HAVE_INTTYPES_H 1
#define HAVE_LIBGEN_H 1
#define HAVE_NETDB_H 1
#define HAVE_NETINET_IN_H 1
#define HAVE_NETINET_IN_SYSTM_H 1
#define HAVE_NETINET_TCP_H 1
#define HAVE_OPENPTY 1
#define HAVE_PATHS_H 1
#define HAVE_PTY_H 1
#define HAVE_PUTENV 1
#define HAVE_SETRESGID 1
#define HAVE_SETRESUID 1
#define HAVE_STATIC_ASSERT 1
#define HAVE_STDINT_H 1
#define HAVE_STDIO_H 1
#define HAVE_STDLIB_H 1
#define HAVE_STRINGS_H 1
#define HAVE_STRING_H 1
#define HAVE_STRUCT_ADDRINFO 1
#define HAVE_STRUCT_IN6_ADDR 1
#define HAVE_STRUCT_SOCKADDR_IN6 1
#define HAVE_STRUCT_SOCKADDR_STORAGE 1
#define HAVE_STRUCT_SOCKADDR_STORAGE_SS_FAMILY 1
#define HAVE_STRUCT_STAT_ST_BLKSIZE 1
#define HAVE_SYS_RANDOM_H 1
#define HAVE_SYS_SELECT_H 1
#define HAVE_SYS_SOCKET_H 1
#define HAVE_SYS_STAT_H 1
#define HAVE_SYS_TYPES_H 1
#define HAVE_SYS_UIO_H 1
#define HAVE_SYS_WAIT_H 1
#define HAVE_UINT16_T 1
#define HAVE_UINT32_T 1
#define HAVE_UINT8_T 1
#define HAVE_UNISTD_H 1
#define HAVE_WRITEV 1

#endif
""",
  )?
}

proc ifndef_wrapped_defines(source: Path) [fs, error] -> Result[Str] {
  var lines: List[Str] = []

  for line in source.read_text()?.split("\n") {
    let words = line.words()

    if words.len() >= 3 and words[0] == "#define" {
      lines = lines.push(f"#ifndef ${words[1]}")
      lines = lines.push(line)
      lines = lines.push("#endif")
    } else {
      lines = lines.push(line)
    }
  }

  return lines.join("\n")
}

export proc build(dest: Path) [fs, process, env, error] {
  let src = fs.cwd()?
  let cc = process.which("cc")?
  let os = system.uname()?
  let triple = f"${os.machine}-linux-musl"

  # LAPUTA_ROOT: prefix where musl/zlib deps are installed (empty = system /usr).
  # Set to /build-env or /rootfs in the Makefile test target so configure can
  # find zlib headers and libs. Matches the YSH PKGBUILD's $kr variable.
  var kr = ""

  match env.Str.LAPUTA_ROOT {
    Ok(v) => {
      if v != "/" {
        kr = v
      }
    }
    Err(_) => {}
  }

  # Feature overrides: disable password auth (no libcrypt in musl), drop-privs
  # (setresgid misdetected by configure tests), and local stream fwd
  # (requires either drop-privs or non-multiuser — we have neither).
  let local_opts = """#define DROPBEAR_SVR_PASSWORD_AUTH 0
#define DROPBEAR_SVR_DROP_PRIVS 0
#define DROPBEAR_SVR_LOCALSTREAMFWD 0
"""

  fs.write(p"localoptions.h", local_opts)?

  # sub-makes (libtomcrypt) don't get -I flags, so copy to src/ too
  fs.write(p"src/localoptions.h", local_opts)?
  let ldflags = f"-L${kr}/usr/lib"
  write_config_h()?
  let default_options_guard = ifndef_wrapped_defines(p"src/default_options.h")?

  fs.write(
    p"default_options_guard.h",
    f"""/*
Generated from src/default_options.h
Local customisation goes in localoptions.h
*/

${default_options_guard}
""",
  )?

  let common_stems = [
    "dbutil",
    "buffer",
    "dbhelpers",
    "dss",
    "bignum",
    "signkey",
    "rsa",
    "dbrandom",
    "queue",
    "atomicio",
    "compat",
    "fake-rfc2553",
    "ltc_prng",
    "ecc",
    "ecdsa",
    "sk-ecdsa",
    "crypto_desc",
    "curve25519",
    "ed25519",
    "sk-ed25519",
    "dbmalloc",
    "gensignkey",
    "gendss",
    "genrsa",
    "gened25519",
  ]

  let clisvr_stems = [
    "common-session",
    "packet",
    "common-algo",
    "common-kex",
    "common-channel",
    "common-chansession",
    "termcodes",
    "loginrec",
    "tcp-accept",
    "listener",
    "process-packet",
    "dh_groups",
    "common-runopts",
    "circbuffer",
    "list",
    "netio",
    "chachapoly",
    "gcm",
    "kex-x25519",
    "kex-dh",
    "kex-ecdh",
    "kex-pqhybrid",
    "sntrup761",
    "mlkem768",
  ]

  let svr_stems = [
    "svr-kex",
    "svr-auth",
    "sshpty",
    "svr-authpasswd",
    "svr-authpubkey",
    "svr-authpubkeyoptions",
    "svr-session",
    "svr-service",
    "svr-chansession",
    "svr-runopts",
    "svr-agentfwd",
    "svr-main",
    "svr-x11fwd",
    "svr-tcpfwd",
    "svr-authpam",
  ]

  let cli_stems = [
    "cli-main",
    "cli-auth",
    "cli-authpasswd",
    "cli-kex",
    "cli-session",
    "cli-runopts",
    "cli-chansession",
    "cli-authpubkey",
    "cli-tcpfwd",
    "cli-channel",
    "cli-authinteract",
    "cli-agentfwd",
    "cli-readconf",
  ]

  let key_stems = ["dropbearkey"]
  let convert_stems = ["dropbearconvert", "keyimport", "signkey_ossh"]

  let all_dropbear_stems = common_stems.extend(clisvr_stems).extend(svr_stems).extend(cli_stems).extend(key_stems).extend(
    convert_stems,
  )

  let defs = [
    "-DHAVE_CONFIG_H",
    "-DLOCALOPTIONS_H_EXISTS",
    "-DBUNDLED_LIBTOM",
    "-DDROPBEAR_SERVER",
    "-DDROPBEAR_CLIENT",
  ]

  let includes = ["-I.", "-I./src", "-I./libtommath", "-I./libtomcrypt/src/headers", f"-I${kr}/usr/include"]
  let dropbear_cflags = ["-W", "-Wall", "-Wno-pointer-sign", "-Os", "-fPIC"]
  let ltc_cflags = ["-W", "-Wall", "-Wno-pointer-sign", "-Os", "-DLTC_SOURCE", "-fPIC"]
  let ltm_cflags = ["-O3", "-funroll-loops", "-fomit-frame-pointer", "-fPIC"]
  var tasks: List[make.MakeTask] = []
  var dropbear_objs: List[Path] = []
  var common_objs: List[Path] = []
  var clisvr_objs: List[Path] = []
  var svr_objs: List[Path] = []
  var cli_objs: List[Path] = []
  var key_objs: List[Path] = []
  var convert_objs: List[Path] = []

  for stem in all_dropbear_stems {
    let out = dropbear_obj(stem)
    dropbear_objs = dropbear_objs.push(out)
    tasks = tasks.push(make.compile_c_task(cc, triple, dropbear_cflags, defs, includes, dropbear_src(stem), out))
  }

  for stem in common_stems {
    common_objs = common_objs.push(dropbear_obj(stem))
  }

  for stem in clisvr_stems {
    clisvr_objs = clisvr_objs.push(dropbear_obj(stem))
  }

  for stem in svr_stems {
    svr_objs = svr_objs.push(dropbear_obj(stem))
  }

  for stem in cli_stems {
    cli_objs = cli_objs.push(dropbear_obj(stem))
  }

  for stem in key_stems {
    key_objs = key_objs.push(dropbear_obj(stem))
  }

  for stem in convert_stems {
    convert_objs = convert_objs.push(dropbear_obj(stem))
  }

  var ltc_objs: List[Path] = []
  let ltc_root = fp"${src}/libtomcrypt/src"

  for entry in fs.files(p"libtomcrypt/src")?
    |> where .ext == "c" and .name != "aes_tab.c" and .name != "safer_tab.c" and .name != "twofish_tab.c" and .name != "whirltab.c" and .name != "sober128tab.c" {
    let out = source_obj(ltc_root, "libtomcrypt", entry.path)
    ltc_objs = ltc_objs.push(out)
    tasks = tasks.push(make.compile_c_task(cc, triple, ltc_cflags, defs, includes, entry.path, out))
  }

  var ltm_objs: List[Path] = []
  let ltm_root = fp"${src}/libtommath"

  for entry in fs.ls(p"libtommath")? |> where .kind == "file" and .ext == "c" {
    let out = source_obj(ltm_root, "libtommath", entry.path)
    ltm_objs = ltm_objs.push(out)
    tasks = tasks.push(make.compile_c_task(cc, triple, ltm_cflags, defs, includes, entry.path, out))
  }

  let ltc_a = p"obj/libtomcrypt.a"
  let ltm_a = p"obj/libtommath.a"
  tasks = tasks.push(make.link_archive_task(cc, ltc_objs, ltc_a, task_names(ltc_objs)))
  tasks = tasks.push(make.link_archive_task(cc, ltm_objs, ltm_a, task_names(ltm_objs)))
  let lib_deps = [ltc_a.display(), ltm_a.display()]
  let libs = [ltc_a, ltm_a]
  let link_flags = [ldflags, "-pie", "-lz"]
  let dropbear_bin_objs = common_objs.extend(clisvr_objs).extend(svr_objs)
  let dbclient_bin_objs = common_objs.extend(clisvr_objs).extend(cli_objs)
  let dropbearkey_bin_objs = common_objs.extend(key_objs)
  let dropbearconvert_bin_objs = common_objs.extend(convert_objs)

  tasks = tasks.push(
    make.link_executable_task(
      cc,
      triple,
      dropbear_bin_objs,
      libs,
      link_flags,
      p"dropbear",
      task_names(dropbear_bin_objs).extend(lib_deps),
    ),
  )

  tasks = tasks.push(
    make.link_executable_task(
      cc,
      triple,
      dbclient_bin_objs,
      libs,
      link_flags,
      p"dbclient",
      task_names(dbclient_bin_objs).extend(lib_deps),
    ),
  )

  tasks = tasks.push(
    make.link_executable_task(
      cc,
      triple,
      dropbearkey_bin_objs,
      libs,
      link_flags,
      p"dropbearkey",
      task_names(dropbearkey_bin_objs).extend(lib_deps),
    ),
  )

  tasks = tasks.push(
    make.link_executable_task(
      cc,
      triple,
      dropbearconvert_bin_objs,
      libs,
      link_flags,
      p"dropbearconvert",
      task_names(dropbearconvert_bin_objs).extend(lib_deps),
    ),
  )

  make.run_tasks(tasks, make.jobs()?)?
  fs.install(p"dropbear", fp"${dest}/usr/bin/dropbear", 0o755, parents: true, overwrite: true)?
  fs.install(p"dbclient", fp"${dest}/usr/bin/dbclient", 0o755, parents: true, overwrite: true)?
  fs.install(p"dropbearkey", fp"${dest}/usr/bin/dropbearkey", 0o755, parents: true, overwrite: true)?
  fs.install(p"dropbearconvert", fp"${dest}/usr/bin/dropbearconvert", 0o755, parents: true, overwrite: true)?

  # Runtime configuration and xinit service module.
  fs.mkdir(fp"${dest}/etc/dropbear")?
  fs.install(p"service.xsh", fp"${dest}/usr/lib/xinit/services/dropbear.xsh", 0o644, parents: true, overwrite: true)?
}
