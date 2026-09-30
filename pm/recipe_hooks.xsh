##! Checked procedure contracts for package recipe hook capabilities.
# Module contracts compare declared effects exactly, so each supported hook
# keeps the recipe's own capability set instead of widening every recipe.

## Validates a build hook with fs, error capabilities.
export type BuildFilesystem = module {
  export proc build(dest: Path) [fs, error] -> Result[Unit]
}

## Validates a build hook with fs, env, error capabilities.
export type BuildFilesystemEnvironment = module {
  export proc build(dest: Path) [fs, env, error] -> Result[Unit]
}

## Validates a build hook with process, env, error capabilities.
export type BuildProcessesEnvironment = module {
  export proc build(dest: Path) [process, env, error] -> Result[Unit]
}

## Validates a build hook with fs, process, env, error capabilities.
export type BuildFilesystemProcessesEnvironment = module {
  export proc build(dest: Path) [fs, process, env, error] -> Result[Unit]
}

## Validates a prepare hook with fs, error capabilities.
export type PrepareFilesystem = module {
  export proc prepare(src: Path) [fs, error] -> Result[Unit]
}

## Validates a prepare hook with fs, env, error capabilities.
export type PrepareFilesystemEnvironment = module {
  export proc prepare(src: Path) [fs, env, error] -> Result[Unit]
}

## Validates a prepare hook with process, env, error capabilities.
export type PrepareProcessesEnvironment = module {
  export proc prepare(src: Path) [process, env, error] -> Result[Unit]
}

## Validates a prepare hook with fs, process, env, error capabilities.
export type PrepareFilesystemProcessesEnvironment = module {
  export proc prepare(src: Path) [fs, process, env, error] -> Result[Unit]
}

## Validates source preparation before package build execution.
export type PrepareSourcesFilesystem = module {
  export proc prepare_sources(src: Path) [fs, error] -> Result[Unit]
}
