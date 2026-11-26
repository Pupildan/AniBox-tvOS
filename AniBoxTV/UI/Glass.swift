import SwiftUI

/// 液态玻璃：tvOS 26 使用系统 glassEffect，旧系统回退为毛玻璃材质
struct GlassModifier: ViewModifier {
    var radius: CGFloat = 28
    var interactive = false
    var tint: Color? = nil
    func body(content: Content) -> some View {
        #if compiler(>=6.2)
        if #available(tvOS 26.0, *) {
            content.glassEffect(glass, in: .rect(cornerRadius: radius))
        } else { fallback(content) }
        #else
        fallback(content)
        #endif
    }
    #if compiler(>=6.2)
    @available(tvOS 26.0, *)
    var glass: Glass {
        var g = Glass.regular
        if let tint { g = g.tint(tint) }
        if interactive { g = g.interactive() }
        return g
    }
    #endif
    func fallback(_ c: Content) -> some View {
        c.background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: radius, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: radius, style: .continuous).strokeBorder(.white.opacity(0.18), lineWidth: 1))
    }
}

extension View {
    func glass(_ radius: CGFloat = 28, interactive: Bool = false, tint: Color? = nil) -> some View {
        modifier(GlassModifier(radius: radius, interactive: interactive, tint: tint))
    }
}

/// 玻璃按钮样式：焦点时放大、提亮（遥控器焦点反馈）
struct GlassButtonStyle: ButtonStyle {
    var radius: CGFloat = 22
    var prominent = false
    func makeBody(configuration: Configuration) -> some View {
        GlassButtonBody(configuration: configuration, radius: radius, prominent: prominent)
    }
    struct GlassButtonBody: View {
        let configuration: Configuration
        let radius: CGFloat
        let prominent: Bool
        @Environment(\.isFocused) var focused
        var body: some View {
            configuration.label
                .font(.system(size: 26, weight: .semibold))
                .padding(.horizontal, 30).padding(.vertical, 16)
                .foregroundStyle(focused ? .black : .white)
                .background {
                    RoundedRectangle(cornerRadius: radius, style: .continuous)
                        .fill(focused ? Color.white : (prominent ? Color.accentColor.opacity(0.55) : .clear))
                }
                .glass(radius, interactive: true)
                .scaleEffect(configuration.isPressed ? 0.96 : (focused ? 1.08 : 1))
                .shadow(color: .black.opacity(focused ? 0.45 : 0), radius: 20, y: 10)
                .animation(.spring(response: 0.3, dampingFraction: 0.7), value: focused)
        }
    }
}

/// 卡片按钮：只给焦点放大+阴影，不加背景（海报卡片用）
struct CardButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View { Body(configuration: configuration) }
    struct Body: View {
        let configuration: Configuration
        @Environment(\.isFocused) var focused
        var body: some View {
            configuration.label
                .scaleEffect(configuration.isPressed ? 0.97 : (focused ? 1.1 : 1))
                .shadow(color: .black.opacity(focused ? 0.6 : 0.2), radius: focused ? 30 : 8, y: focused ? 18 : 4)
                .zIndex(focused ? 1 : 0)
                .animation(.spring(response: 0.32, dampingFraction: 0.72), value: focused)
        }
    }
}

struct AppBackground: View {
    var image: URL? = nil
    var body: some View {
        ZStack {
            LinearGradient(colors: [Color(red: 0.06, green: 0.07, blue: 0.12), Color(red: 0.02, green: 0.02, blue: 0.05)],
                           startPoint: .top, endPoint: .bottom)
            if let image {
                RemoteImage(url: image).scaledToFill().blur(radius: 60).opacity(0.45)
            }
            RadialGradient(colors: [Color.purple.opacity(0.18), .clear], center: .topLeading, startRadius: 0, endRadius: 1400)
            RadialGradient(colors: [Color.cyan.opacity(0.12), .clear], center: .bottomTrailing, startRadius: 0, endRadius: 1200)
        }
        .ignoresSafeArea()
    }
}
