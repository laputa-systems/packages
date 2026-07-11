use pm.make as make
use pm.util as pm_util

error ScriptError = Failed(kind: Str, message: Str)

export let name = "mdevd"

export let ver = "0.1.8.2"

export let rel = "7"

export let deps = ["musl"]

export let mkdeps = ["llvm-toolchain", "xinit"]

export let sources = [
  p"https://skarnet.org/software/mdevd/mdevd-VERSION.tar.gz",
  p"https://skarnet.org/software/skalibs/skalibs-2.15.0.0.tar.gz => skalibs",
  p"service.xsh",
]

export let checksums = [
  "ce1ae0149b6a57a34f608218fd6181aa6aa68135cac2f4d931b5b417b072e244",
  "7fde96e8afb4191593a15328883e9c7726c96891cf071222146821e8c87f8007",
  "SKIP",
]

export let filetree = [
  {path: p"usr/bin/mdevd", kind: "binary"},
  {path: p"usr/bin/mdevd-coldplug", kind: "binary"},
  {path: p"usr/lib/xinit/services/mdevd.xsh", kind: "file"},
]

pure upper_ascii(text: Str) -> Str {
  text.replace("a", "A").replace("b", "B").replace("c", "C").replace("d", "D").replace("e", "E").replace("f", "F").replace("g", "G").replace("h", "H").replace("i", "I").replace("j", "J").replace("k", "K").replace("l", "L").replace("m", "M").replace("n", "N").replace("o", "O").replace("p", "P").replace("q", "Q").replace("r", "R").replace("s", "S").replace("t", "T").replace("u", "U").replace("v", "V").replace("w", "W").replace("x", "X").replace("y", "Y").replace("z", "Z")
}

pure bytes_for_bits(bits: Int) -> Int {
  bits / 8
}

pure gen_types_internal(text: Str, type_name: Str, type_caps: Str, bits: Int) -> Str {
  text.replace("@type@", type_name).replace("@TYPE@", type_caps).replace("@BITS@", f"${bits}").replace("@BYTES@", f"${bytes_for_bits(
  bits,
)}")
}

pure gen_bits_template(text: Str, bits: Int, dfmt: Str, ofmt: Str, xfmt: Str, bfmt: Str) -> Str {
  text.replace("@BITS@", f"${bits}").replace("@DFMT@", dfmt).replace("@OFMT@", ofmt).replace("@XFMT@", xfmt).replace("@BFMT@", bfmt)
}

proc read_sysdeps(path_value: Path) [fs, error] -> Result[Map[Str]] {
  var sysdeps: Map[Str] = {}

  for line in path_value.read_text()?.split("\n") {
    let words = line.words()

    if words.len() >= 2 {
      sysdeps[words[0].replace(":", "")] = words[1]
    }
  }

  return sysdeps
}

proc write_skalibs_sysdeps(target: Str) [fs, error] {
  let sysdeps = p"skalibs/sysdeps.cfg"
  fs.mkdir(sysdeps)?

  fs.write(
    fp"${sysdeps}/target",
    f"""${target}
""",
  )?

  fs.write(fp"${sysdeps}/pthread.lib", "")?
  fs.write(fp"${sysdeps}/socket.lib", "")?
  fs.write(fp"${sysdeps}/spawn.lib", "")?
  fs.write(fp"${sysdeps}/sysclock.lib", "")?
  fs.write(fp"${sysdeps}/timer.lib", "")?
  fs.write(fp"${sysdeps}/util.lib", "")?

  fs.write(
    fp"${sysdeps}/sysdeps",
    """clockrt: yes
clockmon: yes
clockboot: yes
posixspawn: yes
timer: yes
pthread: yes
endianness: little
sizeofushort: 2
sizeofuint: 4
sizeofulong: 8
signedsize: no
sizeofsize: 8
signeduid: no
sizeofuid: 4
signedgid: no
sizeofgid: 4
signedpid: yes
sizeofpid: 4
signedtime: yes
sizeoftime: 8
signeddev: no
sizeofdev: 8
signedino: no
sizeofino: 8
accept4: yes
cmsgcloexec: yes
dirfd: yes
fdopendir: yes
eventfd: yes
flock: yes
getpeereid: no
sopeercred: yes
getpeerucred: no
ipv6: yes
msgdontwait: yes
ocloexec: yes
odirectory: yes
openat: yes
linkat: yes
memmem: yes
pipe2: yes
ppoll: yes
qsortr_posix: yes
qsortr_freebsd: no
revoke: no
sendfile: yes
setgroups: yes
settimeofday: yes
signalfd: yes
splice: yes
statim: yes
statimespec: no
strcasestr: yes
strnlen: yes
uint64t: yes
waitid: yes
futimens: yes
futimes: yes
arc4random: no
arc4random_addrandom: no
itimer: yes
namespaces: yes
nsgetparent: yes
explicit_bzero: yes
getrandom: yes
grndinsecure: yes
chroot: yes
clonenewpid: yes
posixspawnsetsid: yes
posixspawnsetsidnp: no
posixspawnchdir: no
posixspawnchdirnp: yes
getauxval: yes
kernprocpathname: no
_nsgetexecutablepath: no
getexecname: no
dladdr: yes
pidfd_open: yes
prctl: yes
procctl: no
kevent: no
kqueue1: no
pthreadmutextimedlock: yes
pthreadmutexclocklock: no
devurandom: yes
posixspawnearlyreturn: no
procselfexe: /proc/self/exe
""",
  )?
}

