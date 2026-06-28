import Foundation
import ProtocolEngine

/// Continuous random colour generation with creative constraints —
/// a first-class feature, not an afterthought.
public final class RandomColourEngine {
    public enum Palette: String, Codable, CaseIterable, Identifiable, Sendable {
        case fullyRandom, pastel, neon, warm, cool, cinematic
        public var id: String { rawValue }

        public var displayName: String {
            switch self {
            case .fullyRandom: "Fully Random"
            case .pastel: "Pastel"
            case .neon: "Neon"
            case .warm: "Warm"
            case .cool: "Cool"
            case .cinematic: "Cinematic"
            }
        }
    }

    public struct Config: Codable, Hashable, Sendable {
        public var palette: Palette = .fullyRandom
        public var transitionDuration: Double = 2      // fade time
        public var holdDuration: Double = 3            // time on each colour
        public var brightnessRange: ClosedRange<Double> = 0.3...1.0
        public var saturationRange: ClosedRange<Double> = 0.0...1.0
        public var avoidSimilar = true                 // reject colours too close to the last one
        public var avoidRepeats = true                 // reject recent colours
        public var smoothFades = true                  // false = sudden jumps
        /// Hue → weight multipliers for weighted palettes (degrees bucketed by 30°).
        public var hueWeights: [Int: Double] = [:]

        public init() {}
    }

    public var config: Config
    private var recent: [LightColor] = []
    private let recentLimit = 8
    private var generator: SeededGenerator

    public init(config: Config = Config(), seed: UInt64? = nil) {
        self.config = config
        // Seeded SplitMix64 throughout: deterministic when a seed is given
        // (tests), entropy-seeded otherwise.
        self.generator = SeededGenerator(seed: seed ?? UInt64.random(in: .min ... .max))
    }

    /// Next colour honouring all constraints. Falls back to the best candidate
    /// if constraints can't be satisfied after a bounded number of attempts.
    public func next() -> LightColor {
        var best: LightColor?
        var bestScore = -Double.infinity
        for _ in 0..<24 {
            let candidate = generate()
            var score = Double.random(in: 0...0.1, using: &generator)
            if config.avoidSimilar, let last = recent.last {
                let d = candidate.distance(to: last)
                if d < 0.15 { continue }
                score += d
            }
            if config.avoidRepeats {
                let minDist = recent.map { candidate.distance(to: $0) }.min() ?? 1
                if minDist < 0.08 { continue }
                score += minDist * 0.5
            }
            if score > bestScore {
                bestScore = score
                best = candidate
            }
            // Good enough — stop early.
            if score > 0.5 { break }
        }
        let chosen = best ?? generate()
        recent.append(chosen)
        if recent.count > recentLimit { recent.removeFirst() }
        return chosen
    }

    private func generate() -> LightColor {
        let hue = weightedHue()
        let (satRange, intRange) = paletteRanges()
        let sat = clampedRandom(in: intersect(satRange, config.saturationRange))
        let int = clampedRandom(in: intersect(intRange, config.brightnessRange))
        return LightColor(hue: hue, saturation: sat, intensity: int)
    }

    private func paletteRanges() -> (sat: ClosedRange<Double>, int: ClosedRange<Double>) {
        switch config.palette {
        case .fullyRandom: (0.0...1.0, 0.2...1.0)
        case .pastel: (0.2...0.45, 0.7...1.0)
        case .neon: (0.95...1.0, 0.85...1.0)
        case .warm: (0.5...1.0, 0.4...0.9)
        case .cool: (0.4...1.0, 0.4...0.9)
        case .cinematic: (0.45...0.8, 0.25...0.6)
        }
    }

    private func weightedHue() -> Double {
        let hueRange: ClosedRange<Double> = switch config.palette {
        case .warm: -40...60          // red→amber (negative wraps)
        case .cool: 160...280         // teal→violet
        case .cinematic: Bool.random(using: &generator) ? 15...45 : 195...225 // teal & orange
        default: 0...360
        }
        var hue = Double.random(in: hueRange, using: &generator)
        if hue < 0 { hue += 360 }
        // Apply user weights (30° buckets): rejection-sample up to a few tries.
        if !config.hueWeights.isEmpty {
            for _ in 0..<6 {
                let bucket = Int(hue / 30) * 30
                let weight = config.hueWeights[bucket] ?? 1
                if Double.random(in: 0...1, using: &generator) <= weight { break }
                hue = Double.random(in: hueRange, using: &generator)
                if hue < 0 { hue += 360 }
            }
        }
        return hue
    }

    private func intersect(_ a: ClosedRange<Double>, _ b: ClosedRange<Double>) -> ClosedRange<Double> {
        let lower = max(a.lowerBound, b.lowerBound)
        let upper = min(a.upperBound, b.upperBound)
        return lower <= upper ? lower...upper : b
    }

    private func clampedRandom(in range: ClosedRange<Double>) -> Double {
        Double.random(in: range, using: &generator)
    }
}

/// Deterministic RNG (SplitMix64) so tests can pin random sequences.
struct SeededGenerator: RandomNumberGenerator {
    private var state: UInt64
    init(seed: UInt64) { state = seed }
    mutating func next() -> UInt64 {
        state &+= 0x9E3779B97F4A7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9
        z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
        return z ^ (z >> 31)
    }
}
