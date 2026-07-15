#!/bin/xsh

use kbuild

proc main(...argv: List[Str]) [fs, time, error] {
  let root = fp"${argv[0]}"
  let config = kbuild.load_config(fp"${argv[1]}")?
  let srcarch = argv[2]
  let state_path = fp"${argv[3]}"
  let lock_path = fp"${argv[4]}"
  let output_path = fp"${argv[5]}"
  var records: List[Record] = []

  while true {
    let lock = fs.lock(lock_path)?
    let state: Record = json.read(state_path)?
    let done: Bool = state.get("done")?
    let pending: List[Str] = state.get("pending")?
    let active: Int = state.get("active")?
    let error_message: Str = state.get("error")?

    if done or error_message != "" {
      fs.unlock(lock)?
      break
    }

    if pending.len() == 0 {
      if active == 0 {
        json.write(state_path, {...state, done: true})?
        fs.unlock(lock)?
        break
      }

      fs.unlock(lock)?
      time.sleep(1ms)?
      continue
    }

    let dir = pending[0]
    json.write(
      state_path,
      {...state, pending: pending |> drop(1), active: active + 1},
    )?
    fs.unlock(lock)?

    let scan_result = kbuild.scan_record_for_dir(root, config, srcarch, fp"${dir}")
    match scan_result {
      Ok(scan) => {
        records = records.push(scan)
        let child_dirs: List[Str] = scan.get("child_dirs")?
        let commit_lock = fs.lock(lock_path)?
        let committed: Record = json.read(state_path)?
        var seen: List[Str] = committed.get("seen")?
        var new_pending: List[Str] = committed.get("pending")?

        for child in child_dirs {
          if ! (child in seen) {
            new_pending = new_pending.push(child)
            seen = seen.push(child)
          }
        }

        json.write(
          state_path,
          {...committed, pending: new_pending, active: committed.get("active")? - 1, seen: seen},
        )?
        fs.unlock(commit_lock)?
      }
      Err(_) => {
        let error_lock = fs.lock(lock_path)?
        let failed_state: Record = json.read(state_path)?
        json.write(
          state_path,
          {...failed_state, active: failed_state.get("active")? - 1, done: true, error: "directory scan failed"},
        )?
        fs.unlock(error_lock)?
        return Err(ScriptError.Failed("kbuild-process-pool", "directory scan failed"))
      }
    }
  }

  json.write(output_path, records)?
}

main(@args)?
