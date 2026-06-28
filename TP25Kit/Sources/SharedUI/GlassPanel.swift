import SwiftUI

/// Dark-first "lighting console" design language: glass panels on a deep
/// near-black backdrop with subtle strokes.
public struct ConsolePalette {
    public static let backdrop = Color(red: 0.05, green: 0.05, blue: 0.07)
    public static let panelStroke = Color.white.opacity(0.08)
    public static let accent = Color(red: 1.0, green: 0.62, blue: 0.26) // tungsten amber
    public static let dimText = Color.white.opacity(0.55)
}

public struct GlassPanel<Content: View>: View {
    private let content: Content

    public init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    public var body: some View {
        content
            .padding(16)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .strokeBorder(ConsolePalette.panelStroke, lineWidth: 1)
            )
    }
}

/// Section header in the console style.
public struct PanelHeader: View {
    let title: String
    let systemImage: String

    public init(_ title: String, systemImage: String) {
        self.title = title
        self.systemImage = systemImage
    }

    public var body: some View {
        Label(title, systemImage: systemImage)
            .font(.footnote.weight(.semibold))
            .textCase(.uppercase)
            .foregroundStyle(ConsolePalette.dimText)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Labelled slider used across brightness / CCT / HSI controls.
public struct ConsoleSlider: View {
    let label: String
    @Binding var value: Double
    let range: ClosedRange<Double>
    let format: (Double) -> String
    let onCommit: () -> Void

    public init(_ label: String, value: Binding<Double>, in range: ClosedRange<Double>,
                format: @escaping (Double) -> String = { "\(Int($0))" },
                onCommit: @escaping () -> Void = {}) {
        self.label = label
        self._value = value
        self.range = range
        self.format = format
        self.onCommit = onCommit
    }

    public var body: some View {
        VStack(spacing: 4) {
            HStack {
                Text(label).font(.subheadline)
                Spacer()
                Text(format(value))
                    .font(.subheadline.monospacedDigit().weight(.medium))
                    .foregroundStyle(ConsolePalette.accent)
            }
            Slider(value: $value, in: range) { editing in
                if !editing { onCommit() }
            }
            .tint(ConsolePalette.accent)
        }
    }
}

/// RSSI signal bars.
public struct SignalStrengthView: View {
    let rssi: Int

    public init(rssi: Int) { self.rssi = rssi }

    private var bars: Int {
        switch rssi {
        case (-55)...: 4
        case (-67)...: 3
        case (-80)...: 2
        case (-95)...: 1
        default: 0
        }
    }

    public var body: some View {
        HStack(alignment: .bottom, spacing: 2) {
            ForEach(0..<4, id: \.self) { i in
                RoundedRectangle(cornerRadius: 1)
                    .fill(i < bars ? ConsolePalette.accent : Color.white.opacity(0.15))
                    .frame(width: 3, height: CGFloat(4 + i * 3))
            }
        }
        .accessibilityLabel("Signal \(bars) of 4")
    }
}
