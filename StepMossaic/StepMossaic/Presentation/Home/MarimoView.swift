import StepMossaicDomain
import SwiftUI

/// Tunable knobs for the marimo's matte, fibrous, softly-lit look.
///
/// Grouped in one value so the appearance is tuned from a single place (and in
/// previews) instead of from literals scattered across the layers. Length and
/// blur fractions are of the drawn `baseRadius`, so the look holds at any size.
struct MarimoStyle {
  /// Outline samples; dense enough that straight segments read as a smooth edge.
  var sampleCount = 160
  /// Fraction of the half-min dimension the largest marimo may reach. Near-full,
  /// since the hosting view adds its own outer margin around the square.
  var maxExtentFraction = 0.95
  /// Scales the domain `bumpiness` (0…1) down to the rendered wobble amount.
  ///
  /// A rendering taste, like the palette's colour gain: the full domain range
  /// looks too distorted to read as a marimo, so map it into a gentler `0…scale`
  /// band. Kept here (not in the domain) so the stored bumpiness stays 0…1 and a
  /// later taste change re-renders without recomputing.
  var bumpinessScale = 0.4

  /// Direction the body is lit from, as a unit point within the marimo's bounds,
  /// used for the base gradient. The fiber shading uses `lightDirection`.
  var lightSource = UnitPoint(x: 0.4, y: 0.36)
  /// 3D light direction (screen x right, y down, z toward viewer) for the diffuse
  /// sphere shading that colors the fibers. Upper-left-front.
  var lightDirection = (x: -0.32, y: -0.46, z: 0.73)
  /// Diffuse floor so the shadow side stays a soft matte green, never black.
  var ambient = 0.38

  /// Tones the diffuse ramp is quantized into; each becomes one batched stroke, so
  /// shading stays smooth while the draw stays cheap.
  var shadeBands = 12

  /// Short line strokes filling the body — the moss fibers. Drawn one batched pass
  /// per shade band, so density can be high without the draw cost scaling.
  var fiberCount = 11000
  var fiberLength = 0.03...0.11
  /// Exponent biasing fiber length toward the short end (1 = uniform, higher =
  /// mostly short with a few long), so strokes look less uniform and symbolic.
  var fiberLengthBias = 2.2
  var fiberWidth = 0.85
  var fiberOpacity = 0.5
  /// Random wobble added to each fiber's lit tone, so bands don't show as rings.
  var fiberShadeJitter = 0.06
  /// Low-frequency tone patches that make some areas read denser/darker than
  /// others, so the surface isn't an even field.
  var fiberClumpFrequency = 1.1
  var fiberClumpStrength = 0.13
  /// A coherent flow the fibers follow so neighbours align like combed moss rather
  /// than scattered marks, plus how strongly they comb along the surface (toward
  /// the tangent) approaching the rim.
  var fiberFlowFrequency = 1.6
  var fiberSurfaceFollow = 0.55
  var fiberAngleJitter = 0.4

  /// A fine stipple beneath the fibers, lit by the same model, for packed density
  /// under the visible strokes.
  var stippleCount = 9000
  var stippleDotRadius = 0.45
  var stippleOpacity = 0.4

  /// Short fibers straddling the contour — the ragged, fuzzy edge. Lit by the same
  /// model so the fringe is the body's weave continuing past a soft edge.
  var fuzzCount = 18000
  var fuzzLength = 0.02...0.10
  /// Bias toward short rim fibers, leaving a few longer hairs to escape the
  /// contour for a soft, hairy edge.
  var fuzzLengthBias = 2.6
  var fuzzWidth = 0.8
  var fuzzOpacity = 0.38
  var fuzzOutwardJitter = 0.5
  /// How much of each rim fiber sits inside the body; below 0.5 lets a touch more
  /// poke out for a softer edge without going bushy.
  var fuzzInsetFraction = 0.75
  /// Feathers the body silhouette (as a fraction of `baseRadius`) so the solid body
  /// dissolves into the rim fibers instead of ending at a crisp outline.
  var edgeFeatherFraction = 0.045

