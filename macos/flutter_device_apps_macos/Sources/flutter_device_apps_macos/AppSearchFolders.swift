import Foundation

private struct AppSearchFolderBookmark: Codable {
  let id: String
  var path: String
  var data: Data

  var fields: [String: String] { ["id": id, "path": path] }
}

struct AppSearchFolderAccess {
  let urls: [URL]
  let scopedURLs: [URL]

  func stop() {
    for url in scopedURLs { url.stopAccessingSecurityScopedResource() }
  }
}

final class AppSearchFolders {
  static let shared = AppSearchFolders(defaults: .standard)

  private let defaults: UserDefaults?
  private let lock = NSLock()
  private var inMemory = [AppSearchFolderBookmark]()
  private let key = "flutter_device_apps_macos.searchFolders"
  private let bookmarkOptions: URL.BookmarkCreationOptions = [
    .withSecurityScope, .securityScopeAllowOnlyReadAccess,
  ]

  init(defaults: UserDefaults? = nil) {
    self.defaults = defaults
  }

  func add(_ url: URL) throws -> [String: String] {
    let data = try url.bookmarkData(options: bookmarkOptions)
    let path = url.resolvingSymlinksInPath().standardizedFileURL.path
    lock.lock()
    defer { lock.unlock() }
    var entries = load()
    if let index = entries.firstIndex(where: { $0.path == path }) {
      entries[index].data = data
      try save(entries)
      return entries[index].fields
    }
    let entry = AppSearchFolderBookmark(id: UUID().uuidString, path: path, data: data)
    entries.append(entry)
    try save(entries)
    return entry.fields
  }

  func list() -> [[String: String]] {
    lock.lock()
    defer { lock.unlock() }
    return load().map(\.fields)
  }

  func remove(id: String) throws {
    lock.lock()
    defer { lock.unlock() }
    try save(load().filter { $0.id != id })
  }

  func start() -> AppSearchFolderAccess {
    lock.lock()
    defer { lock.unlock() }
    var entries = load()
    var changed = false
    var urls = [URL]()
    var scopedURLs = [URL]()

    for index in entries.indices {
      var stale = false
      guard let url = try? URL(
        resolvingBookmarkData: entries[index].data,
        options: [.withSecurityScope, .withoutUI, .withoutMounting],
        relativeTo: nil, bookmarkDataIsStale: &stale
      ) else { continue }

      let started = url.startAccessingSecurityScopedResource()
      if started { scopedURLs.append(url) }
      urls.append(url)

      let path = url.resolvingSymlinksInPath().standardizedFileURL.path
      if entries[index].path != path {
        entries[index].path = path
        changed = true
      }
      if stale, started, let data = try? url.bookmarkData(options: bookmarkOptions) {
        entries[index].data = data
        changed = true
      }
    }
    if changed { try? save(entries) }
    return AppSearchFolderAccess(urls: urls, scopedURLs: scopedURLs)
  }

  private func load() -> [AppSearchFolderBookmark] {
    guard let defaults = defaults else { return inMemory }
    guard let data = defaults.data(forKey: key) else { return [] }
    return (try? PropertyListDecoder().decode([AppSearchFolderBookmark].self, from: data)) ?? []
  }

  private func save(_ entries: [AppSearchFolderBookmark]) throws {
    guard let defaults = defaults else {
      inMemory = entries
      return
    }
    defaults.set(try PropertyListEncoder().encode(entries), forKey: key)
  }
}
