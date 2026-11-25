import Foundation

public enum XHSURLClassifier {
    private static let allowedDomains: [String] = [
        "xiaohongshu.com",
        "xhscdn.com",
        "xhslink.com"
    ]

    /// Determines whether a URL belongs to Xiaohongshu's web ecosystem and should open in-app.
    public static func isAllowedInApp(_ url: URL) -> Bool {
        guard let scheme = url.scheme?.lowercased(),
              scheme == "https" || scheme == "http" || scheme == "about" else {
            return false
        }
        if scheme == "about" { return true }
        guard let host = url.host?.lowercased() else { return false }
        return allowedDomains.contains { domain in
            host == domain || host.hasSuffix("." + domain)
        }
    }

    /// Extracts a 24-character hex Xiaohongshu note ID from explore/discovery/user note URLs.
    public static func extractNoteId(from urlString: String) -> String? {
        guard let url = URL(string: urlString) else { return nil }
        let components = url.pathComponents.filter { $0 != "/" }

        // Matches /explore/<id>, /discovery/item/<id>, /user/profile/<uid>/<id>
        for (idx, part) in components.enumerated() {
            if part == "explore" || part == "item" {
                if idx + 1 < components.count, isLikelyNoteId(components[idx + 1]) {
                    return components[idx + 1]
                }
            }
        }
        if let last = components.last, isLikelyNoteId(last) {
            return last
        }
        return nil
    }

    /// Canonical key used to deduplicate history & collections entries.
    public static func canonicalKey(for urlString: String) -> String {
        if let noteId = extractNoteId(from: urlString) {
            return "note:\(noteId)"
        }
        guard var components = URLComponents(string: urlString) else {
            return urlString
        }
        // Preserve essential query params (like keyword for search) while stripping volatile tracking params
        let keepParams: Set<String> = ["keyword", "channel_id", "xsec_token"]
        if let queryItems = components.queryItems {
            let filtered = queryItems.filter { keepParams.contains($0.name) }
            components.queryItems = filtered.isEmpty ? nil : filtered
        }
        components.fragment = nil
        return components.string ?? urlString
    }

    /// Builds a Xiaohongshu web search URL for a keyword.
    /// Uses trailing slash `/search_result/` to avoid Nginx 301 downgrade to plain HTTP (which ATS blocks).
    public static func searchURL(for keyword: String) -> URL? {
        let trimmed = keyword.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        var components = URLComponents(string: "https://www.xiaohongshu.com/search_result/")
        components?.queryItems = [
            URLQueryItem(name: "keyword", value: trimmed),
            URLQueryItem(name: "source", value: "web_explore_feed"),
            URLQueryItem(name: "type", value: "51")
        ]
        return components?.url
    }

    /// Detects whether a URL is a meaningful note or profile page worth auto-recording in history.
    public static func shouldAutoRecordHistory(urlString: String) -> Bool {
        guard let url = URL(string: urlString), isAllowedInApp(url) else { return false }
        if extractNoteId(from: urlString) != nil {
            return true
        }
        let path = url.path.lowercased()
        if path.contains("/search_result") {
            return true
        }
        if path.contains("/user/profile/") {
            return true
        }
        return false
    }

    /// Infers which top-level navigation section matches the current URL.
    public static func inferredSection(for urlString: String) -> NavSection? {
        guard let url = URL(string: urlString), let host = url.host?.lowercased() else {
            return nil
        }
        let path = url.path.lowercased()
        if host.hasPrefix("creator.") {
            if path.contains("/chat") || path.contains("/message") {
                return .directMessages
            }
            return .creatorCenter
        }
        if path.hasPrefix("/notification") {
            return .notifications
        }
        if path.hasPrefix("/explore") || path.hasPrefix("/discovery") || path.hasPrefix("/search_result") {
            return .explore
        }
        return nil
    }

    private static func isLikelyNoteId(_ token: String) -> Bool {
        guard token.count == 24 else { return false }
        return token.unicodeScalars.allSatisfy { scalar in
            (scalar >= "0" && scalar <= "9") ||
            (scalar >= "a" && scalar <= "f") ||
            (scalar >= "A" && scalar <= "F")
        }
    }
}