  /// Fine low-contrast speckle for matte graininess.
  var grainCount = 2200
  var grainOpacity = 0.04
  var grainDotRadius = 0.7

  static let `default` = MarimoStyle()

  /// A cheap preset for shelf thumbnails (~90pt). The fiber / stipple / fuzz /
  /// grain counts are cut roughly tenfold because at thumbnail size the dense
  /// texture is below what the eye resolves, so the full-fidelity cost buys
  /// nothing. Shape, lighting, and palette are inherited unchanged, so a thumbnail
  /// and its full-size render in the month detail read as the same marimo — only
  /// the texture density differs.
  static let shelf: MarimoStyle = {
    var style = MarimoStyle.default
    style.sampleCount = 96
    style.fiberCount = 1_200
    style.stippleCount = 1_000
    style.fuzzCount = 1_800
    style.grainCount = 300
    return style
  }()
}

/// Draws a single marimo from its `MarimoParameters`, and nothing else.
///
/// A pure value-driven view: it owns no data, sync, or view model, so it renders
/// identically in previews and on screen and can be tuned in isolation. The
/// outline comes from the domain's `MarimoShape` mapping; the body is a soft
/// gradient overlaid with thousands of short fibers whose tone follows a diffuse
/// sphere lighting model — so the packed fibers themselves shade the ball rather
/// than reading as a flat pattern.
struct MarimoView: View {
  let parameters: MarimoParameters
  /// Levels the condition score can reach, so the palette maps color without
  /// assuming the scale.
  var positiveLevelCount = StepLevelScale().positiveLevelCount
  var style = MarimoStyle.default

  var body: some View {
    GeometryReader { proxy in
      let size = proxy.size
      let baseRadius = geometry.baseRadius(in: size)

      ZStack {
        maskedTextureLayers(size: size, baseRadius: baseRadius)
        // Rim fibers stay unmasked so individual strands still poke past the now-soft
        // edge and blend the body into its surroundings.
        MarimoRimFuzz(geometry: geometry, shades: shades, style: style)
      }
    }
  }

  // Split out of `body`: on an older type checker, the nested ZStack plus the
  // `.mask` trailing closure and modifier chain as one expression hit "unable to
  // type-check this expression in reasonable time".

  /// The solid body and its texture layers, feathered into the rim fibers so the
  /// silhouette fades rather than ending at a crisp outline.
  private func maskedTextureLayers(size: CGSize, baseRadius: Double) -> some View {
    textureLayers(size: size, baseRadius: baseRadius)
      .mask {
        MarimoBlob(geometry: geometry)
          .fill(.black)
          .blur(radius: baseRadius * style.edgeFeatherFraction)
      }
  }

  private func textureLayers(size: CGSize, baseRadius: Double) -> some View {
    ZStack {
      litBody(size: size, baseRadius: baseRadius)
      // Fine stipple first, so the visible fibers sit on a dense base.
      MarimoStipple(geometry: geometry, shades: shades, style: style)
      MarimoFibers(geometry: geometry, shades: shades, style: style)
      MarimoGrain(geometry: geometry, dark: color(MarimoPalette.shadow), style: style)
        .blendMode(.softLight)
        .opacity(style.grainOpacity)
    }
  }

  private var geometry: MarimoGeometry {
    MarimoGeometry(
      // Render a gentler wobble than the raw domain value, which looks distorted.
      bumpiness: parameters.bumpiness * style.bumpinessScale,
      seed: parameters.seed,
      sizeUnit: parameters.sizeUnit,
      sampleCount: style.sampleCount,
      maxExtentFraction: style.maxExtentFraction
    )
  }

  private var blob: MarimoBlob { MarimoBlob(geometry: geometry) }

  /// The diffuse ramp sampled into `shadeBands` tones, shared by the fibers and
  /// the rim so both are lit consistently.
  private var shades: [Color] {
    (0..<style.shadeBands).map { band in
      MarimoPalette.shade(
        Double(band) / Double(style.shadeBands - 1),
        colorLevel: parameters.colorLevel,
        positiveLevelCount: positiveLevelCount)
    }
  }

