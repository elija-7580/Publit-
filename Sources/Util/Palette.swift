import Foundation

/// Status and accent colours. The iOS system green and orange reach only about 2.2:1 on white,
/// which is too faint for the live/delay times people read at a glance, so light mode uses
/// darker tones (all at least 4.5:1 on white and on grouped backgrounds). Dark mode keeps the
/// system tones, which already pass on black.
public enum Palette {
    public struct Tone: Sendable { public let light: String; public let dark: String }
    public static let live   = Tone(light: "1b7a33", dark: "30d158")
    public static let delay  = Tone(light: "b25000", dark: "ff9f0a")
    public static let danger = Tone(light: "d70015", dark: "ff453a")
    public static let accent = Tone(light: "0066d6", dark: "0a84ff")
    public static let all: [Tone] = [live, delay, danger, accent]
    /// "Ink & Dot" surfaces (docs/design): flat warm grey ground, opaque cards, ink for the main action.
    public static let ground  = Tone(light: "f4f4f2", dark: "0b0b0c")
    public static let surface = Tone(light: "ffffff", dark: "19191b")
    public static let fill    = Tone(light: "ebebe7", dark: "2a2a2d")
    public static let ink     = Tone(light: "111111", dark: "f4f4f2")
    public static let onInk   = Tone(light: "ffffff", dark: "111111")
    /// Filled controls with a white label (swipe actions): ink in light mode, dark grey in dark mode,
    /// where light ink would hide the label.
    public static let inkAction = Tone(light: "111111", dark: "3a3a3d")
    /// Route lines on maps, as in Apple Maps: the way still ahead in blue (walks; rides keep their
    /// line colour), the part already behind you in light blue, whatever the mode.
    public static let routeAhead    = Tone(light: "0a7cff", dark: "409cff")
    public static let routeTraveled = Tone(light: "a9cdfa", dark: "5b7fa8")
    /// The yellow dot of the logo: only for "you" and "live", never as a fill.
    public static let signature = Tone(light: "ffc531", dark: "ffc531")
    /// System background colours the tones are drawn on (light: white and grouped grey; dark: black and grouped dark grey).
    public static let lightBackgrounds = ["ffffff", "f2f2f7"]
    public static let darkBackgrounds = ["000000", "1c1c1e"]
}
