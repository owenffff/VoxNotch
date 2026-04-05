//
//  DownloadProgressTracker.swift
//  VoxNotch
//
//  Polls a directory's size to estimate download progress
//

import Foundation

/// Polls a cache directory to estimate download progress.
/// Shared by FluidAudioModelManager and MLXAudioModelManager.
enum DownloadProgressTracker {

  /// Start polling a directory for download progress.
  ///
  /// - Parameters:
  ///   - directory: The directory being downloaded into
  ///   - expectedBytes: Estimated total download size
  ///   - interval: Polling interval in nanoseconds (default: 2 seconds)
  ///   - onProgress: Called on MainActor with (progress 0-0.95, downloadedBytes, totalBytes, speed)
  /// - Returns: A Task that can be cancelled when the download completes
  @discardableResult
  static func poll(
    directory: URL,
    expectedBytes: Int64,
    interval: UInt64 = 2_000_000_000,
    onProgress: @MainActor @escaping (Double, Int64, Int64, Double) -> Void
  ) -> Task<Void, Never> {
    Task {
      var lastBytes: Int64 = 0
      var lastTime = Date()

      while !Task.isCancelled {
        try? await Task.sleep(nanoseconds: interval)
        let current = directorySize(at: directory)
        guard current > 0, expectedBytes > 0 else { continue }

        let now = Date()
        let timeDiff = now.timeIntervalSince(lastTime)
        let bytesDiff = current - lastBytes
        let speed = timeDiff > 0 ? Double(bytesDiff) / timeDiff : 0

        lastBytes = current
        lastTime = now

        let progress = min(Double(current) / Double(expectedBytes), 0.95)
        await onProgress(progress, current, expectedBytes, speed)
      }
    }
  }

  /// Calculate size of a directory in bytes
  static func directorySize(at url: URL) -> Int64 {
    let fileManager = FileManager.default
    guard fileManager.fileExists(atPath: url.path) else { return 0 }

    guard let enumerator = fileManager.enumerator(
      at: url,
      includingPropertiesForKeys: [.fileSizeKey],
      options: [.skipsHiddenFiles]
    ) else { return 0 }

    var size: Int64 = 0
    for case let fileURL as URL in enumerator {
      if let fileSize = try? fileURL.resourceValues(forKeys: [.fileSizeKey]).fileSize {
        size += Int64(fileSize)
      }
    }
    return size
  }
}