  /// A soft matte base under the fibers: lighter on the lit side, easing to the mid
  /// tone and a touch darker at the rim, so gaps between fibers still read as a
  /// lit sphere.
  private func litBody(size: CGSize, baseRadius: Double) -> some View {
    let lightUnit = UnitPoint(
      x: 0.5 - (0.5 - style.lightSource.x) * (2 * baseRadius / max(size.width, 1)),
      y: 0.5 - (0.5 - style.lightSource.y) * (2 * baseRadius / max(size.height, 1))
    )
    let gradient = Gradient(stops: [
      .init(color: color(MarimoPalette.highlight), location: 0.0),
      .init(color: color(MarimoPalette.core), location: 0.62),
      .init(color: color(MarimoPalette.shadow), location: 1.0),
    ])
    return blob.fill(
      RadialGradient(
        gradient: gradient, center: lightUnit, startRadius: 0, endRadius: baseRadius * 1.55))
  }

  /// Resolves a palette color for this marimo's condition level.
  private func color(_ make: (Double, Int) -> Color) -> Color {
    make(parameters.colorLevel, positiveLevelCount)
  }
}

// MARK: - Geometry

/// Pure geometry of a marimo's outline, shared by the `Shape` and the texture
/// canvases so they all agree on the same wobbled silhouette and size.
///
/// `nonisolated`: pure math, called from `Shape.path(in:)` and `Canvas` closures
/// outside the main actor.
nonisolated struct MarimoGeometry {
  var bumpiness: Double
  var seed: UInt64
  var sizeUnit: Double
  var sampleCount: Int
  var maxExtentFraction: Double

  /// The drawn radius before wobble, leaving a fixed margin for the wobble's peak
  /// so size is driven by `sizeUnit` alone, not by bumpiness.
  func baseRadius(in size: CGSize) -> Double {
    let halfMin = min(size.width, size.height) / 2
    let peakUnitRadius = 1 + MarimoShape.maximumAmplitude
    return halfMin * maxExtentFraction / peakUnitRadius * sizeUnit
  }

  func center(in size: CGSize) -> CGPoint {
    CGPoint(x: size.width / 2, y: size.height / 2)
  }

  /// The closed outline path for the wobbled body.
  func path(in size: CGSize) -> Path {
    let center = center(in: size)
    let base = baseRadius(in: size)
    let radii = MarimoShape.radii(bumpiness: bumpiness, seed: seed, sampleCount: sampleCount)

    var path = Path()
    for (index, unitRadius) in radii.enumerated() {
      let angle = 2 * .pi * Double(index) / Double(sampleCount)
      let radius = base * unitRadius
      let point = CGPoint(x: center.x + cos(angle) * radius, y: center.y + sin(angle) * radius)
      if index == 0 { path.move(to: point) } else { path.addLine(to: point) }
    }
    path.closeSubpath()
    return path
  }

  /// The outline point at `angle`, for placing rim fibers along the contour.
  func outlinePoint(at angle: Double, in size: CGSize) -> CGPoint {
    let center = center(in: size)
    let radius =
      baseRadius(in: size) * MarimoShape.radius(atAngle: angle, bumpiness: bumpiness, seed: seed)
    return CGPoint(x: center.x + cos(angle) * radius, y: center.y + sin(angle) * radius)
  }
}

/// SwiftUI `Shape` wrapping `MarimoGeometry`, so the body can be filled, masked,
/// stroked, and blurred like any other shape across the layers.
struct MarimoBlob: Shape {
  var geometry: MarimoGeometry
  func path(in rect: CGRect) -> Path { geometry.path(in: rect.size) }
}

// MARK: - Texture canvases

/// Dense short fibers across the body footprint, clipped to the outline, each
/// toned by its diffuse lighting so the field shades the sphere.
private struct MarimoFibers: View {
  let geometry: MarimoGeometry
  let shades: [Color]
  let style: MarimoStyle

