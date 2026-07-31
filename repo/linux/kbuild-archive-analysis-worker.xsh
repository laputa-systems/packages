#!/bin/xsh
use kbuild

proc main(...argv: List[Str]) [fs, error] {
  let input_path = fp"${argv[0]}"
  let output_path = fp"${argv[1]}"
  let input: Record = json.read(input_path)?
  let items: List[Record] = input.get("items")?
  let cc = fp"${input.get("cc")?}"
  let triple: Str = input.get("triple")?
  let cflags: List[Str] = input.get("cflags")?
  let defs: List[Str] = input.get("defs")?
  let includes: List[Str] = input.get("includes")?
  let results = kbuild.analyze_archive_items_with_task_specs(
    items,
    cc,
    triple,
    cflags,
    defs,
    includes,
  )?
  json.write(output_path, results)?
}

main(@args)?
