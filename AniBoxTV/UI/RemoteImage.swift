import SwiftUI
import UIKit

/// 带鉴权头与磁盘缓存的图片加载（NAS sys/img 需 Cookie/Authorization）
actor ImageLoader {
    static let shared = ImageLoader()
    private let mem = NSCache<NSURL, UIImage>()
    private let dir: URL = {
        let d = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0].appendingPathComponent("img")
        try? FileManager.default.createDirectory(at: d, withIntermediateDirectories: true)
        return d
    }()
    func load(_ url: URL) async -> UIImage? {
        if let i = mem.object(forKey: url as NSURL) { return i }
        let f = dir.appendingPathComponent(FnAuth.md5(url.absoluteString))
        if let d = try? Data(contentsOf: f), let i = UIImage(data: d) { mem.setObject(i, forKey: url as NSURL); return i }
        var r = URLRequest(url: url)
        if url.path.contains("/v/api/v1/") {
            let token = Creds.shared.token
            FnClient.shared.authHeaders(token: token).forEach { r.setValue($1, forHTTPHeaderField: $0) }
            r.setValue(FnAuth.authx(path: url.path, signData: ""), forHTTPHeaderField: "Authx")
        }
        guard let (d, _) = try? await Net.session.data(for: r), let i = UIImage(data: d) else { return nil }
        try? d.write(to: f)
        mem.setObject(i, forKey: url as NSURL)
        return i
    }
}

struct RemoteImage: View {
    let url: URL?
    @State private var image: UIImage?
    var body: some View {
        ZStack {
            if let image { Image(uiImage: image).resizable() }
            else { Rectangle().fill(.white.opacity(0.06)) }
        }
        .task(id: url) {
            guard let url else { return }
            image = await ImageLoader.shared.load(url)
        }
    }
}
