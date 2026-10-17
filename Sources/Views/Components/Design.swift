import SwiftUI

/// "Ink & Dot" (docs/design/README.md): flat opaque cards and matte floating controls,
/// ink instead of a brand colour, the logo's yellow dot only for "you" and "live".
extension Color {
    static let ground = Color(Palette.ground)
    static let surface = Color(Palette.surface)
    static let inkFill = Color(Palette.fill)
    static let ink = Color(Palette.ink)
    static let onInk = Color(Palette.onInk)
    static let signature = Color(Palette.signature)
    static let inkAction = Color(Palette.inkAction)
    static let routeAhead = Color(Palette.routeAhead)
    static let routeTraveled = Color(Palette.routeTraveled)
}

/// The main action: an ink slab with the label in `onInk` (black on light, white on dark).
struct InkButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .foregroundStyle(Color.onInk)
            .padding(.horizontal, 18)
            .padding(.vertical, 11)
            .frame(minHeight: 44)
            .background(Color.ink, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .opacity(isEnabled ? (configuration.isPressed ? 0.75 : 1) : 0.35)
    }
}

/// Switches turn the live green when on: an ink switch was black on light and nearly white on dark,
/// and its thumb disappeared against it.
struct InkSwitchStyle: ToggleStyle {
    func makeBody(configuration: Configuration) -> some View {
        Toggle(configuration).toggleStyle(.switch).tint(Color.live)
    }
}

extension ButtonStyle where Self == InkButtonStyle {
    static var ink: InkButtonStyle { InkButtonStyle() }
}

/// The logo's dot: where you are, what is live.
struct SignatureDot: View {
    var size: CGFloat = 8
    var body: some View {
        Circle().fill(Color.signature).frame(width: size, height: size).accessibilityHidden(true)
    }
}

/// Progress as the logo's stroke: a round-capped track, filled in ink (or a status colour),
/// with the yellow dot where you are now.
struct InkProgress: View {
    let value: Double
    var tint: Color = .ink

    var body: some View {
        let v = min(max(value, 0), 1)
        GeometryReader { geo in
            let w = geo.size.width
            ZStack(alignment: .leading) {
                Capsule().fill(Color.inkFill).frame(height: 6)
                Capsule().fill(tint).frame(width: max(6, w * v), height: 6)
                Circle().fill(Color.signature)
                    .frame(width: 12, height: 12)
                    .overlay(Circle().strokeBorder(Color.surface, lineWidth: 2.5).padding(-2.5))
                    .offset(x: min(max(w * v - 6, 0), max(w - 12, 0)))
            }
            .frame(height: 12)
        }
        .frame(height: 12)
        .accessibilityElement()
        .accessibilityValue(Text(verbatim: "\(Int((v * 100).rounded())) %"))
    }
}

extension View {
    /// A list on the flat "Ink & Dot" ground with opaque cards (apply `inkCard()` to its sections).
    func inkList() -> some View {
        scrollContentBackground(.hidden)
            .background(Color.ground)
            .listSectionSpacing(12)
            .liveBarPadding()
    }

    /// Opaque floating controls with a quiet edge, shared across platforms (no blur).
    func matteSurface<S: InsettableShape>(in shape: S) -> some View {
        background(Color.surface, in: shape)
            .overlay(shape.strokeBorder(Color.ink.opacity(0.09), lineWidth: 1))
    }

    /// Rows of a list section as one flat card.
    func inkCard() -> some View { listRowBackground(Color.surface) }
}

/// A warning in one calm form for every screen: a coloured edge and symbol, the words in ink.
/// Only `critical` (cancelled, missed) gets a tinted card, so it stands out from everything else.
struct Notice: View {
    enum Level { case critical, change, info }
    let level: Level
    let title: String
    var detail: String? = nil

    var tint: Color {
        switch level {
        case .critical: return .danger
        case .change: return .delay
        case .info: return .secondary
        }
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Image(systemName: level == .info ? "info.circle.fill" : "exclamationmark.circle.fill")
                .font(.subheadline.weight(.bold))
                .foregroundStyle(tint)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.subheadline.weight(.semibold)).foregroundStyle(Color.ink)
                if let detail { Text(detail).font(.footnote).foregroundStyle(.secondary) }
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .combine)
        .listRowBackground(NoticeBackground(tint: tint, tinted: level == .critical))
    }
}

/// The card behind a notice row: a 4 pt edge in its colour.
struct NoticeBackground: View {
    let tint: Color
    var tinted = false

    var body: some View {
        Color.surface
            .overlay(tinted ? tint.opacity(0.07) : Color.clear)
            .overlay(alignment: .leading) { tint.frame(width: 4) }
    }
}

