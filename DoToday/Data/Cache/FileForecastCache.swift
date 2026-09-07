//
//  FileForecastCache.swift
//  DoToday
//
//  Data layer.
//

import Foundation

/// Disk-backed forecast cache, one JSON file per location.
///
/// An `actor` because it is shared across concurrent requests and owns mutable file
/// state; serialising access removes any chance of a torn read during a write.
///
/// It lives in `Caches/`, which the system may purge under storage pressure — exactly
/// the right semantics for data we can always re-fetch. Cache failures are swallowed:
/// an unwritable cache must degrade the app to "online only", never break it.
actor FileForecastCache: ForecastCache {
    private let directory: URL
    private let fileManager: FileManager
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    init(fileManager: FileManager = .default, directoryName: String = "ForecastCache") {
        self.fileManager = fileManager
        let base = fileManager.urls(for: .cachesDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory())
        self.directory = base.appendingPathComponent(directoryName, isDirectory: true)
        // Dates are encoded as ISO-8601 so a cache file stays readable if the default
        // encoding strategy ever changes.
        encoder.dateEncodingStrategy = .iso8601
        decoder.dateDecodingStrategy = .iso8601
    }

    func entry(for key: ForecastCacheKey) async -> CachedForecastEntry? {
        let url = fileURL(for: key)
        guard let data = try? Data(contentsOf: url) else { return nil }
        // A file we can no longer decode is from an older schema; drop it quietly.
        guard let entry = try? decoder.decode(CachedForecastEntry.self, from: data) else {
            try? fileManager.removeItem(at: url)
            return nil
        }
        return entry
    }

    func store(_ payload: ForecastResponseDTO, for key: ForecastCacheKey, at date: Date) async {
        let entry = CachedForecastEntry(payload: payload, storedAt: date)
        guard let data = try? encoder.encode(entry) else { return }
        try? fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        try? data.write(to: fileURL(for: key), options: .atomic)
    }

    private func fileURL(for key: ForecastCacheKey) -> URL {
        directory.appendingPathComponent("\(key.storageIdentifier).json")
    }
}

/// Non-persisting cache used by tests and previews where disk I/O adds nothing.
actor InMemoryForecastCache: ForecastCache {
    private var storage: [ForecastCacheKey: CachedForecastEntry] = [:]

    init() {}

    func entry(for key: ForecastCacheKey) async -> CachedForecastEntry? {
        storage[key]
    }

    func store(_ payload: ForecastResponseDTO, for key: ForecastCacheKey, at date: Date) async {
        storage[key] = CachedForecastEntry(payload: payload, storedAt: date)
    }
}
