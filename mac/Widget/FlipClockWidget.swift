import WidgetKit
import SwiftUI
import AppIntents
import CoreText

// MARK: - Font

enum Oswald {
    static let registered: Bool = {
        guard let url = Bundle.main.url(forResource: "Oswald-Variable", withExtension: "ttf") else { return false }
        return CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
    }()

    /// Oswald at weight 600, matching the web clock.
    static func font(_ size: CGFloat) -> Font {
        _ = registered
        let base = CTFontCreateWithName("Oswald" as CFString, size, nil)
        let wght: CFNumber = 0x77676874 as CFNumber // 'wght' axis tag
        let desc = CTFontDescriptorCreateWithAttributes([kCTFontVariationAttribute: [wght: 600]] as CFDictionary)
        return Font(CTFontCreateCopyWithAttributes(base, size, nil, desc))
    }
}

// MARK: - Configuration (right-click the widget → Edit Widget)

struct ClockConfig: WidgetConfigurationIntent {
    static var title: LocalizedStringResource = "Flip Clock"
    static var description = IntentDescription("Choose how the time is shown.")

    @Parameter(title: "24-hour time", default: false)
    var twentyFourHour: Bool
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

struct Card: View {
    let text: String
    let size: CGFloat
    var period: String? = nil

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.085, style: .continuous)
                .fill(Color(white: 0.07))
            Text(text)
                .font(Oswald.font(size * 0.86))
                .foregroundStyle(Color(white: 0.725))
                .lineLimit(1)
                .minimumScaleFactor(0.5)
                .id(text)
                .transition(.push(from: .top))
            Rectangle()
                .fill(.black)
                .frame(height: max(1.5, size * 0.007))
            if let period {
                Text(period)
                    .font(Oswald.font(size * 0.085))
                    .foregroundStyle(Color(white: 0.725))
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    .padding(.leading, size * 0.07)
                    .padding(.top, size * 0.08)
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: size * 0.085, style: .continuous))
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
            let stacked = family == .systemSmall
            let gapRatio: CGFloat = stacked ? 0.05 : 0.08
            let w = geo.size.width, h = geo.size.height
            // Two square cards that fill the widget: side by side, or stacked in the small size.
            let size = stacked
                ? min(w, h / (2 + gapRatio))
                : min(h, w / (2 + gapRatio))
            let gap = size * gapRatio
            Group {
                if stacked {
                    VStack(spacing: gap) { Card(text: hour, size: size, period: period); Card(text: minute, size: size) }
                } else {
                    HStack(spacing: gap) { Card(text: hour, size: size, period: period); Card(text: minute, size: size) }
                }
            }
            .frame(width: w, height: h)
        }
        .padding(family == .systemSmall ? 10 : 14)
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
        .description("A big black-and-white flip clock.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
        .contentMarginsDisabled()
    }
}

@main
struct FlipClockWidgets: WidgetBundle {
    var body: some Widget { FlipClockWidget() }
}