/// A short warning inside a row: the symbol in its colour, the words in ink (same calm form as `Notice`).
struct InlineNotice: View {
    let text: String
    var tint: Color = .delay
    var systemImage = "exclamationmark.triangle.fill"

    var body: some View {
        Label {
            Text(verbatim: text).foregroundStyle(Color.ink)
        } icon: {
            Image(systemName: systemImage).foregroundStyle(tint)
        }
        .font(.caption.weight(.semibold))
        .fixedSize(horizontal: false, vertical: true)
        .accessibilityElement(children: .combine)
    }
}

/// One empty state for every tab: symbol, title, a line of help and an optional ink action.
/// Wraps instead of truncating, also inside a list card.
struct EmptyState<Action: View>: View {
    let title: String
    let systemImage: String
    let message: String
    @ViewBuilder var action: () -> Action

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: systemImage)
                .font(.system(size: 34, weight: .regular))
                .foregroundStyle(.secondary)
                .padding(.bottom, 4)
                .accessibilityHidden(true)
            Text(verbatim: title)
                .font(.title3.weight(.bold))
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            Text(verbatim: message)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            action().padding(.top, 6)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 24)
        .padding(.horizontal, 12)
        .accessibilityElement(children: .contain)
    }
}

extension EmptyState where Action == EmptyView {
    init(title: String, systemImage: String, message: String) {
        self.init(title: title, systemImage: systemImage, message: message) { EmptyView() }
    }
}

/// Small controls above a list (sort, map): the same capsule as the mode chips.
struct ChipButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(Color.ink)
            .padding(.horizontal, 12)
            .frame(minHeight: 34)
            .background(Color.inkFill, in: Capsule())
            .contentShape(Capsule())
            .opacity(configuration.isPressed ? 0.7 : 1)
    }
}

extension ButtonStyle where Self == ChipButtonStyle {
    static var chip: ChipButtonStyle { ChipButtonStyle() }
}

/// Publit's own input look: a field pressed into the card (inner shadow at the top, a light edge
/// at the bottom), instead of the flat system grey.
struct BevelField: ViewModifier {
    @Environment(\.colorScheme) private var scheme
    var radius: CGFloat = 12

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
        let dark = scheme == .dark
        content
            .background(
                shape.fill(Color.inkFill.shadow(.inner(color: .black.opacity(dark ? 0.55 : 0.16), radius: 2.5, x: 0, y: 1.5)))
            )
            .overlay(
                shape.strokeBorder(LinearGradient(colors: [Color.black.opacity(dark ? 0.5 : 0.10),
                                                           Color.white.opacity(dark ? 0.07 : 0.9)],
                                                  startPoint: .top, endPoint: .bottom), lineWidth: 1)
            )
    }
}

/// The raised counterpart: a key standing on the card (light top edge, soft drop shadow).
struct RaisedKey: ViewModifier {
    @Environment(\.colorScheme) private var scheme
    var radius: CGFloat = 12

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
        let dark = scheme == .dark
        content
            .background(shape.fill(Color.surface).shadow(color: .black.opacity(dark ? 0.6 : 0.14), radius: 1.5, x: 0, y: 1.5))
            .overlay(
                shape.strokeBorder(LinearGradient(colors: [Color.white.opacity(dark ? 0.14 : 1), Color.black.opacity(dark ? 0.3 : 0.08)],
                                                  startPoint: .top, endPoint: .bottom), lineWidth: 1)
            )
    }
}

extension View {
    func bevelField(radius: CGFloat = 12) -> some View { modifier(BevelField(radius: radius)) }
    func raisedKey(radius: CGFloat = 12) -> some View { modifier(RaisedKey(radius: radius)) }
}

/// Two or three choices in a bevelled track; the chosen one is a raised key (replaces the system segmented control).
struct BevelSegmented<Value: Hashable>: View {
    @Binding var selection: Value
    let options: [(Value, String)]

    var body: some View {
        HStack(spacing: 4) {
            ForEach(options.indices, id: \.self) { i in
                let value = options[i].0
                let title = options[i].1
                let selected = value == selection
                Button {
                    withAnimation(.snappy(duration: 0.2)) { selection = value }
                } label: {
                    Text(verbatim: title)
                        .font(.subheadline.weight(selected ? .bold : .medium))
                        .foregroundStyle(selected ? Color.ink : Color.secondary)
                        .frame(maxWidth: .infinity, minHeight: 32)
                        .background { if selected { Color.clear.raisedKey(radius: 9) } }
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(selected ? .isSelected : [])
            }
        }
        .padding(3)
        .bevelField(radius: 12)
    }
}
