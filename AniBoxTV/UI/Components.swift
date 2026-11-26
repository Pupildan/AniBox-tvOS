import SwiftUI

struct PosterCard: View {
    let item: MediaItem
    var width: CGFloat = 260
    var landscape = false
    var action: () -> Void
    @EnvironmentObject var settings: AppSettings
    @Environment(\.isFocused) private var envFocused
    @FocusState private var focused: Bool

    var imageURL: URL? {
        let p = landscape ? (item.backdrop ?? item.poster) : (item.poster ?? item.backdrop)
        return FnClient.shared.imageURL(p, width: landscape ? 800 : 500)
    }
    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 12) {
                ZStack(alignment: .bottomLeading) {
                    RemoteImage(url: imageURL)
                        .aspectRatio(contentMode: .fill)
                        .frame(width: width, height: landscape ? width * 9 / 16 : width * 1.5)
                        .clipped()
                    if item.progress > 0.01 && item.progress < 0.98 {
                        GeometryReader { g in
                            Capsule().fill(.white.opacity(0.25)).frame(height: 6)
                                .overlay(alignment: .leading) { Capsule().fill(.white).frame(width: g.size.width * item.progress, height: 6) }
                        }
                        .frame(height: 6).padding(14)
                    }
                    if item.watched {
                        Image(systemName: "checkmark.circle.fill").font(.title3).foregroundStyle(.green)
                            .padding(12).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                    }
                    if let r = item.rating, r > 0 {
                        Text(String(format: "%.1f", r)).font(.system(size: 20, weight: .bold))
                            .padding(.horizontal, 10).padding(.vertical, 4).glass(10)
                            .padding(10).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    }
                }
                .frame(width: width, height: landscape ? width * 9 / 16 : width * 1.5)
                .clipShape(RoundedRectangle(cornerRadius: settings.posterCornerRadius, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: settings.posterCornerRadius, style: .continuous)
                    .strokeBorder(.white.opacity(focused ? 0.9 : 0.08), lineWidth: focused ? 4 : 1))
                VStack(alignment: .leading, spacing: 4) {
                    Text(item.tvTitle.isEmpty ? item.title : item.tvTitle).font(.system(size: 24, weight: .semibold)).lineLimit(1)
                    Text(item.tvTitle.isEmpty ? item.subtitleLine : item.title).font(.system(size: 20)).foregroundStyle(.secondary).lineLimit(1)
                }
                .frame(width: width, alignment: .leading)
                .opacity(focused ? 1 : 0.75)
            }
        }
        .buttonStyle(CardButtonStyle())
        .focused($focused)
    }
}

struct ShelfRow<Content: View>: View {
    let title: String
    var trailing: String? = nil
    @ViewBuilder var content: () -> Content
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                Text(title).font(.system(size: 34, weight: .bold))
                if let trailing { Text(trailing).font(.system(size: 22)).foregroundStyle(.secondary) }
            }
            .padding(.horizontal, 80)
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(alignment: .top, spacing: 44) { content() }
                    .padding(.horizontal, 80).padding(.vertical, 36)
            }
            .scrollClipDisabled()
        }
        .focusSection()
    }
}

struct LoadingView: View {
    var text = "加载中…"
    var body: some View {
        VStack(spacing: 20) { ProgressView().scaleEffect(1.5); Text(text).foregroundStyle(.secondary) }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct ErrorView: View {
    let message: String
    var retry: (() -> Void)? = nil
    var body: some View {
        VStack(spacing: 28) {
            Image(systemName: "exclamationmark.triangle").font(.system(size: 64)).foregroundStyle(.yellow)
            Text(message).font(.title3).multilineTextAlignment(.center).frame(maxWidth: 1100)
            if let retry { Button("重试", action: retry).buttonStyle(GlassButtonStyle()) }
        }
        .padding(60).glass(36).frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct Chip: View {
    let text: String
    var selected = false
    let action: () -> Void
    var body: some View {
        Button(action: action) { Text(text) }
            .buttonStyle(GlassButtonStyle(radius: 30, prominent: selected))
    }
}

struct PersonCard: View {
    let person: ExtMeta.Person
    var action: () -> Void = {}
    var body: some View {
        Button(action: action) {
            VStack(spacing: 10) {
                RemoteImage(url: person.avatar.flatMap(URL.init(string:)))
                    .aspectRatio(contentMode: .fill).frame(width: 160, height: 160).clipShape(Circle())
                Text(person.name).font(.system(size: 22, weight: .semibold)).lineLimit(1)
                Text(person.role).font(.system(size: 18)).foregroundStyle(.secondary).lineLimit(1)
            }
            .frame(width: 190)
        }
        .buttonStyle(CardButtonStyle())
    }
}
