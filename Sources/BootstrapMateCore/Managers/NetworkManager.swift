import Foundation

enum DownloadError: Error {
    case invalidURL
    case requestFailed(String)
}

public final class NetworkManager {
    nonisolated(unsafe) public static let shared = NetworkManager()

    public var authorizationHeader: String?

    private init() {}

    public func downloadData(
        from url: URL,
        followRedirects: Bool,
        authHeader: String?,
        completion: @escaping @Sendable (Data?, Error?) -> Void
    ) {
        var request = URLRequest(url: url)
        if let header = authHeader {
            request.addValue(header, forHTTPHeaderField: "Authorization")
        }
        let session = URLSession(configuration: .default)
        session.dataTask(with: request) { data, _, error in
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
        var request = URLRequest(url: url)
        if let header = authHeader ?? authorizationHeader {
            request.addValue(header, forHTTPHeaderField: "Authorization")
        }

        let session = URLSession(configuration: .default)
        
        // Use dataTask instead of downloadTask to avoid system temp directory
        // which is read-only during Setup Assistant
        let task = session.dataTask(with: request) { data, _, error in
            if let error = error {
                completion(.failure(error))
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
                
                // Write directly to destination (no atomic - avoids temp file on read-only filesystem)
                try data.write(to: URL(fileURLWithPath: path))
                completion(.success(()))
            } catch {
                completion(.failure(error))
            }
        }
        task.resume()
    }
}
