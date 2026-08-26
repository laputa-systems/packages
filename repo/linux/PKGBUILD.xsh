##! Linux package metadata and the dynamic recipe boundary.

## Exported declaration `name`.
export let name = "linux"

## Explicit payload or metapackage classification.
export let package_kind = "payload"

## Exported declaration `ver`.
export let ver = "7.0.5"

## Exported declaration `rel`.
export let rel = "36"

## Exported declaration `deps`.
export let deps: List[Str] = []

## Exported declaration `mkdeps_host`.
export let mkdeps_host = ["llvm-toolchain", "flex", "bison"]

## Exported declaration `nostrip`.
export let nostrip = true

## Exported declaration `upstream_sources`.
export let upstream_sources = [
  {
    source: p"https://cdn.kernel.org/pub/linux/kernel/v7.x/linux-7.0.5.tar.xz",
    kind: "auto",
    architectures: [
      "all",
    ],
    checksums: [
      {
        arch: "all",
        sha256: "965fb0a1c1675399fc60c6063b227c0523041b5f9a662b66462f1212c438ac3c",
      },
    ],
  },
  {
    source: p"files/config/aarch64/base-aarch64.fragment => .laputa-inputs/files/config/aarch64",
    kind: "auto",
    architectures: [
      "all",
    ],
    checksums: [
      {
        arch: "all",
        sha256: "7749fbf7acc9a932683415b6d10f674a200213c7a7be7c55f0b05732cdb45a07",
      },
    ],
  },
  {
    source: p"files/config/x86_64/base-x86_64.fragment => .laputa-inputs/files/config/x86_64",
    kind: "auto",
    architectures: [
      "all",
    ],
    checksums: [
      {
        arch: "all",
        sha256: "baae18e1abe4b764234f97112248c91762904bbad4bac2bbcbb79fb86a8e324e",
      },
    ],
  },
  {
    source: p"files/sysreg-defs.h",
    kind: "auto",
    architectures: [
      "all",
    ],
    checksums: [
      {
        arch: "all",
        sha256: "7578877f5978e66b4ac04d66a2fcdbd6d183ae56d2786f4538d32af0c477e317",
      },
    ],
  },
  {
    source: p"files/generated/timeconst.h",
    kind: "auto",
    architectures: [
      "all",
    ],
    checksums: [
      {
        arch: "all",
        sha256: "664c2e5a8ed45eb327f0f1b1ee83249a24f98ee67f3bcb313a4d0bf99202ceed",
      },
    ],
  },
  {
    source: p"files/generated/bounds.h",
    kind: "auto",
    architectures: [
      "all",
    ],
    checksums: [
      {
        arch: "all",
        sha256: "c7daffc2aa5a964969421942bb000e65a2b9866d2a2a11529689c379005ef1f1",
      },
    ],
  },
  {
    source: p"files/generated/asm-offsets.h",
    kind: "auto",
    architectures: [
      "all",
    ],
    checksums: [
      {
        arch: "all",
        sha256: "bf747255377b322ae454423b1af409d30740196b3403f42ca5b7a38e2549ccb4",
      },
    ],
  },
  {
    source: p"files/generated/rq-offsets.h",
    kind: "auto",
    architectures: [
      "all",
    ],
    checksums: [
      {
        arch: "all",
        sha256: "01f07c33f1d15437c763a3bc0a9a8437a0404f6fbef80ef9781698e0d47cf8d4",
      },
    ],
  },
  {
    source: p"files/generated/sha256-core.S",
    kind: "auto",
    architectures: [
      "all",
    ],
    checksums: [
      {
        arch: "all",
        sha256: "1b7d66d6d221e3663be0da7d0516564e6d5d10c07e8c0612ee0ac87bcb9dc519",
      },
    ],
  },
  {
    source: p"files/generated/sha512-core.S",
    kind: "auto",
    architectures: [
      "all",
    ],
    checksums: [
      {
        arch: "all",
        sha256: "527009fbdd1faa79dee68028a3fd92440412c24e29ec95b32718f911216d27ec",
      },
    ],
  },
  {
    source: p"files/generated/cpufeaturemasks-x86.h",
    kind: "auto",
    architectures: [
      "all",
    ],
    checksums: [
      {
        arch: "all",
        sha256: "fb569e0a080248ddba05c62f450de98b4916190c9c3bea49afb12dc1e5b95fe9",
      },
    ],
  },
  {
    source: p"files/generated/x86-alternative-stubs.h",
    kind: "auto",
    architectures: [
      "all",
    ],
    checksums: [
      {
        arch: "all",
        sha256: "8233e16fc51b623088d439051bc895dc8275d7a4f2f3bd640eb1acc35a888af8",
      },
    ],
  },
  {
    source: p"files/generated/inat-tables-x86.c",
    kind: "auto",
    architectures: [
      "all",
    ],
    checksums: [
      {
        arch: "all",
        sha256: "5bc098c57c3bfaa8d3fbd05f6d7703c5573417431a48160a194961e7cf334525",
      },
    ],
  },
  {
    source: p"files/x86-jump-label-patch.c",
    kind: "auto",
    architectures: [
      "all",
    ],
    checksums: [
      {
        arch: "all",
        sha256: "39fa47de004dc15b2d71fad9256734992f93743cdb65ef1a70d454b0403f5031",
      },
    ],
  },
]

## Exported declaration `filetree`.
export let filetree = [{path: p"boot", kind: "tree"}, {path: p"usr", kind: "tree"}]

## The PM dynamic loader reads this metadata on every catalog scan.  The
## Kbuild program is deliberately executed in a child XSH process instead of
## imported here: the pinned published runner cannot dynamic-load its indexed
## IR, while normal script execution remains supported.
export proc build(dest: Path) [process, env, error] {
  let recipe_dir = env.get("XSH_PM_RECIPE_DIR") ?? ""
  let xsh = process.which("xsh")?
  run $xsh fp"${recipe_dir}/PKGBUILD-build.xsh" "--" $dest ?
}
