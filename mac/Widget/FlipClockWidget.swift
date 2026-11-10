import WidgetKit
import SwiftUI
import AppIntents
import CoreText

// MARK: - Font

// "Flip Digits" is Oswald SemiBold with equal-width digits (see fonts/), so a live
// seconds counter can be clipped to exactly two digits.
enum Digits {
    static let registered: Bool = {
        guard let url = Bundle.main.url(forResource: "FlipDigits-SemiBold", withExtension: "ttf") else { return false }
        return CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
    }()

    static func ctFont(_ size: CGFloat) -> CTFont {
        _ = registered
        return CTFontCreateWithName("FlipDigits-SemiBold" as CFString, size, nil)
    }

    static func font(_ size: CGFloat) -> Font { Font(ctFont(size)) }

    static func width(of text: String, size: CGFloat) -> CGFloat {
        let attributed = NSAttributedString(string: text, attributes: [kCTFontAttributeName as NSAttributedString.Key: ctFont(size)])
        return CTLineGetTypographicBounds(CTLineCreateWithAttributedString(attributed), nil, nil, nil)
    }
}

// MARK: - Per-widget options (right-click the widget → Edit "Flip Clock")
// Each one defaults to "Use app setting", i.e. whatever Flip Clock → Widget Settings says,
// so a single widget can override the app without changing the others.

enum LookChoice: String, AppEnum {
    case app, clear, solid
    static var typeDisplayRepresentation = TypeDisplayRepresentation(name: "Look")
    static var caseDisplayRepresentations: [LookChoice: DisplayRepresentation] = [
        .app: "Use app setting (slider)", .clear: "Clear", .solid: "Solid",
    ]
}

enum OnOffChoice: String, AppEnum {
    case app, off, on
    static var typeDisplayRepresentation = TypeDisplayRepresentation(name: "Setting")
    static var caseDisplayRepresentations: [OnOffChoice: DisplayRepresentation] = [
        .app: "Use app setting", .off: "Off", .on: "On",
    ]
}

struct ClockConfig: WidgetConfigurationIntent {
    static var title: LocalizedStringResource = "Flip Clock"
    static var description = IntentDescription("Override the app's Widget Settings for this widget.")

    @Parameter(title: "Look", default: .app)
    var look: LookChoice

    @Parameter(title: "24-hour time", default: .app)
    var twentyFourHour: OnOffChoice

    @Parameter(title: "Seconds", default: .app)
    var seconds: OnOffChoice

    /// The app's settings with this widget's overrides applied.
    func resolved(over base: WidgetSettings) -> WidgetSettings {
        var s = base
        switch look { case .clear: s.solidity = 0; case .solid: s.solidity = 1; case .app: break }
        switch twentyFourHour { case .on: s.twentyFourHour = true; case .off: s.twentyFourHour = false; case .app: break }
        switch seconds { case .on: s.showSeconds = true; case .off: s.showSeconds = false; case .app: break }
        return s
    }
}

// MARK: - Timeline

struct ClockEntry: TimelineEntry {
    let date: Date
    let settings: WidgetSettings
}

struct ClockProvider: AppIntentTimelineProvider {
    func placeholder(in context: Context) -> ClockEntry { ClockEntry(date: .now, settings: WidgetSettings()) }
    func snapshot(for config: ClockConfig, in context: Context) async -> ClockEntry {
        ClockEntry(date: .now, settings: config.resolved(over: WidgetSettings.load()))
    }

    // One entry per minute for the next two hours; WidgetKit shows each at the right moment
    // and asks for a fresh timeline when they run out (or when the app changes the settings).
    func timeline(for config: ClockConfig, in context: Context) async -> Timeline<ClockEntry> {
        let settings = config.resolved(over: WidgetSettings.load())
        let cal = Calendar.current
        let start = cal.dateInterval(of: .minute, for: .now)?.start ?? .now
        let entries = (0..<120).compactMap { i -> ClockEntry? in
            guard let d = cal.date(byAdding: .minute, value: i, to: start) else { return nil }
            return ClockEntry(date: d, settings: settings)
        }
        return Timeline(entries: entries, policy: .atEnd)
    }
}

