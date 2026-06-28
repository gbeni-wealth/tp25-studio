import Foundation
import ProtocolEngine

/// Parses developer-console input into raw bytes.
/// Supported forms:
///   hex:   "7E 00 04 01 EF", "0x56,0xFF…", "7e0004…"
///   utf8:  `"hello"` or `utf8:hello`
///   preset test commands: `power-on@neewer`, `red@elk`, `bright-30@triones`
public enum ConsoleCommand {
    public enum ParseResult {
        case data(Data, description: String)
        case error(String)
    }

    public static func parse(_ input: String) -> ParseResult {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return .error("Empty command") }

        // AT command: `at:AT+STAT` → sends "AT+STAT\r\n" (TP25-class text protocol)
        if trimmed.lowercased().hasPrefix("at:") {
            let body = String(trimmed.dropFirst(3))
            let withCRLF = body + "\r\n"
            return .data(Data(withCRLF.utf8), description: "AT \"\(body)\" + CRLF")
        }

        // UTF-8 literals (supports \r \n \t escapes for line-terminated protocols)
        if trimmed.hasPrefix("\""), trimmed.hasSuffix("\""), trimmed.count >= 2 {
            let text = unescape(String(trimmed.dropFirst().dropLast()))
            return .data(Data(text.utf8), description: "UTF-8 \(text.debugDescription)")
        }
        if trimmed.lowercased().hasPrefix("utf8:") {
            let text = unescape(String(trimmed.dropFirst(5)))
            return .data(Data(text.utf8), description: "UTF-8 \(text.debugDescription)")
        }

        // Preset test commands: <name>@<family>
        if trimmed.contains("@") {
            return parsePreset(trimmed)
        }

        // Hex
        if let data = Data(hexInput: trimmed) {
            return .data(data, description: "hex \(data.hexString)")
        }
        return .error("Could not parse as hex. Use e.g. 7E 00 04 01 EF, \"text\", or power-on@neewer")
    }

    /// Turn literal "\r" "\n" "\t" sequences into real control characters.
    private static func unescape(_ s: String) -> String {
        s.replacingOccurrences(of: "\\r", with: "\r")
            .replacingOccurrences(of: "\\n", with: "\n")
            .replacingOccurrences(of: "\\t", with: "\t")
    }

    private static func parsePreset(_ input: String) -> ParseResult {
        let parts = input.lowercased().split(separator: "@")
        guard parts.count == 2 else { return .error("Format: <command>@<family>") }
        let family: ProtocolFamily? = switch parts[1] {
        case "neewer", "neewerstyle": .neewerStyle
        case "elk", "bledom", "elkbledom": .elkBledom
        case "triones", "happylighting": .triones
        default: nil
        }
        guard let family else {
            return .error("Unknown family '\(parts[1])'. Use neewer, elk, or triones")
        }
        let command: LightCommand? = switch parts[0] {
        case "power-on", "on": .power(on: true)
        case "power-off", "off": .power(on: false)
        case "red": .rgb(red: 255, green: 0, blue: 0)
        case "green": .rgb(red: 0, green: 255, blue: 0)
        case "blue": .rgb(red: 0, green: 0, blue: 255)
        case "white": .hsi(color: .white)
        case let cmd where cmd.hasPrefix("bright-"):
            Int(cmd.dropFirst(7)).map { LightCommand.brightness(percent: $0) }
        case let cmd where cmd.hasPrefix("cct-"):
            Int(cmd.dropFirst(4)).map { LightCommand.cct(temperature: .init(kelvin: $0), brightness: 50) }
        default: nil
        }
        guard let command else {
            return .error("Unknown test command '\(parts[0])'. Try power-on, red, bright-50, cct-5600")
        }
        do {
            let data = try family.encode(command)
            return .data(data, description: "\(parts[0]) via \(family.displayName): \(data.hexString)")
        } catch {
            return .error("\(family.displayName) cannot encode \(parts[0])")
        }
    }
}
