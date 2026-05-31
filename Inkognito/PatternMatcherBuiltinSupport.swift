import Foundation

struct CompiledBuiltinPattern {
    let id: String
    let category: String
    let regex: NSRegularExpression
}

nonisolated enum PatternMatcherBuiltinSupport {
    static func loadCompiledBuiltinPatterns() -> [CompiledBuiltinPattern] {
        guard let rawPatterns = loadRawPatterns() else { return [] }
        return rawPatterns.compactMap(compile)
    }

    private static func loadRawPatterns() -> [[String: Any]]? {
        guard let url = Bundle.main.url(forResource: "patterns", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let patterns = json["patterns"] as? [[String: Any]]
        else {
            return nil
        }
        return patterns
    }

    private static func compile(_ rawPattern: [String: Any]) -> CompiledBuiltinPattern? {
        guard let id = rawPattern["id"] as? String,
              let category = rawPattern["category"] as? String,
              let regexPattern = rawPattern["regex"] as? String
        else {
            return nil
        }

        guard let regex = try? NSRegularExpression(pattern: regexPattern) else {
            print("PatternMatcher: failed to compile pattern '\(id)'")
            return nil
        }

        return CompiledBuiltinPattern(id: id, category: category, regex: regex)
    }
}
