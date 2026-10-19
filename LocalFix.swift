import Carbon
import Foundation
import FoundationModels
import NaturalLanguage

func keyboardLanguages() -> [String] {
    let filter = [kTISPropertyInputSourceCategory as String: kTISCategoryKeyboardInputSource as String,
                  kTISPropertyInputSourceIsEnabled as String: true] as CFDictionary
    guard let list = TISCreateInputSourceList(filter, false)?.takeRetainedValue() as? [TISInputSource] else { return [] }
    var codes: [String] = []
    for source in list {
        guard let raw = TISGetInputSourceProperty(source, kTISPropertyInputSourceLanguages),
              let langs = Unmanaged<CFArray>.fromOpaque(raw).takeUnretainedValue() as? [String],
              let first = langs.first,
              let code = Locale(identifier: first).language.languageCode?.identifier,
              !codes.contains(code) else { continue }
        codes.append(code)
    }
    return codes
}

func vocabulary() -> [String] {
    (ProcessInfo.processInfo.environment["FIXER_VOCAB"] ?? "")
        .split(whereSeparator: { $0 == "," || $0 == "\n" })
        .map { $0.trimmingCharacters(in: .whitespaces) }
        .filter { !$0.isEmpty }
}

func replace(_ text: String, _ pattern: String, options: NSRegularExpression.Options = [],
             _ transform: (NSTextCheckingResult, NSString) -> String?) -> String {
    guard let re = try? NSRegularExpression(pattern: pattern, options: options) else { return text }
    let ns = text as NSString
    var out = ""
    var last = 0
    for m in re.matches(in: text, range: NSRange(location: 0, length: ns.length)) {
        out += ns.substring(with: NSRange(location: last, length: m.range.location - last))
        out += transform(m, ns) ?? ns.substring(with: m.range)
        last = m.range.location + m.range.length
    }
    out += ns.substring(from: last)
    return out
}

func isProtected(_ word: String, vocab: [String]) -> Bool {
    let lower = word.lowercased()
    if lower.hasPrefix("http") || lower.hasPrefix("www") { return true }
    if word.contains(where: { $0 == "_" || $0 == "/" || $0 == "@" || $0 == "#" || $0 == "`" || $0.isNumber }) { return true }
    if word.dropLast().contains(".") { return true }
    return vocab.contains(where: { $0 == word.trimmingCharacters(in: .punctuationCharacters) })
}

func stripPreamble(_ text: String) -> String {
    var t = text.trimmingCharacters(in: .whitespacesAndNewlines)
    t = replace(t, "^(?:here(?:'s| is)|sure|certainly|rewritten|corrected|revised)[^\\n]*:[ \\t]*\\n+", options: [.caseInsensitive]) { _, _ in "" }
    if t.count >= 2, let f = t.first, let l = t.last, (f == "\"" && l == "\"") || (f == "“" && l == "”") {
        t = String(t.dropFirst().dropLast())
    }
    return t
}

func ensureFinalStop(_ text: String, vocab: [String]) -> String {
    guard let last = text.last, last.isLetter else { return text }
    let lastLine = text.split(separator: "\n").last.map(String.init) ?? text
    let words = lastLine.split(separator: " ")
    guard words.count >= 3, let lastWord = words.last, !isProtected(String(lastWord), vocab: []) else { return text }
    return text + "."
}

func postProcess(_ input: String) -> String {
    let vocab = vocabulary()
    var t = stripPreamble(input)

    for w in vocab {
        let escaped = NSRegularExpression.escapedPattern(for: w)
        t = replace(t, "(?<![\\p{L}\\p{N}_@#/.\\-])\(escaped)(?![\\p{L}\\p{N}_])", options: [.caseInsensitive]) { _, _ in w }
    }

    t = replace(t, "(?<![\\p{L}\\p{N}_'’/@#.\\-])i(?=\\s|[,!?;:]|['’](?:m|d|ll|ve)\\b|\\.(?!\\w)|$)") { _, _ in "I" }

    t = replace(t, "(^|\\n|(?<!\\b(?:e\\.g|i\\.e|etc|vs|approx|incl|Mr|Mrs|Ms|Dr|St))[.!?]+[\"”’)]?\\s+)(\\p{Ll})(?=([^\\s]*))",
                options: [.anchorsMatchLines]) { m, ns in
        let lead = ns.substring(with: m.range(at: 1))
        let first = ns.substring(with: m.range(at: 2))
        let word = first + ns.substring(with: m.range(at: 3))
        if isProtected(word, vocab: vocab) { return nil }
        return lead + first.uppercased()
    }
    return ensureFinalStop(t, vocab: vocab)
}

func language(of text: String) -> NLLanguage? {
    let r = NLLanguageRecognizer()
    r.processString(text)
    return r.dominantLanguage
}

func languageName(_ lang: NLLanguage) -> String {
    Locale(identifier: "en").localizedString(forLanguageCode: lang.rawValue) ?? lang.rawValue
}

func ask(_ model: SystemLanguageModel, _ instructions: String, _ input: String) async throws -> String {
    let session = LanguageModelSession(model: model, instructions: instructions)
    let response = try await session.respond(
        to: "Text to rewrite:\n\(input)",
        options: GenerationOptions(temperature: 0.1)
    )
    return response.content.trimmingCharacters(in: .whitespacesAndNewlines)
}

@main
struct LocalFix {
    static func main() async {
        let input = String(decoding: FileHandle.standardInput.readDataToEndOfFile(), as: UTF8.self)

        if CommandLine.arguments.contains("--info") {
            let m = SystemLanguageModel.default
            let ready: String
            switch m.availability {
            case .available: ready = "ready"
            case .unavailable(.appleIntelligenceNotEnabled): ready = "notEnabled"
            case .unavailable(.deviceNotEligible): ready = "notEligible"
            case .unavailable(.modelNotReady): ready = "notReady"
            case .unavailable(let other): ready = "unavailable: \(other)"
            }
            let en = Locale(identifier: "en")
            let langs = m.supportedLanguages
                .compactMap { $0.languageCode.flatMap { en.localizedString(forLanguageCode: $0.identifier) } }
            let supported = Set(m.supportedLanguages.compactMap { $0.languageCode?.identifier })
            let keyboard = keyboardLanguages().map { code in
                "\(en.localizedString(forLanguageCode: code) ?? code):\(supported.contains(code) ? "yes" : "no")"
            }
            print("status=\(ready)")
            print("context=\(m.contextSize)")
            print("languages=\(Set(langs).sorted().joined(separator: ", "))")
            print("keyboard=\(keyboard.joined(separator: ","))")
            return
        }

        if CommandLine.arguments.contains("--post") {
            print(postProcess(input), terminator: "")
            return
        }

        let instructions = ProcessInfo.processInfo.environment["FIXER_SP"]
            ?? "Fix spelling, grammar and punctuation. Output only the corrected text."
        let model = SystemLanguageModel.default
        guard case .available = model.availability else {
            fputs("apple model unavailable: \(model.availability)\n", stderr)
            exit(2)
        }
        do {
            guard let lang = language(of: input) else {
                print(try await ask(model, instructions, input), terminator: "")
                return
            }
            let name = languageName(lang)
            let pinned = instructions + "\n\nThe text is written in \(name). Write the result in \(name) only. Never translate it."
            var out = try await ask(model, pinned, input)
            if language(of: out) != lang {
                out = try await ask(model, pinned + " Translating is an error.", input)
            }
            if language(of: out) != lang {
                out = postProcess(input)
            }
            print(out, terminator: "")
        } catch {
            fputs("apple model error: \(error)\n", stderr)
            exit(1)
        }
    }
}
