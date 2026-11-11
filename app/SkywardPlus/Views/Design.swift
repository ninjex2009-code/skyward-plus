import SwiftUI
import UniformTypeIdentifiers

#if os(macOS)
import AppKit
typealias PlatformImage = NSImage
#else
import UIKit
typealias PlatformImage = UIImage
#endif

// Shared design system: dynamic window-scaling metrics, background color themes,
// semantic subject colors, double-bezel cards, animated grade rings/bubbles,
// spring motion primitives, and native avatar picking.

extension Color {
    init(hex: UInt32) {
        self.init(
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255
        )
    }
}

extension ThemeColor {
    var color: Color { Color(hex: hex) }
    var secondaryColor: Color { Color(hex: hex2) }
    var gradient: LinearGradient {
        LinearGradient(colors: [Color(hex: hex), Color(hex: hex2)], startPoint: .topLeading, endPoint: .bottomTrailing)
    }
}

extension BackgroundTheme {
    func pageColor(for scheme: ColorScheme) -> Color {
        if self == .standard {
            #if os(macOS)
            return Color(nsColor: .windowBackgroundColor)
            #else
            return Color(uiColor: .systemGroupedBackground)
            #endif
        }
        return Color(hex: scheme == .dark ? darkPageHex : lightPageHex)
    }

    func cardColor(for scheme: ColorScheme) -> Color {
        if self == .standard {
            #if os(macOS)
            return Color(nsColor: .controlBackgroundColor)
            #else
            return Color(uiColor: .secondarySystemGroupedBackground)
            #endif
        }
        return Color(hex: scheme == .dark ? darkCardHex : lightCardHex)
    }

    func glowColor(accent: ThemeColor) -> Color {
        switch self {
        case .standard: return accent.color.opacity(0.35)
        case .tinted: return accent.color
        default: return Color(hex: glowHex)
        }
    }
}

// MARK: - Dynamic Window Scaling Metrics & Theme Environment

struct WindowMetrics: Equatable {
    var width: CGFloat = 860
    var height: CGFloat = 680

    /// Smooth scale factor (0.90x on compact windows up to 1.20x on wide windows).
    /// Text and controls keep their size at every window width, like the system apps.
    var scale: CGFloat { 1 }

    var isCompact: Bool { width < 580 }
    var isWide: Bool { width >= 960 }
    var twoColumnSplit: Bool { width >= 1040 }

    func scaled(_ base: CGFloat) -> CGFloat {
        (base * scale * 2).rounded() / 2
    }

    var horizontalPadding: CGFloat {
        width < 640 ? 16 : 28
    }

    var sectionSpacing: CGFloat { 24 }

    var cardPadding: CGFloat {
        scaled(16)
    }

    var cardRadius: CGFloat { 12 }

    var gridSpacing: CGFloat {
        scaled(10)
    }

    /// Keeps lines and tables at a readable length on large displays.
    var contentMaxWidth: CGFloat { 1040 }

    func statColumns(count: Int = 4) -> [GridItem] {
        let cols: Int
        if width < 560 {
            cols = min(2, max(1, count))
        } else {
            cols = max(1, count)
        }
        return Array(repeating: GridItem(.flexible(), spacing: gridSpacing), count: cols)
    }

    var courseGridColumns: [GridItem] {
        let cols: Int
        if width < 580 {
            cols = 1
        } else if width < 1080 {
            cols = 2
        } else {
            cols = 3
        }
        return Array(repeating: GridItem(.flexible(), spacing: gridSpacing), count: cols)
    }
}

private struct WindowMetricsKey: EnvironmentKey {
    static let defaultValue = WindowMetrics()
}

private struct BackgroundThemeKey: EnvironmentKey {
    static let defaultValue: BackgroundTheme = .tinted
}

private struct AccentThemeKey: EnvironmentKey {
    static let defaultValue: ThemeColor = .sky
}

extension EnvironmentValues {
    var windowMetrics: WindowMetrics {
        get { self[WindowMetricsKey.self] }
        set { self[WindowMetricsKey.self] = newValue }
    }

    var backgroundTheme: BackgroundTheme {
        get { self[BackgroundThemeKey.self] }
        set { self[BackgroundThemeKey.self] = newValue }
    }

    var accentTheme: ThemeColor {
        get { self[AccentThemeKey.self] }
        set { self[AccentThemeKey.self] = newValue }
    }
}

/// Responsive grid for 3 or 4 StatTiles that wraps cleanly into 2 columns on narrow windows
/// and expands across a single row on regular/wide windows.
struct StatGrid<Content: View>: View {
    @Environment(\.windowMetrics) private var metrics
    var count: Int = 4
    @ViewBuilder var content: Content

    var body: some View {
        LazyVGrid(columns: metrics.statColumns(count: count), spacing: metrics.gridSpacing) {
            content
        }
    }
}

/// The page surface: the background theme's colour, nothing else.
struct PageBackground: View {
    @Environment(\.backgroundTheme) private var bgTheme
    @Environment(\.colorScheme) private var scheme

    @Environment(\.windowTranslucent) private var translucent

    var body: some View {
        // Translucent: the theme colour is laid over the blurred desktop, thick
        // enough that text keeps its contrast and thin enough to feel like glass.
        bgTheme.pageColor(for: scheme)
            .opacity(translucent ? (scheme == .dark ? 0.80 : 0.86) : 1)
            .ignoresSafeArea()
            .animation(.easeInOut(duration: 0.25), value: bgTheme)
    }
}

/// Interactive visual picker for BackgroundTheme used in Settings and First-Time Setup.
struct BackgroundThemePicker: View {
    @Environment(AppModel.self) private var model
    @Environment(\.colorScheme) private var scheme
    @Environment(\.windowMetrics) private var metrics

