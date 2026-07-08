#!/bin/xsh --
error FatPutError = Failed(kind: Str, message: Str)

proc ceil_div(value: Int, divisor: Int) [error] -> Int {
  return (value + divisor - 1) / divisor
}

proc le16(value: Int) [error] -> Result[Bytes] {
  return bytes.pack_le(value, 2)?
}

proc le32(value: Int) [error] -> Result[Bytes] {
  return bytes.pack_le(value, 4)?
}

proc fixed_name(name: Str) [error] -> Result[Bytes] {
  let raw = bytes.from_text(name)

  if raw.len() > 11 {
    return Err(FatPutError.Failed("name-too-long", name))
  }

  return bytes.concat([raw, bytes.zero(11 - raw.len())?])
}

proc dir_entry(name: Str, attr: Int, cluster: Int, size: Int) [error] -> Result[Bytes] {
  return bytes.concat(
    [
      fixed_name(name)?,
      bytes.from_ints([attr])?,
      bytes.zero(9)?,
      le16(cluster / 65536 % 65536)?,
      le16(0)?,
      le16(0)?,
      le16(cluster % 65536)?,
      le32(size)?,
    ],
  )
}

proc dir_block(
  self_cluster: Int,
  parent_cluster: Int,
  entries: List[Bytes],
  cluster_size: Int,
) [error] -> Result[Bytes] {
  var parts: List[Bytes] = [
    dir_entry(".          ", 16, self_cluster, 0)?,
    dir_entry("..         ", 16, parent_cluster, 0)?,
  ]

  parts = parts.extend(entries)
  return bytes.concat([bytes.concat(parts), bytes.zero(cluster_size - bytes.concat(parts).len())?])
}

proc set_fat(image: Path, fat_offset: Int, fat_sectors: Int, cluster: Int, value: Int) [error] {
  let encoded = le16(value)?
  let first = bytes.write_at(image, fat_offset + cluster * 2, encoded)?
  let second = bytes.write_at(image, fat_offset + fat_sectors * 512 + cluster * 2, encoded)?
  let _ = [first, second]
}

proc write_cluster(image: Path, data_offset: Int, cluster: Int, data: Bytes, cluster_size: Int) [error] {
  let written = bytes.write_at(
    image,
    data_offset + (cluster - 2) * cluster_size,
    bytes.concat([data, bytes.zero(cluster_size - data.len())?]),
  )?

  let _ = written
}

pure fallback_fat_name(path_value: Str) -> Result[Str] {
  if path_value == "EFI/BOOT/BOOTAA64.EFI" {
    return "BOOTAA64EFI"
  }

  if path_value == "EFI/BOOT/BOOTX64.EFI" {
    return "BOOTX64 EFI"
  }

  return Err(FatPutError.Failed("unsupported-path", path_value))
}

proc main(...argv: List[Str]) [fs, error] {
  if argv.len() != 3 {
    return Err(FatPutError.Failed("usage", "usage: fat-put IMAGE SOURCE EFI/BOOT/{BOOTAA64.EFI,BOOTX64.EFI}"))
  }

  let fat_name = fallback_fat_name(argv[2])?
  let image = fp"${argv[0]}"
  let source = fp"${argv[1]}"
  let data = source.read_bytes()?
  let boot = bytes.read_at(image, 0, 512)?
  let bytes_per_sector = bytes.unpack_le(boot, 2, offset: 11)?
  let sectors_per_cluster = bytes.unpack_le(boot, 1, offset: 13)?
  let reserved = bytes.unpack_le(boot, 2, offset: 14)?
  let fats = bytes.unpack_le(boot, 1, offset: 16)?
  let root_entries = bytes.unpack_le(boot, 2, offset: 17)?
  let fat_sectors = bytes.unpack_le(boot, 2, offset: 22)?

  if bytes_per_sector != 512 or fats != 2 {
    return Err(FatPutError.Failed("unsupported-fat", "only 512-byte-sector FAT16 with two FATs is supported"))
  }

  let cluster_size = sectors_per_cluster * 512
  let fat_offset = reserved * 512
  let root_offset = (reserved + fats * fat_sectors) * 512
  let root_size = root_entries * 32
  let data_offset = root_offset + root_size
  let file_clusters = ceil_div(data.len(), cluster_size)
  let efi_cluster = 2
  let boot_cluster = 3
  let first_file_cluster = 4
  set_fat(image, fat_offset, fat_sectors, efi_cluster, 65535)?
  set_fat(image, fat_offset, fat_sectors, boot_cluster, 65535)?
  var index = 0

  while index < file_clusters {
    let cluster = first_file_cluster + index
    let value = if index + 1 == file_clusters { 65535 } else { cluster + 1 }
    set_fat(image, fat_offset, fat_sectors, cluster, value)?
    let chunk = data.slice(index * cluster_size, cluster_size)
    write_cluster(image, data_offset, cluster, chunk, cluster_size)?
    index += 1
  }

  let root = bytes.concat([dir_entry("EFI        ", 16, efi_cluster, 0)?, bytes.zero(root_size - 32)?])
  let root_written = bytes.write_at(image, root_offset, root)?
  let _ = root_written

  write_cluster(
    image,
    data_offset,
    efi_cluster,
    dir_block(efi_cluster, efi_cluster, [dir_entry("BOOT       ", 16, boot_cluster, 0)?], cluster_size)?,
    cluster_size,
  )?

  write_cluster(
    image,
    data_offset,
    boot_cluster,
    dir_block(boot_cluster, efi_cluster, [dir_entry(fat_name, 32, first_file_cluster, data.len())?], cluster_size)?,
    cluster_size,
  )?
}

main(@args)?