// MARK: - Layout

/// Where each card and colon goes for a given widget size. Cards fill the widget;
/// in the square small widget they stack, everywhere else they sit in a row with colons between.
struct Layout {
    var cards: [CGRect] = []
    var colons: [CGPoint] = []
    var digit: CGFloat = 0

    init(size: CGSize, count: Int, stacked: Bool) {
        let n = CGFloat(count)
        if stacked {
            let gap = max(6, size.width * 0.05)
            let ch = (size.height - gap * (n - 1)) / n
            cards = (0..<count).map { CGRect(x: 0, y: CGFloat($0) * (ch + gap), width: size.width, height: ch) }
            digit = min(ch * 0.86, size.width * 0.88)
        } else {
            // The gap holds a colon, so it scales with the card height.
            let gap = max(10, min(size.height * 0.17, size.width * 0.065))
            let cw = (size.width - gap * (n - 1)) / n
            cards = (0..<count).map { CGRect(x: CGFloat($0) * (cw + gap), y: 0, width: cw, height: size.height) }
            colons = (1..<count).map { CGPoint(x: CGFloat($0) * (cw + gap) - gap / 2, y: size.height / 2) }
            digit = min(size.height * 0.86, cw * 0.88)
        }
    }
}

// MARK: - Colours

/// The look for a given solidity (0 = clear glass, 1 = solid black like the app).
struct Look {
    let solidity: Double
    var t: Double { min(max(solidity, 0), 1) }
    /// Card fill: faint glass at 0, the app's near-black at 1.
    var card: Color { Color(white: 1 - 0.93 * t).opacity(0.12 + 0.88 * t) }
    /// Digits: pure white on glass, the app's light grey on black.
    var ink: Color { Color(white: 1 - 0.275 * t) }
    /// The widget's own background: fully transparent at 0, black at 1.
    var background: Color { t < 0.02 ? .clear : Color.black.opacity(t) }
    /// The gap line across each card, as in the app.
    var seam: Color { Color.black.opacity(0.4 + 0.6 * t) }
}

struct TimeParts {
    let hour: String, minute: String, period: String?
    init(_ date: Date, twentyFourHour: Bool) {
        let cal = Calendar.current
        let h = cal.component(.hour, from: date)
        hour = twentyFourHour ? String(format: "%02d", h) : String(h % 12 == 0 ? 12 : h % 12)
        minute = String(format: "%02d", cal.component(.minute, from: date))
        period = twentyFourHour ? nil : (h < 12 ? "AM" : "PM")
    }
}

// MARK: - Views

/// Everything except the live seconds, drawn as one flat picture. It is shown as an Image that
/// opts out of the Mac's monochrome widget mode, so the chosen colours and transparency survive
/// even when another app is in front.
struct Picture: View {
    let time: TimeParts
    let layout: Layout
    let look: Look
    let size: CGSize
    var seams = true

    var body: some View {
        ZStack(alignment: .topLeading) {
            ForEach(Array(layout.cards.enumerated()), id: \.offset) { i, rect in
                let radius = min(rect.width, rect.height) * 0.085
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .fill(look.card)
                    .frame(width: rect.width, height: rect.height)
                    .position(x: rect.midX, y: rect.midY)
                if i < 2 {
                    Text(i == 0 ? time.hour : time.minute)
                        .font(Digits.font(layout.digit))
                        .foregroundStyle(look.ink)
                        .position(x: rect.midX, y: rect.midY)
                }
                if seams {
                    Rectangle().fill(look.seam)
                        .frame(width: rect.width, height: max(1.5, rect.height * 0.007))
                        .position(x: rect.midX, y: rect.midY)
                }
            }
            if let p = time.period, let rect = layout.cards.first {
                let s = min(rect.width, rect.height)
                Text(p)
                    .font(Digits.font(s * 0.085))
                    .foregroundStyle(look.ink)
                    .position(x: rect.minX + rect.width * 0.06 + s * 0.09, y: rect.minY + rect.height * 0.07 + s * 0.045)
            }
            ForEach(Array(layout.colons.enumerated()), id: \.offset) { _, pt in
                Text(":").font(Digits.font(layout.digit * 0.6)).foregroundStyle(look.ink).position(pt)
            }
        }
        .frame(width: size.width, height: size.height)
    }
}

