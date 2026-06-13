import SwiftUI
import SafariServices

/// 用系统 SFSafariViewController 在应用内打开菜谱视频外链(B站/YouTube/下厨房等)。
/// 视频本身不下载、不托管,仅以外链播放。
struct SafariView: UIViewControllerRepresentable {
    let url: URL

    func makeUIViewController(context: Context) -> SFSafariViewController {
        SFSafariViewController(url: url)
    }

    func updateUIViewController(_ controller: SFSafariViewController, context: Context) {}
}