    var body: some View {
        let current = model.settings.backgroundTheme
        let accent = model.theme
        let cols = [GridItem(.adaptive(minimum: metrics.scaled(124), maximum: 190), spacing: 10)]

        LazyVGrid(columns: cols, spacing: 10) {
            ForEach(BackgroundTheme.allCases) { item in
                let isSelected = item == current
                let pageCol = item.pageColor(for: scheme)
                let cardCol = item.cardColor(for: scheme)
                let glowCol = item.glowColor(accent: accent)

                Button {
                    withAnimation(Motion.snappy) {
                        model.updateSettings { $0.backgroundTheme = item }
                    }
                } label: {
                    VStack(alignment: .leading, spacing: 8) {
                        ZStack(alignment: .bottomLeading) {
                            RoundedRectangle(cornerRadius: 9, style: .continuous)
                                .fill(pageCol)
                                .overlay(
                                    RadialGradient(
                                        colors: [glowCol.opacity(item == .standard ? 0.0 : 0.28), .clear],
                                        center: .topLeading,
                                        startRadius: 4,
                                        endRadius: 70
                                    )
                                    .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
                                )
                                .frame(height: metrics.scaled(42))

                            HStack(spacing: 6) {
                                RoundedRectangle(cornerRadius: 5, style: .continuous)
                                    .fill(cardCol)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 5, style: .continuous)
                                            .strokeBorder(glowCol.opacity(0.35), lineWidth: 0.8)
                                    )
                                    .frame(width: 48, height: 22)
                                Spacer()
                                Circle()
                                    .fill(glowCol)
                                    .frame(width: 12, height: 12)
                            }
                            .padding(8)
                        }
                        .overlay(
                            RoundedRectangle(cornerRadius: 9, style: .continuous)
                                .strokeBorder(Palette.hairline, lineWidth: 1)
                        )

                        HStack(spacing: 4) {
                            VStack(alignment: .leading, spacing: 1) {
                                Text(item.title)
                                    .font(.caption.weight(.bold))
                                    .foregroundStyle(isSelected ? accent.color : .primary)
                                    .lineLimit(1)
                                Text(item.subtitle)
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }
                            Spacer(minLength: 2)
                            if isSelected {
                                Image(systemName: "checkmark.circle.fill")
                                    .font(.caption.weight(.bold))
                                    .foregroundStyle(accent.color)
                            }
                        }
                    }
                    .padding(9)
                    .background(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(isSelected ? accent.color.opacity(0.10) : Palette.inset)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .strokeBorder(isSelected ? accent.color : Palette.hairline, lineWidth: isSelected ? 1.5 : 1)
                    )
                }
                .buttonStyle(ScaleButtonStyle())
            }
        }
    }
}

enum Palette {
    static var page: Color {
        #if os(macOS)
        Color(nsColor: .windowBackgroundColor)
        #else
        Color(uiColor: .systemGroupedBackground)
        #endif
    }

    static var card: Color {
        #if os(macOS)
        Color(nsColor: .controlBackgroundColor)
        #else
        Color(uiColor: .secondarySystemGroupedBackground)
        #endif
    }

    static var elevatedCard: Color {
        #if os(macOS)
        Color(nsColor: .underPageBackgroundColor)
        #else
        Color(uiColor: .tertiarySystemGroupedBackground)
        #endif
    }

    static var inset: Color { Color.primary.opacity(0.055) }
    static var hairline: Color { Color.primary.opacity(0.09) }
    static var innerHighlight: Color { Color.white.opacity(0.07) }

    static let good = Color(hex: 0x10B981)
    static let fine = Color(hex: 0x3B82F6)
    static let warn = Color(hex: 0xF59E0B)
    static let low = Color(hex: 0xF97316)
    static let bad = Color(hex: 0xEF4444)
}

// MARK: - Motion Tokens

enum Motion {
    static let snappy = Animation.spring(response: 0.26, dampingFraction: 0.8)
    static let smooth = Animation.spring(response: 0.38, dampingFraction: 0.84)
    static let gentle = Animation.spring(response: 0.52, dampingFraction: 0.86)
}

struct ScaleButtonStyle: ButtonStyle {
    var scale: CGFloat = 0.975

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? scale : 1.0)
            .animation(Motion.snappy, value: configuration.isPressed)
    }
}

struct StaggeredAppear: ViewModifier {
    let index: Int
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var appeared = false

    func body(content: Content) -> some View {
        content
            .opacity((!reduceMotion && !appeared) ? 0 : 1)
            .offset(y: (!reduceMotion && !appeared) ? 6 : 0)
            .onAppear {
                guard !reduceMotion, !appeared else {
                    appeared = true
                    return
                }
                let delay = min(Double(index) * 0.03, 0.18)
                withAnimation(Motion.smooth.delay(delay)) {
                    appeared = true
                }
            }
    }
}

extension View {
    func staggered(_ index: Int) -> some View {
        modifier(StaggeredAppear(index: index))
    }
}

// MARK: - Subject Color & Icon Engine

struct SubjectStyle {
    var color: Color
    var symbol: String
    var label: String

