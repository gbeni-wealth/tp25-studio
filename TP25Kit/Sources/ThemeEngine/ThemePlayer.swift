import Foundation
import ProtocolEngine
import Observation

/// Plays a Theme (or the random engine) as a stream of colours.
/// Output is a plain callback so the same player drives real lights,
/// the Theme Studio preview, and unit tests.
@Observable
public final class ThemePlayer {
    public private(set) var isPlaying = false
    public private(set) var currentColor: LightColor = .white
    public private(set) var activeThemeName: String?

    /// Receives every colour step. Wire this to FleetController in the apps.
    public var onColor: ((LightColor) -> Void)?
    /// Seconds between interpolation steps while fading (BLE write budget).
    public var stepInterval: Double = 0.1

    private var task: Task<Void, Never>?

    public init() {}

    public func play(theme: Theme) {
        stop()
        activeThemeName = theme.name
        isPlaying = true
        task = Task { [weak self] in
            await self?.runLoop(theme: theme)
        }
    }

    public func play(random engine: RandomColourEngine) {
        stop()
        activeThemeName = "Random · \(engine.config.palette.displayName)"
        isPlaying = true
        task = Task { [weak self] in
            await self?.runRandomLoop(engine: engine)
        }
    }

    public func stop() {
        task?.cancel()
        task = nil
        isPlaying = false
        activeThemeName = nil
    }

    // MARK: Loops

    private func runLoop(theme: Theme) async {
        guard !theme.palette.isEmpty else { return }
        var order = Array(theme.palette.indices)
        var index = 0
        var previous = theme.palette[0]
        emit(previous)

        while !Task.isCancelled {
            if theme.motion == .shuffle, index % order.count == 0 {
                order.shuffle()
            }
            let next = theme.palette[order[index % order.count]]
            index += 1

            switch theme.motion {
            case .suddenJump:
                emit(next)
            case .smoothFade, .shuffle:
                await fade(from: previous, to: next, duration: theme.transitionDuration)
            case .breathe:
                var dimmed = previous
                dimmed.intensity *= 0.15
                await fade(from: previous, to: dimmed, duration: theme.transitionDuration / 2)
                await fade(from: dimmed, to: next, duration: theme.transitionDuration / 2)
            }
            previous = next
            await sleep(theme.holdDuration)
        }
    }

    private func runRandomLoop(engine: RandomColourEngine) async {
        var previous = engine.next()
        emit(previous)
        while !Task.isCancelled {
            await sleep(engine.config.holdDuration)
            let next = engine.next()
            if engine.config.smoothFades {
                await fade(from: previous, to: next, duration: engine.config.transitionDuration)
            } else {
                emit(next)
            }
            previous = next
        }
    }

    private func fade(from: LightColor, to: LightColor, duration: Double) async {
        guard duration > stepInterval else { emit(to); return }
        let steps = max(2, Int(duration / stepInterval))
        for step in 1...steps {
            if Task.isCancelled { return }
            emit(LightColor.lerp(from, to, t: Double(step) / Double(steps)))
            await sleep(duration / Double(steps))
        }
    }

    private func emit(_ color: LightColor) {
        currentColor = color
        onColor?(color)
    }

    private func sleep(_ seconds: Double) async {
        try? await Task.sleep(nanoseconds: UInt64(max(0, seconds) * 1_000_000_000))
    }
}
