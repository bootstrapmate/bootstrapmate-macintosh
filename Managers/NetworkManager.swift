import Foundation

enum DownloadError: Error {
    case invalidURL
    case requestFailed(String)
}

public final class NetworkManager {
    nonisolated(unsafe) public static let shared = NetworkManager()

    public var authorizationHeader: String?

    private init() {}

    /// Session that never serves cached responses. Bootstrap data must reflect ORIGIN
    /// truth on every run: management.json drives the per-item hash check, so a stale
    /// manifest (from the local URL cache or a CDN edge that hasn't purged yet) makes a
    /// changed file — e.g. ProvisioningWatcher.sh — compare against a stale expected hash,
    /// get judged "already valid", and never re-download. Disabling the URL cache and
    /// ignoring local + remote caches makes the hash diff always self-heal.
    private static let noCacheSession: URLSession = {
        let config = URLSessionConfiguration.default
        config.urlCache = nil
        config.requestCachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        return URLSession(configuration: config)
    }()

    public func downloadData(
        from url: URL,
        followRedirects: Bool,
        authHeader: String?,
        completion: @escaping @Sendable (Data?, Error?) -> Void
    ) {
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalAndRemoteCacheData)
        if let header = authHeader {
            request.addValue(header, forHTTPHeaderField: "Authorization")
        }
        Self.noCacheSession.dataTask(with: request) { data, _, error in
            completion(data, error)
        }.resume()
    }

    public func downloadFile(
        toPath path: String,
        from urlString: String,
        followRedirects: Bool,
        authHeader: String?,
        completion: @escaping @Sendable (Result<Void, Error>) -> Void
    ) {
        guard let url = URL(string: urlString) else {
            completion(.failure(DownloadError.invalidURL))
            return
        }
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalAndRemoteCacheData)
        if let header = authHeader ?? authorizationHeader {
            request.addValue(header, forHTTPHeaderField: "Authorization")
        }

        let task = Self.noCacheSession.downloadTask(with: request) { tempURL, _, error in
            if let error = error {
                completion(.failure(error))
                return
            }
            guard let tempURL = tempURL else {
                completion(.failure(DownloadError.requestFailed("No temp file.")))
                return
            }
            do {
                if FileManager.default.fileExists(atPath: path) {
                    try FileManager.default.removeItem(atPath: path)
                }
                try FileManager.default.moveItem(at: tempURL, to: URL(fileURLWithPath: path))
                completion(.success(()))
            } catch {
                completion(.failure(error))
            }
        }
        task.resume()
    }
}
