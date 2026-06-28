import SwiftUI

/// Maps a marimo's `colorLevel` to its moss-green fills.
///
/// Kept beside `StepLevel+Color` as the marimo counterpart: the domain produces a
/// numeric condition score (averaged as-of level over the month) and the palette
/// owns how that reads as color, so the renderer never hard-codes greens.
///
/// Deliberately matte: even the lit side stays a bright green, not a white sheen,
/// so the body reads as moss rather than a glossy sphere. A higher `colorLevel`
/// reads as a richer, deeper moss; a lower one as a paler, lighter moss.
///
/// `shade(_:)` is the key entry point: a continuous ramp from the shadow tone
/// through the mid tone to the lit tone, so the renderer can color each fiber by
/// how the light falls on it and let the texture itself form the sphere's shading.
enum MarimoPalette {
  private typealias HSB = (hue: Double, saturation: Double, brightness: Double)

  /// Normalizes a `colorLevel` to a tonal fraction where `positiveLevelCount` maps
  /// to `1`.
  ///
  /// Only the lower bound is clamped: domain values stay within `0...positiveLevelCount`,
  /// but a tuning value above the scale is allowed to extrapolate past `1` so it
  /// reads as an even deeper moss instead of capping.
  private static func fraction(colorLevel: Double, positiveLevelCount: Int) -> Double {
    let upperBound = Double(max(positiveLevelCount, 1))
    return max(colorLevel, 0) / upperBound
  }

  // The three tonal anchors, as functions of condition. The ramp interpolates
  // between them; the named accessors below expose the anchors themselves.
  private static func shadowHSB(_ fraction: Double) -> HSB {
    (0.33 - 0.03 * fraction, 0.50 + 0.34 * fraction, 0.30 - 0.12 * fraction)
  }
  private static func coreHSB(_ fraction: Double) -> HSB {
    (0.30 - 0.03 * fraction, 0.42 + 0.30 * fraction, 0.58 - 0.16 * fraction)
  }
  private static func highlightHSB(_ fraction: Double) -> HSB {
    (0.31 - 0.03 * fraction, 0.34 + 0.22 * fraction, 0.84 - 0.10 * fraction)
  }

  static func core(colorLevel: Double, positiveLevelCount: Int) -> Color {
    color(coreHSB(fraction(colorLevel: colorLevel, positiveLevelCount: positiveLevelCount)))
  }

  static func highlight(colorLevel: Double, positiveLevelCount: Int) -> Color {
    color(highlightHSB(fraction(colorLevel: colorLevel, positiveLevelCount: positiveLevelCount)))
  }

  static func shadow(colorLevel: Double, positiveLevelCount: Int) -> Color {
    color(shadowHSB(fraction(colorLevel: colorLevel, positiveLevelCount: positiveLevelCount)))
  }

  /// A tone along the ramp: `0` is full shadow, `0.5` the mid moss, `1` the lit
  /// side. Used to color a fiber by its diffuse lighting so the packed fibers read
  /// as a softly lit sphere instead of a flat camouflage pattern.
  static func shade(_ t: Double, colorLevel: Double, positiveLevelCount: Int) -> Color {
    let fraction = fraction(colorLevel: colorLevel, positiveLevelCount: positiveLevelCount)
    let clamped = min(max(t, 0), 1)
    let hsb: HSB
    if clamped < 0.5 {
      hsb = lerp(shadowHSB(fraction), coreHSB(fraction), clamped * 2)
    } else {
      hsb = lerp(coreHSB(fraction), highlightHSB(fraction), (clamped - 0.5) * 2)
    }
    return color(hsb)
  }

  private static func lerp(_ a: HSB, _ b: HSB, _ t: Double) -> HSB {
    (
      a.hue + (b.hue - a.hue) * t,
      a.saturation + (b.saturation - a.saturation) * t,
      a.brightness + (b.brightness - a.brightness) * t
    )
  }

  private static func color(_ hsb: HSB) -> Color {
    Color(hue: hsb.hue, saturation: hsb.saturation, brightness: hsb.brightness)
  }
}
