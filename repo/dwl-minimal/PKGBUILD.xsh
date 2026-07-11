use pm.env as pm_env
use pm.util as pm_util

export let name = "dwl-minimal"

export let ver = "0.8"

export let rel = "8"

export let deps = ["musl", "wlroots0.19-mesa", "wayland-libs-server", "libxkbcommon", "libinput"]

export let mkdeps = [
  "llvm-toolchain",
  "pkgconf",
  "wayland-dev",
  "wayland-protocols",
  "linux",
  "wlroots0.19-mesa",
  "pixman-dev",
  "libdrm",
  "mesa-minimal",
  "libxkbcommon",
  "libinput",
]

export let target_build_deps = ["wayland-dev", "wayland-protocols", "pixman-dev"]

export let sources = [p"https://codeberg.org/dwl/dwl/archive/vVERSION.tar.gz"]

export let checksums = [
  "a80cc39794a17b9753349496e2cb127f1de22eb179d78f2c22ef647f2643a654",
]

proc sysroot_path(root: Str, raw: Str) [fs, error] -> Result[Path] {
  let path_value = fp"${raw.trim()}"

  if fs.exists(path_value)? {
    return path_value
  }

  if root != "" and root != "/" and raw.starts_with("/") {
    return fp"${root}${raw.trim()}"
  }

  path_value
}

proc pkg_config_flags(pkg_config: Path, mode: Str, packages: List[Str]) [process, error] -> Result[List[Str]] {
  let out = run.text $pkg_config $mode @packages ?
  return out.words()
}

proc pkg_config_variable(pkg_config: Path, package: Str, variable: Str) [process, error] -> Result[Str] {
  let out = run.text $pkg_config f"--variable=${variable}" $package ?
  out.trim()
}

proc generate_protocol_headers(pkg_config: Path, root: Str, scanner: Path) [fs, process, error] {
  let protocols = sysroot_path(root, pkg_config_variable(pkg_config, "wayland-protocols", "pkgdatadir")?)?
  run $scanner "enum-header" fp"${protocols}/staging/cursor-shape/cursor-shape-v1.xml" "cursor-shape-v1-protocol.h" ?
  run $scanner "enum-header" fp"${protocols}/unstable/pointer-constraints/pointer-constraints-unstable-v1.xml" "pointer-constraints-unstable-v1-protocol.h" ?
  run $scanner "enum-header" "protocols/wlr-layer-shell-unstable-v1.xml" "wlr-layer-shell-unstable-v1-protocol.h" ?
  run $scanner "server-header" "protocols/wlr-output-power-management-unstable-v1.xml" "wlr-output-power-management-unstable-v1-protocol.h" ?
  run $scanner "server-header" fp"${protocols}/stable/xdg-shell/xdg-shell.xml" "xdg-shell-protocol.h" ?
}

proc patch_startup() [fs, error] {
  let source = p"dwl.c"
  var text = source.read_text()?

  text = text.replace(
    """static void run(char *startup_cmd);
""",
    """static void run(char *startup_cmd);
static char **startup_argv(char *startup_cmd);
""",
  )

  text = text.replace(
    """void
run(char *startup_cmd)
""",
    """char **
startup_argv(char *startup_cmd)
{
	size_t argc = 0;
	char *p = startup_cmd;
	while (*p) {
		while (*p == ' ' || *p == '	')
			p++;
		if (*p) {
			argc++;
			while (*p && *p != ' ' && *p != '	')
				p++;
		}
	}
	if (!argc)
		die("startup: empty command");

	char **argv = ecalloc(argc + 1, sizeof(*argv));
	p = startup_cmd;
	for (size_t i = 0; i < argc; i++) {
		while (*p == ' ' || *p == '	')
			p++;
		argv[i] = p;
		while (*p && *p != ' ' && *p != '	')
			p++;
		if (*p)
			*p++ = 0;
	}
	return argv;
}

void
run(char *startup_cmd)
""",
  )

  text = text.replace(
    """	/* Now that the socket exists and the backend is started, run the startup command */
	if (startup_cmd) {
		int piperw[2];
		if (pipe(piperw) < 0)
			die("startup: pipe:");
		if ((child_pid = fork()) < 0)
			die("startup: fork:");
		if (child_pid == 0) {
			setsid();
			dup2(piperw[0], STDIN_FILENO);
			close(piperw[0]);
			close(piperw[1]);
			execl("/bin/sh", "/bin/sh", "-c", startup_cmd, NULL);
			die("startup: execl:");
		}
		dup2(piperw[1], STDOUT_FILENO);
		close(piperw[1]);
		close(piperw[0]);
	}
""",
    """	/* Now that the socket exists and the backend is started, run the startup command. */
	if (startup_cmd) {
		char **argv = startup_argv(startup_cmd);
		if ((child_pid = fork()) < 0)
			die("startup: fork:");
		if (child_pid == 0) {
			setsid();
			close(STDIN_FILENO);
			execvp(argv[0], argv);
			die("startup: execvp %s failed:", argv[0]);
		}
	}
""",
  )

  text = text.replace(
    """else if (c == 'v')
			die("dwl " VERSION);
""",
    """else if (c == 'v') {
			puts("dwl " VERSION);
			return EXIT_SUCCESS;
		}
""",
  )

  fs.write(source, text)?
}

