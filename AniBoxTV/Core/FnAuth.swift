import Foundation
import CryptoKit

/// 飞牛 Authx 签名（与原项目 authx.rs / request.go 对齐）：
/// sign = md5(apiKey_urlPath_nonce_timestamp_md5(body)_apiSecret)
enum FnAuth {
    // 飞牛官方 Web 影视客户端内置的公开客户端凭据（原项目 proxy/pkg/fnapi/request.go）
    static var apiKey: String { AppSettings.shared.authxKey.isEmpty ? "NDzZTVxnRKP8Z0jXg1VAMonaG8akvh" : AppSettings.shared.authxKey }
    static var apiSecret: String { AppSettings.shared.authxSecret.isEmpty ? "16CCEB3D-AB42-077D-36A1-F355324E4237" : AppSettings.shared.authxSecret }

    static func md5(_ s: String) -> String {
        Insecure.MD5.hash(data: Data(s.utf8)).map { String(format: "%02x", $0) }.joined()
    }
    static func rand6() -> String { String(Int.random(in: 100000..<1000000)) }

    static func authx(path: String, signData: String) -> String {
        let nonce = rand6()
        let ts = String(Int64(Date().timeIntervalSince1970 * 1000))
        let sign = md5([apiKey, path, nonce, ts, md5(signData), apiSecret].joined(separator: "_"))
        return "nonce=\(nonce)&timestamp=\(ts)&sign=\(sign)"
    }
}