    static func forCourse(_ name: String, fallback: Color = Color(hex: 0x2F80ED)) -> SubjectStyle {
        let u = name.uppercased()
        if u.contains("ENGLISH") || u.contains("LIT") || u.contains("HUMANITIES") || u.contains("READING") || u.contains("WRITING") || u.contains("DEBATE") || u.contains("JOURNAL") {
            return SubjectStyle(color: Color(hex: 0xE11D48), symbol: "book.closed.fill", label: "Humanities")
        }
        if u.contains("CALC") || u.contains("STAT") || u.contains("MATH") || u.contains("ALG") || u.contains("GEOM") {
            return SubjectStyle(color: Color(hex: 0x2563EB), symbol: "function", label: "Mathematics")
        }
        if u.contains("PHYS") || u.contains("CHEM") || u.contains("BIO") || u.contains("ASTRON") || u.contains("ANAT") || u.contains("ENV") {
            return SubjectStyle(color: Color(hex: 0x0D9488), symbol: "atom", label: "Science")
        }
        if u.contains("ENGIN") || u.contains("COMP") || u.contains("ROBOT") || u.contains("TECH") || u.contains("CYBER") || u.contains("CODE") {
            return SubjectStyle(color: Color(hex: 0x6366F1), symbol: "cpu.fill", label: "Engineering & CS")
        }
        if u.contains("BAND") || u.contains("ORCH") || u.contains("CHOIR") || u.contains("MUSIC") || u.contains("THEAT") || u.contains("ART") || u.contains("DANCE") {
            return SubjectStyle(color: Color(hex: 0xD97706), symbol: "music.quarternote.3", label: "Fine Arts")
        }
        if u.contains("HIST") || u.contains("GOV") || u.contains("ECON") || u.contains("GEOG") || u.contains("PSYCH") || u.contains("SOC") || u.contains("WORLD") {
            return SubjectStyle(color: Color(hex: 0x059669), symbol: "globe.americas.fill", label: "Social Studies")
        }
        if u.contains("SPAN") || u.contains("FREN") || u.contains("GERM") || u.contains("LATIN") || u.contains("CHIN") || u.contains("ASL") {
            return SubjectStyle(color: Color(hex: 0x9333EA), symbol: "bubble.left.and.exclamationmark.bubble.right.fill", label: "World Languages")
        }
        return SubjectStyle(color: fallback, symbol: "graduationcap.fill", label: "Course")
    }

    static func forCategory(_ categoryName: String, index: Int = 0) -> Color {
        let u = categoryName.uppercased()
        if u.contains("SUMMATIVE") || u.contains("MAJOR") || u.contains("TEST") || u.contains("EXAM") || u.contains("ASSESS") {
            return Color(hex: 0x6366F1)
        }
        if u.contains("FORMATIVE") || u.contains("MINOR") || u.contains("QUIZ") || u.contains("DAILY") || u.contains("HW") {
            return Color(hex: 0x0EA5E9)
        }
        let palette: [Color] = [Color(hex: 0x6366F1), Color(hex: 0x0EA5E9), Color(hex: 0x10B981), Color(hex: 0xF59E0B)]
        return palette[abs(index) % palette.count]
    }
}

enum GradeColor {
    /// Green for A work down to red for failing. Letters are mapped by their first character.
    static func color(percent: Double?, text: String = "") -> Color {
        if let percent {
            switch percent {
            case 89.5...: return Palette.good
            case 79.5..<89.5: return Palette.fine
            case 69.5..<79.5: return Palette.warn
            case 59.5..<69.5: return Palette.low
            default: return Palette.bad
            }
        }
        switch text.uppercased().first {
        case "A", "E", "S", "P": return Palette.good
        case "B": return Palette.fine
        case "C": return Palette.warn
        case "D", "N": return Palette.low
        case "F", "U": return Palette.bad
        default: return .secondary
        }
    }

    static func letter(for percent: Double?) -> String {
        guard let percent else { return "" }
        switch percent {
        case 89.5...: return "A"
        case 79.5..<89.5: return "B"
        case 69.5..<79.5: return "C"
        case 59.5..<69.5: return "D"
        default: return "F"
        }
    }

    static func attendance(_ kind: AttendanceKind) -> Color {
        switch kind {
        case .tardy: return Palette.warn
        case .excused: return Palette.fine
        case .unexcused: return Palette.bad
        case .other: return .secondary
        }
    }
}

/// Animated circular progress ring for course or term averages. Scales dynamically with window size.
struct GradeRing: View {
    @Environment(AppModel.self) private var model
    @Environment(\.windowMetrics) private var metrics
    var percent: Double?
    var text: String = ""
    var size: CGFloat = 68
    var lineWidth: CGFloat = 6.5
    var subtitle: String? = nil

    private var tint: Color {
        if percent == nil && text.isEmpty { return .secondary }
        return model.settings.colorBubbles ? GradeColor.color(percent: percent, text: text) : model.theme.color
    }

    private var trimValue: CGFloat {
        guard let percent, percent.isFinite else { return 0 }
        return CGFloat(max(0.04, min(1.0, percent / 100.0)))
    }

