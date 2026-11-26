import Foundation

/// 聚合元数据：Bangumi / TMDB / AniList（对应原项目 bgm.rs / tmdb.rs / anilist.rs）
struct ExtMeta: Hashable {
    var source: String
    var id: String
    var title: String
    var originalTitle: String = ""
    var summary: String = ""
    var score: Double? = nil
    var rank: Int? = nil
    var votes: Int? = nil
    var cover: String? = nil
    var banner: String? = nil
    var date: String = ""
    var tags: [String] = []
    var cast: [Person] = []
    var staff: [Person] = []
    var related: [ExtMeta] = []
    var episodes: Int? = nil
    var url: String = ""

    struct Person: Hashable, Identifiable {
        var id: String
        var name: String
        var role: String
        var avatar: String?
    }
}

actor MetaCache {
    static let shared = MetaCache()
    private var mem: [String: Any] = [:]
    private let dir: URL = {
        let d = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0].appendingPathComponent("meta")
        try? FileManager.default.createDirectory(at: d, withIntermediateDirectories: true)
        return d
    }()
    func json(_ key: String, ttl: TimeInterval, fetch: () async throws -> JSON) async throws -> JSON {
        let f = dir.appendingPathComponent(FnAuth.md5(key))
        if let a = try? FileManager.default.attributesOfItem(atPath: f.path), let m = a[.modificationDate] as? Date,
           Date().timeIntervalSince(m) < ttl, let d = try? Data(contentsOf: f) { return JSON.parse(d) }
        do {
            let v = try await fetch()
            if let d = try? JSONEncoder().encode(v) { try? d.write(to: f) }
            return v
        } catch {
            if let d = try? Data(contentsOf: f) { return JSON.parse(d) }  // stale-if-error
            throw error
        }
    }
}

enum Bangumi {
    static var base: String { AppSettings.shared.bgmBase.trimmingCharacters(in: CharacterSet(charactersIn: "/")) }
    static var headers: [String: String] {
        var h = ["User-Agent": "anibox-tvos/0.1 (https://github.com/FNOSP/AniBox)", "Accept": "application/json"]
        if !AppSettings.shared.bgmToken.isEmpty { h["Authorization"] = "Bearer \(AppSettings.shared.bgmToken)" }
        return h
    }
    static func img(_ s: String?) -> String? { s.map { $0.replacingOccurrences(of: "http://", with: "https://") } }

