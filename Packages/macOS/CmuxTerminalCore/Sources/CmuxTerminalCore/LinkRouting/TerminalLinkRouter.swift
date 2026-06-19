import Foundation
#if DEBUG
import CMUXDebugLog
#endif

/// Routes a link activated inside a terminal to the embedded browser or the
/// system.
///
/// Routing precedence, preserved exactly from the legacy resolver: absolute
/// file-system paths open externally; `http`/`https` URLs open embedded when
/// the injected ``BrowserHostNormalizing`` accepts their host, externally
/// otherwise; other schemes open externally; scheme-less text that the
/// browser can navigate (bare domains, localhost) opens embedded subject to
/// the same host check; anything else falls back to an external URL when it
/// parses at all.
public struct TerminalLinkRouter: Sendable {
    private let hostNormalizer: any BrowserHostNormalizing
    private static let schemeLessFileExtensions: Set<String> = [
        "app", "bash", "c", "cc", "cfg", "conf", "cpp", "css", "csv", "cxx",
        "diff", "env", "fish", "go", "gradle", "h", "hpp", "htm", "html", "ini",
        "ipynb", "java", "js", "json", "jsx", "kt", "kts", "less", "lock", "log",
        "m", "markdown", "md", "mm", "patch", "php", "pl", "pm", "proto", "py",
        "pyw", "rb", "rs", "sass", "scss", "sh", "sql", "svelte", "swift", "toml",
        "ts", "tsx", "txt", "vue", "xml", "yaml", "yml", "zsh"
    ]

    /// Creates a router that validates web hosts through the browser domain.
    ///
    /// - Parameter hostNormalizer: The browser-domain host validation seam.
    public init(hostNormalizer: any BrowserHostNormalizing) {
        self.hostNormalizer = hostNormalizer
    }

    /// Resolves raw link text into an open target.
    ///
    /// - Parameter rawValue: The raw link text from the runtime or UI.
    /// - Returns: The routing decision, or `nil` for empty or unparseable
    ///   text.
    public func resolveOpenURLTarget(_ rawValue: String) -> TerminalOpenURLTarget? {
        let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        #if DEBUG
        logDebugEvent("link.resolve input=\(trimmed)")
        #endif
        guard !trimmed.isEmpty else {
            #if DEBUG
            logDebugEvent("link.resolve result=nil (empty)")
            #endif
            return nil
        }

        if NSString(string: trimmed).isAbsolutePath {
            #if DEBUG
            logDebugEvent("link.resolve result=external(absolutePath) url=\(trimmed)")
            #endif
            return .external(URL(fileURLWithPath: trimmed))
        }

        if Self.isSchemeLessFileToken(trimmed) {
            #if DEBUG
            logDebugEvent("link.resolve result=nil (schemeLessFileToken) url=\(trimmed)")
            #endif
            return nil
        }

        if let parsed = URL(string: trimmed),
           let scheme = parsed.scheme?.lowercased() {
            if scheme == "http" || scheme == "https" {
                guard hostNormalizer.normalizedHost(parsed.host ?? "") != nil else {
                    #if DEBUG
                    logDebugEvent("link.resolve result=external(invalidHost) url=\(parsed)")
                    #endif
                    return .external(parsed)
                }
                #if DEBUG
                logDebugEvent("link.resolve result=embeddedBrowser url=\(parsed)")
                #endif
                return .embeddedBrowser(parsed)
            }
            #if DEBUG
            logDebugEvent("link.resolve result=external(scheme=\(scheme)) url=\(parsed)")
            #endif
            return .external(parsed)
        }

        if let webURL = hostNormalizer.navigableWebURL(trimmed) {
            guard hostNormalizer.normalizedHost(webURL.host ?? "") != nil else {
                #if DEBUG
                logDebugEvent("link.resolve result=external(bareHost-invalidHost) url=\(webURL)")
                #endif
                return .external(webURL)
            }
            #if DEBUG
            logDebugEvent("link.resolve result=embeddedBrowser(bareHost) url=\(webURL)")
            #endif
            return .embeddedBrowser(webURL)
        }

        guard let fallback = URL(string: trimmed) else {
            #if DEBUG
            logDebugEvent("link.resolve result=nil (unparseable)")
            #endif
            return nil
        }
        #if DEBUG
        logDebugEvent("link.resolve result=external(fallback) url=\(fallback)")
        #endif
        return .external(fallback)
    }

    private static func isSchemeLessFileToken(_ value: String) -> Bool {
        let stripped = stripFragmentAndQuery(value)
        guard !stripped.isEmpty,
              stripped.rangeOfCharacter(from: .whitespacesAndNewlines) == nil,
              URL(string: stripped)?.scheme == nil else {
            return false
        }
        let ext = (stripped as NSString).pathExtension.lowercased()
        return !ext.isEmpty && schemeLessFileExtensions.contains(ext)
    }

    private static func stripFragmentAndQuery(_ value: String) -> String {
        var stripped = value
        if let hashIndex = stripped.firstIndex(of: "#") {
            stripped = String(stripped[..<hashIndex])
        }
        if let questionMarkIndex = stripped.firstIndex(of: "?") {
            stripped = String(stripped[..<questionMarkIndex])
        }
        if let lineSuffixRange = stripped.range(
            of: #":\d+(?::\d+)?$"#,
            options: .regularExpression
        ) {
            stripped.removeSubrange(lineSuffixRange)
        }
        return stripped
    }
}
