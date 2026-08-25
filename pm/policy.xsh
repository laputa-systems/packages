##! Explicit build-policy data for typed package graph resolution.
use types

## Returns the aarch64 Docker build policy, including native bootstrap seed rules.
## `musl -> llvm-toolchain` breaks the musl/LLVM cycle with the already-seeded compiler.
## `musl -> zlib` supplies the native bootstrap toolchain before the rebuilt target runtime is present.
## `gnu-stubs -> llvm-toolchain` likewise uses the seeded compiler until the replacement LLVM is built.
export pure aarch64_docker() -> types.BuildPolicy {
  {
    target: types.Aarch64LinuxMusl,
    build_target: types.Aarch64LinuxMusl,
    native_build: true,
    bootstrap_seeds: [
      {
        package: "musl",
        dependency: "llvm-toolchain",
        native_only: true,
        reason: "musl needs the already-seeded compiler before llvm-toolchain can be rebuilt against musl",
      },
      {
        package: "musl",
        dependency: "zlib",
        native_only: true,
        reason: "the native bootstrap compiler toolchain requires zlib while musl establishes the target runtime",
      },
      {
        package: "gnu-stubs",
        dependency: "llvm-toolchain",
        native_only: true,
        reason: "gnu-stubs is built with the already-seeded compiler before the new llvm-toolchain is available",
      },
    ],
  }
}

## Returns a copy of a policy configured for native or cross build graph resolution.
export pure with_native_build(value: types.BuildPolicy, native_build: Bool) -> types.BuildPolicy {
  {...value, native_build}
}

## Returns whether a policy seed rule applies for one package dependency pair.
export pure is_bootstrap_dependency(value: types.BuildPolicy, package: Str, dependency: Str) -> Bool {
  for rule in value.bootstrap_seeds {
    if rule.package == package and rule.dependency == dependency and (! rule.native_only or value.native_build) {
      return true
    }
  }

  false
}

## Returns the policy-defined bootstrap dependencies for one package in declaration order.
export pure bootstrap_dependencies(value: types.BuildPolicy, package: Str) -> List[Str] {
  var dependencies: List[Str] = []

  for rule in value.bootstrap_seeds {
    if rule.package == package and (! rule.native_only or value.native_build) and rule.dependency not in dependencies {
      dependencies = dependencies.push(rule.dependency)
    }
  }

  dependencies
}
