#!/bin/xsh
error Ext4ToolError = Failed(kind: Str, message: Str)

let BLOCK_SIZE = 4096
let BLOCKS_PER_GROUP = 32768
let INODES_PER_GROUP = 8192
let INODE_SIZE = 256
let INODE_TABLE_BLOCKS = 512
let FIXED_TIME = 1700000000

type ExtEntry = {
  rel: Str,
  parent: Str,
  name: Str,
  path: Path,
  kind: Str,
  mode: Int,
  uid: Int,
  gid: Int,
  mtime: Int,
  size: Int,
  target: Bytes,
  inode: Int,
}

type ExtAlloc = {
  first: Int,
  count: Int,
  blocks: List[Int],
  single: Int,
  double: Int,
  indirects: List[Int],
  sectors: Int,
}

type AllocResult = {used: Map[Bool], next: Int, alloc: ExtAlloc}

type BlockResult = {used: Map[Bool], next: Int, block: Int}

type DirItem = {inode: Int, name: Str, kind: Str}

pure ceil_div(value: Int, divisor: Int) -> Int {
  if value == 0 {
    return 0
  }

  return (value + divisor - 1) / divisor
}

pure align4(value: Int) -> Int {
  return ceil_div(value, 4) * 4
}

pure min_int(left: Int, right: Int) -> Int {
  if left < right {
    return left
  }

  return right
}

proc bit_value(bit: Int) [] -> Int {
  var value = 1
  var index = 0

  while index < bit {
    value *= 2
    index += 1
  }

  return value
}

proc put(data: Bytes, offset: Int, replacement: Bytes) [error] -> Result[Bytes] {
  return bytes.concat(
    [
      data.slice(offset: 0, length: offset),
      replacement,
      data.slice(offset: offset + replacement.len(), length: data.len() - offset - replacement.len()),
    ],
  )
}

proc put_le(data: Bytes, offset: Int, value: Int, width: Int) [error] -> Result[Bytes] {
  return put(data, offset, bytes.pack_le(value, width)?)?
}

proc fixed_text(text: Str, width: Int) [error] -> Result[Bytes] {
  let raw = bytes.from_text(text)

  if raw.len() >= width {
    return raw.slice(offset: 0, length: width)
  }

  return bytes.concat([raw, bytes.zero(width - raw.len())?])
}

proc block_key(block: Int) [] -> Str {
  return f"${block}"
}

proc reserve_block(used: Map[Bool], block: Int) [] -> Map[Bool] {
  return used.set(block_key(block), true)
}

proc block_used(used: Map[Bool], block: Int) [] -> Bool {
  return used.get(block_key(block), false)
}

pure metadata_reserved(block: Int) -> Bool {
  return block % BLOCKS_PER_GROUP < 4 + INODE_TABLE_BLOCKS
}

proc reserve_metadata_blocks(total_blocks: Int, groups: Int) [] -> Map[Bool] {
  let _ = [total_blocks, groups]
  return map.empty()
}

proc collect_entries(root: Path, dir: Path, entries: List[ExtEntry]) [fs, error] -> Result[List[ExtEntry]] {
  var out = entries

  for child in fs.ls(dir)? |> sort-by .path {
    continue when child.kind != "file" and child.kind != "dir" and child.kind != "symlink"
    let rel_path = child.path.strip_prefix(root)?
    let rel = rel_path.display().replace("\\", "/")
    let parent_raw = rel_path.parent().display().replace("\\", "/")
    let parent = if parent_raw == "." { "" } else { parent_raw }

    let target = if child.kind == "symlink" {
      bytes.from_text(child.path.readlink()?.display())
    } else {
      bytes.zero(0)?
    }

    out = out.push({
      rel,
      parent,
      name: child.name,
      path: child.path,
      kind: child.kind,
      mode: child.mode,
      uid: 0,
      gid: 0,
      mtime: FIXED_TIME,
      size: child.size,
      target,
      inode: 0,
    })

    if child.kind == "dir" {
      out = collect_entries(root, child.path, out)?
    }
  }

  return out
}

proc assign_inodes(entries: List[ExtEntry]) [] -> List[ExtEntry] {
  var out = []
  var index = 0

  for entry in entries |> sort-by .rel {
    out = out.push({...entry, inode: 11 + index})
    index += 1
  }

  return out
}

proc inode_for(entries: List[ExtEntry], rel: Str) [] -> Int {
  if rel == "" {
    return 2
  }

  for entry in entries {
    if entry.rel == rel {
      return entry.inode
    }
  }

  return 2
}

