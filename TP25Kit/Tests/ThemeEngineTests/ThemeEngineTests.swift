import XCTest
@testable import ThemeEngine
import ProtocolEngine

final class RandomColourEngineTests: XCTestCase {
    func testRespectsBrightnessAndSaturationLimits() {
        var config = RandomColourEngine.Config()
        config.brightnessRange = 0.4...0.6
        config.saturationRange = 0.5...0.7
        config.palette = .fullyRandom
        let engine = RandomColourEngine(config: config, seed: 42)
        for _ in 0..<200 {
            let color = engine.next()
            XCTAssertGreaterThanOrEqual(color.intensity, 0.4 - 0.0001)
            XCTAssertLessThanOrEqual(color.intensity, 0.6 + 0.0001)
            XCTAssertGreaterThanOrEqual(color.saturation, 0.5 - 0.0001)
            XCTAssertLessThanOrEqual(color.saturation, 0.7 + 0.0001)
        }
    }

    func testAvoidSimilarKeepsConsecutiveColoursApart() {
        var config = RandomColourEngine.Config()
        config.avoidSimilar = true
        config.avoidRepeats = false
        let engine = RandomColourEngine(config: config, seed: 7)
        var previous: LightColor?
        var farCount = 0
        for _ in 0..<100 {
            let color = engine.next()
            if let previous, color.distance(to: previous) >= 0.15 { farCount += 1 }
            previous = color
        }
        // Constraint is best-effort; expect the vast majority to satisfy it.
        XCTAssertGreaterThan(farCount, 90)
    }

    func testNeonPaletteIsSaturatedAndBright() {
        var config = RandomColourEngine.Config()
        config.palette = .neon
        let engine = RandomColourEngine(config: config, seed: 1)
        for _ in 0..<100 {
            let color = engine.next()
            XCTAssertGreaterThanOrEqual(color.saturation, 0.95 - 0.0001)
            XCTAssertGreaterThanOrEqual(color.intensity, 0.85 - 0.0001)
        }
    }

    func testWarmPaletteStaysInWarmHues() {
        var config = RandomColourEngine.Config()
        config.palette = .warm
        config.avoidSimilar = false
        config.avoidRepeats = false
        let engine = RandomColourEngine(config: config, seed: 3)
        for _ in 0..<100 {
            let hue = engine.next().hue
            XCTAssertTrue(hue <= 60 || hue >= 320, "warm hue out of range: \(hue)")
        }
    }

    func testSeededEngineIsDeterministic() {
        let a = RandomColourEngine(seed: 99)
        let b = RandomColourEngine(seed: 99)
        for _ in 0..<20 {
            XCTAssertEqual(a.next(), b.next())
        }
    }
}

final class ThemeTests: XCTestCase {
    func testBuiltInThemesPresent() {
        let names = Set(BuiltInThemes.all.map(\.name))
        for expected in ["Sunset", "Ocean", "Cyberpunk", "Fire", "Forest",
                         "Studio Warm", "Studio Cool", "Party", "Relax"] {
            XCTAssertTrue(names.contains(expected), "missing theme \(expected)")
        }
        for theme in BuiltInThemes.all {
            XCTAssertFalse(theme.palette.isEmpty, "\(theme.name) has empty palette")
            XCTAssertTrue(theme.isBuiltIn)
        }
    }

    func testThemeCodableRoundTrip() throws {
        let theme = BuiltInThemes.all[0]
        let data = try JSONEncoder().encode(theme)
        let decoded = try JSONDecoder().decode(Theme.self, from: data)
        XCTAssertEqual(decoded, theme)
    }
}

final class ThemePlayerTests: XCTestCase {
    func testPlayerEmitsColours() async throws {
        let player = ThemePlayer()
        player.stepInterval = 0.01
        var received: [LightColor] = []
        let lock = NSLock()
        player.onColor = { color in
            lock.lock()
            received.append(color)
            lock.unlock()
        }
        let theme = Theme(name: "t", palette: [
            LightColor(hue: 0, saturation: 1, intensity: 1),
            LightColor(hue: 120, saturation: 1, intensity: 1),
        ], motion: .smoothFade, transitionDuration: 0.05, holdDuration: 0.02)
        player.play(theme: theme)
        try await Task.sleep(nanoseconds: 300_000_000)
        player.stop()
        lock.lock()
        let count = received.count
        lock.unlock()
        XCTAssertGreaterThan(count, 3, "player should emit interpolated colours")
        XCTAssertFalse(player.isPlaying)
    }
}
