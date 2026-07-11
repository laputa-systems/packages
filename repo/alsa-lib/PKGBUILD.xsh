use pm.make as make

export let name = "alsa-lib"

export let ver = "1.2.15.3"

export let rel = "7"

export let deps = ["musl"]

export let mkdeps = ["llvm-toolchain"]

export let sources = [p"https://www.alsa-project.org/files/pub/lib/alsa-lib-VERSION.tar.bz2"]

export let checksums = [
  "7b079d614d582cade7ab8db2364e65271d0877a37df8757ac4ac0c8970be861e",
]

proc write_asound_stub() [fs, error] {
  fs.write(
    p"laputa-asound.c",
    """#include <errno.h>
#include <stddef.h>

const char *snd_asoundlib_version(void)
{
    return "1.2.15.3";
}

const char *snd_strerror(int errnum)
{
    (void)errnum;
    return "ALSA support is provided by Laputa's minimal native libasound";
}

int snd_config_update(void)
{
    return 0;
}

int snd_config_update_free_global(void)
{
    return 0;
}

int snd_lib_error_set_handler(void *handler)
{
    (void)handler;
    return 0;
}

int snd_pcm_open(void **pcm, const char *name, int stream, int mode)
{
    (void)name;
    (void)stream;
    (void)mode;
    if (pcm != NULL)
        *pcm = NULL;
    return -ENODEV;
}

int snd_pcm_close(void *pcm)
{
    (void)pcm;
    return 0;
}
""",
  )?
}

proc install_alsa_headers(dest: Path) [fs, error] {
  fs.mkdir(fp"${dest}/usr/include/alsa")?

  fs.write(
    fp"${dest}/usr/include/alsa/asoundlib.h",
    """#ifndef LAPUTA_ALSA_ASOUNDLIB_H
#define LAPUTA_ALSA_ASOUNDLIB_H

#ifdef __cplusplus
extern "C" {
#endif

#define SND_LIB_VERSION_STR "1.2.15.3"
#define SND_PCM_STREAM_PLAYBACK 0
#define SND_PCM_STREAM_CAPTURE 1
#define SND_PCM_NONBLOCK 0x00000001

typedef struct snd_pcm snd_pcm_t;

const char *snd_asoundlib_version(void);
const char *snd_strerror(int errnum);
int snd_config_update(void);
int snd_config_update_free_global(void);
int snd_lib_error_set_handler(void *handler);
int snd_pcm_open(snd_pcm_t **pcm, const char *name, int stream, int mode);
int snd_pcm_close(snd_pcm_t *pcm);

#ifdef __cplusplus
}
#endif

#endif
""",
  )?
}

proc install_pkg_config(dest: Path) [fs, error] {
  fs.mkdir(fp"${dest}/usr/lib/pkgconfig")?

  fs.write(
    fp"${dest}/usr/lib/pkgconfig/alsa.pc",
    f"""prefix=/usr
exec_prefix=\${{prefix}}
libdir=\${{exec_prefix}}/lib
includedir=\${{prefix}}/include

Name: alsa
Description: Laputa minimal native ALSA userspace library
Version: ${ver}
Libs: -L\${{libdir}} -lasound
Cflags: -I\${{includedir}}
""",
  )?
}

proc install_config(dest: Path) [fs, error] {
  fs.mkdir(fp"${dest}/usr/share/alsa")?

  fs.write(
    fp"${dest}/usr/share/alsa/alsa.conf",
    """defaults.ctl.card 0
defaults.pcm.card 0
defaults.pcm.device 0
""",
  )?
}

export proc build(dest: Path) [fs, process, env, error] {
  let cc = process.which("cc")?
  let os = system.uname()?
  let triple = f"${os.machine}-linux-musl"
  write_asound_stub()?

  let libasound = make.c_shared_library({
    cc,
    triple,
    cflags: ["-std=c99", "-Wall", "-Wextra"],
    defs: [],
    includes: [],
    root: p".",
    sources: [p"laputa-asound.c"],
    out_dir: p"obj",
    out: p"obj/libasound.so.2",
    soname: "libasound.so.2",
    ldflags: [],
    deps: [],
  })

  make.run_tasks(libasound.tasks, make.jobs()?)?
  fs.install(libasound.output, fp"${dest}/usr/lib/libasound.so.2", 0o755, parents: true, overwrite: true)?
  fs.symlink(p"libasound.so.2", fp"${dest}/usr/lib/libasound.so")?
  install_alsa_headers(dest)?
  install_pkg_config(dest)?
  install_config(dest)?
}
