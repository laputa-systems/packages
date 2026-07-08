use pm.make as make

export let name = "libnl3"

export let ver = "3.11.0"

export let rel = "1"

export let deps = ["musl", "linux"]

export let mkdeps = []

export let sources = [p"https://github.com/thom311/libnl/releases/download/libnl3_11_0/libnl-3.11.0.tar.gz"]

export let checksums = ["2a56e1edefa3e68a7c00879496736fdbf62fc94ed3232c0baba127ecfa76874d"]

export proc build(dest: Path) [fs, process, env, error] {
  let cwd = fs.cwd()?
  let src = cwd
  let objs = fp"${dest}/objs"
  fs.mkdir(objs)?

  # Generate include/netlink/version.h from version.h.in
  fs.mkdir(fp"${src}/include/netlink")?
  let version_h = fp"${src}/include/netlink/version.h"
  let version_in = fp"${src}/include/netlink/version.h.in"

  if ! fs.exists(version_h)? and fs.exists(version_in)? {
    let tmpl = fs.read_text(version_in)?
    let parts = ver.split(".")
    let major = parts[0]
    let minor = if parts.len() > 1 { parts[1] } else { "0" }
    let micro = if parts.len() > 2 { parts[2] } else { "0" }
    let body = tmpl.replace("@MAJOR_VERSION@", major).replace("@MINOR_VERSION@", minor).replace("@MICRO_VERSION@", micro)
    fs.write(version_h, body)?
  }

  # Generate include/config.h (minimal — configure would produce this)
  let config_h = fp"${src}/include/config.h"

  if ! fs.exists(config_h)? {
    let cfg_body = f"""#ifndef LIBNL_CONFIG_H
#define LIBNL_CONFIG_H
#define PACKAGE_STRING "libnl ${ver}"
#define PACKAGE_NAME "libnl"
#define PACKAGE_VERSION "${ver}"
#define SYSCONFDIR "/etc"
#define PACKAGE_URL "http://www.infradead.org/~tgr/libnl/"
#define PACKAGE "libnl-3-11-0"
#define STDC_HEADERS 1
#define HAVE_STDINT_H 1
#define HAVE_STDDEF_H 1
#define HAVE_STDLIB_H 1
#define HAVE_STRING_H 1
#define HAVE_UNISTD_H 1
#define HAVE_SYS_SOCKET_H 1
#define HAVE_SYS_TIME_H 1
#define HAVE_LINUX_IF_TUN_H 1
#define HAVE_LINUX_IF_PACKET_H 1
#define HAVE_ARPA_INET_H 1
#define HAVE_DLFCN_H 1
#define HAVE_FCNTL_H 1
#define HAVE_NETDB_H 1
#define HAVE_NETINET_IN_H 1
#define HAVE_SYS_SELECT_H 1
#define HAVE_STRERROR_L 1
#define HAVE_FLOCK 1
#define HAVE_GETTIMEOFDAY 1
#define TIME_WITH_SYS_TIME 1
#define NL_DEBUG 0
#define const /**/
#endif
"""

    fs.write(config_h, cfg_body)?
  }

  let cc = process.which("cc")?
  let triple = f"${env.get("XSH_PM_ARCH") ?? "aarch64"}-linux-musl"

  # Pre-create install directories.
  fs.mkdir(fp"${dest}/usr")?
  fs.mkdir(fp"${dest}/usr/lib")?
  fs.mkdir(fp"${dest}/usr/include")?
  var cflags = ["-O2", "-fPIC", "-DPIC", "-D_GNU_SOURCE"]
  var defs = []

  var includes = [
    "-I",
    fp"${src}/include".display(),
    "-I",
    fp"${src}/include/linux-private".display(),
    "-I",
    fp"${src}/lib".display(),
    "-I",
    src.display(),
  ]

  # Core source files for libnl-3.so
  let core_sources = [
    p"lib/mpls.c",
    p"lib/addr.c",
    p"lib/attr.c",
    p"lib/cache.c",
    p"lib/cache_mngr.c",
    p"lib/cache_mngt.c",
    p"lib/data.c",
    p"lib/error.c",
    p"lib/handlers.c",
    p"lib/hash.c",
    p"lib/hashtable.c",
    p"lib/msg.c",
    p"lib/nl.c",
    p"lib/object.c",
    p"lib/socket.c",
    p"lib/utils.c",
    p"lib/version.c",
  ]

  # genl source files for libnl-genl-3.so
  let genl_sources = [p"lib/genl/ctrl.c", p"lib/genl/family.c", p"lib/genl/genl.c", p"lib/genl/mngt.c"]

  let core_so = fp"${dest}/usr/lib/libnl-3.so.200.26.0"
  let genl_so = fp"${dest}/usr/lib/libnl-genl-3.so.200.26.0"
  let core = make.c_shared_library({
    cc,
    triple,
    cflags,
    defs,
    includes,
    root: src,
    sources: core_sources,
    out_dir: objs,
    out: core_so,
    soname: "libnl-3.so.200",
    ldflags: [],
    deps: [],
  })

  let genl = make.c_shared_library({
    cc,
    triple,
    cflags,
    defs,
    includes,
    root: src,
    sources: genl_sources,
    out_dir: objs,
    out: genl_so,
    soname: "libnl-genl-3.so.200",
    ldflags: [],
    deps: [],
  })

  make.run_tasks(core.tasks.extend(genl.tasks), make.jobs()?)?

  # Create symlinks
  for lib in [core_so, genl_so] {
    let basename = lib.name
    let parts = basename.split(".so.")
    let soname = f"${parts[0]}.so.${parts[1].split(".")[0]}"
    let linker = f"${parts[0]}.so"
    fs.symlink(fp"${basename}", fp"${dest}/usr/lib/${soname}")?
    fs.symlink(fp"${soname}", fp"${dest}/usr/lib/${linker}")?
  }

  # Stub missing kernel header.  linux/filter.h (UAPI) includes linux/compiler.h
  # which is a kernel-internal header not exported to userspace.
  let linux_hdrs = fp"${dest}/usr/include/linux"
  fs.mkdir(linux_hdrs)?

  fs.write(
    fp"${linux_hdrs}/compiler.h",
    """#ifndef _UAPI_LINUX_COMPILER_H
#define _UAPI_LINUX_COMPILER_H
#define __user
#define __force
#define __iomem
#define __bitwise __bitwise__
#define __attribute_const__ __attribute__((__const__))
#define __printf(a, b) __attribute__((__format__(printf, a, b)))
#define __scanf(a, b) __attribute__((__format__(__scanf__, a, b)))
#define __cold __attribute__((__cold__))
#define __visible __attribute__((__externally_visible__))
#define __packed __attribute__((__packed__))
#define __aligned(x) __attribute__((__aligned__(x)))
#define __section(x) __attribute__((__section__(x)))
#define __always_inline inline __attribute__((__always_inline__))
#define __noinline __attribute__((__noinline__))
#define __must_check __attribute__((__warn_unused_result__))
#define __same_type(a, b) __builtin_types_compatible_p(typeof(a), typeof(b))
#define __is_constexpr(x) __builtin_constant_p(x)
#define __counted_by(m)
#define __rcu
#define __nocast
#define __read_mostly
#define __ro_after_init
#endif
""",
  )?

  # Install public headers at /usr/include/netlink/
  let usr_include = fp"${dest}/usr/include"
  fs.mkdir(usr_include)?
  let headers_src = fp"${src}/include/netlink"
  let headers_dest = fp"${dest}/usr/include/netlink"
  make.install_header_tree(headers_src, headers_dest, [p"version.h.in"])?
}