proc write_skalibs_config() [fs, error] {
  fs.write(
    p"skalibs/src/include/skalibs/config.h",
    """#ifndef SKALIBS_CONFIG_H
#define SKALIBS_CONFIG_H

#define SKALIBS_VERSION "2.15.0.0"
#define SKALIBS_DEFAULTPATH "/usr/bin:/bin"
#define SKALIBS_ETC "/usr/etc"
#define SKALIBS_SPROOT ""
#define SKALIBS_HOME ""
#undef SKALIBS_FLAG_CLOCKISTAI
#define SKALIBS_FLAG_WANTIPV6
#undef SKALIBS_FLAG_PREFERSELECT

#endif
""",
  )?
}

proc write_sysdeps_h(target: Str, sysdeps: Map[Str]) [fs, error] {
  let _ = sysdeps

  var lines = [
    "/* ISC license. */",
    "",
    "#ifndef SYSDEPS_H",
    "#define SYSDEPS_H",
    "",
    "#undef SKALIBS_TARGET",
    f"#define SKALIBS_TARGET \"${target}\"",
    "",
  ]

  for line in p"skalibs/sysdeps.cfg/sysdeps".read_text()?.split("\n") {
    let words = line.words()
    continue when words.len() < 2
    let key = upper_ascii(words[0].replace(":", ""))
    let value = words[1]

    if key.starts_with("SIGNED") {
      lines = lines.push(f"#undef SKALIBS_HASUN${key}")
      lines = lines.push(f"#undef SKALIBS_HAS${key}")

      if value == "yes" {
        lines = lines.push(f"#define SKALIBS_HAS${key}")
      } else {
        lines = lines.push(f"#define SKALIBS_HASUN${key}")
      }
    } else if key.starts_with("SIZEOF") {
      lines = lines.push(f"#undef SKALIBS_${key}")
      lines = lines.push(f"#define SKALIBS_${key} ${value}")
    } else {
      if value == "yes" {
        lines = lines.push(f"#undef SKALIBS_HAS${key}")
        lines = lines.push(f"#define SKALIBS_HAS${key}")
      } else if value == "no" {
        lines = lines.push(f"#undef SKALIBS_HAS${key}")
      } else {
        lines = lines.push(f"#undef SKALIBS_${key}")

        if value != "none" {
          lines = lines.push(f"#define SKALIBS_${key} \"${value}\"")
        }
      }
    }

    lines = lines.push("")
  }

  lines = lines.push("#endif")
  fs.write(p"skalibs/src/include/skalibs/sysdeps.h", lines.join("\n"))?
}

proc write_uint_header(bits: Int, dfmt: Str, ofmt: Str, xfmt: Str, bfmt: Str, sysdeps: Map[Str]) [fs, error] {
  var parts = []
  parts = parts.push(gen_types_internal(p"skalibs/src/headers/bits-header".read_text()?, "", "", bits))

  if bits == 64 {
    parts = parts.push(p"skalibs/src/headers/uint64-defs".read_text()?)

    if sysdeps.get("uint64t", "") == "no" {
      if sysdeps.get("sizeofulong", "") == "8" {
        parts = parts.push(p"skalibs/src/headers/uint64-ulong64".read_text()?)
      } else {
        parts = parts.push(p"skalibs/src/headers/uint64-noulong64".read_text()?)
      }

      parts = parts.push(p"skalibs/src/headers/uint64-macros".read_text()?)
    }
  } else {
    parts = parts.push(p"skalibs/src/headers/uint64-include".read_text()?)
  }

  if sysdeps.get("endianness", "") != "little" {
    return Err(ScriptError.Failed("skalibs-gen-bits", "unsupported non-little-endian target"))
  }

  parts = parts.push(fp"skalibs/src/headers/uint${bits}-bswap".read_text()?)
  parts = parts.push(gen_types_internal(p"skalibs/src/headers/bits-lendian".read_text()?, "", "", bits))
  parts = parts.push(gen_bits_template(p"skalibs/src/headers/bits-template".read_text()?, bits, dfmt, ofmt, xfmt, bfmt))
  parts = parts.push(gen_types_internal(p"skalibs/src/headers/bits-footer".read_text()?, "", "", bits))
  fs.write(fp"skalibs/src/include/skalibs/uint${bits}.h", parts.join(""))?
}