    var body: some View {
        let actualSize = metrics.scaled(size)
        let actualStroke = metrics.scaled(lineWidth)
        let display = !text.isEmpty ? text : (percent.map { Fmt.percent($0) } ?? "—")
        ZStack {
            Circle()
                .stroke(tint.opacity(0.14), lineWidth: actualStroke)
            Circle()
                .trim(from: 0, to: trimValue)
                .stroke(tint, style: StrokeStyle(lineWidth: actualStroke, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation(Motion.gentle, value: trimValue)

            VStack(spacing: 0) {
                Text(display.isEmpty ? "—" : display)
                    .font(.system(size: actualSize * 0.29, weight: .bold, design: .rounded).monospacedDigit())
                    .foregroundStyle(percent == nil && text.isEmpty ? .secondary : .primary)
                    .contentTransition(.numericText())
                    .lineLimit(1)
                    .minimumScaleFactor(0.65)
                if let subtitle, !subtitle.isEmpty {
                    Text(subtitle)
                        .font(.system(size: max(9, actualSize * 0.14), weight: .semibold))
                        .foregroundStyle(tint)
                } else if let p = percent {
                    Text(GradeColor.letter(for: p))
                        .font(.system(size: max(9, actualSize * 0.14), weight: .bold, design: .rounded))
                        .foregroundStyle(tint)
                }
            }
            .padding(actualStroke + 2)
        }
        .frame(width: actualSize, height: actualSize)
        .accessibilityLabel(display.isEmpty ? "No grade" : "Grade \(display)")
    }
}

/// The coloured grade chip used in lists. Scales proportionally with window size.
struct GradeBubble: View {
    enum Size { case small, regular, large }

    @Environment(AppModel.self) private var model
    @Environment(\.windowMetrics) private var metrics
    let text: String
    var percent: Double?
    var size: Size = .regular

    private var tint: Color {
        if text.isEmpty { return .secondary }
        return model.settings.colorBubbles ? GradeColor.color(percent: percent, text: text) : model.theme.color
    }

    var body: some View {
        let baseWidth: CGFloat = size == .small ? 46 : size == .regular ? 60 : 88
        let baseHeight: CGFloat = size == .small ? 28 : size == .regular ? 36 : 54
        let baseFontSize: CGFloat = size == .small ? 13 : size == .regular ? 16 : 22
        let width = metrics.scaled(baseWidth)
        let height = metrics.scaled(baseHeight)
        let radius = metrics.scaled(size == .large ? 14 : 10)

        if model.settings.gradeStyle == .number {
            Text(text.isEmpty ? "—" : text)
                .font(.system(size: metrics.scaled(baseFontSize + (size == .large ? 6 : 2)), weight: .semibold, design: .rounded).monospacedDigit())
                .foregroundStyle(text.isEmpty ? Color.secondary : tint)
                .contentTransition(.numericText())
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .frame(minWidth: width, alignment: .trailing)
                .frame(height: height)
                .animation(Motion.snappy, value: text)
                .accessibilityLabel(text.isEmpty ? "No grade" : "Grade \(text)")
        } else {
            bubble(width: width, height: height, radius: radius, fontSize: baseFontSize)
        }
    }

    private func bubble(width: CGFloat, height: CGFloat, radius: CGFloat, fontSize baseFontSize: CGFloat) -> some View {
        Text(text.isEmpty ? "—" : text)
            .font(.system(size: metrics.scaled(baseFontSize), weight: .bold, design: .rounded).monospacedDigit())
            .foregroundStyle(text.isEmpty ? Color.secondary : Color.white)
            .contentTransition(.numericText())
            .lineLimit(1)
            .minimumScaleFactor(0.7)
            .frame(width: width, height: height)
            .background(
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .fill(text.isEmpty ? AnyShapeStyle(Palette.inset) : AnyShapeStyle(tint))
            )

            .animation(Motion.snappy, value: text)
            .accessibilityLabel(text.isEmpty ? "No grade" : "Grade \(text)")
    }
}

/// Period badge that sizes cleanly to both single periods ("1") and block periods ("4A-4B").
struct PeriodBadge: View {
    @Environment(\.windowMetrics) private var metrics
    var period: String
    var tint: Color = .secondary
    var prominent: Bool = false
    var filled: Bool = false

    private var isFilled: Bool { prominent || filled }

    var body: some View {
        Text(period.isEmpty ? "•" : period)
            .font(.system(size: metrics.scaled(11.5), weight: .bold, design: .rounded).monospacedDigit())
            .foregroundStyle(isFilled ? Color.white : tint)
            .lineLimit(1)
            .fixedSize(horizontal: true, vertical: false)
            .padding(.horizontal, metrics.scaled(8))
            .frame(minWidth: metrics.scaled(30), minHeight: metrics.scaled(25))
            .background(
                RoundedRectangle(cornerRadius: 7)
                    .fill(isFilled ? tint : Palette.inset)
            )
    }
}

struct Card<Content: View>: View {
    @Environment(\.backgroundTheme) private var bgTheme
    @Environment(\.colorScheme) private var scheme

    var padding: CGFloat = 16
    /// Marks the card with a thin leading bar, for state that needs attention.
    var tint: Color? = nil
    @ViewBuilder var content: Content

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 12)
        VStack(alignment: .leading, spacing: 12) { content }
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(bgTheme.cardColor(for: scheme), in: shape)
            .overlay(alignment: .leading) {
                if let tint {
                    UnevenRoundedRectangle(topLeadingRadius: 12, bottomLeadingRadius: 12)
                        .fill(tint)
                        .frame(width: 3)
                }
            }
            .clipShape(shape)
            .overlay { shape.strokeBorder(Palette.hairline, lineWidth: 0.5) }
            .shadow(color: .black.opacity(scheme == .dark ? 0 : 0.035), radius: 1.5, y: 1)
    }
}

/// Row wrapper for clickable rows: a faint fill and a light sheen under the cursor.
struct HoverRow<Content: View>: View {
    var tint: Color? = nil
    @ViewBuilder var content: Content

    var body: some View {
        content.hoverSheen()
    }
}

/// A scrolling page that dynamically measures its window size and scales all child views and grids.
struct Screen<Content: View>: View {
    var title: String
    var spacing: CGFloat = 16
    @ViewBuilder var content: Content
    @State private var viewSize: CGSize = CGSize(width: 390, height: 844)

    var body: some View {
        let metrics = WindowMetrics(width: max(320, viewSize.width), height: max(320, viewSize.height))
        ScrollView {
            VStack(alignment: .leading, spacing: metrics.scaled(spacing)) {
                content
            }
            .frame(maxWidth: metrics.contentMaxWidth, alignment: .leading)
            .frame(maxWidth: .infinity)
            .padding(.horizontal, metrics.horizontalPadding)
            .padding(.top, metrics.scaled(12))
            .padding(.bottom, metrics.scaled(60))
        }
        .background {
            GeometryReader { geo in
                Color.clear
                    .preference(key: ScreenSizePreferenceKey.self, value: geo.size)
            }
        }
        .onPreferenceChange(ScreenSizePreferenceKey.self) { size in
            if size.width > 0 && (size.width != viewSize.width || size.height != viewSize.height) {
                viewSize = size
            }
        }
        .background { PageBackground().overlay { PointerLight() } }
        .navigationTitle(title)
        .environment(\.windowMetrics, metrics)
    }
}

