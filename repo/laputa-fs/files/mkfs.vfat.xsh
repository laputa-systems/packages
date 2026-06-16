#!/usr/local/bin/xsh --
error FatToolError = Failed(kind: Str, message: Str)

pure ceil_div(value: Int, divisor: Int) -> Int {
  return (value + divisor - 1) / divisor
}

proc repeated_byte(value: Int, count: Int) [error] -> Result[Bytes] {
  var items: List[Int] = []
  var index = 0

  while index < count {
    items = items.push(value)
    index += 1
  }

  return bytes.from_ints(items)?
}

proc fixed_text(text: Str, width: Int) [error] -> Result[Bytes] {
  let raw = bytes.from_text(text)

  if raw.len() >= width {
    return raw.slice(offset: 0, length: width)
  }

  return bytes.concat([raw, repeated_byte(32, width - raw.len())?])
}

pure total_sectors(size: Int) -> Int {
  return size / 512
}

pure sectors_per_cluster(sectors: Int) -> Int {
  if sectors < 65536 {
    return 1
  }

  if sectors < 262144 {
    return 4
  }

  if sectors < 524288 {
    return 8
  }

  return 16
}

proc fat16_sectors(sectors: Int, spc: Int, reserved: Int, fats: Int, root_dir_sectors: Int) [error] -> Int {
  var fat_sectors = 1
  var changed = true

  while changed {
    let data_sectors = sectors - reserved - root_dir_sectors - fats * fat_sectors
    let clusters = data_sectors / spc
    let needed = ceil_div((clusters + 2) * 2, 512)
    changed = needed != fat_sectors
    fat_sectors = needed
  }

  return fat_sectors
}

proc boot_sector(label: Str, sectors: Int, spc: Int, fat_sectors: Int, serial: Int) [error] -> Result[Bytes] {
  let total16 = if sectors <= 65535 { sectors } else { 0 }
  let total32 = if sectors > 65535 { sectors } else { 0 }

  var boot = bytes.concat(
    [
      bytes.from_ints([235, 60, 144])?,
      fixed_text("mkfs.xsh", 8)?,
      bytes.pack_le(512, 2)?,
      bytes.from_ints([spc])?,
      bytes.pack_le(1, 2)?,
      bytes.from_ints([2])?,
      bytes.pack_le(512, 2)?,
      bytes.pack_le(total16, 2)?,
      bytes.from_ints([248])?,
      bytes.pack_le(fat_sectors, 2)?,
      bytes.pack_le(32, 2)?,
      bytes.pack_le(64, 2)?,
      bytes.pack_le(0, 4)?,
      bytes.pack_le(total32, 4)?,
      bytes.from_ints([128, 0, 41])?,
      bytes.pack_le(serial, 4)?,
      fixed_text(label, 11)?,
      fixed_text("FAT16", 8)?,
    ],
  )

  boot = bytes.concat([boot, bytes.zero(510 - boot.len())?, bytes.from_ints([85, 170])?])
  return boot
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

proc format_fat16(image: Path, label: Str) [fs, error] {
  let size = image_size(image)?

  if size < 2 * 1024 * 1024 {
    return Err(FatToolError.Failed("too-small", "FAT16 image must be at least 2MiB"))
  }

  if size % 512 != 0 {
    return Err(FatToolError.Failed("bad-size", "FAT image size must be a multiple of 512 bytes"))
  }

  let sectors = total_sectors(size)
  let spc = sectors_per_cluster(sectors)
  let root_dir_sectors = 32
  let fat_sectors = fat16_sectors(sectors, spc, 1, 2, root_dir_sectors)
  let data_sectors = sectors - 1 - root_dir_sectors - 2 * fat_sectors
  let clusters = data_sectors / spc

  if clusters < 4085 or clusters >= 65525 {
    return Err(FatToolError.Failed("unsupported-size", "native mkfs.vfat currently supports FAT16-sized images"))
  }

  let cleared = bytes.zero_at(image, 0, size)?
  let boot_written = bytes.write_at(image, 0, boot_sector(label, sectors, spc, fat_sectors, 387344745)?)?
  let fat_offset = 512
  let fat_len = fat_sectors * 512
  let fat = bytes.concat([bytes.from_ints([248, 255, 255, 255])?, bytes.zero(fat_len - 4)?])
  let fat0_written = bytes.write_at(image, fat_offset, fat)?
  let fat1_written = bytes.write_at(image, fat_offset + fat_len, fat)?
  let _ = [cleared, boot_written, fat0_written, fat1_written]
}

proc main(...argv: List[Str]) [fs, error] {
  var label = "NO NAME"
  var image = ""
  var index = 0

  while index < argv.len() {
    let arg = argv[index]

    if arg == "-n" or arg == "-F" {
      if index + 1 >= argv.len() {
        return Err(FatToolError.Failed("usage", "option requires an argument"))
      }

      if arg == "-n" {
        label = argv[index + 1]
      }

      index += 2
    } else if arg.starts_with("-") {
      return Err(FatToolError.Failed("unsupported-option", arg))
    } else {
      image = arg
      index += 1
    }
  }

  if image == "" {
    return Err(FatToolError.Failed("usage", "usage: mkfs.vfat [-n LABEL] IMAGE"))
  }

  format_fat16(Path.parse(image)?, label)?
}

main(@args)?
