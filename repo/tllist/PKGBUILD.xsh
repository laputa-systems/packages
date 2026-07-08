export let name = "tllist"

export let ver = "1.1.0"

export let rel = "3"

export let deps = []

export let mkdeps = []

export let sources = [p"https://codeberg.org/dnkl/tllist/archive/VERSION.tar.gz"]

export let checksums = ["0e7b7094a02550dd80b7243bcffc3671550b0f1d8ba625e4dff52517827d5d23"]

export proc build(dest: Path) [fs, error] {
  fs.install(p"tllist.h", fp"${dest}/usr/include/tllist.h", 0o644, parents: true, overwrite: true)?
  fs.mkdir(fp"${dest}/usr/lib/pkgconfig")?

  fs.write(
    fp"${dest}/usr/lib/pkgconfig/tllist.pc",
    f"""prefix=/usr
includedir=\${prefix}/include

Name: tllist
Description: Typed linked list C header-only library
Version: ${ver}
Cflags: -I\${includedir}
""",
  )?
}
