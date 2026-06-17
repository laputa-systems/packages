use pm.util as pm_util

error LlvmToolchainError = Failed(message: Str)

export let name: Str = "llvm-toolchain"

export let ver: Str = "22.1.3"

export let rel: Str = "7"

export let deps: List[Str] = ["musl"]

export let mkdeps: List[Str] = []

export let nostrip: Bool = true

export let sources: List[Path] = [
  p"https://github.com/laputa-systems/artifacts/releases/download/llvm-toolchain-VERSION/llvm-toolchain-VERSION-ARCH.tar.gz",
]

export let checksums: List[Str] = ["SKIP"]

export let checksums_aarch64: List[Str] = ["3b9d9015a9b3ad74e111e7128c820d009cf35c7e2711ee1aa2b93b0a4bc1b0d4"]

export let checksums_x86_64: List[Str] = ["79b31c8ac33e791420d8282466eab85e8384d678728051748fc087bc0d049f8f"]

pure wrapper_source() -> Str {
  return """#include <errno.h>
#include <limits.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>
#include <sys/utsname.h>
#include <unistd.h>

struct tool {
  const char *name;
  const char *real;
  int clang;
};

static const struct tool tools[] = {
  {"cc", "usr/lib/llvm22/bin/clang-22", 1},
  {"clang", "usr/lib/llvm22/bin/clang-22", 1},
  {"c++", "usr/lib/llvm22/bin/clang++", 1},
  {"clang++", "usr/lib/llvm22/bin/clang++", 1},
  {"ld", "usr/lib/llvm-toolchain/bin/ld.lld", 0},
  {"ld.lld", "usr/lib/llvm-toolchain/bin/ld.lld", 0},
  {"ar", "usr/bin/llvm22-ar", 0},
  {"ranlib", "usr/bin/llvm22-ranlib", 0},
  {"nm", "usr/bin/llvm22-nm", 0},
  {"objcopy", "usr/bin/llvm22-objcopy", 0},
  {"objdump", "usr/bin/llvm22-objdump", 0},
  {"readelf", "usr/bin/llvm22-readelf", 0},
  {"strip", "usr/bin/llvm22-strip", 0},
  {"llvm-ar", "usr/bin/llvm22-ar", 0},
  {"llvm-ranlib", "usr/bin/llvm22-ranlib", 0},
  {"llvm-nm", "usr/bin/llvm22-nm", 0},
  {"llvm-objcopy", "usr/bin/llvm22-objcopy", 0},
  {"llvm-objdump", "usr/bin/llvm22-objdump", 0},
  {"llvm-readelf", "usr/bin/llvm22-readelf", 0},
  {"llvm-strip", "usr/bin/llvm22-strip", 0},
};

static const char *base_name(const char *path) {
  const char *slash = strrchr(path, '/');
  return slash ? slash + 1 : path;
}

static const struct tool *find_tool(const char *name) {
  size_t count = sizeof(tools) / sizeof(tools[0]);
  for (size_t i = 0; i < count; i++) {
    if (strcmp(tools[i].name, name) == 0) {
      return &tools[i];
    }
  }
  return NULL;
}

static int executable(const char *path) {
  struct stat st;
  return stat(path, &st) == 0 && (st.st_mode & S_IXUSR);
}

static int find_self(const char *argv0, char *out, size_t out_len) {
  if (strchr(argv0, '/')) {
    if (snprintf(out, out_len, "%s", argv0) >= (int)out_len) {
      return -1;
    }
    return 0;
  }

  const char *path = getenv("PATH");
  if (!path) {
    return -1;
  }

  const char *start = path;
  while (*start) {
    const char *end = strchr(start, ':');
    size_t len = end ? (size_t)(end - start) : strlen(start);
    const char *dir = len == 0 ? "." : start;
    int n = len == 0 ? snprintf(out, out_len, "./%s", argv0) : snprintf(out, out_len, "%.*s/%s", (int)len, dir, argv0);
    if (n > 0 && n < (int)out_len && executable(out)) {
      return 0;
    }
    if (!end) {
      break;
    }
    start = end + 1;
  }

  return -1;
}

static void dirname_in_place(char *path) {
  char *slash = strrchr(path, '/');
  if (!slash) {
    strcpy(path, ".");
  } else if (slash == path) {
    path[1] = 0;
  } else {
    *slash = 0;
  }
}

static int prefix_from_self(const char *self, char *out, size_t out_len) {
  if (snprintf(out, out_len, "%s", self) >= (int)out_len) {
    return -1;
  }
  dirname_in_place(out);
  dirname_in_place(out);
  dirname_in_place(out);
  return 0;
}

static int join_path(char *out, size_t out_len, const char *prefix, const char *rel) {
  if (strcmp(prefix, "/") == 0) {
    return snprintf(out, out_len, "/%s", rel) < (int)out_len ? 0 : -1;
  }
  return snprintf(out, out_len, "%s/%s", prefix, rel) < (int)out_len ? 0 : -1;
}

static int has_compile_only_arg(int argc, char **argv) {
  for (int i = 1; i < argc; i++) {
    if (strcmp(argv[i], "-c") == 0 || strcmp(argv[i], "-S") == 0 || strcmp(argv[i], "-E") == 0) {
      return 1;
    }
  }
  return 0;
}

static int has_option_prefix(int argc, char **argv, const char *prefix) {
  size_t len = strlen(prefix);
  for (int i = 1; i < argc; i++) {
    if (strncmp(argv[i], prefix, len) == 0) {
      return 1;
    }
  }
  return 0;
}

static int has_arg(int argc, char **argv, const char *arg) {
  for (int i = 1; i < argc; i++) {
    if (strcmp(argv[i], arg) == 0) {
      return 1;
    }
  }
  return 0;
}

static int has_suffix(const char *value, const char *suffix) {
  size_t value_len = strlen(value);
  size_t suffix_len = strlen(suffix);
  return value_len >= suffix_len && strcmp(value + value_len - suffix_len, suffix) == 0;
}

static int needs_frontend_flags(int argc, char **argv) {
  int saw_frontend_input = 0;
  int explicit_assembler = 0;

  for (int i = 1; i < argc; i++) {
    if (strcmp(argv[i], "-x") == 0 && i + 1 < argc) {
      i++;
      explicit_assembler = strcmp(argv[i], "assembler") == 0;
      if (!explicit_assembler) {
        saw_frontend_input = 1;
      }
      continue;
    }

    if (argv[i][0] == '-') {
      if ((strcmp(argv[i], "-o") == 0 || strcmp(argv[i], "-MF") == 0 || strcmp(argv[i], "-MT") == 0 || strcmp(argv[i], "-MQ") == 0 || strcmp(argv[i], "-include") == 0 || strcmp(argv[i], "-isystem") == 0) && i + 1 < argc) {
        i++;
      }
      continue;
    }

    if (explicit_assembler) {
      continue;
    }
    if (has_suffix(argv[i], ".s")) {
      continue;
    }
    if (has_suffix(argv[i], ".c") || has_suffix(argv[i], ".cc") || has_suffix(argv[i], ".cpp") || has_suffix(argv[i], ".cxx") || has_suffix(argv[i], ".C") || has_suffix(argv[i], ".S")) {
      saw_frontend_input = 1;
    }
  }

  return saw_frontend_input || has_arg(argc, argv, "-E");
}

static int has_include_control_arg(int argc, char **argv) {
  return has_arg(argc, argv, "-nostdinc") || has_arg(argc, argv, "-nostdlibinc") || has_arg(argc, argv, "-nostdsysteminc");
}

static int is_cxx_tool(const char *name) {
  return strcmp(name, "c++") == 0 || strcmp(name, "clang++") == 0;
}

static void normalize_arch(char *arch, size_t len) {
  struct utsname uts;
  if (uname(&uts) == 0) {
    snprintf(arch, len, "%s", strcmp(uts.machine, "arm64") == 0 ? "aarch64" : uts.machine);
  } else {
    snprintf(arch, len, "x86_64");
  }
}

static int arch_from_triple(const char *triple, char *arch, size_t len) {
  if (strncmp(triple, "x86_64", 6) == 0 || strncmp(triple, "amd64", 5) == 0) {
    snprintf(arch, len, "x86_64");
    return 0;
  }
  if (strncmp(triple, "aarch64", 7) == 0 || strncmp(triple, "arm64", 5) == 0) {
    snprintf(arch, len, "aarch64");
    return 0;
  }
  return -1;
}

static void target_arch(char *arch, size_t len, int argc, char **argv) {
  normalize_arch(arch, len);

  for (int i = 1; i < argc; i++) {
    if ((strcmp(argv[i], "-target") == 0 || strcmp(argv[i], "--target") == 0) && i + 1 < argc) {
      if (arch_from_triple(argv[i + 1], arch, len) == 0) {
        return;
      }
      i++;
      continue;
    }
    if (strncmp(argv[i], "--target=", 9) == 0) {
      if (arch_from_triple(argv[i] + 9, arch, len) == 0) {
        return;
      }
      continue;
    }
  }
}

static const char *default_march_flag(const char *arch) {
  if (strcmp(arch, "x86_64") == 0) {
    return "-march=x86-64-v3";
  }
  if (strcmp(arch, "aarch64") == 0) {
    return "-march=armv8-a";
  }
  return NULL;
}

int main(int argc, char **argv) {
  const struct tool *tool = find_tool(base_name(argv[0]));
  if (!tool) {
    fprintf(stderr, "llvm-toolchain wrapper: unknown tool name: %s\\n", base_name(argv[0]));
    return 127;
  }

  char self[PATH_MAX];
  char prefix[PATH_MAX];
  char real[PATH_MAX];
  if (find_self(argv[0], self, sizeof(self)) != 0 || prefix_from_self(self, prefix, sizeof(prefix)) != 0 || join_path(real, sizeof(real), prefix, tool->real) != 0) {
    fprintf(stderr, "llvm-toolchain wrapper: failed to resolve tool path\\n");
    return 127;
  }

  char libs[PATH_MAX * 2];
  if (strcmp(prefix, "/") == 0) {
    snprintf(libs, sizeof(libs), "/usr/lib:/lib");
  } else {
    snprintf(libs, sizeof(libs), "%s/usr/lib:%s/lib", prefix, prefix);
  }

  const char *old_ld = getenv("LD_LIBRARY_PATH");
  char ld[PATH_MAX * 3];
  if (old_ld && old_ld[0]) {
    snprintf(ld, sizeof(ld), "%s:%s", libs, old_ld);
  } else {
    snprintf(ld, sizeof(ld), "%s", libs);
  }
  setenv("LD_LIBRARY_PATH", ld, 1);

  const char *tool_name = base_name(argv[0]);
  int compile_only = has_compile_only_arg(argc, argv);
  int frontend_flags = needs_frontend_flags(argc, argv);
  int extra_count = tool->clang ? 32 : 0;
  char **exec_argv = calloc((size_t)argc + (size_t)extra_count + 1, sizeof(char *));
  if (!exec_argv) {
    perror("calloc");
    return 127;
  }

  int out = 0;
  exec_argv[out++] = tool->clang ? real : (char *)base_name(argv[0]);

  char arch[128];
  char triple[160];
  char sysroot[PATH_MAX + 16];
  char resource_dir[PATH_MAX + 32];
  char resource_include[PATH_MAX + 40];
  char sys_include[PATH_MAX + 16];
  char cxx_include[PATH_MAX + 32];
  char cxx_target_include[PATH_MAX + 64];
  char lib_dir[PATH_MAX + 8];
  char compiler_rt[PATH_MAX + 64] = {0};
  if (tool->clang) {
    normalize_arch(arch, sizeof(arch));
    char march_arch[128];
    target_arch(march_arch, sizeof(march_arch), argc, argv);
    snprintf(triple, sizeof(triple), "--target=%s-linux-musl", march_arch);
    snprintf(sysroot, sizeof(sysroot), "--sysroot=%s", prefix);
    join_path(resource_dir, sizeof(resource_dir), prefix, "usr/lib/llvm22/lib/clang/22");
    join_path(resource_include, sizeof(resource_include), prefix, "usr/lib/llvm22/lib/clang/22/include");
    join_path(sys_include, sizeof(sys_include), prefix, "usr/include");
    join_path(cxx_include, sizeof(cxx_include), prefix, "usr/include/c++/15.2.0");
    snprintf(cxx_target_include, sizeof(cxx_target_include), "%s/usr/include/c++/15.2.0/%s-alpine-linux-musl", strcmp(prefix, "/") == 0 ? "" : prefix, march_arch);
    join_path(lib_dir, sizeof(lib_dir), prefix, "usr/lib");
    snprintf(compiler_rt, sizeof(compiler_rt), "%s/usr/lib/libclang_rt.builtins-%s.a", strcmp(prefix, "/") == 0 ? "" : prefix, march_arch);

    exec_argv[out++] = "--no-default-config";
    exec_argv[out++] = triple;
    exec_argv[out++] = sysroot;
    exec_argv[out++] = "-resource-dir";
    exec_argv[out++] = resource_dir;

    if (frontend_flags && !has_include_control_arg(argc, argv)) {
      exec_argv[out++] = "-nostdinc";
      if (is_cxx_tool(tool_name)) {
        exec_argv[out++] = "-isystem";
        exec_argv[out++] = cxx_include;
        exec_argv[out++] = "-isystem";
        exec_argv[out++] = cxx_target_include;
      }
      exec_argv[out++] = "-isystem";
      exec_argv[out++] = resource_include;
      exec_argv[out++] = "-isystem";
      exec_argv[out++] = sys_include;
    }

    if (frontend_flags) {
      exec_argv[out++] = "-fno-stack-protector";
      const char *march = default_march_flag(march_arch);
      if (march && !has_option_prefix(argc, argv, "-march=") && !has_option_prefix(argc, argv, "-mcpu=")) {
        exec_argv[out++] = (char *)march;
      }
    }

    if (!compile_only) {
      if (!has_option_prefix(argc, argv, "--rtlib=")) {
        exec_argv[out++] = "--rtlib=compiler-rt";
      }
      if (!has_option_prefix(argc, argv, "--unwindlib=")) {
        exec_argv[out++] = "--unwindlib=libunwind";
      }
      exec_argv[out++] = "-fuse-ld=lld";
      exec_argv[out++] = "-L";
      exec_argv[out++] = lib_dir;
    }
  }

  for (int i = 1; i < argc; i++) {
    exec_argv[out++] = argv[i];
  }

  if (tool->clang && !compile_only && !has_arg(argc, argv, "-nostdlib") && compiler_rt[0] && access(compiler_rt, R_OK) == 0) {
    exec_argv[out++] = compiler_rt;
  }
  exec_argv[out] = NULL;

  execv(real, exec_argv);
  fprintf(stderr, "llvm-toolchain wrapper: exec %s failed: %s\\n", real, strerror(errno));
  return errno == ENOENT ? 127 : 126;
}
"""
}