private struct ScreenSizePreferenceKey: PreferenceKey {
    static var defaultValue: CGSize = .zero
    static func reduce(value: inout CGSize, nextValue: () -> CGSize) {
        let next = nextValue()
        if next != .zero { value = next }
    }
}

/// A very faint light on the page that follows the pointer, the way a glass
/// surface catches a moving highlight. Off under Reduce Motion.
struct PointerLight: View {
    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var point: CGPoint?

    var body: some View {
        #if os(macOS)
        GeometryReader { geo in
            Color.clear
                .overlay {
                    if let point, !reduceMotion {
                        RadialGradient(
                            colors: [Color.white.opacity(scheme == .dark ? 0.05 : 0.55), .clear],
                            center: UnitPoint(x: point.x / max(geo.size.width, 1), y: point.y / max(geo.size.height, 1)),
                            startRadius: 0,
                            endRadius: 380
                        )
                        .transition(.opacity)
                    }
                }
                .contentShape(Rectangle())
                .onContinuousHover(coordinateSpace: .local) { phase in
                    withAnimation(.easeOut(duration: point == nil ? 0.3 : 0.12)) {
                        switch phase {
                        case .active(let location): point = location
                        case .ended: point = nil
                        }
                    }
                }
        }
        .ignoresSafeArea()
        #else
        Color.clear
        #endif
    }
}

struct SectionHeader<Trailing: View>: View {
    @Environment(\.windowMetrics) private var metrics
    var title: String
    var subtitle: String?
    @ViewBuilder var trailing: Trailing

    init(title: String, subtitle: String? = nil, @ViewBuilder trailing: () -> Trailing) {
        self.title = title
        self.subtitle = subtitle
        self.trailing = trailing()
    }

    init(_ title: String, subtitle: String? = nil, @ViewBuilder trailing: () -> Trailing) {
        self.title = title
        self.subtitle = subtitle
        self.trailing = trailing()
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.title3.weight(.semibold))
                if let subtitle {
                    Text(subtitle)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 8)
            trailing
        }
        .padding(.top, 4)
    }
}

extension SectionHeader where Trailing == EmptyView {
    init(_ title: String, subtitle: String? = nil) {
        self.init(title: title, subtitle: subtitle) { EmptyView() }
    }
}

struct EmptyState: View {
    var symbol: String
    var title: String
    var message: String

    var body: some View {
        ContentUnavailableView {
            Label(title, systemImage: symbol)
        } description: {
            Text(message)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
    }
}

struct Pill: View {
    @Environment(\.windowMetrics) private var metrics
    var text: String
    var tint: Color = .secondary
    var filled = false
    var symbol: String? = nil

    var body: some View {
        HStack(spacing: 4) {
            if let symbol {
                Image(systemName: symbol)
                    .font(.system(size: metrics.scaled(10), weight: .bold))
            }
            Text(text)
                .font(.system(size: metrics.scaled(11.5), weight: .semibold))
        }
        .foregroundStyle(filled ? Color.white : tint)
        .padding(.horizontal, 7)
        .padding(.vertical, 2.5)
        .background(Capsule().fill(filled ? tint : tint.opacity(0.12)))
    }
}

struct StatTile: View {
    @Environment(\.backgroundTheme) private var bgTheme
    @Environment(\.colorScheme) private var scheme

    var title: String
    var value: String
    var caption: String?
    var tint: Color = .primary
    var symbol: String? = nil

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 12)
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            Text(value)
                .font(.system(.title, design: .rounded).weight(.semibold).monospacedDigit())
                .foregroundStyle(tint)
                .contentTransition(.numericText())
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            if let caption {
                Text(caption)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(bgTheme.cardColor(for: scheme), in: shape)
        .overlay { shape.strokeBorder(Palette.hairline, lineWidth: 0.5) }
        .shadow(color: .black.opacity(scheme == .dark ? 0 : 0.035), radius: 1.5, y: 1)
        .accessibilityElement(children: .combine)
    }
}

struct ProgressBar: View {
    var value: Double       // 0...1
    var tint: Color
    var height: CGFloat = 8
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// Bars draw themselves in once, the first time they are seen.
    @State private var grown = false

    var body: some View {
        let clamped = max(0, min(1, value.isFinite ? value : 0))
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(tint.opacity(0.14))
                Capsule()
                    .fill(tint)
                    .frame(width: (grown ? clamped : 0) * geo.size.width)
                    .animation(Motion.smooth, value: clamped)
            }
        }
        .frame(height: height)
        .onAppear {
            guard !grown else { return }
            withAnimation(reduceMotion ? nil : Motion.gentle.delay(0.12)) { grown = true }
        }
        .accessibilityHidden(true)
    }
}

/// Up or down arrow with the size of a change in an average.
struct DeltaLabel: View {
    @Environment(\.windowMetrics) private var metrics
    var delta: Double

    var body: some View {
        let color = delta >= 0 ? Palette.good : Palette.bad
        Label(Fmt.signed(delta), systemImage: delta >= 0 ? "arrow.up.right" : "arrow.down.right")
            .labelStyle(.titleAndIcon)
            .font(.system(size: metrics.scaled(11.5), weight: .bold).monospacedDigit())
            .foregroundStyle(color)
            .padding(.horizontal, metrics.scaled(7))
            .padding(.vertical, metrics.scaled(3))
            .background(color.opacity(0.12), in: Capsule())
    }
}

