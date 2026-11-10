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

// MARK: - Configuration (right-click the widget → Edit Widget)

struct ClockConfig: WidgetConfigurationIntent {
    static var title: LocalizedStringResource = "Flip Clock"
    static var description = IntentDescription("Choose how the time is shown.")

    @Parameter(title: "24-hour time", default: false)
    var twentyFourHour: Bool

    @Parameter(title: "Seconds", default: false)
    var showSeconds: Bool
}

// MARK: - Timeline

struct ClockEntry: TimelineEntry {
    let date: Date
    let config: ClockConfig
}

struct ClockProvider: AppIntentTimelineProvider {
    func placeholder(in context: Context) -> ClockEntry { ClockEntry(date: .now, config: ClockConfig()) }
    func snapshot(for config: ClockConfig, in context: Context) async -> ClockEntry { ClockEntry(date: .now, config: config) }

    // One entry per minute for the next two hours; WidgetKit shows each at the right moment
    // and asks for a fresh timeline when they run out.
    func timeline(for config: ClockConfig, in context: Context) async -> Timeline<ClockEntry> {
        let cal = Calendar.current
        let start = cal.dateInterval(of: .minute, for: .now)?.start ?? .now
        let entries = (0..<120).compactMap { i -> ClockEntry? in
            guard let d = cal.date(byAdding: .minute, value: i, to: start) else { return nil }
            return ClockEntry(date: d, config: config)
        }
        return Timeline(entries: entries, policy: .atEnd)
    }
}

// MARK: - Views

let inkColor = Color(white: 0.725)

struct Card<Content: View>: View {
    let width: CGFloat
    let height: CGFloat
    var period: String? = nil
    @ViewBuilder let content: () -> Content

    private var radius: CGFloat { min(width, height) * 0.085 }

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: radius, style: .continuous)
                .fill(Color(white: 0.07))
            content()
            Rectangle()
                .fill(.black)
                .frame(height: max(1.5, height * 0.007))
            if let period {
                Text(period)
                    .font(Digits.font(min(width, height) * 0.085))
                    .foregroundStyle(inkColor)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    .padding(.leading, width * 0.06)
                    .padding(.top, height * 0.07)
            }
        }
        .frame(width: width, height: height)
        .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
    }
}

/// Digit size for a card: limited by height, or by width when the card is narrow (two digits ≈ 0.95em).
func digitSize(width: CGFloat, height: CGFloat) -> CGFloat { min(height * 0.86, width * 0.88) }

struct DigitCard: View {
    let text: String
    let width: CGFloat
    let height: CGFloat
    var period: String? = nil

    var body: some View {
        Card(width: width, height: height, period: period) {
            Text(text)
                .font(Digits.font(digitSize(width: width, height: height)))
                .foregroundStyle(inkColor)
                .lineLimit(1)
                .id(text)
                .transition(.push(from: .top))
        }
    }
}

/// Widgets can't redraw every second, but a timer Text ticks live. It counts "0:00, 0:01, …"
/// from the start of the minute; clipping it to exactly two digits leaves just the seconds.
struct SecondsCard: View {
    let minuteStart: Date
    let width: CGFloat
    let height: CGFloat

    var body: some View {
        let size = digitSize(width: width, height: height)
        Card(width: width, height: height) {
            Text(timerInterval: minuteStart...minuteStart.addingTimeInterval(86_400), countsDown: false, showsHours: false)
                .font(Digits.font(size))
                .foregroundStyle(inkColor)
                .lineLimit(1)
                .multilineTextAlignment(.trailing)
                .frame(width: Digits.width(of: "00", size: size), alignment: .trailing)
                .clipped()
        }
    }
}

struct ClockView: View {
    let entry: ClockEntry
    @Environment(\.widgetFamily) private var family

    private var hour: String {
        let h = Calendar.current.component(.hour, from: entry.date)
        return entry.config.twentyFourHour ? String(format: "%02d", h) : String(h % 12 == 0 ? 12 : h % 12)
    }
    private var minute: String { String(format: "%02d", Calendar.current.component(.minute, from: entry.date)) }
    private var period: String? {
        entry.config.twentyFourHour ? nil : (Calendar.current.component(.hour, from: entry.date) < 12 ? "AM" : "PM")
    }

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width, h = geo.size.height
            let count: CGFloat = entry.config.showSeconds ? 3 : 2
            // The small widget is square, so stack the cards; every other size puts them side by side.
            // The cards fill the whole widget, whatever its shape.
            let stacked = family == .systemSmall
            let gap = max(6, min(w, h) * 0.05)
            if stacked {
                let ch = (h - gap * (count - 1)) / count
                VStack(spacing: gap) {
                    DigitCard(text: hour, width: w, height: ch, period: period)
                    DigitCard(text: minute, width: w, height: ch)
                    if entry.config.showSeconds { SecondsCard(minuteStart: entry.date, width: w, height: ch) }
                }
            } else {
                let cw = (w - gap * (count - 1)) / count
                HStack(spacing: gap) {
                    DigitCard(text: hour, width: cw, height: h, period: period)
                    DigitCard(text: minute, width: cw, height: h)
                    if entry.config.showSeconds { SecondsCard(minuteStart: entry.date, width: cw, height: h) }
                }
            }
        }
        .padding(8)
        .animation(.easeInOut(duration: 0.5), value: entry.date)
    }
}

// MARK: - Widget

struct FlipClockWidget: Widget {
    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: "FlipClock", intent: ClockConfig.self, provider: ClockProvider()) { entry in
            ClockView(entry: entry)
                .containerBackground(.black, for: .widget)
        }
        .configurationDisplayName("Flip Clock")
        .description("A big black-and-white flip clock. Options: 24-hour time, seconds.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge, .systemExtraLarge])
        .contentMarginsDisabled()
    }
}

@main
struct FlipClockWidgets: WidgetBundle {
    var body: some Widget { FlipClockWidget() }
}
