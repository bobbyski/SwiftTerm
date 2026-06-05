import Foundation

/// Tiny parser for the constrained VTG path grammar.
///
/// Supported commands intentionally mirror the common SVG command names but only
/// absolute coordinates are accepted in this first pass: `M`, `L`, `Q`, `C`,
/// and `Z`.
enum VTGPathParser {
    static func parse(_ payload: String) -> [VTGPathCommand]? {
        let tokens = tokenize(payload)
        guard tokens.isEmpty == false else {
            return nil
        }
        var index = 0
        var commands: [VTGPathCommand] = []

        func nextNumber() -> Double? {
            guard index < tokens.count, let value = Double(tokens[index]) else {
                return nil
            }
            index += 1
            return value
        }

        func nextPoint() -> VTGPoint? {
            guard let x = nextNumber(), let y = nextNumber() else {
                return nil
            }
            return VTGPoint(x: x, y: y)
        }

        while index < tokens.count {
            let token = tokens[index].uppercased()
            index += 1
            switch token {
            case "M":
                guard let point = nextPoint() else { return nil }
                commands.append(.move(to: point))
            case "L":
                guard let point = nextPoint() else { return nil }
                commands.append(.line(to: point))
            case "Q":
                guard let control = nextPoint(), let end = nextPoint() else { return nil }
                commands.append(.quadratic(control: control, end: end))
            case "C":
                guard let control1 = nextPoint(), let control2 = nextPoint(), let end = nextPoint() else { return nil }
                commands.append(.cubic(control1: control1, control2: control2, end: end))
            case "Z":
                commands.append(.close)
            default:
                return nil
            }
        }
        return commands
    }

    private static func tokenize(_ payload: String) -> [String] {
        var expanded = ""
        for character in payload {
            if "MLQCZmlqcz".contains(character) {
                expanded.append(" ")
                expanded.append(character)
                expanded.append(" ")
            } else if character == "," || character.isWhitespace {
                expanded.append(" ")
            } else {
                expanded.append(character)
            }
        }
        return expanded.split(separator: " ").map(String.init)
    }
}
