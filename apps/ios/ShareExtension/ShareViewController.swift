import UIKit
import UniformTypeIdentifiers

/// Share-extension principal class: when the user shares a 懒饭 / 下厨房 recipe
/// link (or page) into 食材管家, it extracts the URL, host-gates it, and hands it
/// to the main app via the custom scheme `com.sunpebble.freshpantry://import-recipe?url=…`.
/// The app then opens 新建食谱 pre-filled for AI import (parity with the Flutter
/// share intent). The success path stays UI-less — forward and dismiss
/// immediately; an unsupported share (no URL / unknown host) raises one alert
/// before closing, because the activation rule surfaces the entry on ANY web
/// page or text and a silent close reads as "imported" when nothing happened.
///
/// Uses a custom-scheme handoff (NOT an App Group), so the MAIN app's signing /
/// entitlements are unchanged — only this plain extension bundle is added.
final class ShareViewController: UIViewController {
    /// Recipe hosts the importer understands (mirrors Flutter `kSupportedRecipeHosts`).
    private static let supportedHosts = ["lanfanapp.com", "xiachufang.com"]

    /// `viewDidAppear` re-fires when a presented alert tears down — without this
    /// guard the share would be re-processed (and could re-alert forever).
    private var didHandleShare = false

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        guard !didHandleShare else { return }
        didHandleShare = true
        Task {
            let url = await extractURL()
            if let url, let supported = Self.supportedRecipeURL(url) {
                open(recipe: supported)
                complete()
            } else {
                showUnsupportedNotice(foundURL: url != nil)
            }
        }
    }

    /// One-tap alert explaining why nothing will be imported, completing the
    /// request only after dismissal (the extension's sole failure surface — it
    /// cannot toast, and closing silently is indistinguishable from success).
    private func showUnsupportedNotice(foundURL: Bool) {
        let alert = UIAlertController(
            title: "无法导入",
            message: foundURL
                ? "目前仅支持「懒饭」和「下厨房」的菜谱链接。"
                : "分享内容里没有找到链接，目前仅支持「懒饭」和「下厨房」的菜谱链接。",
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: "知道了", style: .default) { [weak self] _ in
            self?.complete()
        })
        present(alert, animated: true)
    }

    /// Pulls the first URL (or a URL embedded in shared text) from the input items.
    private func extractURL() async -> URL? {
        let items = (extensionContext?.inputItems as? [NSExtensionItem]) ?? []
        for item in items {
            for provider in item.attachments ?? [] {
                if provider.hasItemConformingToTypeIdentifier(UTType.url.identifier),
                   let url = try? await provider.loadItem(forTypeIdentifier: UTType.url.identifier) as? URL {
                    return url
                }
                if provider.hasItemConformingToTypeIdentifier(UTType.plainText.identifier),
                   let text = try? await provider.loadItem(forTypeIdentifier: UTType.plainText.identifier) as? String,
                   let url = Self.firstURL(in: text) {
                    return url
                }
            }
        }
        return nil
    }

    /// Returns `url` only if its host is a supported recipe site.
    private static func supportedRecipeURL(_ url: URL) -> URL? {
        guard let host = url.host?.lowercased() else { return nil }
        let matches = supportedHosts.contains { host == $0 || host.hasSuffix(".\($0)") }
        return matches ? url : nil
    }

    /// First http(s) URL embedded in free text (shared pages often arrive as text).
    private static func firstURL(in text: String) -> URL? {
        let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue)
        let range = NSRange(text.startIndex..., in: text)
        return detector?.firstMatch(in: text, range: range)?.url
    }

    /// Hands the recipe URL to the main app via the custom scheme.
    ///
    /// A Share extension can NOT use `UIApplication.open` (unavailable in
    /// extensions) nor `extensionContext.open` (Today-widget-only — it silently
    /// no-ops here). The portable workaround is to walk the responder chain to the
    /// app object and invoke its `openURL:`; this opens the containing app (which
    /// registers `com.sunpebble.freshpantry://`). It's an undocumented selector, but
    /// the standard share-extension handoff and low-risk for this TestFlight app.
    @MainActor
    private func open(recipe url: URL) {
        var components = URLComponents()
        components.scheme = "com.sunpebble.freshpantry"
        components.host = "import-recipe"
        components.queryItems = [URLQueryItem(name: "url", value: url.absoluteString)]
        guard let appURL = components.url else { return }
        let selector = NSSelectorFromString("openURL:")
        var responder: UIResponder? = self
        while let current = responder {
            if current.responds(to: selector) {
                _ = current.perform(selector, with: appURL)
                return
            }
            responder = current.next
        }
    }

    private func complete() {
        extensionContext?.completeRequest(returningItems: [], completionHandler: nil)
    }
}
