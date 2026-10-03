##! Boundary regression for the deterministic ext4 formatter shipped by laputa-fs.
const block_size = 4096
const inode_size = 256
const inode_table_block = 4

proc runner() [process, env, error] -> Result[Path] {
  let configured = env.get("XSH_HOST") ?? ""
  return fp"${configured}" when configured != ""

  process.which("xsh")?
}

proc inode_offset(inode: Int) [] -> Int {
  inode_table_block * block_size + (inode - 1) * inode_size
}

test test_ext4_uses_inline_storage_only_below_sixty_byte_symlink_boundary [fs, process, env, error] { |ctx|
  let root = test.temp_dir(ctx, name: "laputa-fs-symlink-boundary")?
  let source = fp"${root}/source"
  let image = fp"${root}/rootfs.ext4"
  let fast_target = "fffffffffffffffffffffffffffffffffffffffffffffffffffffffffff"
  let block_target = "bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"
  assert fast_target.byte_len() == 59
  assert block_target.byte_len() == 60
  fs.mkdir(source)?
  fs.symlink(fp"${fast_target}", fp"${source}/fast")?
  fs.symlink(fp"${block_target}", fp"${source}/block")?
  fs.write(image, b"")?
  image.truncate(8 * 1024 * 1024)?

  let xsh = runner()?
  let status = process.run(
    process.command_argv(
      xsh,
      [
        xsh.display(),
        "repo/laputa-fs/files/mkfs.ext4.xsh",
        "--",
        "-d",
        source.display(),
        image.display(),
      ],
    ),
  )?
  assert status.ok

  # Entries are ordered lexically: block is inode 11 and fast is inode 12.
  let block_inode = inode_offset(11)
  let fast_inode = inode_offset(12)
  assert bytes.unpack_le(bytes.read_at(image, block_inode + 28, 4)?, 4)? == 8
  assert bytes.unpack_le(bytes.read_at(image, fast_inode + 28, 4)?, 4)? == 0
  assert bytes.read_at(image, fast_inode + 40, 59)? == bytes.from_text(fast_target)

  let block = bytes.unpack_le(bytes.read_at(image, block_inode + 40, 4)?, 4)?
  assert block > 0
  assert bytes.read_at(image, block * block_size, 60)? == bytes.from_text(block_target)
}
