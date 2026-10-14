import Foundation

/// Converts "JSON with comments" into strict JSON by removing `//` and `/* */` comments
/// and trailing commas before `}` or `]`. String literals are left untouched.
///
/// Comments are replaced with spaces (newlines are kept) so parser error offsets and line
/// numbers still point at the right place in the original file.
public enum JSONC {
    public static func strip(_ source: String) -> String {
        let withoutComments = stripComments(Array(source))
        return String(stripTrailingCommas(withoutComments))
    }

    private static func stripComments(_ input: [Character]) -> [Character] {
        var output: [Character] = []
        output.reserveCapacity(input.count)
        var i = 0
        var inString = false

        while i < input.count {
            let c = input[i]
            let next: Character? = i + 1 < input.count ? input[i + 1] : nil

            if inString {
                output.append(c)
                if c == "\\", let next {
                    output.append(next)
                    i += 2
                    continue
                }
                if c == "\"" { inString = false }
                i += 1
                continue
            }

            if c == "\"" {
                inString = true
                output.append(c)
                i += 1
            } else if c == "/" && next == "/" {
                while i < input.count && !input[i].isNewline {
                    output.append(" ")
                    i += 1
                }
            } else if c == "/" && next == "*" {
                output.append(contentsOf: "  ")
                i += 2
                while i < input.count && !(input[i] == "*" && i + 1 < input.count && input[i + 1] == "/") {
                    output.append(input[i].isNewline ? input[i] : " ")
                    i += 1
                }
                if i < input.count {
                    output.append(contentsOf: "  ")
                    i += 2
                }
            } else {
                output.append(c)
                i += 1
            }
        }
        return output
    }

    private static func stripTrailingCommas(_ input: [Character]) -> [Character] {
        var output = input
        var inString = false
        var i = 0
        while i < output.count {
            let c = output[i]
            if inString {
                if c == "\\" {
                    i += 2
                    continue
                }
                if c == "\"" { inString = false }
            } else if c == "\"" {
                inString = true
            } else if c == "," {
                var j = i + 1
                while j < output.count && output[j].isWhitespace { j += 1 }
                if j < output.count && (output[j] == "}" || output[j] == "]") {
                    output[i] = " "
                }
            }
            i += 1
        }
        return output
    }
}