proc dir_links(entries: List[ExtEntry], rel: Str) [] -> Int {
  var links = 2

  for entry in entries {
    if entry.parent == rel and entry.kind == "dir" {
      links += 1
    }
  }

  return links
}

proc dir_file_type(kind: Str) [error] -> Result[Int] {
  if kind == "file" {
    return 1
  }

  if kind == "dir" {
    return 2
  }

  if kind == "symlink" {
    return 7
  }

  return Err(Ext4ToolError.Failed("bad-dir-kind", kind))
}

proc dirent(item: DirItem, rec_len: Int) [error] -> Result[Bytes] {
  let name = bytes.from_text(item.name)

  return bytes.concat(
    [
      bytes.pack_le(item.inode, 4)?,
      bytes.pack_le(rec_len, 2)?,
      bytes.from_ints([name.len(), dir_file_type(item.kind)?])?,
      name,
      bytes.zero(rec_len - 8 - name.len())?,
    ],
  )
}

proc dir_items(entries: List[ExtEntry], rel: Str, self_inode: Int, parent_inode: Int) [] -> List[DirItem] {
  var items = [{inode: self_inode, name: ".", kind: "dir"}, {inode: parent_inode, name: "..", kind: "dir"}]

  for entry in entries {
    if entry.parent == rel {
      items = items.push({inode: entry.inode, name: entry.name, kind: entry.kind})
    }
  }

  return items
}

proc min_dirent_len(item: DirItem) [] -> Int {
  return align4(8 + bytes.from_text(item.name).len())
}

proc dir_data(entries: List[ExtEntry], rel: Str, self_inode: Int, parent_inode: Int) [error] -> Result[Bytes] {
  let items = dir_items(entries, rel, self_inode, parent_inode)
  var blocks = []
  var parts = []
  var used = 0
  var index = 0

  while index < items.len() {
    let item = items[index]
    let min_len = min_dirent_len(item)

    if used > 0 and used + min_len > BLOCK_SIZE {
      blocks = blocks.push(bytes.concat([bytes.concat(parts), bytes.zero(BLOCK_SIZE - used)?]))
      parts = []
      used = 0
    }

    let next_fits = if index + 1 < items.len() {
      used + min_len + min_dirent_len(items[index + 1]) <= BLOCK_SIZE
    } else {
      false
    }

    let rec_len = if next_fits { min_len } else { BLOCK_SIZE - used }
    parts = parts.push(dirent(item, rec_len)?)
    used += rec_len

    if used == BLOCK_SIZE {
      blocks = blocks.push(bytes.concat(parts))
      parts = []
      used = 0
    }

    index += 1
  }

  if parts.len() > 0 {
    blocks = blocks.push(bytes.concat([bytes.concat(parts), bytes.zero(BLOCK_SIZE - used)?]))
  }

  return bytes.concat(blocks)
}

proc allocate_block(used: Map[Bool], next: Int, total_blocks: Int) [error] -> Result[BlockResult] {
  var cursor = next

  while cursor < total_blocks {
    if ! metadata_reserved(cursor) {
      return {used, next: cursor + 1, block: cursor}
    }

    cursor += 1
  }

  return Err(Ext4ToolError.Failed("full", "image is full"))
}

proc next_data_block(cursor: Int) [] -> Int {
  var block = cursor

  while metadata_reserved(block) {
    block += 1
  }

  return block
}

proc skip_data_blocks(cursor: Int, count: Int) [] -> Int {
  var block = cursor
  var remaining = count

  while remaining > 0 {
    if metadata_reserved(block) {
      block += 1
    } else {
      block += 1
      remaining -= 1
    }
  }

  return block
}

