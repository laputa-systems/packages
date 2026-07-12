#!/bin/xsh
error Ext4FsckError = Failed(kind: Str, message: Str)

let BLOCK_SIZE = 4096
let BLOCKS_PER_GROUP = 32768
let INODES_PER_GROUP = 8192

pure ceil_div(value: Int, divisor: Int) -> Int {
  if value == 0 {
    return 0
  }

  return (value + divisor - 1) / divisor
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

proc bit_set(bitmap: Bytes, bit: Int) [error] -> Result[Bool] {
  let byte = bytes.unpack_le(bitmap, 1, offset: bit / 8)?
  return byte / bit_value(bit % 8) % 2 == 1
}

proc expect_int(kind: Str, actual: Int, expected: Int) [error] {
  if actual != expected {
    return Err(Ext4FsckError.Failed(kind, f"expected ${expected}, found ${actual}"))
  }
}

proc used_bits(bitmap: Bytes, limit: Int) [error] -> Result[Int] {
  var used = 0
  var bit = 0

  while bit < limit {
    if bit_set(bitmap, bit)? {
      used += 1
    }

    bit += 1
  }

  return used
}

proc check_image(image: Path) [error] {
  let super = bytes.read_at(image, 1024, 1024)?
  let total_inodes = bytes.unpack_le(super, 4, offset: 0)?
  let total_blocks = bytes.unpack_le(super, 4, offset: 4)?
  let free_blocks = bytes.unpack_le(super, 4, offset: 12)?
  let free_inodes = bytes.unpack_le(super, 4, offset: 16)?
  let log_block_size = bytes.unpack_le(super, 4, offset: 24)?
  let blocks_per_group = bytes.unpack_le(super, 4, offset: 32)?
  let inodes_per_group = bytes.unpack_le(super, 4, offset: 40)?
  let magic = bytes.unpack_le(super, 2, offset: 56)?
  let inode_size = bytes.unpack_le(super, 2, offset: 88)?
  expect_int("bad-magic", magic, 61267)?
  expect_int("bad-block-size", log_block_size, 2)?
  expect_int("bad-blocks-per-group", blocks_per_group, BLOCKS_PER_GROUP)?
  expect_int("bad-inodes-per-group", inodes_per_group, INODES_PER_GROUP)?
  expect_int("bad-inode-size", inode_size, 256)?
  let groups = ceil_div(total_blocks, BLOCKS_PER_GROUP)
  expect_int("bad-total-inodes", total_inodes, groups * INODES_PER_GROUP)?
  let descs = bytes.read_at(image, BLOCK_SIZE, groups * 32)?
  var counted_free_blocks = 0
  var counted_free_inodes = 0
  var group_index = 0

  while group_index < groups {
    let desc = descs.slice(offset: group_index * 32, length: 32)
    let first = group_index * BLOCKS_PER_GROUP
    let group_blocks = min_int(BLOCKS_PER_GROUP, total_blocks - first)
    let block_bitmap = bytes.unpack_le(desc, 4, offset: 0)?
    let inode_bitmap = bytes.unpack_le(desc, 4, offset: 4)?
    let inode_table = bytes.unpack_le(desc, 4, offset: 8)?
    let desc_free_blocks = bytes.unpack_le(desc, 2, offset: 12)?
    let desc_free_inodes = bytes.unpack_le(desc, 2, offset: 14)?
    expect_int("bad-block-bitmap", block_bitmap, first + 2)?
    expect_int("bad-inode-bitmap", inode_bitmap, first + 3)?
    expect_int("bad-inode-table", inode_table, first + 4)?
    let block_map = bytes.read_at(image, block_bitmap * BLOCK_SIZE, BLOCK_SIZE)?
    let inode_map = bytes.read_at(image, inode_bitmap * BLOCK_SIZE, BLOCK_SIZE)?
    let block_used = used_bits(block_map, group_blocks)?
    let inode_used = used_bits(inode_map, INODES_PER_GROUP)?
    let block_free = group_blocks - block_used
    let inode_free = INODES_PER_GROUP - inode_used
    expect_int("bad-free-blocks", desc_free_blocks, block_free)?
    expect_int("bad-free-inodes", desc_free_inodes, inode_free)?
    counted_free_blocks += block_free
    counted_free_inodes += inode_free
    group_index += 1
  }

  expect_int("bad-free-block-total", free_blocks, counted_free_blocks)?
  expect_int("bad-free-inode-total", free_inodes, counted_free_inodes)?
}

proc main(...argv: List[Str]) [error] {
  var image = ""
  var index = 0

  while index < argv.len() {
    let arg = argv[index]

    if arg == "-n" or arg == "-p" or arg == "-a" or arg == "-f" {
      index += 1
    } else if arg.starts_with("-") {
      return Err(Ext4FsckError.Failed("unsupported-option", arg))
    } else {
      image = arg
      index += 1
    }
  }

  if image == "" {
    return Err(Ext4FsckError.Failed("usage", "usage: fsck.ext4 [-n|-p] IMAGE"))
  }

  check_image(fp"${image}")?
}

main(@args)?
