import Foundation

struct DistrictState: Codable, Hashable, Identifiable {
    var id: String
    var name: String
}

struct DistrictResult: Codable, Hashable, Identifiable {
    var name: String
    var label: String
    var url: String
    var isQmlativ: Bool

    var id: String { url + "|" + label }
}

actor DistrictSearch {
    static let endpoint = URL(string: "https://www.skyward.com/Marketing/LoginPage.aspx")!

    private let session: URLSession
    private var cachedStates: [DistrictState] = []
    private var cachedTokens: [(String, String)] = []

    init(session: URLSession? = nil) {
        if let session {
            self.session = session
        } else {
            let config = URLSessionConfiguration.ephemeral
            config.timeoutIntervalForRequest = 20
            config.httpAdditionalHeaders = ["User-Agent": URLSessionTransport.userAgent]
            self.session = URLSession(configuration: config)
        }
    }

    func states() async throws -> [DistrictState] {
        if !cachedStates.isEmpty, !cachedTokens.isEmpty { return cachedStates }
        let html = try await fetchPage(form: nil)
        let parsedStates = DistrictSearch.parseStates(html)
        let parsedTokens = DistrictSearch.parseTokens(html)
        guard !parsedStates.isEmpty else {
            throw SkywardError.server("Could not load the state list from Skyward's district finder.")
        }
        cachedStates = parsedStates
        cachedTokens = parsedTokens
        return parsedStates
    }

    func search(stateID: String, query: String) async throws -> [DistrictResult] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 3 else { return [] }
        if cachedTokens.isEmpty {
            _ = try await states()
        }
        var form = cachedTokens
        if !form.contains(where: { $0.0 == "__EVENTTARGET" }) { form.append(("__EVENTTARGET", "")) }
        if !form.contains(where: { $0.0 == "__EVENTARGUMENT" }) { form.append(("__EVENTARGUMENT", "")) }
        form.append(("ddlStates", stateID))
        form.append(("txtSearch", trimmed))
        form.append(("btnSearch", "Search"))

        let html = try await fetchPage(form: form)
        let freshTokens = DistrictSearch.parseTokens(html)
        if !freshTokens.isEmpty { cachedTokens = freshTokens }
        return DistrictSearch.parseResults(html)
    }

    private func fetchPage(form: [(String, String)]?) async throws -> String {
        var request = URLRequest(url: DistrictSearch.endpoint)
        if let form {
            request.httpMethod = "POST"
            request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
            request.httpBody = Data(FormEncoding.encode(form).utf8)
        } else {
            request.httpMethod = "GET"
        }
        do {
            let (data, response) = try await session.data(for: request)
            if let http = response as? HTTPURLResponse, http.statusCode >= 400 {
                throw SkywardError.server("The district finder returned HTTP \(http.statusCode).")
            }
            return URLSessionTransport.decode(data)
        } catch let error as SkywardError {
            throw error
        } catch {
            throw SkywardError.network(error.localizedDescription)
        }
    }

    // MARK: Pure parsers

    static func parseStates(_ html: String) -> [DistrictState] {
        let doc = HTMLNode.parse(html)
        guard let select = doc.byId("ddlStates") ?? doc.first(where: { $0.tag == "select" && ($0.attr("name") ?? "").contains("ddlStates") }) else {
            return []
        }
        var out: [DistrictState] = []
        for option in select.all("option") {
            let value = (option.attr("value") ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            let name = option.cleanText
            guard !value.isEmpty, value != "0", value != "-1", !name.isEmpty else { continue }
            if name.lowercased().hasPrefix("select") || name.lowercased().hasPrefix("choose") { continue }
            out.append(DistrictState(id: value, name: name))
        }
        return out
    }

    static func parseTokens(_ html: String) -> [(String, String)] {
        let doc = HTMLNode.parse(html)
        let wanted = ["__VIEWSTATE", "__VIEWSTATEGENERATOR", "__EVENTVALIDATION", "__EVENTTARGET", "__EVENTARGUMENT"]
        var byName: [String: String] = [:]
        for input in doc.all("input") {
            guard let name = input.attr("name"), wanted.contains(name) else { continue }
            byName[name] = input.attr("value") ?? ""
        }
        return wanted.compactMap { name in
            guard let value = byName[name] else { return nil }
            return (name, value)
        }
    }

    static func parseResults(_ html: String) -> [DistrictResult] {
        let doc = HTMLNode.parse(html)
        let containers = doc.select("div.login-flex-container.rowCount")
        let rows = containers.isEmpty ? doc.select("div.rowCount") : containers
        var out: [DistrictResult] = []
        var seen = Set<String>()

        for container in rows {
            var districtName = container.firstTag("span")?.cleanText ?? ""
            for link in container.all("a") where link.hasClass("goButton") || (link.attr("href") ?? "").contains("WriteCookie") {
                var url = (link.attr("title") ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                let href = link.attr("href") ?? ""
                if let groups = Str.match("WriteCookie\\(\\s*'([^']*)'\\s*,\\s*'([^']*)'", in: href) {
                    if url.isEmpty { url = groups[1].trimmingCharacters(in: .whitespacesAndNewlines) }
                    if districtName.isEmpty { districtName = HTMLNode.clean(groups[2]) }
                }
                guard !url.isEmpty else { continue }
                var label = ""
                var p = link.parent
                while let node = p, node !== container {
                    if let strong = node.firstTag("strong") {
                        label = strong.cleanText
                        break
                    }
                    p = node.parent
                }
                if label.isEmpty {
                    label = container.firstTag("strong")?.cleanText ?? "Family Access Login"
                }
                let result = DistrictResult(
                    name: districtName,
                    label: label,
                    url: url,
                    isQmlativ: SkywardEndpoint.looksLikeQmlativ(url)
                )
                if !seen.contains(result.id) {
                    seen.insert(result.id)
                    out.append(result)
                }
            }
        }
        return out
    }
}