proc sysdep_bits(sysdeps: Map[Str], type_name: Str) [error] -> Result[Int] {
  sysdeps.get(f"sizeof${type_name}")?.parse_int()? * 8
}

proc append_type_template(
  parts: List[Str],
  template: Path,
  type_name: Str,
  type_caps: Str,
  bits: Int,
) [fs, error] -> Result[List[Str]] {
  return parts.push(gen_types_internal(template.read_text()?, type_name, type_caps, bits))
}

proc write_types_h(sysdeps: Map[Str]) [fs, error] {
  var parts = [p"skalibs/src/headers/types-header".read_text()?]

  for type_name in ["short", "int", "long"] {
    let bits = sysdep_bits(sysdeps, f"u${type_name}")?

    parts = append_type_template(
      parts,
      p"skalibs/src/headers/unsigned-template",
      f"u${type_name}",
      f"U${upper_ascii(type_name)}",
      bits,
    )?

    parts = append_type_template(parts, p"skalibs/src/headers/signed-template", type_name, upper_ascii(type_name), bits)?
  }

  for type_name in ["size", "uid", "gid", "pid", "time", "dev", "ino"] {
    let bits = sysdep_bits(sysdeps, type_name)?

    let template = if sysdeps.get(f"signed${type_name}", "") == "yes" {
      p"skalibs/src/headers/signed-template"
    } else {
      p"skalibs/src/headers/unsigned-template"
    }

    parts = append_type_template(parts, template, type_name, upper_ascii(type_name), bits)?
  }

  parts = parts.push(p"skalibs/src/headers/types-footer".read_text()?)
  fs.write(p"skalibs/src/include/skalibs/types.h", parts.join(""))?
}

proc generate_skalibs_headers(target: Str) [fs, error] {
  let sysdeps = read_sysdeps(p"skalibs/sysdeps.cfg/sysdeps")?
  write_sysdeps_h(target, sysdeps)?
  write_uint_header(64, "21", "25", "17", "65", sysdeps)?
  write_uint_header(32, "11", "13", "9", "33", sysdeps)?
  write_uint_header(16, "6", "7", "5", "17", sysdeps)?
  write_types_h(sysdeps)?

  fs.write(
    p"skalibs/src/include/skalibs/ip46.h",
    f"${p"skalibs/src/headers/ip46-header".read_text()?}${p"skalibs/src/headers/ip46-with".read_text()?}${p"skalibs/src/headers/ip46-footer".read_text()?}",
  )?
}

proc write_mdevd_config() [fs, error] {
  fs.write(
    p"src/include/mdevd/config.h",
    f"""#ifndef MDEVD_CONFIG_H
#define MDEVD_CONFIG_H

#define MDEVD_VERSION "${ver}"
#define MDEVD_BINPREFIX ""
#define MDEVD_EXTBINPREFIX ""
#define MDEVD_EXTLIBEXECPREFIX "/usr/libexec/mdevd/"
#define MDEVD_LIBEXECPREFIX "/usr/libexec/mdevd/"
#define MDEVD_SYSCONFPREFIX "/usr/etc/"

#endif
""",
  )?
}

