import Foundation

/// Settings shared between the app (which edits them) and the widget (which only reads them).
/// They live in a small JSON file in the user's Library; the sandboxed widget is allowed to read
/// just that folder (see FlipClockWidget.entitlements).
struct WidgetSettings: Codable, Equatable {
    /// 0 = clear (see-through glass), 1 = solid (black, like the app).
    var solidity: Double = 1
    var twentyFourHour = false
    var showSeconds = false
    var animationStyle: Animation = .roll

    enum CodingKeys: String, CodingKey { case solidity, twentyFourHour, showSeconds, animationStyle = "animation" }

    enum Animation: String, Codable { case roll, book }

    init() {}

    /// Settings files written before a field existed simply lack it; keep the default for it.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        solidity = try c.decodeIfPresent(Double.self, forKey: .solidity) ?? 1
        twentyFourHour = try c.decodeIfPresent(Bool.self, forKey: .twentyFourHour) ?? false
        showSeconds = try c.decodeIfPresent(Bool.self, forKey: .showSeconds) ?? false
        animationStyle = (try? c.decodeIfPresent(Animation.self, forKey: .animationStyle)) ?? .roll
    }

    static let folder = "Library/Application Support/FlipClock"
    static let fileName = "widget-settings.json"

    /// The real home folder, even inside the widget's sandbox (where NSHomeDirectory() points at the container).
    static var realHome: URL {
        if let dir = getpwuid(getuid())?.pointee.pw_dir { return URL(fileURLWithPath: String(cString: dir)) }
        return FileManager.default.homeDirectoryForCurrentUser
    }
    static var fileURL: URL { realHome.appendingPathComponent(folder).appendingPathComponent(fileName) }

    static func load() -> WidgetSettings {
        guard let data = try? Data(contentsOf: fileURL),
              let s = try? JSONDecoder().decode(WidgetSettings.self, from: data) else { return WidgetSettings() }
        return s
    }

    func save() throws {
        let dir = Self.fileURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try JSONEncoder().encode(self).write(to: Self.fileURL, options: .atomic)
    }
}