  var body: some View {
    Canvas { context, size in
      context.clip(to: geometry.path(in: size))
      var rng = SplitMix64Generator(seed: geometry.seed ^ 0xF1BE_0001)
      let center = geometry.center(in: size)
      let base = geometry.baseRadius(in: size)
      // Shared with the stipple so the two layers clump together; the flow field
      // gives neighbouring fibers a coherent direction.
      let clump = FlowNoise(
        seed: geometry.seed ^ 0xC1A3_7777, frequency: style.fiberClumpFrequency, octaves: 2)
      let flow = FlowNoise(
        seed: geometry.seed ^ 0xF10A_2222, frequency: style.fiberFlowFrequency, octaves: 2)

      // One Path per shade band; the whole field draws in `shades.count` strokes
      // regardless of fiber count.
      var bands = [Path](repeating: Path(), count: shades.count)

      for _ in 0..<style.fiberCount {
        // sqrt keeps the placement uniform by area, not bunched at the center.
        let position: Double = Double.random(in: 0...1, using: &rng).squareRoot() * base * 0.99
        let placeAngle: Double = Double.random(in: 0..<(2 * .pi), using: &rng)
        let dx: Double = cos(placeAngle) * position
        let dy: Double = sin(placeAngle) * position
        let nx: Double = dx / base
        let ny: Double = dy / base
        let point = CGPoint(x: center.x + dx, y: center.y + dy)

        // Follow a coherent flow field, combing toward the tangent (along the
        // surface) as fibers approach the rim, then add a little jitter.
        let tangential: Double = atan2(dy, dx) + .pi / 2
        let flowAngle: Double = flow.value(nx, ny) * .pi
        let distanceFraction: Double = min(position / base, 1)
        let coherent: Double = lerpAngle(
          flowAngle, tangential, style.fiberSurfaceFollow * distanceFraction)
        let angleJitter: Double = Double.random(
          in: -style.fiberAngleJitter...style.fiberAngleJitter, using: &rng)
        let orientation: Double = coherent + angleJitter

        let length: Double =
          base * biasedRandom(style.fiberLength, bias: style.fiberLengthBias, using: &rng)
        let half: Double = length / 2
        let start = CGPoint(
          x: point.x - cos(orientation) * half, y: point.y - sin(orientation) * half)
        let end = CGPoint(
          x: point.x + cos(orientation) * half, y: point.y + sin(orientation) * half)

        // Tone from the lit sphere, pushed by the clump field into denser/sparser
        // patches, plus a little per-fiber jitter.
        let clumpTerm: Double = style.fiberClumpStrength * clump.value(nx, ny)
        let shadeJitter: Double = Double.random(
          in: -style.fiberShadeJitter...style.fiberShadeJitter, using: &rng)
        let lit: Double =
          sphereDiffuse(dx: dx, dy: dy, radius: base, style: style) + clumpTerm + shadeJitter
        addSegment(to: &bands[bandIndex(lit, count: shades.count)], start, end)
      }

      strokeBands(
        bands, shades: shades, opacity: style.fiberOpacity, width: style.fiberWidth,
        into: context)
    }
  }
}

/// A fine stipple beneath the fibers, lit and clumped by the same fields, so the
/// body reads as packed density rather than a few sparse strokes.
private struct MarimoStipple: View {
  let geometry: MarimoGeometry
  let shades: [Color]
  let style: MarimoStyle

  var body: some View {
    Canvas { context, size in
      context.clip(to: geometry.path(in: size))
      var rng = SplitMix64Generator(seed: geometry.seed ^ 0x5719_3333)
      let center = geometry.center(in: size)
      let base = geometry.baseRadius(in: size)
      let clump = FlowNoise(
        seed: geometry.seed ^ 0xC1A3_7777, frequency: style.fiberClumpFrequency, octaves: 2)

      var bands = [Path](repeating: Path(), count: shades.count)
      for _ in 0..<style.stippleCount {
        let position = Double.random(in: 0...1, using: &rng).squareRoot() * base * 0.99
        let angle = Double.random(in: 0..<(2 * .pi), using: &rng)
        let dx = cos(angle) * position
        let dy = sin(angle) * position
        let lit =
          sphereDiffuse(dx: dx, dy: dy, radius: base, style: style)
          + style.fiberClumpStrength * clump.value(dx / base, dy / base)
          + Double.random(in: -style.fiberShadeJitter...style.fiberShadeJitter, using: &rng)
        let radius = style.stippleDotRadius
        let dot = CGPoint(x: center.x + dx, y: center.y + dy)
        bands[bandIndex(lit, count: shades.count)].addEllipse(
          in: CGRect(x: dot.x - radius, y: dot.y - radius, width: radius * 2, height: radius * 2))
      }
      for index in bands.indices {
        context.fill(bands[index], with: .color(shades[index].opacity(style.stippleOpacity)))
      }
    }
  }
}