proc allocate_blocks(used: Map[Bool], next: Int, total_blocks: Int, count: Int) [error] -> Result[AllocResult] {
  var current_used = used
  var current_next = next_data_block(next)
  let first = current_next
  current_next = skip_data_blocks(current_next, count)

  if current_next > total_blocks {
    return Err(Ext4ToolError.Failed("full", "image is full"))
  }

  var single = 0

  if count > 12 {
    let result = allocate_block(current_used, current_next, total_blocks)?
    current_used = result.used
    current_next = result.next
    single = result.block
  }

  var double = 0
  var indirects = []

  if count > 1036 {
    let result = allocate_block(current_used, current_next, total_blocks)?
    current_used = result.used
    current_next = result.next
    double = result.block
    var remaining = count - 1036

    while remaining > 0 {
      let indirect = allocate_block(current_used, current_next, total_blocks)?
      current_used = indirect.used
      current_next = indirect.next
      indirects = indirects.push(indirect.block)
      remaining -= if remaining > 1024 { 1024 } else { remaining }
    }
  }

  let metadata_blocks = (if single != 0 { 1 } else { 0 }) + (if double != 0 { 1 } else { 0 }) + indirects.len()
  let blocks = []

  return {
    used: current_used,
    next: current_next,
    alloc: {
      first,
      count,
      blocks,
      single,
      double,
      indirects,
      sectors: (count + metadata_blocks) * (BLOCK_SIZE / 512),
    },
  }
}

proc write_block(image: Path, block: Int, data: Bytes) [error] {
  let payload = if data.len() < BLOCK_SIZE { bytes.concat([data, bytes.zero(BLOCK_SIZE - data.len())?]) } else { data }
  let written = bytes.write_at(image, block * BLOCK_SIZE, payload.slice(offset: 0, length: BLOCK_SIZE))?
  let _ = written
}

proc u32_block(values: List[Int]) [error] -> Result[Bytes] {
  var parts = [bytes.pack_le(value, 4)? for value in values]
  return bytes.concat(parts)
}

proc int_slice(values: List[Int], offset: Int, length: Int) [] -> List[Int] {
  var out = []
  var index = offset
  let end = offset + length

  while index < end and index < values.len() {
    out = out.push(values[index])
    index += 1
  }

  return out
}

proc data_block_at(alloc: ExtAlloc, index: Int) [] -> Int {
  var block = alloc.first
  var seen = 0

  while true {
    if ! metadata_reserved(block) {
      if seen == index {
        return block
      }

      seen += 1
    }

    block += 1
  }

  return 0
}

proc data_blocks_slice(alloc: ExtAlloc, offset: Int, length: Int) [] -> List[Int] {
  var values = []
  var block = alloc.first
  var seen = 0

  while values.len() < length and seen < alloc.count {
    if ! metadata_reserved(block) {
      if seen >= offset {
        values = values.push(block)
      }

      seen += 1
    }

    block += 1
  }

  return values
}

proc write_indirect_blocks(image: Path, alloc: ExtAlloc) [error] {
  if alloc.single != 0 {
    write_block(image, alloc.single, u32_block(data_blocks_slice(alloc, 12, min_int(alloc.count, 1036) - 12))?)?
  }

  if alloc.double != 0 {
    var double_ptrs = []
    var offset = 1036

    for indirect in alloc.indirects {
      double_ptrs = double_ptrs.push(indirect)
      let end = min_int(offset + 1024, alloc.count)
      write_block(image, indirect, u32_block(data_blocks_slice(alloc, offset, end - offset))?)?
      offset = end
    }

    write_block(image, alloc.double, u32_block(double_ptrs)?)?
  }
}

proc allocate_bytes(
  image: Path,
  used: Map[Bool],
  next: Int,
  total_blocks: Int,
  data: Bytes,
) [error] -> Result[AllocResult] {
  let result = allocate_blocks(used, next, total_blocks, ceil_div(data.len(), BLOCK_SIZE))?
  var index = 0

  while index < result.alloc.count {
    let start = index * BLOCK_SIZE

    write_block(
      image,
      data_block_at(result.alloc, index),
      data.slice(offset: start, length: min_int(data.len() - start, BLOCK_SIZE)),
    )?

    index += 1
  }

  write_indirect_blocks(image, result.alloc)?
  return result
}

proc allocate_file(
  image: Path,
  used: Map[Bool],
  next: Int,
  total_blocks: Int,
  source: Path,
  size: Int,
) [error] -> Result[AllocResult] {
  let result = allocate_blocks(used, next, total_blocks, ceil_div(size, BLOCK_SIZE))?
  var source_offset = 0
  var block = result.alloc.first
  var remaining = result.alloc.count

  while remaining > 0 {
    while metadata_reserved(block) {
      block += 1
    }

    let first = block
    var run_len = 1

    while run_len < remaining and ! metadata_reserved(first + run_len) {
      run_len += 1
    }

    let length = min_int(size - source_offset, run_len * BLOCK_SIZE)

    let copied = bytes.copy_file(
      source,
      image,
      source_offset: source_offset,
      dest_offset: first * BLOCK_SIZE,
      length: length,
      create: false,
      truncate: false,
    )?

    let _ = copied
    source_offset += length
    block = first + run_len
    remaining -= run_len
  }

  write_indirect_blocks(image, result.alloc)?
  return result
}

