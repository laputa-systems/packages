use pm.proof as proof
use pm.util as pm_util

error ScriptError = Failed(kind: Str, message: Str)

proc ensure(condition: Bool, kind: Str, message: Str) [error] {
  if ! condition {
    Err(ScriptError.Failed(kind, message))?
  }
}

proc main(root: Path = /rootfs) [fs, process, env, error] {
  let cc = process.which("cc")?
  let tmp = fp"${root}/var/tmp/proof-zlib"
  fs.remove(tmp, missing_ok: true)?
  fs.mkdir(tmp)?
  defer fs.remove(tmp, missing_ok: true)?

  fs.write(
    fp"${tmp}/proof-zlib.c",
    """#include <string.h>
#include <zlib.h>

int main(void) {
  const unsigned char input[] = "laputa zlib proof";
  unsigned char compressed[128];
  unsigned char output[128];
  uLongf compressed_len = sizeof(compressed);
  uLongf output_len = sizeof(output);

  if (compress(compressed, &compressed_len, input, strlen((const char *)input) + 1) != Z_OK) {
    return 1;
  }
  if (uncompress(output, &output_len, compressed, compressed_len) != Z_OK) {
    return 2;
  }
  return strcmp((const char *)output, (const char *)input) == 0 ? 0 : 3;
}
""",
  )?

  let binary = fp"${tmp}/proof-zlib"
  run $cc fp"${tmp}/proof-zlib.c" f"-I${root}/usr/include" f"-L${root}/usr/lib" "-lz" "-o" $binary ?

  if pm_util.build_arch()? == pm_util.target_arch()? {
    env {
      LD_LIBRARY_PATH = fp"${root}/usr/lib".display()
    } {
      run $binary ?
    } ?
  } else {
    proof.target_elf(root, p"usr/lib/libz.so", "zlib")?
  }

  ensure(fs.exists(fp"${root}/usr/include/zlib.h")?, "zlib", "missing zlib.h")?
  ensure(fs.exists(fp"${root}/usr/lib/libz.so")?, "zlib", "missing libz.so")?
  print "zlib ok"
}

main(@args)?
