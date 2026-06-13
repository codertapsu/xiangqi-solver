import UIKit
import Social
import ImageIO

/// Thin, self-contained iOS share-in shim — NO Flutter engine, NO plugin import.
///
/// iOS forbids both an overlay over other apps and on-demand cross-app capture,
/// so Android's Solver Mode has no iOS equivalent. Instead the user screenshots
/// their Xiangqi game in another app and shares it in here. This extension writes
/// the image into the shared App Group container and deep-links back into the
/// Flutter app via the `ShareMedia-<host bundle id>` URL scheme.
///
/// The payload format matches exactly what `receive_sharing_intent` reads on the
/// Flutter side (UserDefaults suite `group.<host bundle id>`, key "ShareKey":
/// a JSON array of `{path, mimeType, type}`). The Flutter app then runs the same
/// `analyzeScreenshot()` pipeline used everywhere else. We deliberately avoid
/// importing the plugin (it links Flutter, which we don't want in a ~120 MB-capped
/// extension) and replicate its tiny write+redirect contract instead.
/// See docs/IOS_PORT.md §3.
class ShareViewController: SLComposeServiceViewController {

    private let userDefaultsKey = "ShareKey"
    private let schemePrefix = "ShareMedia"
    private let imageTypeId = "public.image"

    /// Vision pixel budget (mirrors the backend + Android capture): models
    /// downscale to ~2048px / shortest side 768px before reading, so larger
    /// uploads only cost transfer time. JPEG 0.92 keeps glyph edges crisp.
    private let maxShortSide: CGFloat = 768
    private let maxLongSide: CGFloat = 2048
    private let jpegQuality: CGFloat = 0.92

    /// Extension id is "<host>.ShareExtension" → strip the last component.
    private var hostAppBundleIdentifier: String {
        let id = Bundle.main.bundleIdentifier ?? ""
        if let dot = id.lastIndex(of: ".") { return String(id[..<dot]) }
        return id
    }
    private var appGroupId: String { "group.\(hostAppBundleIdentifier)" }