proc inode_bytes(
  mode: Int,
  uid: Int,
  gid: Int,
  size: Int,
  mtime: Int,
  links: Int,
  alloc: ExtAlloc,
  fast_symlink: Bytes,
) [error] -> Result[Bytes] {
  var out = bytes.zero(INODE_SIZE)?
  out = put_le(out, 0, mode, 2)?
  out = put_le(out, 2, uid % 65536, 2)?
  out = put_le(out, 4, size % 4294967296, 4)?
  out = put_le(out, 8, mtime, 4)?
  out = put_le(out, 12, mtime, 4)?
  out = put_le(out, 16, mtime, 4)?
  out = put_le(out, 24, gid % 65536, 2)?
  out = put_le(out, 26, links, 2)?
  out = put_le(out, 28, alloc.sectors, 4)?

  if fast_symlink.len() > 0 and fast_symlink.len() <= 60 {
    out = put(out, 40, bytes.concat([fast_symlink, bytes.zero(60 - fast_symlink.len())?]))?
  } else {
    var index = 0

    while index < min_int(alloc.count, 12) {
      out = put_le(out, 40 + index * 4, data_block_at(alloc, index), 4)?
      index += 1
    }

    out = put_le(out, 88, alloc.single, 4)?
    out = put_le(out, 92, alloc.double, 4)?
  }

  return out
}

proc write_inode(image: Path, inode: Int, data: Bytes) [error] {
  let group_index = (inode - 1) / INODES_PER_GROUP
  let local = (inode - 1) % INODES_PER_GROUP
  let table = group_index * BLOCKS_PER_GROUP + 4
  let written = bytes.write_at(image, table * BLOCK_SIZE + local * INODE_SIZE, data)?
  let _ = written
}

proc group_desc(
  block_bitmap: Int,
  inode_bitmap: Int,
  inode_table: Int,
  free_blocks: Int,
  free_inodes: Int,
  used_dirs: Int,
) [error] -> Result[Bytes] {
  var out = bytes.zero(32)?
  out = put_le(out, 0, block_bitmap, 4)?
  out = put_le(out, 4, inode_bitmap, 4)?
  out = put_le(out, 8, inode_table, 4)?
  out = put_le(out, 12, free_blocks, 2)?
  out = put_le(out, 14, free_inodes, 2)?
  out = put_le(out, 16, used_dirs, 2)?
  return out
}

proc superblock(
  total_inodes: Int,
  total_blocks: Int,
  free_blocks: Int,
  free_inodes: Int,
  label: Str,
) [error] -> Result[Bytes] {
  var out = bytes.zero(1024)?
  out = put_le(out, 0, total_inodes, 4)?
  out = put_le(out, 4, total_blocks, 4)?
  out = put_le(out, 12, free_blocks, 4)?
  out = put_le(out, 16, free_inodes, 4)?
  out = put_le(out, 24, 2, 4)?
  out = put_le(out, 28, 2, 4)?
  out = put_le(out, 32, BLOCKS_PER_GROUP, 4)?
  out = put_le(out, 36, BLOCKS_PER_GROUP, 4)?
  out = put_le(out, 40, INODES_PER_GROUP, 4)?
  out = put_le(out, 44, FIXED_TIME, 4)?
  out = put_le(out, 48, FIXED_TIME, 4)?
  out = put_le(out, 54, 65535, 2)?
  out = put_le(out, 56, 61267, 2)?
  out = put_le(out, 58, 1, 2)?
  out = put_le(out, 60, 1, 2)?
  out = put_le(out, 64, FIXED_TIME, 4)?
  out = put_le(out, 76, 1, 4)?
  out = put_le(out, 84, 11, 4)?
  out = put_le(out, 88, INODE_SIZE, 2)?
  out = put_le(out, 96, 2, 4)?
  out = put_le(out, 100, 2, 4)?

  out = put(
    out,
    104,
    bytes.from_ints(
      [
        17,
        17,
        17,
        17,
        34,
        34,
        51,
        51,
        68,
        68,
        85,
        85,
        85,
        85,
        85,
        85,
      ],
    )?,
  )?

  out = put(out, 120, fixed_text(label, 16)?)?
  return out
}