struct AvatarView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.windowMetrics) private var metrics
    var profile: Profile
    var size: CGFloat = 40
    var scalesWithWindow: Bool = true

    var body: some View {
        let _ = model.avatarVersion
        let actualSize = scalesWithWindow ? metrics.scaled(size) : size
        Group {
            if let data = model.avatarData(for: profile.id), let image = PlatformImage(data: data) {
                #if os(macOS)
                Image(nsImage: image).resizable().scaledToFill()
                #else
                Image(uiImage: image).resizable().scaledToFill()
                #endif
            } else {
                ZStack {
                    profile.theme.gradient
                    Text(profile.initials.isEmpty ? "?" : profile.initials)
                        .font(.system(size: actualSize * 0.4, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                }
            }
        }
        .frame(width: actualSize, height: actualSize)
        .clipShape(Circle())
        .overlay(Circle().strokeBorder(Color.white.opacity(0.22), lineWidth: 1))
        .shadow(color: profile.theme.color.opacity(0.22), radius: 4, x: 0, y: 2)
        .accessibilityLabel(profile.name)
    }
}

// MARK: - Native Avatar Image Picker & Processor

enum AvatarImageHelper {
    /// Normalizes any raw image data (PNG/JPEG/HEIC/TIFF) into a center-cropped 256×256 PNG.
    static func normalizedPNGData(from rawData: Data) -> Data? {
        #if os(macOS)
        guard let source = NSImage(data: rawData) else { return nil }
        let targetSize = NSSize(width: 256, height: 256)
        guard let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: 256,
            pixelsHigh: 256,
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        ) else {
            return source.tiffRepresentation
        }
        rep.size = targetSize
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        let srcSize = source.size
        if srcSize.width > 0 && srcSize.height > 0 {
            let scale = max(targetSize.width / srcSize.width, targetSize.height / srcSize.height)
            let drawW = srcSize.width * scale
            let drawH = srcSize.height * scale
            let drawRect = NSRect(
                x: (targetSize.width - drawW) / 2,
                y: (targetSize.height - drawH) / 2,
                width: drawW,
                height: drawH
            )
            source.draw(in: drawRect, from: .zero, operation: .copy, fraction: 1.0)
        }
        NSGraphicsContext.restoreGraphicsState()
        return rep.representation(using: .png, properties: [:])
        #else
        guard let image = UIImage(data: rawData) else { return nil }
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: 256, height: 256))
        let out = renderer.image { _ in
            let src = image.size
            let scale = max(256.0 / max(1, src.width), 256.0 / max(1, src.height))
            let w = src.width * scale
            let h = src.height * scale
            image.draw(in: CGRect(x: (256 - w) / 2, y: (256 - h) / 2, width: w, height: h))
        }
        return out.pngData()
        #endif
    }

    /// Generates a crisp 256×256 symbol avatar badge so users can also pick a custom badge icon in one click.
    static func badgePNGData(symbol: String, theme: ThemeColor) -> Data? {
        #if os(macOS)
        let size = NSSize(width: 256, height: 256)
        guard let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: 256,
            pixelsHigh: 256,
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        ) else { return nil }
        rep.size = size
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        let rect = NSRect(origin: .zero, size: size)
        let c1 = NSColor(
            srgbRed: CGFloat((theme.hex >> 16) & 0xFF) / 255,
            green: CGFloat((theme.hex >> 8) & 0xFF) / 255,
            blue: CGFloat(theme.hex & 0xFF) / 255,
            alpha: 1
        )
        let c2 = NSColor(
            srgbRed: CGFloat((theme.hex2 >> 16) & 0xFF) / 255,
            green: CGFloat((theme.hex2 >> 8) & 0xFF) / 255,
            blue: CGFloat(theme.hex2 & 0xFF) / 255,
            alpha: 1
        )
        NSGradient(starting: c1, ending: c2)?.draw(in: rect, angle: -45)
        if let sym = NSImage(systemSymbolName: symbol, accessibilityDescription: nil) {
            let cfg = NSImage.SymbolConfiguration(pointSize: 108, weight: .bold)
                .applying(.init(paletteColors: [.white]))
            if let styled = sym.withSymbolConfiguration(cfg) {
                let s = styled.size
                let dst = NSRect(x: (rect.width - s.width) / 2, y: (rect.height - s.height) / 2, width: s.width, height: s.height)
                styled.draw(in: dst)
            }
        }
        NSGraphicsContext.restoreGraphicsState()
        return rep.representation(using: .png, properties: [:])
        #else
        return nil
        #endif
    }

    #if os(macOS)
    /// Opens a native macOS NSOpenPanel to select an image file without triggering PhotosPicker XPC sandbox errors.
    @MainActor
    static func pickImageOnMac() -> Data? {
        let panel = NSOpenPanel()
        panel.title = "Choose Profile Picture"
        panel.prompt = "Choose"
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowedContentTypes = [.image, .png, .jpeg, .heic, .tiff, .gif]
        guard panel.runModal() == .OK, let url = panel.url,
              let raw = try? Data(contentsOf: url) else {
            return nil
        }
        return normalizedPNGData(from: raw)
    }
    #endif
}

/// Reusable interactive avatar picker row with file upload, drag-and-drop, and one-click symbol badges.
struct AvatarPickerRow: View {
    @Environment(AppModel.self) private var model
    let profile: Profile
    @State private var importingFile = false
    @State private var errorMessage: String?

