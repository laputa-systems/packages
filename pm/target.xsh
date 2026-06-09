use pm.util as pm_util

export type MuslAbi = {
  arch: Str,
  ptrdiff_bits: Str,
  sig_atomic_bits: Str,
  size_t_bits: Str,
  wchar_t_bits: Str,
  wint_t_bits: Str,
  ptrdiff_suffix: Str,
  sig_atomic_suffix: Str,
  size_t_suffix: Str,
  wchar_t_suffix: Str,
  wint_t_suffix: Str,
  signed_sig_atomic_t: Bool,
  signed_wchar_t: Bool,
}

export pure lp64_musl_abi(arch: Str) -> MuslAbi {
  {
    arch,
    ptrdiff_bits: "64",
    sig_atomic_bits: "32",
    size_t_bits: "64",
    wchar_t_bits: "32",
    wint_t_bits: "32",
    ptrdiff_suffix: "\"L\"",
    sig_atomic_suffix: "\"INT\"",
    size_t_suffix: "\"UL\"",
    wchar_t_suffix: "\"INT\"",
    wint_t_suffix: "\"UINT\"",
    signed_sig_atomic_t: true,
    signed_wchar_t: true,
  }
}

export proc musl_abi() [env, error] -> Result[MuslAbi] {
  lp64_musl_abi(pm_util.target_arch()?)
}