    static func search(_ keyword: String, animeOnly: Bool = true) async throws -> [JSON] {
        let body: [String: Any] = animeOnly ? ["keyword": keyword, "filter": ["type": [2]]] : ["keyword": keyword]
        let r = try await MetaCache.shared.json("bgm:s:\(keyword):\(animeOnly)", ttl: 30*86400) {
            try await Net.postJSON(URL(string: "\(base)/v0/search/subjects?limit=20")!, body: body, headers: headers)
        }
        return r["data"].array
    }
    static func subject(_ id: String) async throws -> JSON {
        try await MetaCache.shared.json("bgm:sub:\(id)", ttl: 7*86400) { try await Net.getJSON(URL(string: "\(base)/v0/subjects/\(id)")!, headers: headers) }
    }
    static func characters(_ id: String) async throws -> [JSON] {
        try await MetaCache.shared.json("bgm:ch:\(id)", ttl: 7*86400) { try await Net.getJSON(URL(string: "\(base)/v0/subjects/\(id)/characters")!, headers: headers) }.array
    }
    static func persons(_ id: String) async throws -> [JSON] {
        try await MetaCache.shared.json("bgm:p:\(id)", ttl: 7*86400) { try await Net.getJSON(URL(string: "\(base)/v0/subjects/\(id)/persons")!, headers: headers) }.array
    }
    static func relations(_ id: String) async throws -> [JSON] {
        try await MetaCache.shared.json("bgm:rel:\(id)", ttl: 7*86400) { try await Net.getJSON(URL(string: "\(base)/v0/subjects/\(id)/subjects")!, headers: headers) }.array
    }
    static func episodes(_ id: String) async throws -> [JSON] {
        try await MetaCache.shared.json("bgm:ep:\(id)", ttl: 86400) { try await Net.getJSON(URL(string: "\(base)/v0/episodes?subject_id=\(id)&type=0&limit=200")!, headers: headers) }["data"].array
    }
    static func calendar() async throws -> [JSON] {
        let day = Calendar.current.ordinality(of: .day, in: .era, for: Date()) ?? 0
        return try await MetaCache.shared.json("bgm:cal:\(day)", ttl: 12*3600) { try await Net.getJSON(URL(string: "\(base)/calendar")!, headers: headers) }.array
    }
    static func season(year: Int, month: Int) async throws -> [JSON] {
        try await MetaCache.shared.json("bgm:season:\(year)-\(month)", ttl: 86400) {
            try await Net.getJSON(URL(string: "\(base)/v0/subjects?type=2&sort=rank&year=\(year)&month=\(month)&limit=50")!, headers: headers)
        }["data"].array
    }
    // 账号
    static func me() async throws -> JSON { try await Net.getJSON(URL(string: "\(base)/v0/me")!, headers: headers) }
    static func collection(username: String, type: Int) async throws -> [JSON] {
        try await Net.getJSON(URL(string: "\(base)/v0/users/\(username)/collections?subject_type=2&type=\(type)&limit=50")!, headers: headers)["data"].array
    }
    static func setCollection(subjectId: String, type: Int, rate: Int? = nil) async throws {
        var b: [String: Any] = ["type": type]
        if let rate { b["rate"] = rate }
        _ = try await Net.postJSON(URL(string: "\(base)/v0/users/-/collections/\(subjectId)")!, body: b, headers: headers)
    }
    static func markEpisode(episodeId: String) async throws {
        var r = URLRequest(url: URL(string: "\(base)/v0/users/-/collections/-/episodes/\(episodeId)")!)
        r.httpMethod = "PUT"
        headers.forEach { r.setValue($1, forHTTPHeaderField: $0) }
        r.setValue("application/json", forHTTPHeaderField: "Content-Type")
        r.httpBody = try JSONSerialization.data(withJSONObject: ["type": 2])
        _ = try await Net.plain.data(for: r)
    }

    static func toMeta(_ s: JSON) -> ExtMeta {
        ExtMeta(source: "Bangumi", id: s["id"].str, title: s["name_cn"].str.isEmpty ? s["name"].str : s["name_cn"].str,
                originalTitle: s["name"].str, summary: s["summary"].str,
                score: s["rating"]["score"].double ?? s["score"].double, rank: s["rating"]["rank"].int ?? s["rank"].int,
                votes: s["rating"]["total"].int, cover: img(s["images"]["large"].string ?? s["images"]["common"].string),
                date: s.first("date", "air_date").str, tags: s["tags"].array.prefix(12).compactMap { $0["name"].string },
                episodes: s.first("eps", "total_episodes").int, url: "https://bgm.tv/subject/\(s["id"].str)")
    }

