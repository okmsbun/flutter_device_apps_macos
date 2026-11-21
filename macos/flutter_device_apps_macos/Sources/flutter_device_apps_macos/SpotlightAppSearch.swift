import CoreServices
import Foundation

@MainActor
final class SpotlightAppSearch {
  private let query = NSMetadataQuery()
  private let completion: ([URL]) -> Void
  private var observer: NSObjectProtocol?

  private init(completion: @escaping ([URL]) -> Void) {
    self.completion = completion
  }

  nonisolated static func search(_ completion: @escaping ([URL]) -> Void) {
    DispatchQueue.main.async {
      SpotlightAppSearch(completion: completion).start()
    }
  }

  private func start() {
    query.searchScopes = [NSMetadataQueryLocalComputerScope]
    query.predicate = NSPredicate(
      format: "ANY %K == %@", kMDItemContentTypeTree as String, "com.apple.application-bundle"
    )
    observer = NotificationCenter.default.addObserver(
      forName: .NSMetadataQueryDidFinishGathering, object: query, queue: .main
    ) { _ in
      DispatchQueue.main.async { self.finish() }
    }

    if query.start() {
      DispatchQueue.main.asyncAfter(deadline: .now() + .seconds(2)) { [weak self] in
        self?.finish()
      }
    } else {
      finish()
    }
  }

  private func finish() {
    guard let observer = observer else { return }
    self.observer = nil
    NotificationCenter.default.removeObserver(observer)
    query.stop()
    completion((0..<query.resultCount).compactMap { index in
      guard let item = query.result(at: index) as? NSMetadataItem,
            let path = item.value(forAttribute: NSMetadataItemPathKey) as? String,
            path.hasPrefix("/") else { return nil }
      return URL(fileURLWithPath: path)
    })
  }
}