proc block_bitmap_bytes(first: Int, group_blocks: Int, allocated_next: Int) [error] -> Result[Bytes] {
  var out = []
  var byte_index = 0

  while byte_index < BLOCK_SIZE {
    var value = 0
    var bit = 0

    while bit < 8 {
      let local = byte_index * 8 + bit

      if local >= group_blocks or local < 4 + INODE_TABLE_BLOCKS or first + local < allocated_next {
        value += bit_value(bit)
      }

      bit += 1
    }

    out = out.push(value)
    byte_index += 1
  }

  return bytes.from_ints(out)?
}

proc inode_bitmap_bytes(first_inode: Int, max_inode: Int) [error] -> Result[Bytes] {
  var out = []
  var byte_index = 0

  while byte_index < BLOCK_SIZE {
    var value = 0
    var bit = 0

    while bit < 8 {
      let local = byte_index * 8 + bit
      let inode = first_inode + local

      if local >= INODES_PER_GROUP or inode <= 10 or inode >= 11 and inode <= max_inode {
        value += bit_value(bit)
      }

      bit += 1
    }

    out = out.push(value)
    byte_index += 1
  }

  return bytes.from_ints(out)?
}

proc used_dirs_in_group(entries: List[ExtEntry], group_index: Int) [] -> Int {
  var count = if group_index == 0 { 1 } else { 0 }

  for entry in entries {
    if entry.kind == "dir" and (entry.inode - 1) / INODES_PER_GROUP == group_index {
      count += 1
    }
  }

  return count
}

proc write_headers(
  image: Path,
  entries: List[ExtEntry],
  allocated_next: Int,
  groups: Int,
  total_blocks: Int,
  label: Str,
) [error] {
  let max_inode = if entries.len() == 0 { 10 } else { entries[entries.len() - 1].inode }
  var desc_parts = []
  var free_blocks_total = 0
  var group_index = 0

  while group_index < groups {
    let first = group_index * BLOCKS_PER_GROUP
    let group_blocks = min_int(BLOCKS_PER_GROUP, total_blocks - first)
    let block_bitmap = first + 2
    let inode_bitmap = first + 3
    let inode_table = first + 4
    let block_bitmap_data = block_bitmap_bytes(first, group_blocks, allocated_next)?
    write_block(image, block_bitmap, block_bitmap_data)?
    var used_blocks = 0
    var local = 0

    while local < group_blocks {
      if local < 4 + INODE_TABLE_BLOCKS or first + local < allocated_next {
        used_blocks += 1
      }

      local += 1
    }

    let free_blocks = group_blocks - used_blocks
    free_blocks_total += free_blocks
    let first_inode = group_index * INODES_PER_GROUP + 1
    let inode_bitmap_data = inode_bitmap_bytes(first_inode, max_inode)?
    write_block(image, inode_bitmap, inode_bitmap_data)?
    var used_inodes = 0
    local = 0

    while local < INODES_PER_GROUP {
      let inode = first_inode + local

      if inode <= 10 or inode >= 11 and inode <= max_inode {
        used_inodes += 1
      }

      local += 1
    }

    desc_parts = desc_parts.push(
      group_desc(
        block_bitmap,
        inode_bitmap,
        inode_table,
        free_blocks,
        INODES_PER_GROUP - used_inodes,
        used_dirs_in_group(entries, group_index),
      )?,
    )

    group_index += 1
  }

  let total_inodes = groups * INODES_PER_GROUP
  let sb = superblock(total_inodes, total_blocks, free_blocks_total, total_inodes - max_inode, label)?
  let written = bytes.write_at(image, 1024, sb)?
  let _ = written
  write_block(image, 1, bytes.concat(desc_parts))?
  group_index = 1

  while group_index < groups {
    let first = group_index * BLOCKS_PER_GROUP
    write_block(image, first, sb)?
    write_block(image, first + 1, bytes.concat(desc_parts))?
    group_index += 1
  }
}

proc zero_image(image: Path, size: Int) [error] {
  let chunk = 1024 * 1024
  var offset = 0

  while offset < size {
    let length = min_int(size - offset, chunk)
    bytes.zero_at(image, offset, length)?
    offset += length
  }
}

proc image_size(image: Path) [fs, error] -> Result[Int] {
  let size = image.metadata()?.size

  if size > 0 {
    return size
  }

  let sectors_path = fp"/sys/class/block/${image.name}/size"

  if fs.exists(sectors_path)? {
    return fs.read_text(sectors_path)?.trim().parse_int()? * 512
  }

  return size
}

