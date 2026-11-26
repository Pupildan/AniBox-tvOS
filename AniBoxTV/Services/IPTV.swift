import Foundation

struct IPTVChannel: Identifiable, Hashable {
    var id: String { url }
    let name: String
    let group: String
    let logo: String?
    let url: String
}

/// IPTV / 电视直播（对应原项目 iptv.rs：M3U 订阅解析）
enum IPTV {
    static func load(_ urlString: String) async throws -> [IPTVChannel] {
        guard let u = URL(string: urlString) else { throw FnError(message: "直播源地址无效") }
        let (d, _) = try await Net.plain.data(from: u)
        return parse(String(decoding: d, as: UTF8.self))
    }
    static func parse(_ text: String) -> [IPTVChannel] {
        var out: [IPTVChannel] = []
        var name = "", group = "未分组", logo: String?
        func attr(_ line: String, _ key: String) -> String? {
            guard let r = line.range(of: "\(key)=\"") else { return nil }
            let rest = line[r.upperBound...]
            return rest.firstIndex(of: "\"").map { String(rest[..<$0]) }
        }
        for raw in text.components(separatedBy: .newlines) {
            let line = raw.trimmingCharacters(in: .whitespaces)
            if line.hasPrefix("#EXTINF") {
                name = line.components(separatedBy: ",").last ?? ""
                group = attr(line, "group-title") ?? "未分组"
                logo = attr(line, "tvg-logo")
            } else if !line.isEmpty, !line.hasPrefix("#") {
                if line.contains(",") && !line.hasPrefix("http"), let i = line.firstIndex(of: ",") {   // txt 格式：名称,地址
                    let n = String(line[..<i]); let u = String(line[line.index(after: i)...])
                    if u.hasPrefix("http") { out.append(.init(name: n, group: group, logo: nil, url: u)) }
                    else if u == "#genre#" { group = n }
                } else {
                    out.append(.init(name: name.isEmpty ? line : name, group: group, logo: logo, url: line))
                    name = ""; logo = nil
                }
            }
        }
        return out
    }
}