proc compile_skalibs(cc: Path, triple: Str, target: Str) [fs, process, env, error] -> Result[Path] {
  write_skalibs_sysdeps(target)?
  write_skalibs_config()?
  generate_skalibs_headers(target)?

  let cflags = [
    "-pipe",
    "-Wall",
    "-std=c99",
    "-fno-exceptions",
    "-fno-unwind-tables",
    "-fno-asynchronous-unwind-tables",
    "-ffunction-sections",
    "-fdata-sections",
    "-O2",
    "-fomit-frame-pointer",
  ]

  let defs = [
    "-D_POSIX_C_SOURCE=200809L",
    "-D_XOPEN_SOURCE=700",
    "-Werror=implicit-function-declaration",
    "-Werror=implicit-int",
    "-Werror=pointer-sign",
    "-Werror=pointer-arith",
    "-Wno-unused-value",
    "-Wno-parentheses",
  ]

  let includes = ["-Iskalibs/src/include"]
  var skalibs_sources = []

  for entry in fs.walk(p"skalibs/src", gitignore: false)? |> where .kind == "file" and .ext == "c" {
    let src_display = entry.path.display()

    if src_display.starts_with("skalibs/src/lib") or "/skalibs/src/lib" in src_display {
      skalibs_sources = skalibs_sources.push(entry.path)
    }
  }

  let skarnet_archive = p"obj/libskarnet.a"

  let skarnet = make.c_static_library({
    cc,
    triple,
    cflags,
    defs,
    includes,
    root: p"",
    sources: skalibs_sources,
    out_dir: p"obj/skalibs",
    out: skarnet_archive,
    deps: [],
  })

  make.run_tasks(skarnet.tasks, make.jobs()?)?
  return skarnet_archive
}

export proc build(dest: Path) [fs, process, env, error] {
  let cc = process.which("cc")?
  let arch = pm_util.target_arch()?
  let triple = f"${arch}-linux-musl"
  let target = f"${arch}-alpine-linux-musl"
  fs.mkdir(p"laputa-headers/linux")?

  fs.write(
    p"laputa-headers/linux/netlink.h",
    """#pragma once
#include <stdint.h>
#include <sys/socket.h>

#define NETLINK_KOBJECT_UEVENT 15

struct sockaddr_nl {
  sa_family_t nl_family;
  unsigned short nl_pad;
  uint32_t nl_pid;
  uint32_t nl_groups;
};
""",
  )?

  let skarnet = compile_skalibs(cc, triple, target)?

  let cflags = [
    "-pipe",
    "-Wall",
    "-std=c99",
    "-fno-exceptions",
    "-fno-unwind-tables",
    "-fno-asynchronous-unwind-tables",
    "-ffunction-sections",
    "-fdata-sections",
    "-O2",
    "-fomit-frame-pointer",
  ]

  let defs = [
    "-D_POSIX_C_SOURCE=200809L",
    "-D_XOPEN_SOURCE=700",
    "-Werror=implicit-function-declaration",
    "-Werror=implicit-int",
    "-Werror=pointer-sign",
    "-Werror=pointer-arith",
  ]

  let includes = ["-iquote", "src/include-local", "-Ilaputa-headers", "-Isrc/include", "-Iskalibs/src/include"]
  write_mdevd_config()?

  let multi = make.c_multi_program({
    cc,
    triple,
    cflags,
    defs,
    includes,
    root: p"src/mdevd",
    out_dir: p"obj/objs",
    groups: [
      {
        name: "helpers",
        cflags: [],
        defs: [],
        includes: [],
        root: p"",
        sources: [p"mdevd_netlink_init.c", p"mdevd_uevent_read.c", p"mdevd_uevent_getvar.c"],
        out_dir: p"",
        deps: [],
      },
    ],
    targets: [
      {
        name: "mdevd",
        groups: ["helpers"],
        sources: [p"mdevd.c"],
        libs: [skarnet],
        ldflags: ["-Wl,--gc-sections"],
        out: p"obj/mdevd",
        deps: [],
      },
      {
        name: "mdevd-coldplug",
        groups: ["helpers"],
        sources: [p"mdevd-coldplug.c"],
        libs: [skarnet],
        ldflags: ["-Wl,--gc-sections"],
        out: p"obj/mdevd-coldplug",
        deps: [],
      },
    ],
  })?

  make.run_tasks(multi.tasks, make.jobs()?)?
  let mdevd_bin = multi.outputs.get("mdevd")?
  let coldplug_bin = multi.outputs.get("mdevd-coldplug")?
  fs.install(mdevd_bin, fp"${dest}/usr/bin/mdevd", 0o755, parents: true, overwrite: true)?
  fs.install(coldplug_bin, fp"${dest}/usr/bin/mdevd-coldplug", 0o755, parents: true, overwrite: true)?
  fs.install(p"service.xsh", fp"${dest}/usr/lib/xinit/services/mdevd.xsh", 0o644, parents: true, overwrite: true)?
}