proc format_ext_image(image: Path, source_root: Path, label: Str) [fs, error] {
  let size = image_size(image)?

  if size < 8 * 1024 * 1024 {
    return Err(Ext4ToolError.Failed("too-small", "ext image must be at least 8MiB"))
  }

  if size % BLOCK_SIZE != 0 {
    return Err(Ext4ToolError.Failed("bad-size", "ext image size must be a multiple of 4096 bytes"))
  }

  let total_blocks = size / BLOCK_SIZE
  let groups = ceil_div(total_blocks, BLOCKS_PER_GROUP)
  var used = reserve_metadata_blocks(total_blocks, groups)
  var next = 4 + INODE_TABLE_BLOCKS
  let source_root = source_root.resolve()?
  let collected = collect_entries(source_root, source_root, [])?
  let entries = assign_inodes(collected)
  zero_image(image, size)?
  let root_data = dir_data(entries, "", 2, 2)?
  var result = allocate_bytes(image, used, next, total_blocks, root_data)?
  used = result.used
  next = result.next

  write_inode(
    image,
    2,
    inode_bytes(0o040755, 0, 0, root_data.len(), FIXED_TIME, dir_links(entries, ""), result.alloc, bytes.zero(0)?)?,
  )?

  for entry in entries {
    if entry.kind == "dir" {
      let parent_inode = inode_for(entries, entry.parent)
      let data = dir_data(entries, entry.rel, entry.inode, parent_inode)?
      result = allocate_bytes(image, used, next, total_blocks, data)?
      used = result.used
      next = result.next

      write_inode(
        image,
        entry.inode,
        inode_bytes(
          0o040000 + entry.mode % 4096,
          entry.uid,
          entry.gid,
          data.len(),
          entry.mtime,
          dir_links(entries, entry.rel),
          result.alloc,
          bytes.zero(0)?,
        )?,
      )?
    } else if entry.kind == "file" {
      result = allocate_file(image, used, next, total_blocks, entry.path, entry.size)?
      used = result.used
      next = result.next

      write_inode(
        image,
        entry.inode,
        inode_bytes(
          0o100000 + entry.mode % 4096,
          entry.uid,
          entry.gid,
          entry.size,
          entry.mtime,
          1,
          result.alloc,
          bytes.zero(0)?,
        )?,
      )?
    } else if entry.kind == "symlink" {
      if entry.target.len() <= 60 {
        result = {
          used,
          next,
          alloc: {
            first: 0,
            count: 0,
            blocks: [],
            single: 0,
            double: 0,
            indirects: [],
            sectors: 0,
          },
        }
      } else {
        result = allocate_bytes(image, used, next, total_blocks, entry.target)?
        used = result.used
        next = result.next
      }

      write_inode(
        image,
        entry.inode,
        inode_bytes(0o120777, entry.uid, entry.gid, entry.target.len(), entry.mtime, 1, result.alloc, entry.target)?,
      )?
    }
  }

  write_headers(image, entries, next, groups, total_blocks, label)?
}

proc main(...argv: List[Str]) [fs, error] {
  var label = "LAPUTA_ROOT"
  var source_root = p""
  var image = ""
  var index = 0

  while index < argv.len() {
    let arg = argv[index]

    if arg == "-q" or arg == "-F" {
      index += 1
    } else if arg == "-L" or arg == "-d" or arg == "-O" or arg == "-E" {
      if index + 1 >= argv.len() {
        return Err(Ext4ToolError.Failed("usage", f"${arg} requires an argument"))
      }

      let value = argv[index + 1]

      if arg == "-L" {
        label = value
      } else if arg == "-d" {
        source_root = fp"${value}"
      } else if arg == "-O" {
        if value != "^64bit,^metadata_csum" and value != "^metadata_csum,^64bit" {
          return Err(Ext4ToolError.Failed("unsupported-feature", value))
        }
      }

      index += 2
    } else if arg.starts_with("-") {
      return Err(Ext4ToolError.Failed("unsupported-option", arg))
    } else {
      image = arg
      index += 1
    }
  }

  if image == "" {
    return Err(Ext4ToolError.Failed("usage", "usage: mkfs.ext4 [-L LABEL] [-d ROOT] IMAGE"))
  }

  if source_root.display() == "" {
    let empty_dir = /tmp/mkfs-ext4-empty
    fs.mkdir(empty_dir)?
    source_root = empty_dir
  }

  format_ext_image(fp"${image}", source_root, label)?
}

main(@args)?