proc require_env_path(env_name: Str) [env, error] -> Result[Path] {
  let value = (env.get(env_name) ?? "").trim()

  if value == "" {
    return Err(LlvmToolchainError.Failed(f"${env_name} is required"))
  }

  Path.parse(value)?
}

proc build_wrapper(dest: Path) [fs, process, env, error] -> Result[Path] {
  let target_arch = pm_util.target_arch()?
  let build_arch = pm_util.build_arch()?
  let target_triple = f"${target_arch}-linux-musl"
  let source = p"llvm-toolchain-wrapper.c"
  let object = p"llvm-toolchain-wrapper.o"
  let binary = p"llvm-toolchain-wrapper"
  let compiler_rt = fp"${dest}/usr/lib/llvm22/lib/clang/22/lib/${target_arch}-alpine-linux-musl/libclang_rt.builtins-${target_arch}.a"
  fs.write(source, wrapper_source())?

  if build_arch == target_arch {
    let cc = fp"${dest}/usr/lib/llvm22/bin/clang-22"
    let ld = fp"${dest}/usr/lib/llvm-toolchain/bin/ld.lld"

    env {
      LD_LIBRARY_PATH = f"${dest}/usr/lib:${dest}/usr/lib/llvm22/lib"
    } {
      run $cc "-Os" "-fno-stack-protector" "-c" "-o" $object $source ?
      run $ld "-static" "-o" $binary /usr/lib/crt1.o /usr/lib/crti.o $object "-L/usr/lib" "--start-group" "-lc" $compiler_rt "--end-group" /usr/lib/crtn.o ?
    } ?
  } else {
    let build_root = require_env_path("XSH_PM_BUILD_ROOT")?
    let target_root = require_env_path("LAPUTA_ROOT")?
    let cc = fp"${build_root}/usr/lib/llvm22/bin/clang-22"
    let ld = fp"${build_root}/usr/lib/llvm-toolchain/bin/ld.lld"
    let target_crt1 = fp"${target_root}/usr/lib/crt1.o"
    let target_crti = fp"${target_root}/usr/lib/crti.o"
    let target_crtn = fp"${target_root}/usr/lib/crtn.o"

    env {
      LD_LIBRARY_PATH = f"${build_root}/usr/lib:${build_root}/usr/lib/llvm22/lib"
    } {
      run $cc f"--target=${target_triple}" f"--sysroot=${target_root.display()}" "-Os" "-fno-stack-protector" "-c" "-o" $object $source ?
      run $ld "-static" "-o" $binary $target_crt1 $target_crti $object f"-L${target_root}/usr/lib" "--start-group" "-lc" $compiler_rt "--end-group" $target_crtn ?
    } ?
  }

  return binary
}