    override func isContentValid() -> Bool { true }
    override func configurationItems() -> [Any]! { [] }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        handleShare()
    }

    override func didSelectPost() {
        extensionContext?.completeRequest(returningItems: [], completionHandler: nil)
    }

    private func handleShare() {
        guard
            let item = extensionContext?.inputItems.first as? NSExtensionItem,
            let provider = item.attachments?.first(where: {
                $0.hasItemConformingToTypeIdentifier(imageTypeId)
            })
        else { return finish() }

        provider.loadItem(forTypeIdentifier: imageTypeId, options: nil) { [weak self] data, _ in
            guard let self = self else { return }
            if let url = data as? URL {
                self.save(copyingFileAt: url)
            } else if let image = data as? UIImage {
                self.save(image: image)
            } else if let raw = data as? Data,
                      let source = CGImageSourceCreateWithData(raw as CFData, nil),
                      let jpeg = self.downsampledJpeg(from: source) {
                // Memory-bounded: never materialize the full-resolution bitmap.
                self.write(jpeg: jpeg)
            } else {
                self.finish()
            }
        }
    }

    private func container() -> URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroupId)
    }

    private func save(copyingFileAt src: URL) {
        // Prefer re-encoding to a downscaled JPEG: full-size screenshots/photos
        // upload several MB the vision model would discard anyway, and HEIC
        // (the iOS camera default) must be converted regardless — the backend
        // accepts only PNG/JPEG/WebP. ImageIO decodes DOWNSAMPLED (a full
        // 48 MP decode would blow the extension's ~120 MB memory cap). Fall
        // back to a raw copy when decoding fails (e.g. an exotic format).
        if let source = CGImageSourceCreateWithURL(src as CFURL, nil),
           let jpeg = downsampledJpeg(from: source) {
            return write(jpeg: jpeg)
        }
        guard let dir = container() else { return finish() }
        let name = src.lastPathComponent.isEmpty
            ? "\(UUID().uuidString).png" : src.lastPathComponent
        let dst = dir.appendingPathComponent(name)
        do {
            if FileManager.default.fileExists(atPath: dst.path) {
                try FileManager.default.removeItem(at: dst)
            }
            try FileManager.default.copyItem(at: src, to: dst)
            persistAndRedirect(fileURL: dst, mimeType: mimeType(forExtension: dst.pathExtension))
        } catch {
            finish()
        }
    }

    private func save(image: UIImage) {
        guard let jpeg = downscaledJpeg(from: image) else { return finish() }
        write(jpeg: jpeg)
    }

    private func write(jpeg: Data) {
        guard let dir = container() else { return finish() }
        let dst = dir.appendingPathComponent("\(UUID().uuidString).jpg")
        do {
            try jpeg.write(to: dst)
            persistAndRedirect(fileURL: dst, mimeType: "image/jpeg")
        } catch {
            finish()
        }
    }

    /// Memory-bounded downscale via ImageIO: decodes the image already
    /// downsampled to [maxLongSide] (with EXIF orientation applied), instead
    /// of materializing the full-resolution bitmap.
    private func downsampledJpeg(from source: CGImageSource) -> Data? {
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxLongSide,
        ]
        guard let cg = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
            return nil
        }
        return UIImage(cgImage: cg).jpegData(compressionQuality: jpegQuality)
    }

    /// Scale down (never up) so the shortest side fits [maxShortSide] and the
    /// longest fits [maxLongSide], then encode JPEG. Used for payloads that
    /// arrive ALREADY decoded as UIImage (no file to downsample from).
    private func downscaledJpeg(from image: UIImage) -> Data? {
        let w = image.size.width * image.scale
        let h = image.size.height * image.scale
        guard w > 0, h > 0 else { return image.jpegData(compressionQuality: jpegQuality) }
        let scale = min(maxShortSide / min(w, h), maxLongSide / max(w, h), 1)
        if scale >= 1 { return image.jpegData(compressionQuality: jpegQuality) }
        let size = CGSize(width: max(1, floor(w * scale)), height: max(1, floor(h * scale)))
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        let resized = UIGraphicsImageRenderer(size: size, format: format).image { _ in
            image.draw(in: CGRect(origin: .zero, size: size))
        }
        return resized.jpegData(compressionQuality: jpegQuality)
    }

    private func persistAndRedirect(fileURL: URL, mimeType: String) {
        // Decoded absolute file URL string; the Flutter side strips "file://".
        let path = fileURL.absoluteString.removingPercentEncoding ?? fileURL.absoluteString
        let payload: [[String: Any]] = [["path": path, "mimeType": mimeType, "type": "image"]]
        if let json = try? JSONSerialization.data(withJSONObject: payload, options: []) {
            UserDefaults(suiteName: appGroupId)?.set(json, forKey: userDefaultsKey)
        }
        DispatchQueue.main.async { [weak self] in self?.redirectToHost() }
    }

    private func redirectToHost() {
        guard let url = URL(string: "\(schemePrefix)-\(hostAppBundleIdentifier):share") else {
            return finish()
        }
        // Walk the responder chain to reach UIApplication and open the host app.
        var responder: UIResponder? = self
        if #available(iOS 18.0, *) {
            while responder != nil {
                if let application = responder as? UIApplication {
                    application.open(url, options: [:], completionHandler: nil)
                }
                responder = responder?.next
            }
        } else {
            let selectorOpenURL = sel_registerName("openURL:")
            while responder != nil {
                if responder?.responds(to: selectorOpenURL) == true {
                    responder?.perform(selectorOpenURL, with: url)
                }
                responder = responder?.next
            }
        }
        extensionContext?.completeRequest(returningItems: [], completionHandler: nil)
    }

    private func finish() {
        DispatchQueue.main.async { [weak self] in
            self?.extensionContext?.completeRequest(returningItems: [], completionHandler: nil)
        }
    }

    private func mimeType(forExtension ext: String) -> String {
        switch ext.lowercased() {
        case "png": return "image/png"
        case "jpg", "jpeg": return "image/jpeg"
        case "heic": return "image/heic"
        case "gif": return "image/gif"
        case "webp": return "image/webp"
        default: return "image/png"
        }
    }
}