proc write_config() [fs, error] {
  var config = p"config.def.h".read_text()?

  config = config.replace(
    """/* helper for spawning shell commands in the pre dwm-5.0 fashion */
#define SHCMD(cmd) { .v = (const char*[]){ "/bin/sh", "-c", cmd, NULL } }

/* commands */
static const char *termcmd[] = { "foot", NULL };
static const char *menucmd[] = { "wmenu-run", NULL };
""",
    """/* commands */
static const char *termcmd[] = { "/usr/bin/foot", NULL };
static const char *browsercmd[] = { "/usr/bin/waterfox", NULL };
""",
  )

  config = config.replace(
    """	{ MODKEY,                    XKB_KEY_p,           spawn,            {.v = menucmd} },
""",
    """	{ MODKEY,                    XKB_KEY_b,           spawn,            {.v = browsercmd} },
""",
  )

  fs.write(p"config.h", config)?
}

export proc build(dest: Path) [fs, process, env, error] {
  let cc = process.which("cc")?
  let pc = pm_env.pkg_config_context()?
  let pkg_config = pc.pkg_config
  let root = env.get("LAPUTA_ROOT") ?? "/"
  let build_root = env.get("XSH_PM_BUILD_ROOT") ?? ""
  let cross_build = pm_util.build_arch()? != pm_util.target_arch()? and build_root != ""

  let native_tools_ld = if cross_build {
    f"${build_root}/usr/lib:${build_root}/usr/lib/llvm22/lib"
  } else {
    pc.ld_library_path
  }

  let scanner = if cross_build { fp"${build_root}/usr/bin/wayland-scanner" } else { process.which("wayland-scanner")? }
  let packages = ["wayland-server", "xkbcommon", "libinput", "wlroots-0.19"]
  patch_startup()?
  write_config()?

  env {
    LD_LIBRARY_PATH = native_tools_ld
    PKG_CONFIG = pc.pkg_config
    PKG_CONFIG_LIBDIR = pc.pkg_config_libdir
    PKG_CONFIG_PATH = pc.pkg_config_path
    PKG_CONFIG_SYSROOT_DIR = pc.pkg_config_sysroot
  } {
    generate_protocol_headers(pkg_config, root, scanner)?
    let pkg_cflags = pkg_config_flags(pkg_config, "--cflags", packages)?
    let pkg_libs = pkg_config_flags(pkg_config, "--libs", packages)?

    let cflags = [
      "-I.",
      "-DWLR_USE_UNSTABLE",
      "-D_POSIX_C_SOURCE=200809L",
      f"-DVERSION=\"${ver}\"",
      "-Wall",
      "-Wextra",
      "-Wno-unused-parameter",
      "-Wno-unused-macros",
      "-Wno-missing-braces",
      "-O2",
    ].extend(pkg_cflags)

    run $cc "-c" "dwl.c" "-o" "dwl.o" @cflags ?
    run $cc "-c" "util.c" "-o" "util.o" @cflags ?
    run $cc "dwl.o" "util.o" "-o" "dwl" @pkg_libs "-lm" ?
  } ?

  fs.install(p"dwl", fp"${dest}/usr/bin/dwl", 0o755, parents: true, overwrite: true)?
}