proc write_wrapper(dest: Path, wrapper: Path, wrapper_name: Str) [fs, error] {
  let path_value = fp"${dest}/usr/bin/${wrapper_name}"
  fs.remove(path_value, missing_ok: true)?
  fs.install(wrapper, path_value, 0o755, parents: true, overwrite: true)?
}

export proc build(dest: Path) [fs, process, env, error] {
  let _ = fs.copy_tree(p".", dest, parents: true, overwrite: true)?

  for path_value in [fp"${dest}/usr/lib/libz.so.1", fp"${dest}/usr/lib/libz.so.1.3.2"] {
    fs.remove(path_value, missing_ok: true)?
  }

  fs.mkdir(fp"${dest}/usr/lib/llvm-toolchain/bin")?
  fs.rename(fp"${dest}/usr/bin/ld.lld", fp"${dest}/usr/lib/llvm-toolchain/bin/ld.lld", overwrite: true)?
  let wrapper = build_wrapper(dest)?
  let compiler_rt_lib = fp"${dest}/usr/lib/llvm22/lib/clang/22/lib"

  for entry in fs.ls(compiler_rt_lib)? |> where .kind == "dir" {
    if entry.name.ends_with("-alpine-linux-musl") {
      let alias = entry.name.replace("-alpine-linux-musl", "-linux-musl")
      let alias_path = fp"${compiler_rt_lib}/${alias}"
      fs.remove(alias_path, missing_ok: true)?
      fs.symlink(Path.parse(entry.name)?, alias_path)?
    }
  }

  write_wrapper(dest, wrapper, "cc")?
  write_wrapper(dest, wrapper, "clang")?
  write_wrapper(dest, wrapper, "c++")?
  write_wrapper(dest, wrapper, "clang++")?
  write_wrapper(dest, wrapper, "ld")?
  write_wrapper(dest, wrapper, "ld.lld")?
  write_wrapper(dest, wrapper, "ar")?
  write_wrapper(dest, wrapper, "ranlib")?
  write_wrapper(dest, wrapper, "nm")?
  write_wrapper(dest, wrapper, "objcopy")?
  write_wrapper(dest, wrapper, "objdump")?
  write_wrapper(dest, wrapper, "readelf")?
  write_wrapper(dest, wrapper, "strip")?

  for tool in ["ar", "ranlib", "nm", "objcopy", "objdump", "readelf", "strip"] {
    write_wrapper(dest, wrapper, f"llvm-${tool}")?
  }
}
