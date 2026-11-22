import Foundation
import MachO

struct MachOInspection {
  var dependencies = Set<String>()
  var hasSwiftMetadata = false
  var isMacCatalyst = false
  var hasDartAot = false
}

/// Reads metadata from the 64-bit Mach-O slices used by macOS apps.
struct MachOInspector {
  private static let swiftSections: Set<String> = [
    "__swift5_types", "__swift5_fieldmd", "__swift5_proto", "__swift5_protos",
  ]
  private static let dartSymbols: [Set<String>] = [
    ["_kDartSnapshotData", "_kDartSnapshotText"],
    ["_kDartIsolateSnapshotData", "_kDartIsolateSnapshotInstructions"],
  ]

  private let file: FileHandle
  private let size: UInt64

  static func inspect(_ url: URL, checkDartAot: Bool = false) -> MachOInspection {
    var result = MachOInspection()
    guard let file = try? FileHandle(forReadingFrom: url) else { return result }
    defer { try? file.close() }
    guard let size = try? file.seekToEnd() else { return result }
    let reader = MachOInspector(file: file, size: size)
    for slice in reader.slices() {
      guard let info = reader.inspect(slice, checkDartAot: checkDartAot) else { continue }
      result.dependencies.formUnion(info.dependencies)
      result.hasSwiftMetadata = result.hasSwiftMetadata || info.hasSwiftMetadata
      result.isMacCatalyst = result.isMacCatalyst || info.isMacCatalyst
      result.hasDartAot = result.hasDartAot || info.hasDartAot
    }
    return result
  }

  private func slices() -> [Range<UInt64>] {
    let fileRange = 0..<size
    guard let header = read(0, count: 8, in: fileRange) else { return [] }
    if header.word(0) == MH_MAGIC_64 { return [fileRange] }

    let magic = header.word(0, bigEndian: true)
    guard magic == FAT_MAGIC || magic == FAT_MAGIC_64 else { return [] }
    let wide = magic == FAT_MAGIC_64
    let entrySize = wide ? MemoryLayout<fat_arch_64>.size : MemoryLayout<fat_arch>.size
    let count = Int(header.word(4, bigEndian: true))
    guard count <= 32,
          let entries = read(8, count: count * entrySize, in: fileRange) else { return [] }
    return (0..<count).compactMap { index in
      let entry = index * entrySize
      let offset = wide ? entries.quad(entry + 8, bigEndian: true)
        : UInt64(entries.word(entry + 8, bigEndian: true))
      let length = wide ? entries.quad(entry + 16, bigEndian: true)
        : UInt64(entries.word(entry + 12, bigEndian: true))
      guard offset >= UInt64(8 + entries.count), offset < size,
            length <= size - offset else { return nil }
      return offset..<(offset + length)
    }
  }

  private func inspect(_ slice: Range<UInt64>, checkDartAot: Bool) -> MachOInspection? {
    let headerSize = MemoryLayout<mach_header_64>.size
    guard let header = read(0, count: headerSize, in: slice),
          header.word(0) == MH_MAGIC_64 else { return nil }
    let commandCount = Int(header.word(16))
    let commandBytes = Int(header.word(20))
    guard commandCount <= commandBytes / 8,
          let commands = read(UInt64(headerSize), count: commandBytes, in: slice) else { return nil }

    var result = MachOInspection()
    var offset = 0
    for _ in 0..<commandCount {
      guard offset <= commands.count - 8 else { return nil }
      let commandSize = Int(commands.word(offset + 4))
      guard commandSize >= 8, commandSize % 8 == 0,
            commandSize <= commands.count - offset else { return nil }
      switch commands.word(offset) {
      case UInt32(LC_LOAD_DYLIB), UInt32(LC_LOAD_WEAK_DYLIB), UInt32(LC_REEXPORT_DYLIB),
           UInt32(LC_LOAD_UPWARD_DYLIB), UInt32(LC_LAZY_LOAD_DYLIB):
        if commandSize >= MemoryLayout<dylib_command>.size {
          let name = Int(commands.word(offset + 8))
          if name >= MemoryLayout<dylib_command>.size, name < commandSize,
             let dependency = commands.name(offset + name, end: offset + commandSize, terminated: true) {
            result.dependencies.insert(dependency)
          }
        }
      case UInt32(LC_SEGMENT_64) where !result.hasSwiftMetadata:
        result.hasSwiftMetadata = Self.hasSwiftSection(
          commands, offset: offset, size: commandSize, sliceSize: slice.upperBound - slice.lowerBound
        )
      case UInt32(LC_BUILD_VERSION):
        if commandSize >= MemoryLayout<build_version_command>.size,
           commands.word(offset + 8) == UInt32(PLATFORM_MACCATALYST) {
          result.isMacCatalyst = true
        }
      case UInt32(LC_SYMTAB) where checkDartAot && !result.hasDartAot:
        if commandSize >= MemoryLayout<symtab_command>.size {
          result.hasDartAot = hasDartSnapshot(commands, offset: offset, slice: slice)
        }
      default:
        break
      }
      offset += commandSize
    }
    return offset == commands.count ? result : nil
  }

