import Foundation

struct Episode: Codable, Equatable, Identifiable, Sendable {
    let mediaKey: String
    let title: String
    let updateDate: String?

    var id: String {
        mediaKey
    }
}
