#!/bin/xsh
##! XSH module `kbuild-archive-analysis-worker` package and build operations.
use kbuild

proc main(...argv: List[Str]) [fs, error] {
  let input_path = fp"${argv[0]}"
  let output_path = fp"${argv[1]}"
  let input: Record = json.read(input_path)?
  let context_path = fp"${input.get("context")?}"
  let context: Record = json.read(context_path)?
  let start: Int = input.get("start")?
  let end: Int = input.get("end")?
  let flags_path = fp"${input.get("flags")?}"
  let flag_context: Record = json.read(flags_path)?
  let flag_entries: List[Record] = flag_context.get("flags")?
  let emit_task_specs: Bool = input.get("emit_task_specs")?
  let cc = fp"${input.get("cc")?}"
  let triple: Str = input.get("triple")?
  let cflags: List[Str] = input.get("cflags")?
  let defs: List[Str] = input.get("defs")?
  let includes: List[Str] = input.get("includes")?
  let results = kbuild.analyze_archive_plan_slice(
    context,
    start,
    end,
    flag_entries,
    emit_task_specs,
    cc,
    triple,
    cflags,
    defs,
    includes,
  )?
  json.write(output_path, results)?
}

main(@args)?
