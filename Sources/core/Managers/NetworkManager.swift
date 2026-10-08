import Foundation

enum DownloadError: Error {
    case invalidURL
    case requestFailed(String)
}

extension DownloadError: LocalizedError {
    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "Invalid URL."
        case .requestFailed(let message):
            return message
        }
    }
}

/// Decides, per request, whether an HTTP redirect is followed. Installed as the
/// task's own delegate, so every download carries the setting it was asked
/// for. When redirects are refused the 3xx response itself completes the task,
/// and the caller fails it as a non-2xx response.
final class RedirectPolicy: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    let follow: Bool
    let source: String

    init(follow: Bool, source: String) {
        self.follow = follow
        self.source = source
    }

    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest,
        completionHandler: @escaping @Sendable (URLRequest?) -> Void
    ) {
        let target = request.url?.absoluteString ?? "unknown"
        if follow {
            Logger.debug("Following HTTP \(response.statusCode) redirect from \(source) to \(target)")
            completionHandler(request)
        } else {
            Logger.warning("Not following HTTP \(response.statusCode) redirect from \(source) to \(target): followRedirects is off")
            completionHandler(nil)
        }
    }
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

    /// The header to send, or nil when there is none. An empty value is what a
    /// profile sets to manage the field without giving a header, and an empty
    /// Authorization header is an error to most servers, blob storage included.
    static func usableHeader(_ header: String?) -> String? {
        guard let header, !header.trimmingCharacters(in: .whitespaces).isEmpty else { return nil }
        return header
    }

    public func downloadData(
        from url: URL,
        followRedirects: Bool,
        authHeader: String?,
        completion: @escaping @Sendable (Data?, Error?) -> Void
    ) {
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalAndRemoteCacheData)
        if let header = Self.usableHeader(authHeader) {
            request.addValue(header, forHTTPHeaderField: "Authorization")
        }
        let task = Self.noCacheSession.dataTask(with: request) { data, response, error in
            if let error = error {
                completion(nil, error)
                return
            }
            // A redirect that was not followed, or any other non-2xx answer,
            // carries a body that is not the document asked for.
            if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
                completion(nil, DownloadError.requestFailed("HTTP \(http.statusCode) for \(url.absoluteString)"))
                return
            }
            completion(data, nil)
        }
        task.delegate = RedirectPolicy(follow: followRedirects, source: url.absoluteString)
        task.resume()
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
        if let header = Self.usableHeader(authHeader) ?? Self.usableHeader(authorizationHeader) {
            request.addValue(header, forHTTPHeaderField: "Authorization")
        }

        // Use dataTask instead of downloadTask to avoid the system temp directory,
        // which is read-only during Setup Assistant. Route through the shared
        // no-cache session so manifest and artifact bytes always reflect origin
        // truth (a stale cached payload would defeat the per-item hash check).
        let task = Self.noCacheSession.dataTask(with: request) { data, response, error in
            if let error = error {
                completion(.failure(error))
                return
            }
            // A non-2xx response still carries a body — a 404 page, a CDN error
            // document, an auth challenge. Writing that to the destination makes a
            // broken URL look like a hash mismatch (or, for an item with no hash,
            // hands the installer an HTML error page), so fail the download here
            // and name the status and the URL.
            if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
                let detail: String
                switch http.statusCode {
                case 401, 403:
                    detail = "HTTP \(http.statusCode) (unauthorized — the origin is private and the request carried no valid Authorization header)"
                default:
                    detail = "HTTP \(http.statusCode)"
                }
                Logger.error("Download failed: \(detail) for \(urlString)")
                completion(.failure(DownloadError.requestFailed("\(detail) for \(urlString)")))
                return
            }
            guard let data = data else {
                completion(.failure(DownloadError.requestFailed("No data received.")))
                return
            }
            do {
                // Ensure parent directory exists
                let parentDir = URL(fileURLWithPath: path).deletingLastPathComponent().path
                if !FileManager.default.fileExists(atPath: parentDir) {
                    try FileManager.default.createDirectory(atPath: parentDir, withIntermediateDirectories: true, attributes: nil)
                }
                
                // Written directly (no atomic temp file, which fails on the
                // read-only filesystem during Setup Assistant), as a new file
                // so the write never follows a link left at the path.
                try FileTrust.writeNewFile(data, to: path)
                completion(.success(()))
            } catch {
                completion(.failure(error))
            }
        }
        task.delegate = RedirectPolicy(follow: followRedirects, source: urlString)
        task.resume()
    }
}
