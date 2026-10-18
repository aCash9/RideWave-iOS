import SwiftUI
import ImageIO

struct PlaylistArtwork: View {
    let url: URL?
    let name: String
    @State private var image: UIImage?

    var body: some View {
        ZStack {
            Color(white: 0.08)
            if let image {
                Image(uiImage: image).resizable().scaledToFill()
            } else {
                Text(name).font(.title3.weight(.semibold)).multilineTextAlignment(.center)
                    .lineLimit(3).padding(20)
            }
        }
        .accessibilityHidden(true)
        .task(id: url) {
            image = nil
            guard let url else { return }
            let loaded = await Self.load(url)
            if !Task.isCancelled { image = loaded }
        }
    }

    // No authorization headers or persistent image cache. Bound network and decode costs.
    @concurrent private static func load(_ url: URL) async -> UIImage? {
        guard url.scheme == "https" else { return nil }
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 10
        configuration.timeoutIntervalForResource = 15
        let session = URLSession(configuration: configuration)
        defer { session.invalidateAndCancel() }
        do {
            let (bytes, response) = try await session.bytes(from: url)
            guard let response = response as? HTTPURLResponse, response.statusCode == 200,
                  response.url?.scheme == "https", response.expectedContentLength <= 2_097_152 else { return nil }
            var data = Data()
            for try await byte in bytes {
                try Task.checkCancellation()
                guard data.count < 2_097_152 else { return nil }
                data.append(byte)
            }
            guard let source = CGImageSourceCreateWithData(data as CFData, nil),
                  let thumbnail = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                    kCGImageSourceCreateThumbnailFromImageAlways: true,
                    kCGImageSourceCreateThumbnailWithTransform: true,
                    kCGImageSourceThumbnailMaxPixelSize: 512,
                    kCGImageSourceShouldCacheImmediately: true
                  ] as CFDictionary) else { return nil }
            return UIImage(cgImage: thumbnail)
        } catch { return nil }
    }
}
