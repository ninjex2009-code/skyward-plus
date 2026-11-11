import Foundation

/// What the widgets show, written by the app after every sync.
struct WidgetSnapshot: Codable {
    struct Course: Codable, Hashable {
        var name: String
        var grade: String
        var percent: Double?
        var belowGoal: Bool
    }

    struct Due: Codable, Hashable {
        var title: String
        var course: String
        var due: Date
    }

    var student: String
    var period: String
    var average: Double?
    var gpa: Double?
    var missing: Int
    var courses: [Course]
    var due: [Due]
    var updated: Date

    static let fileName = "widget.json"

    /// The app's data folder. The widget is sandboxed, so it resolves the real
    /// home folder rather than its container.
    static var fileURL: URL {
        let home: String = {
            if let pw = getpwuid(getuid()), let dir = pw.pointee.pw_dir { return String(cString: dir) }
            return NSHomeDirectory()
        }()
        return URL(fileURLWithPath: home)
            .appendingPathComponent("Library/Application Support/SkywardPlus", isDirectory: true)
            .appendingPathComponent(fileName)
    }

    static func load() -> WidgetSnapshot? {
        guard let data = try? Data(contentsOf: fileURL) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(WidgetSnapshot.self, from: data)
    }

    func save() {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(self) else { return }
        try? FileManager.default.createDirectory(at: WidgetSnapshot.fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? data.write(to: WidgetSnapshot.fileURL, options: .atomic)
    }
}
