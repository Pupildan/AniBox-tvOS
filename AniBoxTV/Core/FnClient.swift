import Foundation

/// 线程安全的当前凭据（供非主线程网络层读取）
final class Creds: @unchecked Sendable {
    static let shared = Creds()
    private let lock = NSLock()
    private var _server = "", _token = ""
    var server: String { get { lock.lock(); defer { lock.unlock() }; return _server } set { lock.lock(); _server = newValue; lock.unlock() } }
    var token: String { get { lock.lock(); defer { lock.unlock() }; return _token } set { lock.lock(); _token = newValue; lock.unlock() } }
}

struct FnError: LocalizedError {
    let message: String
    var errorDescription: String? { message }
    static let authExpired = FnError(message: "登录已过期，请重新登录")
}

/// 允许自签证书（内网 NAS 常见）
final class InsecureDelegate: NSObject, URLSessionDelegate, URLSessionTaskDelegate {
    func urlSession(_ session: URLSession, didReceive challenge: URLAuthenticationChallenge,
                    completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) {
        if challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust,
           let trust = challenge.protectionSpace.serverTrust {
            completionHandler(.useCredential, URLCredential(trust: trust))
        } else {
            completionHandler(.performDefaultHandling, nil)
        }
    }
    // 不自动跟随重定向：跨 host 会剥鉴权头，由调用方手动重签
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
        completionHandler(nil)
    }
}

enum Net {
    static let delegate = InsecureDelegate()
    static let session: URLSession = {
        let c = URLSessionConfiguration.default
        c.timeoutIntervalForRequest = 30
        c.httpCookieStorage = HTTPCookieStorage.shared
        c.httpShouldSetCookies = true
        return URLSession(configuration: c, delegate: delegate, delegateQueue: nil)
    }()
    static let plain: URLSession = {
        let c = URLSessionConfiguration.default
        c.timeoutIntervalForRequest = 20
        c.urlCache = URLCache(memoryCapacity: 64 << 20, diskCapacity: 512 << 20)
        return URLSession(configuration: c)
    }()

    static func getJSON(_ url: URL, headers: [String: String] = [:]) async throws -> JSON {
        var r = URLRequest(url: url)
        headers.forEach { r.setValue($1, forHTTPHeaderField: $0) }
        let (d, resp) = try await plain.data(for: r)
        if let h = resp as? HTTPURLResponse, h.statusCode >= 400 { throw FnError(message: "HTTP \(h.statusCode)") }
        return JSON.parse(d)
    }
    static func postJSON(_ url: URL, body: Any, headers: [String: String] = [:]) async throws -> JSON {
        var r = URLRequest(url: url)
        r.httpMethod = "POST"
        r.setValue("application/json", forHTTPHeaderField: "Content-Type")
        headers.forEach { r.setValue($1, forHTTPHeaderField: $0) }
        r.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (d, resp) = try await plain.data(for: r)
        if let h = resp as? HTTPURLResponse, h.statusCode >= 400 { throw FnError(message: "HTTP \(h.statusCode)") }
        return JSON.parse(d)
    }
}

/// 飞牛影视 API 客户端
final class FnClient {
    static let shared = FnClient()