    var body: some View {
        HStack(spacing: 14) {
            AvatarView(profile: profile, size: 52)
                .onDrop(of: [.fileURL, .image], isTargeted: nil) { providers in
                    handleDrop(providers)
                }
                .help("Drop an image here")
            VStack(alignment: .leading, spacing: 2) {
                Text(profile.name).font(.headline)
                if let errorMessage {
                    Text(errorMessage).font(.subheadline).foregroundStyle(Palette.bad)
                } else {
                    Text("Profile picture").font(.subheadline).foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 8)
            if profile.avatarFile != nil {
                Button("Remove") {
                    withAnimation(.snappy) { model.setAvatar(nil, for: profile.id) }
                }
            }
            Button("Choose…") { choosePhoto() }
        }
        .fileImporter(
            isPresented: $importingFile,
            allowedContentTypes: [.image],
            allowsMultipleSelection: false
        ) { result in
            switch result {
            case .success(let urls):
                guard let url = urls.first else { return }
                let accessed = url.startAccessingSecurityScopedResource()
                defer { if accessed { url.stopAccessingSecurityScopedResource() } }
                if let raw = try? Data(contentsOf: url),
                   let png = AvatarImageHelper.normalizedPNGData(from: raw) {
                    errorMessage = nil
                    model.setAvatar(png, for: profile.id)
                } else {
                    errorMessage = "Could not read that image file. Try a PNG or JPG."
                }
            case .failure(let error):
                errorMessage = error.localizedDescription
            }
        }
    }

    private func choosePhoto() {
        errorMessage = nil
        #if os(macOS)
        if let png = AvatarImageHelper.pickImageOnMac() {
            withAnimation(Motion.snappy) {
                model.setAvatar(png, for: profile.id)
            }
        }
        #else
        importingFile = true
        #endif
    }

    private func handleDrop(_ providers: [NSItemProvider]) -> Bool {
        guard let provider = providers.first else { return false }
        if provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
            provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, _ in
                if let data = item as? Data,
                   let url = URL(dataRepresentation: data, relativeTo: nil),
                   let raw = try? Data(contentsOf: url),
                   let png = AvatarImageHelper.normalizedPNGData(from: raw) {
                    Task { @MainActor in
                        model.setAvatar(png, for: profile.id)
                    }
                }
            }
            return true
        }
        return false
    }
}

/// A slim line that says what syncing is doing, or what went wrong.
struct SyncStatusView: View {
    @Environment(AppModel.self) private var model
    var onSignIn: (() -> Void)?

    var body: some View {
        switch model.syncState {
        case .idle:
            EmptyView()
        case .syncing(let step):
            HStack(spacing: 10) {
                ProgressView().controlSize(.small)
                Text(step + "…").font(.footnote.weight(.medium)).foregroundStyle(.secondary)
                Spacer()
            }
            .padding(.horizontal, 14).padding(.vertical, 9)
            .background(model.theme.color.opacity(0.08), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(model.theme.color.opacity(0.20), lineWidth: 1))
            .transition(.opacity.combined(with: .move(edge: .top)))
        case .failed(let message):
            banner(symbol: "exclamationmark.triangle.fill", tint: Palette.warn, message: message, button: "Try again") {
                Task { await model.refresh() }
            }
        case .needsSignIn(let message):
            banner(symbol: "person.crop.circle.badge.exclamationmark", tint: Palette.bad, message: message, button: "Sign in") {
                if let onSignIn { onSignIn() } else { model.requestReauth() }
            }
        }
    }

    private func banner(symbol: String, tint: Color, message: String, button: String, action: @escaping () -> Void) -> some View {
        HStack(alignment: .center, spacing: 10) {
            Image(systemName: symbol).foregroundStyle(tint)
            Text(message).font(.footnote.weight(.medium)).fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 8)
            Button(button, action: action).buttonStyle(.borderedProminent).tint(tint).controlSize(.small)
        }
        .padding(12)
        .background(tint.opacity(0.12), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(tint.opacity(0.25), lineWidth: 1))
    }
}

/// A row that looks the same in every list: leading content, a title block, trailing content.
struct RowLabel: View {
    var title: String
    var subtitle: String?
    var symbol: String?
    var tint: Color = .accentColor

    var body: some View {
        HStack(spacing: 12) {
            if let symbol {
                Image(systemName: symbol)
                    .font(.body.weight(.medium))
                    .foregroundStyle(.white)
                    .frame(width: 30, height: 30)
                    .background(tint, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.body)
                if let subtitle, !subtitle.isEmpty { Text(subtitle).font(.caption).foregroundStyle(.secondary) }
            }
        }
    }
}

extension View {
    /// Dividers between the rows of a card, without one after the last row.
    func rowDivider(_ show: Bool) -> some View {
        overlay(alignment: .bottom) {
            if show { Rectangle().fill(Palette.hairline).frame(height: 1) }
        }
    }
}

/// Current average against a goal: a track, a fill, and a tick at the goal.
struct GoalBar: View {
    let current: Double
    let goal: Double
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var grown = false

    var body: some View {
        let low = max(0, min(current, goal) - 10)
        let span = max(1, 100 - low)
        let fill = (current - low) / span
        let mark = (goal - low) / span
        let tint = current >= goal ? Palette.good : Palette.warn
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(Palette.inset)
                Capsule().fill(tint).frame(width: max(4, geo.size.width * (grown ? max(0, min(1, fill)) : 0)))
                Rectangle()
                    .fill(Color.primary.opacity(0.6))
                    .frame(width: 2, height: 12)
                    .offset(x: geo.size.width * max(0, min(1, mark)) - 1)
            }
            .frame(height: 12)
            .animation(.snappy, value: fill)
        }
        .frame(height: 12)
        .onAppear {
            guard !grown else { return }
            withAnimation(reduceMotion ? nil : Motion.gentle.delay(0.12)) { grown = true }
        }
        .accessibilityElement()
        .accessibilityLabel("Average \(Fmt.percent(current)), goal \(Fmt.percent(goal))")
    }
}


// MARK: - Hover

/// The hover response for anything clickable: a soft fill plus a light glint
/// that follows the pointer, like light catching glass. Static under Reduce Motion.
private struct HoverSheen: ViewModifier {
    var cornerRadius: CGFloat
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var scheme
    @State private var point: CGPoint?

    func body(content: Content) -> some View {
        content
            .background {
                if let point {
                    GeometryReader { geo in
                        ZStack {
                            Color.primary.opacity(scheme == .dark ? 0.05 : 0.03)
                            if !reduceMotion {
                                RadialGradient(
                                    colors: [Color.white.opacity(scheme == .dark ? 0.07 : 0.35), .clear],
                                    center: UnitPoint(x: point.x / max(geo.size.width, 1), y: point.y / max(geo.size.height, 1)),
                                    startRadius: 0,
                                    endRadius: max(140, geo.size.width * 0.35)
                                )
                            }
                        }
                    }
                    .clipShape(.rect(cornerRadius: cornerRadius))
                    .transition(.opacity)
                }
            }
            .onContinuousHover(coordinateSpace: .local) { phase in
                withAnimation(.easeOut(duration: point == nil ? 0.15 : 0.08)) {
                    switch phase {
                    case .active(let location): point = location
                    case .ended: point = nil
                    }
                }
            }
    }
}