/// Outward fibers straddling the contour, drawn unclipped for a fuzzy edge, lit by
/// the same model so the fringe matches the body.
private struct MarimoRimFuzz: View {
  let geometry: MarimoGeometry
  let shades: [Color]
  let style: MarimoStyle

  var body: some View {
    Canvas { context, size in
      var rng = SplitMix64Generator(seed: geometry.seed ^ 0xF022_2222)
      let center = geometry.center(in: size)
      let base = geometry.baseRadius(in: size)

      var bands = [Path](repeating: Path(), count: shades.count)

      // Explicit `Double`/`CGPoint` annotations below split what was previously one
      // large inferred expression per line — on this toolchain, the combined
      // overload resolution for the un-annotated arithmetic took over 10s ("unable
      // to type-check this expression in reasonable time").
      for _ in 0..<style.fuzzCount {
        let angle: Double = Double.random(in: 0..<(2 * .pi), using: &rng)
        let anchor: CGPoint = geometry.outlinePoint(at: angle, in: size)
        let outwardJitter: Double = Double.random(
          in: -style.fuzzOutwardJitter...style.fuzzOutwardJitter, using: &rng)
        let outward: Double = angle + outwardJitter
        let length: Double =
          base * biasedRandom(style.fuzzLength, bias: style.fuzzLengthBias, using: &rng)
        let dxOut: Double = cos(outward) * length
        let dyOut: Double = sin(outward) * length
        let start = CGPoint(
          x: anchor.x - dxOut * style.fuzzInsetFraction,
          y: anchor.y - dyOut * style.fuzzInsetFraction)
        let end = CGPoint(
          x: anchor.x + dxOut * (1 - style.fuzzInsetFraction),
          y: anchor.y + dyOut * (1 - style.fuzzInsetFraction))

        let lit: Double = sphereDiffuse(
          dx: anchor.x - center.x, dy: anchor.y - center.y, radius: base, style: style)
        addSegment(to: &bands[bandIndex(lit, count: shades.count)], start, end)
      }

      strokeBands(
        bands, shades: shades, opacity: style.fuzzOpacity, width: style.fuzzWidth,
        into: context)
    }
  }
}

/// Fine speckle clipped to the body, for matte micro-noise.
private struct MarimoGrain: View {
  let geometry: MarimoGeometry
  let dark: Color
  let style: MarimoStyle

  var body: some View {
    Canvas { context, size in
      context.clip(to: geometry.path(in: size))
      var rng = SplitMix64Generator(seed: geometry.seed ^ 0x6261_4E33)
      let center = geometry.center(in: size)
      let base = geometry.baseRadius(in: size)

      var dots = Path()
      for _ in 0..<style.grainCount {
        let position: Double = Double.random(in: 0...1, using: &rng).squareRoot() * base
        let angle: Double = Double.random(in: 0..<(2 * .pi), using: &rng)
        let dot = CGPoint(x: center.x + cos(angle) * position, y: center.y + sin(angle) * position)
        let radius: Double = style.grainDotRadius
        dots.addEllipse(
          in: CGRect(x: dot.x - radius, y: dot.y - radius, width: radius * 2, height: radius * 2))
      }
      context.fill(dots, with: .color(dark))
    }
  }
}

// MARK: - Helpers