    static func normalize(_ input: String) -> String {
        var s = input.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "：", with: ":")
            .trimmingCharacters(in: CharacterSet(charactersIn: "\"' "))
        if !s.lowercased().hasPrefix("http://") && !s.lowercased().hasPrefix("https://") { s = "http://" + s }
        if let r = s.range(of: "://") {
            let rest = s[r.upperBound...]
            if let slash = rest.firstIndex(of: "/") { s = String(s[..<r.upperBound]) + String(rest[..<slash]) }
        }
        return s
    }

    func authHeaders(token: String) -> [String: String] {
        [
            "Authorization": token,
            "Cookie": token.isEmpty ? "mode=relay" : "mode=relay; Trim-MC-token=\(token)",
            "x-trim-client": "web",
            "x-trim-client-version": "616",
        ]
    }

    @discardableResult
    func call(_ path: String, method: String = "GET", body: [String: Any]? = nil,
              query: [(String, String)] = [], base: String? = nil, token: String? = nil) async throws -> JSON {
        let b = FnClient.normalize(base ?? Creds.shared.server)
        let t = token ?? Creds.shared.token
        var lastErr: Error = FnError(message: "请求失败")
        for attempt in 0..<3 {
            if attempt > 0 { try? await Task.sleep(nanoseconds: UInt64(attempt) * 400_000_000) }
            do { return try await callInner(base: b, path: path, method: method, body: body, query: query, token: t, depth: 0) }
            catch let e as FnError where e.message.contains("非 JSON") || e.message.contains("invalid sign") { lastErr = e }
        }
        throw lastErr
    }

    private func callInner(base: String, path: String, method: String, body: [String: Any]?,
                           query: [(String, String)], token: String, depth: Int) async throws -> JSON {
        if depth > 3 { throw FnError(message: "重定向次数过多") }
        let m = method.uppercased()
        let hasBody = m == "POST" || m == "PUT" || m == "PATCH" || (m == "DELETE" && body != nil)
        var bodyStr = ""
        if hasBody {
            var obj = body ?? [:]
            obj["nonce"] = FnAuth.rand6()
            let d = try JSONSerialization.data(withJSONObject: obj, options: [.sortedKeys])
            bodyStr = String(data: d, encoding: .utf8) ?? "{}"
        }
        let sortedQ = query.sorted { $0.0 < $1.0 }
        let signQ = sortedQ.map { "\($0.0)=\($0.1)" }.joined(separator: "&")
        var comps = URLComponents(string: base + path)
        if !sortedQ.isEmpty { comps?.queryItems = sortedQ.map { URLQueryItem(name: $0.0, value: $0.1) } }
        guard let url = comps?.url else { throw FnError(message: "服务器地址格式无效") }
        var req = URLRequest(url: url)
        req.httpMethod = m
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        authHeaders(token: token).forEach { req.setValue($1, forHTTPHeaderField: $0) }
        req.setValue(FnAuth.authx(path: path, signData: sortedQ.isEmpty ? bodyStr : signQ), forHTTPHeaderField: "Authx")
        if hasBody { req.httpBody = Data(bodyStr.utf8) }

        let (data, resp): (Data, URLResponse)
        do { (data, resp) = try await Net.session.data(for: req) }
        catch { throw FnError(message: "无法连接服务器：\(error.localizedDescription)") }
        let http = resp as? HTTPURLResponse
        let status = http?.statusCode ?? 0
        if [301, 302, 307, 308].contains(status), let loc = http?.value(forHTTPHeaderField: "Location"), !loc.isEmpty {
            if let u = URL(string: loc), let host = u.host {
                let nb = "\(u.scheme ?? "http")://\(host)\(u.port.map { ":\($0)" } ?? "")"
                if path.hasPrefix("/v/api/v1/user/info") || path.hasPrefix("/v/api/v1/login") {
                    await MainActor.run { Session.shared.updateServer(nb) }
                }
                return try await callInner(base: nb, path: u.path.isEmpty ? path : u.path, method: method, body: body, query: query, token: token, depth: depth + 1)
            }
        }
        if status == 401 { throw FnError.authExpired }
        let ct = http?.value(forHTTPHeaderField: "Content-Type")?.lowercased() ?? ""
        if ct.contains("text/html") { throw FnError(message: "HTTP \(status) 接口返回了网页而非 JSON，服务器地址/端口可能填错") }
        guard let obj = try? JSONDecoder().decode(JSON.self, from: data) else { throw FnError(message: "HTTP \(status) 返回非 JSON 数据") }
        let code = obj["code"].int ?? -1
        if code == 5000 { throw FnError(message: "invalid sign") }
        if code != 0 {
            let msg = obj.first("msg", "message").string ?? "未知业务错误"
            if code == -2 || msg.lowercased().contains("auth expired") {
                await MainActor.run { Session.shared.handleAuthExpired() }
                throw FnError.authExpired
            }
            throw FnError(message: "code=\(code): \(msg)")
        }
        return obj["data"]
    }

    // MARK: - 业务接口
    func login(server: String, username: String, password: String) async throws -> String {
        let d = try await call("/v/api/v1/login", method: "POST",
                               body: ["app_name": "trimemedia-web", "username": username, "password": password],
                               base: server, token: "")
        guard let t = d.first("token").string ?? d.string, !t.isEmpty else { throw FnError(message: "登录失败：未返回 token") }
        return t
    }
    func userInfo() async throws -> JSON { try await call("/v/api/v1/user/info") }
    func mediaLibs() async throws -> [JSON] { try await call("/v/api/v1/mediadb/list").array }
    func mediaSum() async throws -> JSON { try await call("/v/api/v1/mediadb/sum") }
    func continueWatching() async throws -> [JSON] { try await call("/v/api/v1/play/list").array }

    func items(ancestor: String? = nil, parent: String? = nil, types: [String]? = nil, tags: [String: Any] = [:],
               sortColumn: String = "create_time", sortType: String = "DESC", page: Int = 1, pageSize: Int = 60) async throws -> (list: [JSON], total: Int) {
        var t = tags
        if let types { t["type"] = types }
        var body: [String: Any] = ["exclude_grouped_video": parent == nil ? 1 : 0, "sort_type": sortType,
                                   "sort_column": sortColumn, "page_size": pageSize, "page": page, "tags": t]
        if let ancestor { body["ancestor_guid"] = ancestor }
        if let parent { body["parent_guid"] = parent }
        let d = try await call("/v/api/v1/item/list", method: "POST", body: body)
        return (d["list"].array, d["total"].int ?? 0)
    }
    func favorites(page: Int = 1) async throws -> [JSON] {
        try await call("/v/api/v1/favorite/list", method: "POST", body: [
            "tags": ["type": [String]()], "sort_type": "DESC", "sort_column": "create_time",
            "exclude_grouped_video": 1, "page": page, "page_size": 60])["list"].array
    }
    func item(_ guid: String) async throws -> JSON { try await call("/v/api/v1/item/\(guid)") }
    func seasons(_ guid: String) async throws -> [JSON] { try await call("/v/api/v1/season/list/\(guid)").array }
    func episodes(_ seasonGuid: String) async throws -> [JSON] { try await call("/v/api/v1/episode/list/\(seasonGuid)").array }
    func search(_ q: String) async throws -> [JSON] {
        let d = try await call("/v/api/v1/search/list", query: [("q", q)])
        return d.array.isEmpty ? d["list"].array : d.array
    }
    func playInfo(_ guid: String, mediaGuid: String? = nil) async throws -> JSON {
        var b: [String: Any] = ["item_guid": guid]
        if let mediaGuid { b["media_guid"] = mediaGuid }
        return try await call("/v/api/v1/play/info", method: "POST", body: b)
    }
    func streamList(_ guid: String) async throws -> JSON { try await call("/v/api/v1/stream/list/\(guid)") }
    func stream(mediaGuid: String) async throws -> JSON {
        try await call("/v/api/v1/stream", method: "POST", body: [
            "header": ["User-Agent": ["trim_player"]], "level": 1, "media_guid": mediaGuid,
            "ip": UUID().uuidString.lowercased()])
    }
    func recordPlay(itemGuid: String, info: JSON, ts: Double, duration: Double) async {
        _ = try? await call("/v/api/v1/play/record", method: "POST", body: [
            "item_guid": itemGuid, "media_guid": info["media_guid"].str, "video_guid": info["video_guid"].str,
            "audio_guid": info["audio_guid"].str, "subtitle_guid": info["subtitle_guid"].str,
            "play_link": URL(string: Creds.shared.server)?.host ?? "", "ts": Int(ts), "duration": Int(duration)])
    }
    func setWatched(_ guid: String, watched: Bool) async throws {
        try await call("/v/api/v1/item/watched", method: watched ? "POST" : "DELETE", body: ["item_guid": guid])
    }
    func setFavorite(_ guid: String, fav: Bool) async throws {
        try await call("/v/api/v1/item/favorite", method: fav ? "POST" : "DELETE", body: ["item_guid": guid])
    }
    func setSkip(parentGuid: String, opening: Int, ending: Int) async throws {
        try await call("/v/api/v1/play/setConfigByItem", method: "POST",
                       body: ["guid": parentGuid, "skip_opening": opening, "skip_ending": ending])
    }
    func refreshItem(_ guid: String) async throws {
        try await call("/v/api/v1/item/refresh", method: "POST", body: ["item_guid": guid, "refresh_mode": 0])
    }
    func scrapSearch(keyword: String, source: String = "TMDB", itemGuid: String?) async throws -> [JSON] {
        var b: [String: Any] = ["source": source, "source_keyword": keyword, "lan": "zh-CN"]
        if let itemGuid { b["item_guid"] = itemGuid }
        let d = try await call("/v/api/v1/scrap/search", method: "POST", body: b)
        return d.array.isEmpty ? d["list"].array : d.array
    }
    func rescrap(itemGuid: String, sourceId: String, source: String, type: String) async throws {
        try await call("/v/api/v1/scrap/rescrap", method: "POST",
                       body: ["item_guid": itemGuid, "source_id": sourceId, "source": source, "type": type])
    }
    func tagGenres() async throws -> [JSON] { try await call("/v/api/v1/tag/genres", query: [("lan", "zh-CN")]).array }

    // MARK: - URL
    func imageURL(_ path: String?, width: Int = 500) -> URL? {
        guard let p = path, !p.isEmpty else { return nil }
        if p.hasPrefix("http") { return URL(string: p) }
        let pp = p.hasPrefix("/") ? p : "/" + p
        return URL(string: "\(FnClient.normalize(Creds.shared.server))/v/api/v1/sys/img\(pp)?w=\(width)")
    }
    func mediaURL(mediaGuid: String) -> URL? {
        URL(string: "\(FnClient.normalize(Creds.shared.server))/v/api/v1/media/range/\(mediaGuid)")
    }
    func subtitleURL(_ guid: String) -> URL? {
        URL(string: "\(FnClient.normalize(Creds.shared.server))/v/api/v1/subtitle/dl/\(guid)")
    }
    func download(_ url: URL) async throws -> Data {
        var r = URLRequest(url: url)
        authHeaders(token: Creds.shared.token).forEach { r.setValue($1, forHTTPHeaderField: $0) }
        let path = url.path
        r.setValue(FnAuth.authx(path: path, signData: ""), forHTTPHeaderField: "Authx")
        let (d, _) = try await Net.session.data(for: r)
        return d
    }
}