@MainActor
enum PictureCache {
    static var key = ""
    static var image: CGImage?

    static func render(_ view: Picture, scale: CGFloat, key newKey: String) -> CGImage? {
        if newKey == key, let image { return image }
        let renderer = ImageRenderer(content: view)
        renderer.scale = scale
        renderer.isOpaque = false
        image = renderer.cgImage
        key = newKey
        return image
    }
}

/// Widgets can't redraw every second, but a timer Text ticks live. It counts "0:00, 0:01, …"
/// from the start of the minute; showing only its last two digits leaves just the seconds.
struct SecondsCounter: View {
    let minuteStart: Date
    let rect: CGRect
    let digit: CGFloat
    let color: Color

    var body: some View {
        Text(timerInterval: minuteStart...minuteStart.addingTimeInterval(86_400), countsDown: false, showsHours: false)
            .font(Digits.font(digit))
            .foregroundStyle(color)
            .lineLimit(1)
            .fixedSize(horizontal: true, vertical: false)
            .frame(width: Digits.width(of: "00", size: digit), alignment: .trailing)
            .clipped()
            .position(x: rect.midX, y: rect.midY)
    }
}

struct ClockView: View {
    let entry: ClockEntry
    @Environment(\.widgetFamily) private var family
    @Environment(\.widgetRenderingMode) private var renderingMode
    @Environment(\.displayScale) private var displayScale

    var body: some View {
        GeometryReader { geo in
            let settings = entry.settings
            // While another app is in front, macOS shows widgets as a dimmed two-tone snapshot:
            // live text can't tick there, so the seconds card is left out until the desktop is active again.
            let accented = renderingMode == .accented
            let showSeconds = settings.showSeconds && !accented
            let time = TimeParts(entry.date, twentyFourHour: settings.twentyFourHour)
            let count = showSeconds ? 3 : 2
            let layout = Layout(size: geo.size, count: count, stacked: family == .systemSmall)
            let look = Look(solidity: settings.solidity)
            let picture = Picture(time: time, layout: layout, look: look, size: geo.size, seams: !accented)
            let key = "\(time.hour)|\(time.minute)|\(time.period ?? "")|\(count)|\(Int(geo.size.width))x\(Int(geo.size.height))|\(displayScale)|\(look.t)|\(accented)"
            ZStack(alignment: .topLeading) {
                if let cg = PictureCache.render(picture, scale: displayScale, key: key) {
                    Image(decorative: cg, scale: displayScale)
                        .resizable()
                        .widgetAccentedRenderingMode(.fullColor)
                        .frame(width: geo.size.width, height: geo.size.height)
                } else {
                    picture
                }
                if showSeconds, let rect = layout.cards.last {
                    // Live text can't be part of the picture.
                    SecondsCounter(minuteStart: entry.date, rect: rect, digit: layout.digit, color: look.ink)
                    Rectangle().fill(look.seam)
                        .frame(width: rect.width, height: max(1.5, rect.height * 0.007))
                        .position(x: rect.midX, y: rect.midY)
                }
            }
        }
        .padding(8)
    }
}

// MARK: - Widget

struct FlipClockWidget: Widget {
    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: "FlipClock", intent: ClockConfig.self, provider: ClockProvider()) { entry in
            ClockView(entry: entry)
                .containerBackground(for: .widget) { Look(solidity: entry.settings.solidity).background }
        }
        .configurationDisplayName("Flip Clock")
        .description("A big flip clock. Set its look in Flip Clock → Widget Settings, or override it here.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge, .systemExtraLarge])
        .contentMarginsDisabled()
    }
}

@main
struct FlipClockWidgets: WidgetBundle {
    var body: some Widget { FlipClockWidget() }
}