/// Diffuse lighting at a planar offset within the marimo, treated as a sphere.
///
/// Reconstructs the sphere normal from the offset (the front-facing `z` falls off
/// toward the rim), dots it with the light direction, and adds an ambient floor so
/// the shadow side stays a soft matte green rather than going black. Returns a
/// `0...1` tone for the shade ramp. `nonisolated` for use inside `Canvas`.
private nonisolated func sphereDiffuse(
  dx: Double, dy: Double, radius: Double, style: MarimoStyle
) -> Double {
  guard radius > 0 else { return 0.5 }
  let nx = dx / radius
  let ny = dy / radius
  let planar = nx * nx + ny * ny
  let nz = planar < 1 ? (1 - planar).squareRoot() : 0
  let light = style.lightDirection
  let diffuse = max(0, nx * light.x + ny * light.y + nz * light.z)
  return min(1, style.ambient + (1 - style.ambient) * diffuse)
}

/// Maps a `0...1` tone to a shade-band index.
private nonisolated func bandIndex(_ t: Double, count: Int) -> Int {
  let scaled = Int((min(max(t, 0), 1) * Double(count - 1)).rounded())
  return min(max(scaled, 0), count - 1)
}

/// Strokes each shade band's accumulated path once, in order, into the context.
private nonisolated func strokeBands(
  _ bands: [Path], shades: [Color], opacity: Double, width: Double, into context: GraphicsContext
) {
  let strokeStyle = StrokeStyle(lineWidth: width, lineCap: .round)
  for index in bands.indices {
    context.stroke(bands[index], with: .color(shades[index].opacity(opacity)), style: strokeStyle)
  }
}

/// Draws a value in `range`, biased toward the lower bound by `bias` (1 = uniform,
/// higher = mostly low with a few high), so lengths look organic, not uniform.
private nonisolated func biasedRandom(
  _ range: ClosedRange<Double>, bias: Double, using rng: inout SplitMix64Generator
) -> Double {
  let t = pow(Double.random(in: 0...1, using: &rng), bias)
  return range.lowerBound + (range.upperBound - range.lowerBound) * t
}

/// A cheap, seeded, smooth 2D field built from a few sine octaves, used both as a
/// low-frequency clump field (denser/sparser tone patches) and a flow field
/// (coherent fiber direction). Values land roughly in `-1...1`.
///
/// `nonisolated`: pure math, evaluated inside `Canvas` closures.
private nonisolated struct FlowNoise {
  private let terms: [(fx: Double, fy: Double, px: Double, py: Double, weight: Double)]
  private let totalWeight: Double

  init(seed: UInt64, frequency: Double, octaves: Int) {
    var rng = SplitMix64Generator(seed: seed)
    var terms: [(fx: Double, fy: Double, px: Double, py: Double, weight: Double)] = []
    var total = 0.0
    for octave in 0..<max(octaves, 1) {
      let baseFrequency = frequency * Double(octave + 1)
      let weight = 1.0 / Double(octave + 1)
      terms.append(
        (
          fx: baseFrequency * (0.7 + 0.6 * Double.random(in: 0..<1, using: &rng)),
          fy: baseFrequency * (0.7 + 0.6 * Double.random(in: 0..<1, using: &rng)),
          px: Double.random(in: 0..<(2 * .pi), using: &rng),
          py: Double.random(in: 0..<(2 * .pi), using: &rng),
          weight: weight
        ))
      total += weight
    }
    self.terms = terms
    self.totalWeight = total
  }

  func value(_ x: Double, _ y: Double) -> Double {
    var sum = 0.0
    for term in terms {
      sum += term.weight * sin(term.fx * x + term.px) * sin(term.fy * y + term.py)
    }
    return sum / totalWeight
  }
}

/// Appends one line segment to a shared path, so many fibers batch into a single
/// stroke. `nonisolated` for use inside `Canvas` closures.
private nonisolated func addSegment(to path: inout Path, _ start: CGPoint, _ end: CGPoint) {
  path.move(to: start)
  path.addLine(to: end)
}

