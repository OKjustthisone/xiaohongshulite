import AppKit
import Foundation
import ImageIO

/// Ultra-lightweight bounded thumbnail cache (~8 MB cap) using ImageIO downsampling
/// so list views never retain full-resolution images in memory.
final class ThumbnailCache: @unchecked Sendable {
    static let shared = ThumbnailCache()

    private let cache: NSCache<NSString, NSImage> = {
        let c = NSCache<NSString, NSImage>()
        c.countLimit = 48
        c.totalCostLimit = 8 * 1024 * 1024
        return c
    }()

    private let session: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.requestCachePolicy = .returnCacheDataElseLoad
        config.timeoutIntervalForRequest = 8
        config.urlCache = URLCache(memoryCapacity: 2 * 1024 * 1024, diskCapacity: 10 * 1024 * 1024)
        return URLSession(configuration: config)
    }()

    func image(for urlString: String) -> NSImage? {
        cache.object(forKey: urlString as NSString)
    }

    @MainActor
    func load(urlString: String, maxPixelSize: CGFloat = 140) async -> NSImage? {
        if let cached = image(for: urlString) {
            return cached
        }
        guard let url = URL(string: urlString) else { return nil }
        var request = URLRequest(url: url)
        request.setValue("https://www.xiaohongshu.com/", forHTTPHeaderField: "Referer")
        request.setValue(
            "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.2 Safari/605.1.15",
            forHTTPHeaderField: "User-Agent"
        )

        do {
            let (data, _) = try await session.data(for: request)
            guard let cgImage = Self.downsampleCGImage(data: data, maxPixelSize: maxPixelSize) else {
                return nil
            }
            let downsampled = NSImage(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height))
            let estimatedCost = Int(cgImage.width * cgImage.height * 4)
            cache.setObject(downsampled, forKey: urlString as NSString, cost: estimatedCost)
            return downsampled
        } catch {
            return nil
        }
    }

    func clear() {
        cache.removeAllObjects()
        session.configuration.urlCache?.removeAllCachedResponses()
    }

    private static func downsampleCGImage(data: Data, maxPixelSize: CGFloat) -> CGImage? {
        let options: [CFString: Any] = [kCGImageSourceShouldCache: false]
        guard let source = CGImageSourceCreateWithData(data as CFData, options as CFDictionary) else {
            return nil
        }
        let thumbOptions: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixelSize
        ]
        return CGImageSourceCreateThumbnailAtIndex(source, 0, thumbOptions as CFDictionary)
    }
}
