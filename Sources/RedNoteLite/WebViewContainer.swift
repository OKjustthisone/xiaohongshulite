import AppKit
import SwiftUI
import WebKit

/// True macOS frosted glass background backed by NSVisualEffectView.
struct VisualEffectBackground: NSViewRepresentable {
    let material: NSVisualEffectView.Material
    let blendingMode: NSVisualEffectView.BlendingMode

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = material
        view.blendingMode = blendingMode
        view.state = .followsWindowActiveState
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {
        nsView.material = material
        nsView.blendingMode = blendingMode
    }
}

/// Allows dragging the borderless/hidden-titlebar macOS window by empty header space.
struct WindowDragRegion: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        DraggableNSView()
    }
    func updateNSView(_ nsView: NSView, context: Context) {}

    private final class DraggableNSView: NSView {
        override var mouseDownCanMoveWindow: Bool { true }
    }
}

struct WebViewContainer: NSViewRepresentable {
    let webView: WKWebView?

    func makeNSView(context: Context) -> NSView {
        let host = NSView(frame: .zero)
        host.wantsLayer = true
        host.layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor
        attach(webView, to: host)
        return host
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        if let webView {
            if webView.superview !== nsView {
                nsView.subviews.forEach { $0.removeFromSuperview() }
                attach(webView, to: nsView)
            }
        } else {
            nsView.subviews.forEach { $0.removeFromSuperview() }
        }
    }

    private func attach(_ webView: WKWebView?, to host: NSView) {
        guard let webView else { return }
        webView.translatesAutoresizingMaskIntoConstraints = false
        host.addSubview(webView)
        NSLayoutConstraint.activate([
            webView.leadingAnchor.constraint(equalTo: host.leadingAnchor),
            webView.trailingAnchor.constraint(equalTo: host.trailingAnchor),
            webView.topAnchor.constraint(equalTo: host.topAnchor),
            webView.bottomAnchor.constraint(equalTo: host.bottomAnchor)
        ])
    }
}

struct AsyncThumbnailView: View {
    let urlString: String?
    var width: CGFloat = 56
    var height: CGFloat = 56
    var cornerRadius: CGFloat = 8
    @State private var image: NSImage?

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(Color.secondary.opacity(0.1))
            if let image {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                Image(systemName: "photo")
                    .font(.system(size: min(width, height) * 0.3))
                    .foregroundStyle(.secondary.opacity(0.5))
            }
        }
        .frame(width: width, height: height)
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        .task(id: urlString) {
            guard let urlString, !urlString.isEmpty else {
                image = nil
                return
            }
            if let cached = ThumbnailCache.shared.image(for: urlString) {
                image = cached
                return
            }
            image = await ThumbnailCache.shared.load(urlString: urlString, maxPixelSize: max(width, height) * 2)
        }
    }
}

/// Waterfall card cover image that preserves the photo's natural aspect ratio (clamped between
/// portrait 3:4 and landscape 4:3) just like Xiaohongshu's home waterfall grid.
struct AsyncCoverImageView: View {
    let urlString: String?
    var cornerRadius: CGFloat = 12
    @State private var image: NSImage?

    private var clampedAspectRatio: CGFloat {
        guard let image, image.size.height > 0 else { return 0.8 } // Default 4:5 portrait ratio
        let ratio = image.size.width / image.size.height
        return min(max(ratio, 0.72), 1.32)
    }

    var body: some View {
        ZStack {
            Color.secondary.opacity(0.09)
            if let image {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                Image(systemName: "photo")
                    .font(.system(size: 26))
                    .foregroundStyle(.secondary.opacity(0.45))
            }
        }
        .aspectRatio(clampedAspectRatio, contentMode: .fit)
        .frame(maxWidth: .infinity)
        .clipped()
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        .task(id: urlString) {
            guard let urlString, !urlString.isEmpty else {
                image = nil
                return
            }
            if let cached = ThumbnailCache.shared.image(for: urlString) {
                image = cached
                return
            }
            image = await ThumbnailCache.shared.load(urlString: urlString, maxPixelSize: 520)
        }
    }
}
