import Foundation

/// 本地观影记录（对应原项目 history.rs：热力图 / 年度报告 / 观看时长统计）
struct HistoryEntry: Codable, Identifiable, Hashable {
    var id: String { guid }
    let guid: String
    var title: String
    var subtitle: String
    var poster: String?
    var seriesGuid: String?
    var lastWatched: Date
    var watchedSeconds: Double
    var progress: Double
    var finished: Bool
    var type: String
    var sessions: [Session] = []
    struct Session: Codable, Hashable { let date: Date; let seconds: Double }
}

@MainActor
final class HistoryStore: ObservableObject {
    static let shared = HistoryStore()
    @Published private(set) var entries: [HistoryEntry] = []
    private let url = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0].appendingPathComponent("history.json")

    private init() {
        if let d = try? Data(contentsOf: url), let e = try? JSONDecoder().decode([HistoryEntry].self, from: d) { entries = e }
    }
    private func save() { if let d = try? JSONEncoder().encode(entries) { try? d.write(to: url) } }

    func record(item: MediaItem, seconds: Double, progress: Double, finished: Bool) {
        let now = Date()
        if let i = entries.firstIndex(where: { $0.guid == item.guid }) {
            entries[i].lastWatched = now
            entries[i].watchedSeconds += seconds
            entries[i].progress = progress
            entries[i].finished = entries[i].finished || finished
            entries[i].sessions.append(.init(date: now, seconds: seconds))
        } else {
            entries.insert(HistoryEntry(guid: item.guid, title: item.tvTitle.isEmpty ? item.title : item.tvTitle,
                                        subtitle: item.tvTitle.isEmpty ? item.subtitleLine : item.title, poster: item.poster,
                                        seriesGuid: item.seriesGuid.isEmpty ? nil : item.seriesGuid, lastWatched: now,
                                        watchedSeconds: seconds, progress: progress, finished: finished, type: item.type,
                                        sessions: [.init(date: now, seconds: seconds)]), at: 0)
        }
        entries.sort { $0.lastWatched > $1.lastWatched }
        save()
    }
    func remove(_ guid: String) { entries.removeAll { $0.guid == guid }; save() }
    func clear() { entries.removeAll(); save() }

    /// 按天汇总观看秒数（热力图）
    func dailySeconds(days: Int = 182) -> [(Date, Double)] {
        let cal = Calendar.current
        var map: [Date: Double] = [:]
        for e in entries { for s in e.sessions { map[cal.startOfDay(for: s.date), default: 0] += s.seconds } }
        let today = cal.startOfDay(for: Date())
        return (0..<days).reversed().compactMap { off in
            cal.date(byAdding: .day, value: -off, to: today).map { ($0, map[$0] ?? 0) }
        }
    }
    struct Report { var totalHours: Double; var titles: Int; var finished: Int; var topTitles: [(String, Double)]; var busiestDay: (Date, Double)?; var byMonth: [Double] }
    func report(year: Int) -> Report {
        let cal = Calendar.current
        var total = 0.0, byTitle: [String: Double] = [:], byDay: [Date: Double] = [:], byMonth = Array(repeating: 0.0, count: 12)
        var titles = Set<String>(), fin = 0
        for e in entries {
            var touched = false
            for s in e.sessions where cal.component(.year, from: s.date) == year {
                total += s.seconds; byTitle[e.title, default: 0] += s.seconds; touched = true
                byDay[cal.startOfDay(for: s.date), default: 0] += s.seconds
                byMonth[cal.component(.month, from: s.date) - 1] += s.seconds / 3600
            }
            if touched { titles.insert(e.title); if e.finished { fin += 1 } }
        }
        return Report(totalHours: total / 3600, titles: titles.count, finished: fin,
                      topTitles: byTitle.sorted { $0.value > $1.value }.prefix(10).map { ($0.key, $0.value / 3600) },
                      busiestDay: byDay.max { $0.value < $1.value }, byMonth: byMonth)
    }
}
