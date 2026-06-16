export let name: Str = "libunwind"

export let ver: Str = "22.1.3"

export let rel: Str = "3"

export let deps: List[Str] = ["musl"]

export let mkdeps: List[Str] = []

export let sources: List[Path] = [
  p"https://github.com/laputa-systems/artifacts/releases/download/llvm-toolchain-VERSION/llvm-toolchain-VERSION-ARCH.tar.gz",
]

export let checksums: List[Str] = ["SKIP"]

export let checksums_aarch64: List[Str] = ["3b9d9015a9b3ad74e111e7128c820d009cf35c7e2711ee1aa2b93b0a4bc1b0d4"]

export let checksums_x86_64: List[Str] = ["79b31c8ac33e791420d8282466eab85e8384d678728051748fc087bc0d049f8f"]

export proc build(dest: Path) [fs, error] {
  fs.mkdir(fp"${dest}/usr/lib")?
  fs.copy(p"usr/lib/libunwind.so.1.0", fp"${dest}/usr/lib/libunwind.so.1.0", overwrite: true)?
  fs.symlink(p"libunwind.so.1.0", fp"${dest}/usr/lib/libunwind.so.1")?
  fs.symlink(p"libunwind.so.1", fp"${dest}/usr/lib/libunwind.so")?
}
