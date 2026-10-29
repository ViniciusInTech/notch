import AppKit
import ImageIO
import NotchCore

private final class CachedArtwork: NSObject {
    let image: NSImage
    let accent: ArtworkAccent
    init(image: NSImage, accent: ArtworkAccent) { self.image = image; self.accent = accent }
}

private struct DecodedArtwork {
    let thumbnail: CGImage
    let accent: ArtworkAccent
}

@MainActor final class ArtworkStore: ObservableObject {
    @Published private(set) var image: NSImage?
    @Published private(set) var accent: ArtworkAccent = .fallback
    private let cache = NSCache<NSURL, CachedArtwork>()
    private var task: Task<Void, Never>?
    private var currentURL: URL?
    private var retryAfter = Date.distantPast
    private var loading = false

    /// No URLCache: thumbnails already live in `cache`, so raw responses never touch memory or disk twice.
    nonisolated private static let session: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.urlCache = nil
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.httpMaximumConnectionsPerHost = 2
        return URLSession(configuration: configuration)
    }()

    init() { cache.countLimit = 12; cache.totalCostLimit = 12 * 1024 * 1024 }

    func load(_ url: URL?) {
        guard url != currentURL || (image == nil && !loading && Date() >= retryAfter) else { return }
        currentURL = url
        task?.cancel()
        image = nil
        accent = .fallback
        loading = false
        guard let url, url.scheme == "https" else { return }
        if let cached = cache.object(forKey: url as NSURL) { image = cached.image; accent = cached.accent; return }
        loading = true
        task = Task { [weak self] in
            do {
                let decoded = try await Self.fetchThumbnail(url)
                guard !Task.isCancelled, let self, self.currentURL == url else { return }
                self.loading = false
                guard let decoded else { self.retryAfter = Date().addingTimeInterval(30); return }
                let image = NSImage(cgImage: decoded.thumbnail, size: NSSize(width: 128, height: 128))
                self.cache.setObject(CachedArtwork(image: image, accent: decoded.accent), forKey: url as NSURL, cost: 256 * 256 * 4)
                self.image = image
                self.accent = decoded.accent
            } catch {
                guard !Task.isCancelled, let self, self.currentURL == url else { return }
                self.loading = false
                self.retryAfter = Date().addingTimeInterval(30)
            }
        }
    }

    /// Network streaming and ImageIO decoding execute outside the UI actor.
    nonisolated private static func fetchThumbnail(_ url: URL) async throws -> DecodedArtwork? {
        var request = URLRequest(url: url)
        request.timeoutInterval = 8
        let (bytes, response) = try await session.bytes(for: request)
        guard let response = response as? HTTPURLResponse, response.statusCode == 200,
              response.url?.scheme == "https", response.expectedContentLength <= 2_000_000 else { return nil }
        var data = Data()
        for try await byte in bytes {
            try Task.checkCancellation()
            data.append(byte)
            guard data.count <= 2_000_000 else { return nil }
        }
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        guard let thumbnail = CGImageSourceCreateThumbnailAtIndex(source, 0, [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceThumbnailMaxPixelSize: 256
        ] as CFDictionary) else { return nil }
        var pixels = [UInt8](repeating: 0, count: 16 * 16 * 4)
        let accent = pixels.withUnsafeMutableBytes { buffer -> ArtworkAccent in
            guard let context = CGContext(data: buffer.baseAddress, width: 16, height: 16,
                bitsPerComponent: 8, bytesPerRow: 16 * 4, space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue) else { return .fallback }
            context.draw(thumbnail, in: CGRect(x: 0, y: 0, width: 16, height: 16))
            return ArtworkPalette.dominantColor(inRGBA: Array(buffer))
        }
        return DecodedArtwork(thumbnail: thumbnail, accent: accent)
    }
}