    /// 匹配飞牛条目 → Bangumi 条目（打分：标题完全匹配 > 年份 > 排名）
    static func match(title: String, year: String) async -> ExtMeta? {
        let clean = title.replacingOccurrences(of: #"\s*(第.季|Season\s*\d+|S\d+)$"#, with: "", options: .regularExpression)
        var hits = (try? await search(title)) ?? []
        if hits.isEmpty && clean != title { hits = (try? await search(clean)) ?? [] }
        guard !hits.isEmpty else { return nil }
        func score(_ h: JSON) -> Int {
            var s = 0
            if h["name_cn"].str == title || h["name"].str == title { s += 100 }
            if h["name_cn"].str.contains(clean) || h["name"].str.contains(clean) { s += 30 }
            if !year.isEmpty, h["date"].str.hasPrefix(year) { s += 40 }
            return s
        }
        let best = hits.max { score($0) < score($1) }!
        var m = toMeta(best)
        if let full = try? await subject(best["id"].str) { m = toMeta(full) }
        let id = m.id
        async let ch = characters(id)
        async let ps = persons(id)
        async let rel = relations(id)
        m.cast = ((try? await ch) ?? []).prefix(30).map { c in
            let actor = c["actors"][0]
            return .init(id: c["id"].str, name: c["name"].str, role: actor["name"].string.map { "CV \($0)" } ?? c["relation"].str,
                         avatar: img(c["images"]["grid"].string ?? c["images"]["medium"].string))
        }
        m.staff = ((try? await ps) ?? []).prefix(30).map { p in
            .init(id: p["id"].str, name: p["name"].str, role: p["relation"].str, avatar: img(p["images"]["grid"].string))
        }
        m.related = ((try? await rel) ?? []).prefix(20).map { r in
            ExtMeta(source: "Bangumi", id: r["id"].str, title: r["name_cn"].str.isEmpty ? r["name"].str : r["name_cn"].str,
                    summary: r["relation"].str, cover: img(r["images"]["large"].string ?? r["images"]["common"].string))
        }
        return m
    }
}

enum TMDB {
    static var key: String { AppSettings.shared.tmdbKey }
    static func url(_ path: String, _ q: [String: String] = [:]) -> URL {
        var c = URLComponents(string: AppSettings.shared.tmdbBase.trimmingCharacters(in: CharacterSet(charactersIn: "/")) + path)!
        var items = q.map { URLQueryItem(name: $0.key, value: $0.value) }
        if !key.isEmpty && !key.hasPrefix("eyJ") { items.append(URLQueryItem(name: "api_key", value: key)) }
        c.queryItems = items
        return c.url!
    }
    static var headers: [String: String] { key.hasPrefix("eyJ") ? ["Authorization": "Bearer \(key)"] : [:] }
    static func img(_ p: String?, _ size: String = "w500") -> String? {
        guard let p, !p.isEmpty else { return nil }
        return p.hasPrefix("http") ? p : "\(AppSettings.shared.tmdbImageBase)/\(size)\(p)"
    }
    static func details(id: String, isTV: Bool) async throws -> JSON {
        let k = "tmdb:\(isTV ? "tv" : "movie"):\(id)"
        return try await MetaCache.shared.json(k, ttl: 30*86400) {
            try await Net.getJSON(url("/\(isTV ? "tv" : "movie")/\(id)", ["language": "zh-CN",
                "append_to_response": "credits,images,videos,recommendations,reviews,keywords",
                "include_image_language": "zh,en,null", "include_video_language": "zh-CN,en,ja,null"]), headers: headers)
        }
    }
    static func search(_ q: String, isTV: Bool) async throws -> [JSON] {
        try await Net.getJSON(url("/search/\(isTV ? "tv" : "movie")", ["query": q, "language": "zh-CN"]), headers: headers)["results"].array
    }
    static func seasonStills(id: String, season: Int) async throws -> [JSON] {
        try await MetaCache.shared.json("tmdb:season:\(id):\(season)", ttl: 86400) {
            try await Net.getJSON(url("/tv/\(id)/season/\(season)", ["language": "zh-CN"]), headers: headers)
        }["episodes"].array
    }
    static func person(_ id: String) async throws -> JSON {
        try await MetaCache.shared.json("tmdb:person:\(id)", ttl: 7*86400) {
            try await Net.getJSON(url("/person/\(id)", ["language": "zh-CN", "append_to_response": "combined_credits"]), headers: headers)
        }
    }
    static func toMeta(_ d: JSON, isTV: Bool) -> ExtMeta {
        var m = ExtMeta(source: "TMDB", id: d["id"].str, title: d.first("title", "name").str,
                        originalTitle: d.first("original_title", "original_name").str, summary: d["overview"].str,
                        score: d["vote_average"].double, votes: d["vote_count"].int,
                        cover: img(d["poster_path"].string), banner: img(d["backdrop_path"].string, "original"),
                        date: d.first("release_date", "first_air_date").str,
                        tags: d["genres"].array.compactMap { $0["name"].string },
                        url: "https://www.themoviedb.org/\(isTV ? "tv" : "movie")/\(d["id"].str)")
        m.cast = d["credits"]["cast"].array.prefix(30).map {
            .init(id: $0["id"].str, name: $0["name"].str, role: $0["character"].str, avatar: img($0["profile_path"].string, "w185"))
        }
        m.staff = d["credits"]["crew"].array.prefix(20).map {
            .init(id: $0["id"].str, name: $0["name"].str, role: $0["job"].str, avatar: img($0["profile_path"].string, "w185"))
        }
        m.related = d["recommendations"]["results"].array.prefix(20).map {
            ExtMeta(source: "TMDB", id: $0["id"].str, title: $0.first("title", "name").str, summary: "", score: $0["vote_average"].double,
                    cover: img($0["poster_path"].string))
        }
        return m
    }
}

enum AniList {
    static func query(_ q: String, _ vars: [String: Any]) async throws -> JSON {
        try await Net.postJSON(URL(string: "https://graphql.anilist.co")!, body: ["query": q, "variables": vars])["data"]
    }
    static func search(_ title: String) async -> ExtMeta? {
        let q = """
        query($s:String){ Media(search:$s, type:ANIME){ id title{romaji native english} description(asHtml:false)
          averageScore popularity episodes startDate{year month day} coverImage{extraLarge large} bannerImage genres
          siteUrl characters(perPage:20,sort:ROLE){edges{role node{id name{full native} image{medium}} voiceActors(language:JAPANESE){name{full native}}}} } }
        """
        guard let d = try? await MetaCache.shared.json("anilist:\(title)", ttl: 30*86400, fetch: { try await query(q, ["s": title]) }) else { return nil }
        let m = d["Media"]
        guard !m.isNull else { return nil }
        var e = ExtMeta(source: "AniList", id: m["id"].str, title: m["title"]["native"].string ?? m["title"]["romaji"].str,
                        originalTitle: m["title"]["romaji"].str,
                        summary: m["description"].str.replacingOccurrences(of: "<br>", with: "\n"),
                        score: m["averageScore"].double.map { $0 / 10 }, votes: m["popularity"].int,
                        cover: m["coverImage"]["extraLarge"].string ?? m["coverImage"]["large"].string,
                        banner: m["bannerImage"].string,
                        date: [m["startDate"]["year"].str, m["startDate"]["month"].str].filter { !$0.isEmpty }.joined(separator: "-"),
                        tags: m["genres"].array.compactMap { $0.string }, episodes: m["episodes"].int, url: m["siteUrl"].str)
        e.cast = m["characters"]["edges"].array.map {
            .init(id: $0["node"]["id"].str, name: $0["node"]["name"]["native"].string ?? $0["node"]["name"]["full"].str,
                  role: $0["voiceActors"][0]["name"]["native"].string.map { "CV \($0)" } ?? $0["role"].str,
                  avatar: $0["node"]["image"]["medium"].string)
        }
        return e
    }
}

/// 本地元数据覆盖（对应原项目 metadata_override.rs：手动匹配结果保存在本机）
enum MetaOverride {
    static func key(_ guid: String) -> String { "override.\(guid)" }
    static func get(_ guid: String) -> (source: String, id: String)? {
        guard let s = UserDefaults.standard.string(forKey: key(guid)) else { return nil }
        let p = s.split(separator: ":", maxSplits: 1).map(String.init)
        return p.count == 2 ? (p[0], p[1]) : nil
    }
    static func set(_ guid: String, source: String, id: String) { UserDefaults.standard.set("\(source):\(id)", forKey: key(guid)) }
    static func clear(_ guid: String) { UserDefaults.standard.removeObject(forKey: key(guid)) }
}
