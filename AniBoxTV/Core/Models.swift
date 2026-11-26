import Foundation

/// 统一的条目视图模型（飞牛 item / play/list / search 结果兼容）
struct MediaItem: Identifiable, Hashable {
    let raw: JSON
    var id: String { guid }
    var guid: String { raw.first("guid", "item_guid").str }
    var title: String {
        let t = raw.first("title", "tv_title", "name").str
        return t.isEmpty ? raw["file_name"].str : t
    }
    var tvTitle: String { raw.first("tv_title", "tvTitle").str }
    var type: String { raw.first("type").str }
    var isSeries: Bool { type == "TV" || type == "Season" }
    var isFolder: Bool { type == "Directory" || type == "Folder" }
    var isLive: Bool { type == "LiveChannel" }
    var overview: String { raw.first("overview").str }
    var year: String {
        let d = raw.first("air_date", "release_date", "first_air_date", "year").str
        return String(d.prefix(4))
    }
    var rating: Double? { raw.first("vote_average", "rating").double }
    var poster: String? {
        let p = raw.first("poster", "posters", "poster_path")
        if let s = p.string, !s.isEmpty { return s }
        return p[0].string ?? p[0]["file_path"].string
    }
    var backdrop: String? {
        let b = raw.first("backdrops", "backdrop", "backdrop_path", "still_path", "still")
        if let s = b.string, !s.isEmpty { return s }
        var best: JSON = b[0]; var size = 0.0
        for x in b.array { let s = (x["width"].double ?? 0) * (x["height"].double ?? 0); if s > size { size = s; best = x } }
        return best.string ?? best.first("file_path", "url", "path").string
    }
    var logo: String? { raw.first("logo", "logos")[0].first("file_path", "url").string ?? raw["logo"].string }
    var ts: Double { raw.first("ts", "watched_ts").double ?? 0 }
    var duration: Double { raw.first("duration", "runtime").double ?? 0 }
    var progress: Double { duration > 0 ? min(1, ts / (duration > 10000 ? duration / 1000 : duration)) : 0 }
    var watched: Bool { raw.first("watched", "is_watched").bool }
    var favorite: Bool { raw.first("is_favorite").bool }
    var season: Int { raw["season_number"].int ?? 0 }
    var episode: Int { raw["episode_number"].int ?? 0 }
    var parentGuid: String { raw.first("parent_guid", "parentGuid").str }
    var ancestorGuid: String { raw.first("ancestor_guid").str }
    var seriesGuid: String { raw.first("seriesGuid", "grand_guid").str }
    var subtitleLine: String {
        var parts: [String] = []
        if !year.isEmpty { parts.append(year) }
        if season > 0 && episode > 0 { parts.append("S\(season)E\(episode)") }
        if let r = rating, r > 0 { parts.append(String(format: "★ %.1f", r)) }
        return parts.joined(separator: " · ")
    }
    var tmdbId: String { raw.first("tmdb_id", "trim_id").str }
    var genres: [String] { raw["genres"].array.compactMap { $0.string ?? $0["name"].string ?? $0["value"].string } }

    static func list(_ a: [JSON]) -> [MediaItem] { a.map { MediaItem(raw: $0) }.filter { !$0.guid.isEmpty } }
}

struct Library: Identifiable, Hashable {
    let raw: JSON
    var id: String { raw["guid"].str }
    var name: String { raw.first("title", "name").str }
    var category: String { raw.first("category", "type").str }
    var posters: [String] { raw["posters"].array.compactMap { $0.string } }
}

struct StreamTrack: Identifiable, Hashable {
    let id: String
    let title: String
    let language: String
    let codec: String
    let isDefault: Bool
    let isExternal: Bool
    let mediaGuid: String
}