/// Interpolates between two angles the short way around the circle, so blending a
/// random direction toward the radial never swings the long way through 2π.
private nonisolated func lerpAngle(_ from: Double, _ to: Double, _ t: Double) -> Double {
  var delta = (to - from).truncatingRemainder(dividingBy: 2 * .pi)
  if delta > .pi { delta -= 2 * .pi }
  if delta < -.pi { delta += 2 * .pi }
  return from + delta * t
}

/// Small deterministic PRNG so texture placement is seeded and reproducible
/// without pulling the domain's private generator into the view layer.
///
/// `nonisolated`: constructed and advanced inside `Canvas` closures and noise
/// fields, all outside the main actor.
private nonisolated struct SplitMix64Generator: RandomNumberGenerator {
  private var state: UInt64

  init(seed: UInt64) { state = seed }

  mutating func next() -> UInt64 {
    state = state &+ 0x9E37_79B9_7F4A_7C15
    var z = state
    z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
    z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
    return z ^ (z >> 31)
  }
}

// MARK: - Previews

/// Marks the marimo onto a card matching the Home surface, so contrast and the
/// fibrous edge read the way they will in place.
private struct MarimoSampleCard: View {
  let title: String
  let parameters: MarimoParameters

  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      Text(title)
        .font(.headline)
      MarimoView(parameters: parameters)
        .frame(maxWidth: .infinity)
        .frame(height: 200)
    }
    .padding()
    .background(.background.secondary, in: RoundedRectangle(cornerRadius: 20))
    .padding()
  }
}

private func sampleParameters(
  size: Double, color: Double, bumpiness: Double, seed: UInt64
) -> MarimoParameters {
  MarimoParameters(
    sizeUnit: size, colorLevel: color, bumpiness: bumpiness, seed: seed, totalSteps: 0)
}

#Preview("Interactive") {
  @Previewable @State var sizeUnit = 1.0
  @Previewable @State var colorLevel = 2.5
  @Previewable @State var bumpiness = 0.17
  @Previewable @State var seed = 6.0

  ScrollView {
    VStack(spacing: 20) {
      MarimoView(
        parameters: sampleParameters(
          size: sizeUnit, color: colorLevel, bumpiness: bumpiness, seed: UInt64(seed))
      )
      .frame(height: 240)
      .frame(maxWidth: .infinity)
      .background(.background.secondary, in: RoundedRectangle(cornerRadius: 20))

      VStack(alignment: .leading, spacing: 4) {
        labeledSlider("Size", value: $sizeUnit, range: 0.12...1)
        labeledSlider("Color", value: $colorLevel, range: 0...8)
        labeledSlider("Bumpiness", value: $bumpiness, range: 0...1)
        labeledSlider("Seed", value: $seed, range: 0...20, step: 1)
      }
    }
    .padding()
  }
}

@ViewBuilder
private func labeledSlider(
  _ title: String, value: Binding<Double>, range: ClosedRange<Double>, step: Double = 0.01
) -> some View {
  HStack {
    Text(title)
      .font(.caption)
      .frame(width: 80, alignment: .leading)
    Slider(value: value, in: range, step: step)
    Text(value.wrappedValue.formatted(.number.precision(.fractionLength(step < 1 ? 2 : 0))))
      .font(.caption.monospacedDigit())
      .frame(width: 44, alignment: .trailing)
  }
}

#Preview("On card · Light") {
  VStack {
    MarimoSampleCard(
      title: "Early month",
      parameters: sampleParameters(size: 0.25, color: 1, bumpiness: 0.25, seed: 6)
    )
    MarimoSampleCard(
      title: "Strong month",
      parameters: sampleParameters(size: 0.9, color: 3.4, bumpiness: 0.55, seed: 6))
  }
  .preferredColorScheme(.light)
}

#Preview("On card · Dark") {
  VStack {
    MarimoSampleCard(
      title: "Early month",
      parameters: sampleParameters(size: 0.25, color: 1, bumpiness: 0.25, seed: 6)
    )
    MarimoSampleCard(
      title: "Strong month",
      parameters: sampleParameters(size: 0.9, color: 3.4, bumpiness: 0.55, seed: 6))
  }
  .preferredColorScheme(.dark)
}
