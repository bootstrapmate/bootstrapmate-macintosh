import Foundation

struct JSONManifest: Codable {
    struct Task: Codable {
        let name: String
        let url: String
        let type: String
    }

    let tasks: [Task]
}
