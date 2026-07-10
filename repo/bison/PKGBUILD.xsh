use pm.configure as configure
use pm.make as make
use pm.target as target
use pm.util as pm_util

export let name = "bison"

export let ver = "3.8.2"

export let rel = "6"

export let deps = ["musl"]

export let mkdeps = ["llvm-toolchain"]

export let sources = [p"https://mirrors.kernel.org/gnu/bison/bison-VERSION.tar.xz", p"files/bison.xsh"]

export let checksums = [
  "9bba0214ccf7f1079c5d59210045227bcf619519840ebfa80cd3849cff5a5bf2",
  "0f6f22bcd40969af45cfd50bdb5ffd78cc68c3da06354084291cffd77740e7f4",
]

proc install_data_tree(src: Path, dest: Path) [fs, error] {
  for e in fs.ls(src)? {
    if e.kind == "dir" {
      install_data_tree(e.path, fp"${dest}/${e.name}")?
    } else if e.kind == "file" {
      fs.install(e.path, fp"${dest}/${e.name}", 0o644, parents: true, overwrite: true)?
    }
  }
}

export proc build(dest: Path) [fs, process, env, error] {
  let cc = process.which("cc")?
  let arch = pm_util.target_arch()?
  let triple = f"${arch}-linux-musl"
  let abi = target.lp64_musl_abi(arch)

  # Generate config.h from lib/config.in.h.
  # lib/config.in.h is the bison/gnulib unified config template (549 #undef
  # entries, zero @VAR@ substitutions — all values are set explicitly here).
  # Values are for musl + Clang on x86_64 and aarch64; both
  # architectures exercise the same configure probes.
  var defines: Map[Str] = {}

  # Package metadata
  defines["PACKAGE"] = "\"bison\""
  defines["PACKAGE_BUGREPORT"] = "\"bug-bison@gnu.org\""
  defines["PACKAGE_COPYRIGHT_YEAR"] = "2021"
  defines["PACKAGE_NAME"] = "\"GNU Bison\""
  defines["PACKAGE_STRING"] = f"\"GNU Bison ${ver}\""
  defines["PACKAGE_TARNAME"] = "\"bison\""
  defines["PACKAGE_URL"] = "\"https://www.gnu.org/software/bison/\""
  defines["PACKAGE_VERSION"] = f"\"${ver}\""
  defines["VERSION"] = f"\"${ver}\""

  # musl-specific
  defines["MUSL_LIBC"] = "1"
  defines["MALLOC_0_IS_NONNULL"] = "1"
  defines["STDC_HEADERS"] = "1"

  # m4 runtime path and GNU option flag
  defines["M4"] = "\"/usr/bin/m4\""
  defines["M4_GNU_OPTION"] = "\"--gnu\""
  defines["BITSIZEOF_PTRDIFF_T"] = abi.ptrdiff_bits
  defines["BITSIZEOF_SIG_ATOMIC_T"] = abi.sig_atomic_bits
  defines["BITSIZEOF_SIZE_T"] = abi.size_t_bits
  defines["BITSIZEOF_WCHAR_T"] = abi.wchar_t_bits
  defines["BITSIZEOF_WINT_T"] = abi.wint_t_bits
  defines["PTRDIFF_T_SUFFIX"] = abi.ptrdiff_suffix
  defines["SIG_ATOMIC_T_SUFFIX"] = abi.sig_atomic_suffix
  defines["SIZE_T_SUFFIX"] = abi.size_t_suffix
  defines["WCHAR_T_SUFFIX"] = abi.wchar_t_suffix
  defines["WINT_T_SUFFIX"] = abi.wint_t_suffix
  defines["HAVE_SIGNED_SIG_ATOMIC_T"] = if abi.signed_sig_atomic_t { "1" } else { "0" }
  defines["HAVE_SIGNED_WCHAR_T"] = if abi.signed_wchar_t { "1" } else { "0" }

  # Compiler features (Clang-based)
  defines["HAVE_INLINE"] = "1"
  defines["HAVE___BUILTIN_EXPECT"] = "1"
  defines["HAVE___INLINE"] = "1"
  defines["HAVE_VISIBILITY"] = "1"

  # Standard headers — all present in musl
  defines["HAVE_ALLOCA_H"] = "1"
  defines["HAVE_DIRENT_H"] = "1"
  defines["HAVE_FEATURES_H"] = "1"
  defines["HAVE_GETOPT_H"] = "1"
  defines["HAVE_ICONV_H"] = "1"
  defines["HAVE_INTTYPES_H"] = "1"
  defines["HAVE_LANGINFO_H"] = "1"
  defines["HAVE_LIMITS_H"] = "1"
  defines["HAVE_LOCALE_H"] = "1"
  defines["HAVE_MATH_H"] = "1"
  defines["HAVE_PATHS_H"] = "1"
  defines["HAVE_SCHED_H"] = "1"
  defines["HAVE_SEARCH_H"] = "1"
  defines["HAVE_SPAWN_H"] = "1"
  defines["HAVE_STDINT_H"] = "1"
  defines["HAVE_STDIO_H"] = "1"
  defines["HAVE_STDLIB_H"] = "1"
  defines["HAVE_STRINGS_H"] = "1"
  defines["HAVE_STRING_H"] = "1"
  defines["HAVE_SYS_IOCTL_H"] = "1"
  defines["HAVE_SYS_MMAN_H"] = "1"
  defines["HAVE_SYS_PARAM_H"] = "1"
  defines["HAVE_SYS_RESOURCE_H"] = "1"
  defines["HAVE_SYS_SOCKET_H"] = "1"
  defines["HAVE_SYS_STAT_H"] = "1"
  defines["HAVE_SYS_TIMES_H"] = "1"
  defines["HAVE_SYS_TIME_H"] = "1"
  defines["HAVE_SYS_TYPES_H"] = "1"
  defines["HAVE_SYS_WAIT_H"] = "1"
  defines["HAVE_TERMIOS_H"] = "1"
  defines["HAVE_UNISTD_H"] = "1"
  defines["HAVE_WCHAR_H"] = "1"
  defines["HAVE_WCTYPE_H"] = "1"

  # Standard functions — all present in musl
  defines["HAVE_ALLOCA"] = "1"
  defines["HAVE_CANONICALIZE_FILE_NAME"] = "1"
  defines["HAVE_CLOCK_GETTIME"] = "1"
  defines["HAVE_CLOSEDIR"] = "1"
  defines["HAVE_DIRFD"] = "1"
  defines["HAVE_FACCESSAT"] = "1"
  defines["HAVE_FCHDIR"] = "1"
  defines["HAVE_FCNTL"] = "1"
  defines["HAVE_FDOPENDIR"] = "1"
  defines["HAVE_FFSL"] = "1"
  defines["HAVE_FLOCKFILE"] = "1"
  defines["HAVE_FREE_POSIX"] = "1"
  defines["HAVE_FSTATAT"] = "1"
  defines["HAVE_FSYNC"] = "1"
  defines["HAVE_FUNLOCKFILE"] = "1"
  defines["HAVE_GETCWD"] = "1"
  defines["HAVE_GETDELIM"] = "1"
  defines["HAVE_GETDTABLESIZE"] = "1"
  defines["HAVE_GETOPT_LONG_ONLY"] = "1"
  defines["HAVE_GETPAGESIZE"] = "1"
  defines["HAVE_GETPROGNAME"] = "1"
  defines["HAVE_GETRUSAGE"] = "1"
  defines["HAVE_GETTIMEOFDAY"] = "1"
  defines["HAVE_ICONV"] = "1"
  defines["HAVE_INTMAX_T"] = "1"
  defines["HAVE_ISASCII"] = "1"
  defines["HAVE_ISWBLANK"] = "1"
  defines["HAVE_ISWCNTRL"] = "1"
  defines["HAVE_LANGINFO_CODESET"] = "1"
  defines["HAVE_LDEXPL"] = "1"
  defines["HAVE_LINK"] = "1"
  defines["HAVE_LONG_LONG_INT"] = "1"
  defines["HAVE_LSTAT"] = "1"
  defines["HAVE_MALLOC_POSIX"] = "1"
  defines["HAVE_MBRTOWC"] = "1"
  defines["HAVE_MBSINIT"] = "1"
  defines["HAVE_MBSTATE_T"] = "1"
  defines["HAVE_MEMPCPY"] = "1"
  defines["HAVE_MEMRCHR"] = "1"
  defines["HAVE_MPROTECT"] = "1"
  defines["HAVE_NL_LANGINFO"] = "1"
  defines["HAVE_OPENAT"] = "1"
  defines["HAVE_OPENDIR"] = "1"
  defines["HAVE_PIPE"] = "1"
  defines["HAVE_PIPE2"] = "1"
  defines["HAVE_POSIX_SPAWN"] = "1"
  defines["HAVE_POSIX_SPAWNATTR_T"] = "1"
  defines["HAVE_POSIX_SPAWN_FILE_ACTIONS_T"] = "1"
  defines["HAVE_PTHREAD_API"] = "1"
  defines["HAVE_PTHREAD_MUTEX_RECURSIVE"] = "1"
  defines["HAVE_PTHREAD_RWLOCK"] = "1"
  defines["HAVE_PTHREAD_RWLOCK_RDLOCK_PREFER_WRITER"] = "1"
  defines["HAVE_RAISE"] = "1"
  defines["HAVE_RAWMEMCHR"] = "0"
  defines["HAVE_READDIR"] = "1"
  defines["HAVE_READLINK"] = "1"
  defines["HAVE_READLINKAT"] = "1"
  defines["HAVE_REALLOCARRAY"] = "1"
  defines["HAVE_REALPATH"] = "1"
  defines["HAVE_REWINDDIR"] = "1"
  defines["HAVE_SCHED_SETPARAM"] = "1"
  defines["HAVE_SCHED_SETSCHEDULER"] = "1"
  defines["HAVE_SETENV"] = "1"
  defines["HAVE_SETLOCALE"] = "1"
  defines["HAVE_SIGACTION"] = "1"
  defines["HAVE_SIGALTSTACK"] = "1"
  defines["HAVE_SIGINFO_T"] = "1"
  defines["HAVE_SIGINTERRUPT"] = "1"
  defines["HAVE_SIGSET_T"] = "1"
  defines["HAVE_SIG_ATOMIC_T"] = "1"
  defines["HAVE_SNPRINTF"] = "1"
  defines["HAVE_SNPRINTF_RETVAL_C99"] = "1"
  defines["HAVE_SNPRINTF_TRUNCATION_C99"] = "1"
  defines["HAVE_STPCPY"] = "1"
  defines["HAVE_STPNCPY"] = "1"
  defines["HAVE_STRCHRNUL"] = "1"
  defines["HAVE_STRERROR_R"] = "1"
  defines["HAVE_STRNDUP"] = "1"
  defines["HAVE_STRNLEN"] = "1"
  defines["HAVE_STRUCT_SIGACTION_SA_SIGACTION"] = "1"
  defines["HAVE_STRUCT_STAT_ST_ATIM_TV_NSEC"] = "1"
  defines["HAVE_STRUCT_TMS"] = "1"
  defines["HAVE_SYMLINK"] = "1"
  defines["HAVE_TCDRAIN"] = "1"
  defines["HAVE_TSEARCH"] = "1"
  defines["HAVE_UNSETENV"] = "1"
  defines["HAVE_UNSIGNED_LONG_LONG_INT"] = "1"
  defines["HAVE_VASNPRINTF"] = "1"
  defines["HAVE_VASPRINTF"] = "1"
  defines["HAVE_VFORK"] = "1"
  defines["HAVE_VSNPRINTF"] = "1"
  defines["HAVE_WAITID"] = "1"
  defines["HAVE_WCHAR_T"] = "1"
  defines["HAVE_WCRTOMB"] = "1"
  defines["HAVE_WCSLEN"] = "1"
  defines["HAVE_WCSNLEN"] = "1"
  defines["HAVE_WCWIDTH"] = "1"
  defines["HAVE_WINT_T"] = "1"
  defines["HAVE__BOOL"] = "1"

  # Declarations present in musl headers
  defines["HAVE_DECL_ALARM"] = "1"
  defines["HAVE_DECL_CLEARERR_UNLOCKED"] = "1"
  defines["HAVE_DECL_DIRFD"] = "1"
  defines["HAVE_DECL_FCHDIR"] = "1"
  defines["HAVE_DECL_FDOPENDIR"] = "1"
  defines["HAVE_DECL_FEOF_UNLOCKED"] = "1"
  defines["HAVE_DECL_FERROR_UNLOCKED"] = "1"
  defines["HAVE_DECL_FFLUSH_UNLOCKED"] = "1"
  defines["HAVE_DECL_FGETS_UNLOCKED"] = "1"
  defines["HAVE_DECL_FPUTC_UNLOCKED"] = "1"
  defines["HAVE_DECL_FPUTS_UNLOCKED"] = "1"
  defines["HAVE_DECL_FREAD_UNLOCKED"] = "1"
  defines["HAVE_DECL_FWRITE_UNLOCKED"] = "1"
  defines["HAVE_DECL_GETCWD"] = "1"
  defines["HAVE_DECL_GETCHAR_UNLOCKED"] = "1"
  defines["HAVE_DECL_GETC_UNLOCKED"] = "1"
  defines["HAVE_DECL_GETDELIM"] = "1"
  defines["HAVE_DECL_GETDTABLESIZE"] = "1"
  defines["HAVE_DECL_GETLINE"] = "1"
  defines["HAVE_DECL_ISWBLANK"] = "1"
  defines["HAVE_DECL_MBRTOWC"] = "1"
  defines["HAVE_DECL_MBSINIT"] = "1"
  defines["HAVE_DECL_MEMRCHR"] = "1"
  defines["HAVE_DECL_POSIX_SPAWN"] = "1"
  defines["HAVE_DECL_PROGRAM_INVOCATION_NAME"] = "0"
  defines["HAVE_DECL_PROGRAM_INVOCATION_SHORT_NAME"] = "0"
  defines["HAVE_VAR___PROGNAME"] = "1"
  defines["HAVE_DECL_PUTCHAR_UNLOCKED"] = "1"
  defines["HAVE_DECL_PUTC_UNLOCKED"] = "1"
  defines["HAVE_DECL_SETENV"] = "1"
  defines["HAVE_DECL_SNPRINTF"] = "1"
  defines["HAVE_DECL_STPNCPY"] = "1"
  defines["HAVE_DECL_STRDUP"] = "1"
  defines["HAVE_DECL_STRERROR_R"] = "1"
  defines["HAVE_DECL_STRNDUP"] = "1"
  defines["HAVE_DECL_STRNLEN"] = "1"
  defines["HAVE_DECL_TOWLOWER"] = "1"
  defines["HAVE_DECL_UNSETENV"] = "1"
  defines["HAVE_DECL_VSNPRINTF"] = "1"
  defines["HAVE_DECL_WCWIDTH"] = "1"

  # Struct fields present in musl's stat
  defines["TYPEOF_STRUCT_STAT_ST_ATIM_IS_STRUCT_TIMESPEC"] = "1"
  defines["LSTAT_FOLLOWS_SLASHED_SYMLINK"] = "1"

  # iconv: musl uses const char ** for the inbuf argument (same as glibc)
  defines["ICONV_CONST"] = "const"

  # Threads: pthreads are part of musl's libc (no separate libpthread)
  defines["USE_POSIX_THREADS"] = "1"
  defines["USE_POSIX_THREADS_FROM_LIBC"] = "1"

  # Optional deps not available in our sysroot
  defines["HAVE_READLINE"] = "0"
  defines["HAVE_LIBTEXTSTYLE"] = "0"

  # NLS disabled
  defines["ENABLE_NLS"] = "0"
  defines["YYENABLE_NLS"] = "0"

  # gnulib unistring modules used by bison (controls declarations in unistr.h)
  defines["GNULIB_UNISTR_U8_MBTOUCR"] = "1"
  defines["GNULIB_UNISTR_U8_UCTOMB"] = "1"
  defines["GNULIB_DIRNAME"] = "1"
  defines["GNULIB_FOPEN_SAFER"] = "1"
  defines["GNULIB_XALLOC"] = "1"
  defines["GNULIB_XALLOC_DIE"] = "1"

  # Replace flags — musl implementations are all correct, no gnulib overrides
  defines["REPLACE_DIRFD"] = "0"
  defines["REPLACE_FCHDIR"] = "0"
  defines["REPLACE_FPRINTF_POSIX"] = "0"
  defines["REPLACE_FUNC_STAT_FILE"] = "0"
  defines["REPLACE_OPEN_DIRECTORY"] = "0"
  defines["REPLACE_POSIX_SPAWN"] = "0"
  defines["REPLACE_PRINTF_POSIX"] = "0"
  defines["REPLACE_STRERROR_0"] = "0"
  defines["REPLACE_VASNPRINTF"] = "0"
  defines["REPLACE_VFPRINTF_POSIX"] = "0"
  configure.config_h(p"lib/config.in.h", p"config.h", defines)?

  # Generate gnulib POSIX header passthroughs.
  # On musl, all POSIX headers are complete. Each wrapper just redirects to
  # the system header via #include_next. The pragma suppresses warnings.
  let pt = """#pragma GCC system_header
#include_next """

  fs.write(
    p"lib/alloca.h",
    f"""${pt}<alloca.h>
""",
  )?

  fs.write(
    p"lib/dirent.h",
    f"""${pt}<dirent.h>
""",
  )?

  fs.write(
    p"lib/errno.h",
    f"""${pt}<errno.h>
""",
  )?

  fs.write(
    p"lib/fcntl.h",
    f"""${pt}<fcntl.h>
#ifndef O_BINARY
# define O_BINARY 0
#endif
#ifndef O_TEXT
# define O_TEXT 0
#endif
""",
  )?

  fs.write(
    p"lib/float.h",
    f"""${pt}<float.h>
""",
  )?

  fs.write(
    p"lib/getopt.h",
    f"""${pt}<getopt.h>
""",
  )?

  fs.write(
    p"lib/iconv.h",
    f"""${pt}<iconv.h>
""",
  )?

  fs.write(
    p"lib/inttypes.h",
    f"""${pt}<inttypes.h>
""",
  )?

  fs.write(
    p"lib/limits.h",
    f"""${pt}<limits.h>
""",
  )?

  fs.write(
    p"lib/locale.h",
    f"""${pt}<locale.h>
#include "setlocale_null.h"
""",
  )?

  fs.write(
    p"lib/math.h",
    f"""${pt}<math.h>
""",
  )?

  fs.write(
    p"lib/sched.h",
    f"""${pt}<sched.h>
""",
  )?

  fs.write(
    p"lib/signal.h",
    f"""${pt}<signal.h>
""",
  )?

  fs.write(
    p"lib/spawn.h",
    f"""${pt}<spawn.h>
""",
  )?

  fs.write(
    p"lib/stdbool.h",
    f"""${pt}<stdbool.h>
""",
  )?

  fs.write(
    p"lib/stddef.h",
    f"""${pt}<stddef.h>
""",
  )?

  fs.write(
    p"lib/stdint.h",
    f"""${pt}<stdint.h>
""",
  )?

  fs.write(
    p"lib/stdio.h",
    f"""${pt}<stdio.h>
#include "arg-nonnull.h"
#ifndef _GL_ATTRIBUTE_SPEC_PRINTF_STANDARD
# if __GNUC__ > 4 || (__GNUC__ == 4 && __GNUC_MINOR__ >= 4)
#  define _GL_ATTRIBUTE_SPEC_PRINTF_STANDARD __gnu_printf__
# else
#  define _GL_ATTRIBUTE_SPEC_PRINTF_STANDARD __printf__
# endif
#endif
#ifndef _GL_ATTRIBUTE_SPEC_PRINTF_SYSTEM
# define _GL_ATTRIBUTE_SPEC_PRINTF_SYSTEM __printf__
#endif
#ifndef _GL_ATTRIBUTE_FORMAT_PRINTF_STANDARD
# define _GL_ATTRIBUTE_FORMAT_PRINTF_STANDARD(formatstring_parameter, first_argument) _GL_ATTRIBUTE_FORMAT ((_GL_ATTRIBUTE_SPEC_PRINTF_STANDARD, formatstring_parameter, first_argument))
#endif
#ifndef _GL_ATTRIBUTE_FORMAT_PRINTF_SYSTEM
# define _GL_ATTRIBUTE_FORMAT_PRINTF_SYSTEM(formatstring_parameter, first_argument) _GL_ATTRIBUTE_FORMAT ((_GL_ATTRIBUTE_SPEC_PRINTF_SYSTEM, formatstring_parameter, first_argument))
#endif
""",
  )?

  fs.write(
    p"lib/stdlib.h",
    f"""${pt}<stdlib.h>
""",
  )?

  fs.write(
    p"lib/string.h",
    f"""${pt}<string.h>
""",
  )?

  fs.write(
    p"lib/strings.h",
    f"""${pt}<strings.h>
""",
  )?

  fs.write(
    p"lib/termios.h",
    f"""${pt}<termios.h>
""",
  )?

  fs.write(
    p"lib/time.h",
    f"""${pt}<time.h>
""",
  )?

  fs.write(
    p"lib/unistd.h",
    f"""${pt}<unistd.h>
""",
  )?

  fs.write(
    p"lib/wchar.h",
    f"""${pt}<wchar.h>
""",
  )?

  fs.write(
    p"lib/wctype.h",
    f"""${pt}<wctype.h>
""",
  )?

  # sys/ headers live in a subdirectory
  fs.mkdir(p"lib/sys")?

  fs.write(
    p"lib/sys/ioctl.h",
    f"""${pt}<sys/ioctl.h>
""",
  )?

  fs.write(
    p"lib/sys/resource.h",
    f"""${pt}<sys/resource.h>
""",
  )?

  fs.write(
    p"lib/sys/stat.h",
    f"""${pt}<sys/stat.h>
""",
  )?

  fs.write(
    p"lib/sys/time.h",
    f"""${pt}<sys/time.h>
""",
  )?

  fs.write(
    p"lib/sys/times.h",
    f"""${pt}<sys/times.h>
""",
  )?

  fs.write(
    p"lib/sys/types.h",
    f"""${pt}<sys/types.h>
""",
  )?

  fs.write(
    p"lib/sys/wait.h",
    f"""${pt}<sys/wait.h>
""",
  )?

  # Files with zero @VAR@ placeholders — copy .in.h directly as the header.
  # stdalign/getopt-cdefs: gnulib portability headers, complete as shipped.
  # unitypes/unistr/uniwidth: bundled libunistring API, no substitution needed.
  # textstyle: already a complete no-libtextstyle stub per its header comment.
  fs.write(p"lib/stdalign.h", fs.read_text(p"lib/stdalign.in.h")?)?
  fs.write(p"lib/getopt-cdefs.h", fs.read_text(p"lib/getopt-cdefs.in.h")?)?
  fs.write(p"lib/unitypes.h", fs.read_text(p"lib/unitypes.in.h")?)?
  fs.write(p"lib/unistr.h", fs.read_text(p"lib/unistr.in.h")?)?
  fs.write(p"lib/uniwidth.h", fs.read_text(p"lib/uniwidth.in.h")?)?
  fs.write(p"lib/textstyle.h", fs.read_text(p"lib/textstyle.in.h")?)?
  var scratch_lines = []

  for line in p"lib/malloc/scratch_buffer.h".lines()? {
    if ! ("libc_hidden_proto" in line) {
      var generated = line.replace("__always_inline", "inline _GL_ATTRIBUTE_ALWAYS_INLINE")
      generated = generated.replace("__glibc_likely", "_GL_LIKELY")
      generated = generated.replace("__glibc_unlikely", "_GL_UNLIKELY")
      scratch_lines = scratch_lines.push(generated)
    }
  }

  fs.write(
    p"lib/malloc/scratch_buffer.gl.h",
    f"""/* DO NOT EDIT! GENERATED AUTOMATICALLY! */
${scratch_lines.join("\n")}
""",
  )?

  fs.write(
    p"lib/xsh-gnulib-shims.h",
    """#include <errno.h>
#include <spawn.h>
#include <stddef.h>
#include <stdio.h>
#include "setlocale_null.h"
FILE *fopen_safer (char const *filename, char const *mode);
const char *getprogname (void);
void *rawmemchr (const void *s, int c_in);
static inline int
posix_spawn_file_actions_addchdir (posix_spawn_file_actions_t *actions, const char *path)
{
  (void) actions;
  (void) path;
  return ENOSYS;
}
""",
  )?

  fs.write(
    p"lib/xsh-getprogname.c",
    """const char *
getprogname (void)
{
  return "bison";
}
""",
  )?

  fs.write(
    p"lib/configmake.h",
    """#define PREFIX "/usr"
#define EXEC_PREFIX "/usr"
#define BINDIR "/usr/bin"
#define SBINDIR "/usr/bin"
#define LIBEXECDIR "/usr/libexec"
#define DATAROOTDIR "/usr/share"
#define DATADIR "/usr/share"
#define SYSCONFDIR "/etc"
#define SHAREDSTATEDIR "/usr/com"
#define LOCALSTATEDIR "/var"
#define RUNSTATEDIR "/run"
#define INCLUDEDIR "/usr/include"
#define OLDINCLUDEDIR "/usr/include"
#define DOCDIR "/usr/share/doc/bison"
#define INFODIR "/usr/share/info"
#define HTMLDIR "/usr/share/doc/bison"
#define DVIDIR "/usr/share/doc/bison"
#define PDFDIR "/usr/share/doc/bison"
#define PSDIR "/usr/share/doc/bison"
#define LIBDIR "/usr/lib"
#define LISPDIR "/usr/share/emacs/site-lisp"
#define LOCALEDIR "/usr/share/locale"
#define MANDIR "/usr/share/man"
#define MANEXT ""
#define PKGDATADIR "/usr/share/bison"
#define PKGINCLUDEDIR "/usr/include/bison"
#define PKGLIBDIR "/usr/lib/bison"
#define PKGLIBEXECDIR "/usr/libexec/bison"
""",
  )?

  let cflags = ["-g", "-O2", "-Wno-error=implicit-function-declaration"]

  # PKGDATADIR: hardcoded path where bison finds skeleton and m4sugar files.
  let defs = [
    "-DHAVE_CONFIG_H",
    "-D_GNU_SOURCE",
    "-DUINTPTR_WIDTH=64",
    "-DUCHAR_WIDTH=8",
    "-include",
    "lib/xsh-gnulib-shims.h",
    "-DPKGDATADIR=\"/usr/share/bison\"",
  ]

  # -I. first so <config.h> resolves to ./config.h, not lib/config.h.
  # -Ilib for gnulib interface headers and generated passthrough headers.
  # -Isrc for bison's own internal headers.
  let includes = ["-I.", "-Ilib", "-Isrc"]
  var lib_sources = []
  var in_sources = false

  for line in p"lib/gnulib.mk".lines()? {
    var chunk: Str = line

    if line.starts_with("lib_libbison_a_SOURCES +=") {
      chunk = line.replace("lib_libbison_a_SOURCES +=", "")
      in_sources = true
    }

    if in_sources {
      let keep_going = chunk.trim().ends_with("\\")

      for word in chunk.replace("\\", "").trim().split(" ") |> where . != "" {
        if word.ends_with(".c") {
          lib_sources = lib_sources.push(fp"${word}")
        }
      }

      in_sources = keep_going
    }
  }

  lib_sources = lib_sources.push(p"lib/rawmemchr.c")
  lib_sources = lib_sources.push(p"lib/error.c")
  lib_sources = lib_sources.push(p"lib/obstack.c")
  lib_sources = lib_sources.push(p"lib/obstack_printf.c")
  lib_sources = lib_sources.push(p"lib/asnprintf.c")
  lib_sources = lib_sources.push(p"lib/printf-args.c")
  lib_sources = lib_sources.push(p"lib/printf-parse.c")
  lib_sources = lib_sources.push(p"lib/vasnprintf.c")
  lib_sources = lib_sources.push(p"lib/get-errno.c")
  lib_sources = lib_sources.push(p"lib/setlocale-lock.c")
  lib_sources = lib_sources.push(p"lib/chdir-long.c")
  lib_sources = lib_sources.push(p"lib/path-join.c")
  lib_sources = lib_sources.push(p"lib/xsh-getprogname.c")

  # Compile bison's src/*.c (scanners and parsers are pre-generated in tarball)
  let src_sources = make.discover_sources(
    p"src",
    ["c"],
    [p"i18n-strings.c", p"scan-code.c", p"scan-gram.c", p"scan-skel.c"],
  )?

  let bison = make.c_program({
    cc,
    triple,
    cflags,
    defs,
    includes,
    root: p".",
    sources: lib_sources.extend([fp"src/${source}" for source in src_sources]),
    out_dir: p"obj",
    out: p"obj/bison",
    libs: [],
    ldflags: [],
    deps: [],
  })

  make.run_tasks(bison.tasks, make.jobs()?)?
  fs.install(bison.output, fp"${dest}/usr/bin/bison", 0o755, parents: true, overwrite: true)?

  # POSIX yacc compatibility wrapper
  fs.write(
    fp"${dest}/usr/bin/yacc",
    """#!/bin/xsh --
proc main(...argv: List[Str]) [process, error] {
  unix.exec(process.command_argv("bison", ["bison", "-y"].extend(argv)))?
}

main(@args)?
""",
  )?

  fs.chmod(fp"${dest}/usr/bin/yacc", 0o755)?

  # Install bison's data files to /usr/share/bison/.
  # bison reads skeleton files and m4sugar helpers here at runtime; the path
  # is compiled in via -DPKGDATADIR above.
  install_data_tree(p"data", fp"${dest}/usr/share/bison")?
  fs.install(p"bison.xsh", fp"${dest}/usr/lib/pm/repo/bison/files/bison.xsh", 0o755, parents: true, overwrite: true)?
}
