use pm.make as make

export let name: Str = "alsa-lib"

export let ver: Str = "1.2.15.3"

export let rel: Str = "3"

export let deps: List[Str] = ["musl"]

export let mkdeps: List[Str] = ["llvm-toolchain"]

export let sources: List[Path] = [p"https://www.alsa-project.org/files/pub/lib/alsa-lib-VERSION.tar.bz2"]

export let checksums: List[Str] = ["7b079d614d582cade7ab8db2364e65271d0877a37df8757ac4ac0c8970be861e"]

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

proc install_headers(dest: Path) [fs, error] {
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
  let src = p"laputa-asound.c"
  let obj = p"obj/laputa-asound.lo"
  let so = p"obj/libasound.so.2"
  let compile = make.compile_lo_task(cc, triple, ["-std=c99", "-Wall", "-Wextra"], [], [], src, obj)
  let link = make.link_shared_task(cc, triple, [obj], "libasound.so.2", [], so, [compile.name])
  write_asound_stub()?
  make.run_tasks([compile, link], make.jobs()?)?
  fs.install(so, fp"${dest}/usr/lib/libasound.so.2", 0o755, parents: true, overwrite: true)?
  fs.symlink(p"libasound.so.2", fp"${dest}/usr/lib/libasound.so")?
  install_headers(dest)?
  install_pkg_config(dest)?
  install_config(dest)?
}