  private static func hasSwiftSection(
    _ commands: Data, offset: Int, size: Int, sliceSize: UInt64
  ) -> Bool {
    let segmentSize = MemoryLayout<segment_command_64>.size
    let sectionSize = MemoryLayout<section_64>.size
    guard size >= segmentSize,
          commands.name(offset + 8, end: offset + 24) == "__TEXT" else { return false }
    let count = Int(commands.word(offset + 64))
    guard count <= (size - segmentSize) / sectionSize else { return false }
    for index in 0..<count {
      let section = offset + segmentSize + index * sectionSize
      guard let name = commands.name(section, end: section + 16),
            swiftSections.contains(name) else { continue }
      let length = commands.quad(section + 40)
      let fileOffset = UInt64(commands.word(section + 48))
      if length > 0, fileOffset > 0, fileOffset <= sliceSize,
         length <= sliceSize - fileOffset,
         commands.word(section + 64) & UInt32(SECTION_TYPE) == UInt32(S_REGULAR) {
        return true
      }
    }
    return false
  }

  private func hasDartSnapshot(_ commands: Data, offset: Int, slice: Range<UInt64>) -> Bool {
    let entrySize = MemoryLayout<nlist_64>.size
    let count = Int(commands.word(offset + 12))
    guard let symbols = read(UInt64(commands.word(offset + 8)), count: count * entrySize, in: slice),
          let strings = read(UInt64(commands.word(offset + 16)),
            count: Int(commands.word(offset + 20)), in: slice) else { return false }
    var found = Set<String>()
    for index in 0..<count {
      let entry = index * entrySize
      // N_SECT | N_EXT identifies an externally visible, defined section symbol.
      guard symbols[entry + 4] == 0x0f, symbols[entry + 5] != 0 else { continue }
      let start = Int(symbols.word(entry))
      guard start > 0, start < strings.count, strings[start] == 0x5f,
            let name = strings.name(start, end: min(start + 64, strings.count), terminated: true),
            Self.dartSymbols.contains(where: { $0.contains(name) }) else { continue }
      found.insert(name)
      if Self.dartSymbols.contains(where: { $0.isSubset(of: found) }) { return true }
    }
    return false
  }

  private func read(_ offset: UInt64, count: Int, in slice: Range<UInt64>) -> Data? {
    // Limit memory to metadata rather than mapping the executable.
    let length = slice.upperBound - slice.lowerBound
    guard count > 0, count <= 4 * 1024 * 1024, offset <= length,
          UInt64(count) <= length - offset else { return nil }
    do {
      try file.seek(toOffset: slice.lowerBound + offset)
      guard let bytes = try file.read(upToCount: count), bytes.count == count else { return nil }
      return bytes
    } catch {
      return nil
    }
  }
}

private extension Data {
  func word(_ offset: Int, bigEndian: Bool = false) -> UInt32 {
    let value = withUnsafeBytes { $0.loadUnaligned(fromByteOffset: offset, as: UInt32.self) }
    return bigEndian ? UInt32(bigEndian: value) : UInt32(littleEndian: value)
  }

  func quad(_ offset: Int, bigEndian: Bool = false) -> UInt64 {
    let value = withUnsafeBytes { $0.loadUnaligned(fromByteOffset: offset, as: UInt64.self) }
    return bigEndian ? UInt64(bigEndian: value) : UInt64(littleEndian: value)
  }

  func name(_ start: Int, end: Int, terminated: Bool = false) -> String? {
    if let zero = self[start..<end].firstIndex(of: 0) {
      return String(bytes: self[start..<zero], encoding: .utf8)
    }
    return terminated ? nil : String(bytes: self[start..<end], encoding: .utf8)
  }
}
