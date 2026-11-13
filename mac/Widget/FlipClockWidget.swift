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

enum AnimationChoice: String, AppEnum {
    case app, roll, book
    static var typeDisplayRepresentation = TypeDisplayRepresentation(name: "Animation")
    static var caseDisplayRepresentations: [AnimationChoice: DisplayRepresentation] = [
        .app: "Use app setting", .roll: "Roll", .book: "Book",
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

    @Parameter(title: "Animation", default: .app)
    var animation: AnimationChoice

    /// The app's settings with this widget's overrides applied.
    func resolved(over base: WidgetSettings) -> WidgetSettings {
        var s = base
        switch look { case .clear: s.solidity = 0; case .solid: s.solidity = 1; case .app: break }
        switch twentyFourHour { case .on: s.twentyFourHour = true; case .off: s.twentyFourHour = false; case .app: break }
        switch seconds { case .on: s.showSeconds = true; case .off: s.showSeconds = false; case .app: break }
        switch animation { case .roll: s.animationStyle = .roll; case .book: s.animationStyle = .book; case .app: break }
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

    // One entry per minute for the next two hours, or one per second for the next 5 minutes
    // when the seconds are shown (so each second can animate like the other digits). macOS refuses
    // a timeline whose archive is too big (15 minutes of Book-mode seconds was ~11 MB and left the
    // widget blank), so the per-second timeline is kept short. WidgetKit shows
    // each entry at its moment and asks for a fresh timeline when they run out (or when the app
    // changes the settings).
    func timeline(for config: ClockConfig, in context: Context) async -> Timeline<ClockEntry> {
        let settings = config.resolved(over: WidgetSettings.load())
        let cal = Calendar.current
        let perSecond = settings.showSeconds
        // Book flips need macOS to show every entry (each one flips the card the other way), and
        // macOS only redraws about every 2 seconds, so Book's seconds step by two.
        let step = perSecond && settings.animationStyle == .book ? 2 : 1
        let unit: Calendar.Component = perSecond ? .second : .minute
        var start = cal.dateInterval(of: unit, for: .now)?.start ?? .now
        if step == 2 { start = Date(timeIntervalSince1970: (start.timeIntervalSince1970 / 2).rounded(.down) * 2) }
        let entries = (0..<(perSecond ? 300 / step : 120)).compactMap { i -> ClockEntry? in
            guard let d = cal.date(byAdding: unit, value: i * step, to: start) else { return nil }
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
    let hour: String, minute: String, second: String, period: String?
    init(hour: String, minute: String, second: String, period: String?) {
        self.hour = hour; self.minute = minute; self.second = second; self.period = period
    }
    /// `padHour` gives one-digit 12-hour times a leading zero (08), as Book mode does in the app.
    init(_ date: Date, twentyFourHour: Bool, padHour: Bool = false) {
        let cal = Calendar.current
        let h = cal.component(.hour, from: date)
        let h12 = h % 12 == 0 ? 12 : h % 12
        hour = twentyFourHour || padHour ? String(format: "%02d", twentyFourHour ? h : h12) : String(h12)
        minute = String(format: "%02d", cal.component(.minute, from: date))
        second = String(format: "%02d", cal.component(.second, from: date))
        period = twentyFourHour ? nil : (h < 12 ? "AM" : "PM")
    }
}

extension TimeParts {
    /// Each card's value `steps` steps away from `date` (an hour, a minute, or `secondStep` seconds per step).
    static func stepped(_ date: Date, by steps: Double, secondStep: Double, twentyFourHour: Bool, padHour: Bool) -> TimeParts {
        let h = TimeParts(date.addingTimeInterval(3600 * steps), twentyFourHour: twentyFourHour, padHour: padHour)
        let m = TimeParts(date.addingTimeInterval(60 * steps), twentyFourHour: twentyFourHour, padHour: padHour)
        let s = TimeParts(date.addingTimeInterval(secondStep * steps), twentyFourHour: twentyFourHour, padHour: padHour)
        return TimeParts(hour: h.hour, minute: m.minute, second: s.second, period: nil)
    }
}

// MARK: - Views

/// One card's number. Widgets only animate SwiftUI's built-in transitions (a true 3D flap or page
/// turn is ignored), so each animation uses the closest built-in one:
/// - Roll: the digits roll and blur into the new number.
/// - Book: each changing digit fades out with a short nudge to the left while the new one nudges in
///   from the right, like a page turning over the spine down the middle of the card. (A full slide
///   looked wrong: widgets don't clip during transitions, so the old digit slid over its neighbour.)
struct CardNumber: View {
    let text: String
    let rect: CGRect
    let digit: CGFloat
    let ink: Color
    let animation: WidgetSettings.Animation

    var body: some View {
        switch animation {
        case .roll:
            Text(text)
                .font(Digits.font(digit))
                .foregroundStyle(ink)
                .widgetAccentable()
                .contentTransition(.numericText())
                .frame(width: rect.width, height: rect.height)
                .clipped()
                .position(x: rect.midX, y: rect.midY)
        case .book:
            let cell = Digits.width(of: "0", size: digit)
            HStack(spacing: 0) {
                ForEach(Array(text.enumerated()), id: \.offset) { _, ch in
                    Text(String(ch))
                        .font(Digits.font(digit))
                        .foregroundStyle(ink)
                        .widgetAccentable()
                        .id(String(ch))
                        .transition(.asymmetric(
                            insertion: .offset(x: cell * 0.12).combined(with: .opacity),
                            removal: .offset(x: -cell * 0.12).combined(with: .opacity)))
                        .frame(width: cell, height: rect.height)
                        .clipped()
                }
            }
            .position(x: rect.midX, y: rect.midY)
        }
    }
}

/// Book: the card flips around its vertical middle. A widget can't run a real 3D turn, but it does
/// animate a view's width between timeline entries, as long as the view's text stays the same.
/// So each card has three faces that take turns (by `index`, which counts the card's changes):
/// - the current face is full width, showing the current value;
/// - the next face is squashed to nothing and already shows the next value;
/// - the last face is squashed to nothing and still shows the previous value.
/// When the value changes, the last-current face narrows to the spine and then the next face widens
/// out from it, which reads as the card turning over. Neither face's text changes while it moves
/// (if it did, macOS would blur-fade it instead).
struct BookCard: View {
    let previous: String
    let current: String
    let next: String
    let index: Int
    let rect: CGRect
    let digit: CGFloat
    let look: Look
    var seams = true

    static let half = 0.28

    func face(_ text: String, open: Bool) -> some View {
        let radius = min(rect.width, rect.height) * 0.085
        let line = max(1.5, min(rect.width, rect.height) * 0.007)
        return ZStack {
            RoundedRectangle(cornerRadius: radius, style: .continuous).fill(look.card)
            Text(text)
                .font(Digits.font(digit))
                .foregroundStyle(look.ink)
                .widgetAccentable()
            if seams { Rectangle().fill(look.seam).frame(width: line) }
        }
        .frame(width: rect.width, height: rect.height)
        .scaleEffect(x: open ? 1 : 0.001, y: 1, anchor: .center)
        .animation(open ? .easeOut(duration: Self.half).delay(Self.half) : .easeIn(duration: Self.half), value: open)
    }

    var body: some View {
        ZStack {
            ForEach(0..<3, id: \.self) { j in
                let role = ((j - index) % 3 + 3) % 3   // 0 current, 1 next, 2 previous
                face(role == 0 ? current : role == 1 ? next : previous, open: role == 0)
            }
        }
        .position(x: rect.midX, y: rect.midY)
    }
}

/// The whole clock, drawn with plain SwiftUI shapes and text.
/// (It used to be flattened into one bitmap, but macOS showed that bitmap as a blank grey slab.)
/// In the Mac's monochrome mode the digits and colons are the accented part, so they stay bright.
struct Picture: View {
    let time: TimeParts
    /// Book only: the values one step earlier and later, and how many steps each card has changed (see BookCard).
    var previous: TimeParts? = nil
    var next: TimeParts? = nil
    var indices: [Int] = []
    let layout: Layout
    let look: Look
    let size: CGSize
    let animation: WidgetSettings.Animation
    var seams = true

    var body: some View {
        let values = [time.hour, time.minute, time.second]
        ZStack(alignment: .topLeading) {
            ForEach(Array(layout.cards.enumerated()), id: \.offset) { i, rect in
              if animation == .book, let previous, let next {
                let before = [previous.hour, previous.minute, previous.second]
                let after = [next.hour, next.minute, next.second]
                BookCard(previous: before[i], current: values[i], next: after[i], index: indices[i], rect: rect,
                         digit: layout.digit, look: look, seams: seams)
              } else {
                let radius = min(rect.width, rect.height) * 0.085
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .fill(look.card)
                    .frame(width: rect.width, height: rect.height)
                    .position(x: rect.midX, y: rect.midY)
                CardNumber(text: values[i], rect: rect, digit: layout.digit, ink: look.ink, animation: animation)
                if seams {
                    // Flip/Roll cards split across the middle; Book cards split down the spine.
                    let line = max(1.5, min(rect.width, rect.height) * 0.007)
                    Rectangle().fill(look.seam)
                        .frame(width: animation == .book ? line : rect.width,
                               height: animation == .book ? rect.height : line)
                        .position(x: rect.midX, y: rect.midY)
                }
              }
            }
            if let p = time.period, let rect = layout.cards.first {
                let s = min(rect.width, rect.height)
                Text(p)
                    .font(Digits.font(s * 0.075))
                    .foregroundStyle(look.ink)
                    .widgetAccentable()
                    .position(x: rect.minX + rect.width * 0.055 + s * 0.08, y: rect.minY + rect.height * 0.045 + s * 0.04)
            }
            ForEach(Array(layout.colons.enumerated()), id: \.offset) { _, pt in
                Text(":").font(Digits.font(layout.digit * 0.6)).foregroundStyle(look.ink).widgetAccentable().position(pt)
            }
        }
        .frame(width: size.width, height: size.height)
    }
}

struct ClockView: View {
    let entry: ClockEntry
    @Environment(\.widgetFamily) private var family
    @Environment(\.widgetRenderingMode) private var renderingMode

    var body: some View {
        GeometryReader { geo in
            let settings = entry.settings
            // Monochrome (accented) mode: either Widget style is set to Monochrome, or another app is in front.
            // The seconds still show there; they may pause while macOS dims the desktop.
            let accented = renderingMode == .accented
            let showSeconds = settings.showSeconds
            let time = TimeParts(entry.date, twentyFourHour: settings.twentyFourHour, padHour: settings.animationStyle == .book)
            let count = showSeconds ? 3 : 2
            let layout = Layout(size: geo.size, count: count, stacked: family == .systemSmall)
            let look = Look(solidity: settings.solidity)
            let book = settings.animationStyle == .book
            // Book: the value each card showed one step earlier, and a per-card step counter.
            let secondStep: Double = 2
            let local = entry.date.timeIntervalSince1970 + Double(TimeZone.current.secondsFromGMT(for: entry.date))
            let previous = TimeParts.stepped(entry.date, by: -1, secondStep: secondStep, twentyFourHour: settings.twentyFourHour, padHour: book)
            let next = TimeParts.stepped(entry.date, by: 1, secondStep: secondStep, twentyFourHour: settings.twentyFourHour, padHour: book)
            let indices = [Int((local / 3600).rounded(.down)), Int((local / 60).rounded(.down)), Int((local / secondStep).rounded(.down))]
            Picture(time: time, previous: book ? previous : nil, next: book ? next : nil, indices: indices, layout: layout, look: look,
                    size: geo.size, animation: settings.animationStyle, seams: !accented)
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