/// For clickable cards: rises a point and casts a slightly deeper shadow on hover.
private struct HoverLift: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var scheme
    @State private var hovering = false

    func body(content: Content) -> some View {
        content
            .shadow(color: .black.opacity(hovering ? (scheme == .dark ? 0.35 : 0.09) : 0), radius: hovering ? 10 : 0, y: hovering ? 4 : 0)
            .offset(y: hovering && !reduceMotion ? -1 : 0)
            .scaleEffect(hovering && !reduceMotion ? 1.004 : 1)
            .animation(.spring(response: 0.3, dampingFraction: 0.8), value: hovering)
            .onHover { hovering = $0 }
    }
}

extension View {
    func hoverSheen(cornerRadius: CGFloat = 0) -> some View {
        modifier(HoverSheen(cornerRadius: cornerRadius))
    }

    func hoverLift() -> some View {
        modifier(HoverLift())
    }

    /// Liquid Glass on macOS 26 and later; the regular material before that.
    @ViewBuilder
    func glassSurface(cornerRadius: CGFloat) -> some View {
        #if os(macOS)
        if #available(macOS 26, *) {
            self.glassEffect(.regular, in: .rect(cornerRadius: cornerRadius))
        } else {
            self.background(.regularMaterial, in: .rect(cornerRadius: cornerRadius))
        }
        #else
        if #available(iOS 26, *) {
            self.glassEffect(.regular, in: .rect(cornerRadius: cornerRadius))
        } else {
            self.background(.regularMaterial, in: .rect(cornerRadius: cornerRadius))
        }
        #endif
    }
}


// MARK: - Motion pieces

/// A number that counts up to its value the first time it is shown and rolls
/// to the new value whenever it changes.
struct RollingNumber: View {
    let value: Double
    let format: (Double) -> String
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var shown: Double?

    var body: some View {
        RollingText(value: shown ?? (reduceMotion ? value : value * 0.6), format: format)
            .onAppear {
                guard shown == nil else { return }
                if reduceMotion { shown = value; return }
                shown = value * 0.6
                withAnimation(.easeOut(duration: 0.8)) { shown = value }
            }
            .onChange(of: value) { _, new in
                withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.5)) { shown = new }
            }
            .accessibilityLabel(format(value))
    }
}

private struct RollingText: View, Animatable {
    var value: Double
    let format: (Double) -> String

    var animatableData: Double {
        get { value }
        set { value = newValue }
    }

    var body: some View {
        Text(format(value))
    }
}

/// A hairline of light that runs along the top of the content while grades sync.
struct SyncLine: View {
    @Environment(AppModel.self) private var model
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var phase: CGFloat = -0.4

    var body: some View {
        let syncing = model.syncState.isSyncing
        GeometryReader { geo in
            LinearGradient(
                colors: [.clear, model.theme.color.opacity(0.9), .clear],
                startPoint: .leading, endPoint: .trailing
            )
            .frame(width: geo.size.width * 0.4)
            .offset(x: geo.size.width * phase)
        }
        .frame(height: 2)
        .clipped()
        .opacity(syncing && !reduceMotion ? 1 : 0)
        .animation(.easeInOut(duration: 0.3), value: syncing)
        .onChange(of: syncing, initial: true) { _, on in
            guard on, !reduceMotion else { return }
            phase = -0.4
            withAnimation(.easeInOut(duration: 1.3).repeatForever(autoreverses: false)) { phase = 1 }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}


// MARK: - Row groups

/// A list of tappable rows. On the Mac and iPad they share one card with hairlines
/// between them; on a phone each row is its own lifted bubble, which gives every
/// option a bigger, clearly separate target for a thumb.
struct RowGroup<Data: RandomAccessCollection, Row: View>: View where Data.Element: Identifiable {
    let items: Data
    @ViewBuilder var row: (Data.Element) -> Row
    @Environment(\.horizontalSizeClass) private var sizeClass

    var body: some View {
        if isPhone {
            VStack(spacing: 10) {
                ForEach(items) { item in
                    row(item).bubble()
                }
            }
        } else {
            let list = Array(items)
            Card(padding: 0) {
                VStack(spacing: 0) {
                    ForEach(Array(list.enumerated()), id: \.element.id) { index, item in
                        row(item).rowDivider(index < list.count - 1)
                    }
                }
            }
        }
    }

    private var isPhone: Bool {
        #if os(iOS)
        sizeClass == .compact
        #else
        false
        #endif
    }
}

/// The lifted surface behind a single option on the phone.
private struct Bubble: ViewModifier {
    @Environment(\.backgroundTheme) private var bgTheme
    @Environment(\.colorScheme) private var scheme
    var cornerRadius: CGFloat = 16

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        content
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(bgTheme.cardColor(for: scheme), in: shape)
            .overlay { shape.strokeBorder(Palette.hairline, lineWidth: 0.5) }
            .shadow(color: .black.opacity(scheme == .dark ? 0.28 : 0.07), radius: 9, y: 4)
            .contentShape(shape)
    }
}

extension View {
    func bubble(cornerRadius: CGFloat = 16) -> some View {
        modifier(Bubble(cornerRadius: cornerRadius))
    }
}

/// Press feedback for a bubble: it settles into the page while your finger is on it.
struct BubbleButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.975 : 1)
            .opacity(configuration.isPressed ? 0.9 : 1)
            .animation(.spring(response: 0.25, dampingFraction: 0.7), value: configuration.isPressed)
    }
}
