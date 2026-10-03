#!/bin/xsh
# Kbuild archive-analysis worker entry script, executed from the staged recipe tree.
use kbuild

proc main(...argv: List[Str]) [fs, error] {
  let input_path = fp"${argv[0]}"
  let output_path = fp"${argv[1]}"
  let input = json.read(input_path)?.require(kbuild.ArchiveAnalysisInput)?
  let context = json.read(fp"${input.context}")?.require(kbuild.ArchivePlanContext)?
  let flag_context = json.read(fp"${input.flags}")?.require(kbuild.ArchiveAnalysisFlags)?
  let results = kbuild.analyze_archive_plan_slice(
    context,
    input.start,
    input.end,
    flag_context.flags,
    input.emit_task_specs,
    fp"${input.cc}",
    input.triple,
    input.cflags,
    input.defs,
    input.includes,
  )?
  json.write(output_path, results)?
}

main(@args)?
