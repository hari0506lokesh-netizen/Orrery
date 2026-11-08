// Orrery for iPhone.
// A native shell around the Orrery day app. The page ships inside the app bundle and is served
// from a private URL scheme, so it works offline. Data is mirrored to the app's own storage,
// links like orrery://gate/instagram open the lock screen, and taps get real haptics.

import SwiftUI
import UIKit
import WebKit

@main
struct OrreryApp: App {
    @StateObject private var host = WebHost()

    var body: some Scene {
        WindowGroup {
            OrreryWebView(host: host)
                .ignoresSafeArea()
                .background(Color.black.ignoresSafeArea())
                .preferredColorScheme(.dark)
                .onOpenURL { host.handle(url: $0) }
        }
    }
}

struct OrreryWebView: UIViewRepresentable {
    let host: WebHost
    func makeUIView(context: Context) -> WKWebView { host.webView }
    func updateUIView(_ uiView: WKWebView, context: Context) {}
}

@MainActor
final class WebHost: NSObject, ObservableObject, WKNavigationDelegate, WKUIDelegate, WKScriptMessageHandler {
    /// Private scheme the bundled page is served from (orreryapp://localhost/index.html).
    static let pageScheme = "orreryapp"
    /// Public scheme other apps and Shortcuts use (orrery://gate/<app id>).
    static let linkScheme = "orrery"

    let webView: WKWebView
    private let store: NativeStore
    private var pageReady = false
    private var pendingHash: String?

    override init() {
        let store = NativeStore()
        let config = WKWebViewConfiguration()
        config.setURLSchemeHandler(BundleSchemeHandler(), forURLScheme: WebHost.pageScheme)
        config.websiteDataStore = .default()
        config.allowsInlineMediaPlayback = true
        config.mediaTypesRequiringUserActionForPlayback = []
        let controller = WKUserContentController()
        controller.addUserScript(WKUserScript(source: store.bootstrapScript(),
                                              injectionTime: .atDocumentStart,
                                              forMainFrameOnly: true))
        config.userContentController = controller

        let webView = WKWebView(frame: .zero, configuration: config)
        webView.isOpaque = false
        webView.backgroundColor = .black
        webView.scrollView.backgroundColor = .black
        webView.scrollView.contentInsetAdjustmentBehavior = .never
        webView.scrollView.bounces = false
        webView.allowsLinkPreview = false
        #if DEBUG
        if #available(iOS 16.4, *) { webView.isInspectable = true }
        #endif

        self.store = store
        self.webView = webView
        super.init()

        controller.add(WeakMessageHandler(self), name: "native")
        webView.navigationDelegate = self
        webView.uiDelegate = self
        load(hash: nil)
    }

    // MARK: Loading and deep links

    private func load(hash: String?) {
        var address = "\(WebHost.pageScheme)://localhost/index.html"
        if let hash { address += "#" + hash }
        if let url = URL(string: address) { webView.load(URLRequest(url: url)) }
    }

    /// orrery://gate/instagram opens the gate for that app.
    func handle(url: URL) {
        guard url.scheme?.lowercased() == WebHost.linkScheme else { return }
        let parts = ([url.host ?? ""] + url.pathComponents).filter { !$0.isEmpty && $0 != "/" }
        guard parts.count >= 2, parts[0].lowercased() == "gate" else { return }
        let id = String(parts[1].lowercased().filter { $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "-") })
        guard !id.isEmpty else { return }
        let hash = "gate-" + id
        if pageReady {
            webView.evaluateJavaScript("location.hash='#\(hash)'", completionHandler: nil)
        } else {
            pendingHash = hash
        }
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        pageReady = true
        if let hash = pendingHash {
            pendingHash = nil
            webView.evaluateJavaScript("location.hash='#\(hash)'", completionHandler: nil)
        }
    }

    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        pageReady = false
        load(hash: nil)
    }

    func webView(_ webView: WKWebView,
                 decidePolicyFor navigationAction: WKNavigationAction,
                 decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        guard let url = navigationAction.request.url, let scheme = url.scheme?.lowercased() else {
            decisionHandler(.allow)
            return
        }
        if [WebHost.pageScheme, "about", "blob", "data"].contains(scheme) {
            decisionHandler(.allow)
            return
        }
        if scheme == WebHost.linkScheme {
            handle(url: url)
            decisionHandler(.cancel)
            return
        }
        // Everything else the page navigates to (shortcuts://, https links) opens outside the app.
        if navigationAction.targetFrame?.isMainFrame ?? true {
            UIApplication.shared.open(url)
            decisionHandler(.cancel)
            return
        }
        decisionHandler(.allow)
    }

    // MARK: Dialogs and new windows

    func webView(_ webView: WKWebView,
                 runJavaScriptConfirmPanelWithMessage message: String,
                 initiatedByFrame frame: WKFrameInfo,
                 completionHandler: @escaping (Bool) -> Void) {
        guard let presenter = topController() else { completionHandler(false); return }
        let alert = UIAlertController(title: nil, message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel) { _ in completionHandler(false) })
        alert.addAction(UIAlertAction(title: "Replace", style: .destructive) { _ in completionHandler(true) })
        presenter.present(alert, animated: true)
    }

    func webView(_ webView: WKWebView,
                 runJavaScriptAlertPanelWithMessage message: String,
                 initiatedByFrame frame: WKFrameInfo,
                 completionHandler: @escaping () -> Void) {
        guard let presenter = topController() else { completionHandler(); return }
        let alert = UIAlertController(title: nil, message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "OK", style: .default) { _ in completionHandler() })
        presenter.present(alert, animated: true)
    }

    func webView(_ webView: WKWebView,
                 createWebViewWith configuration: WKWebViewConfiguration,
                 for navigationAction: WKNavigationAction,
                 windowFeatures: WKWindowFeatures) -> WKWebView? {
        if let url = navigationAction.request.url { UIApplication.shared.open(url) }
        return nil
    }

    // MARK: Messages from the page

    func userContentController(_ userContentController: WKUserContentController,
                               didReceive message: WKScriptMessage) {
        guard let body = message.body as? [String: Any], let type = body["type"] as? String else { return }
        switch type {
        case "store":
            guard let key = body["k"] as? String else { return }
            if let value = body["v"] as? String { store.set(key, value) } else { store.remove(key) }
        case "haptic":
            Haptics.play(body["kind"] as? String ?? "light")
        case "copy":
            if let text = body["text"] as? String { UIPasteboard.general.string = text }
        case "share":
            guard let text = body["text"] as? String else { return }
            share(text: text, filename: body["filename"] as? String ?? "orrery-backup.json")
        default:
            break
        }
    }

    private func share(text: String, filename: String) {
        let safeName = filename.replacingOccurrences(of: "/", with: "-")
        let file = FileManager.default.temporaryDirectory.appendingPathComponent(safeName)
        do { try Data(text.utf8).write(to: file, options: .atomic) } catch { return }
        let sheet = UIActivityViewController(activityItems: [file], applicationActivities: nil)
        if let popover = sheet.popoverPresentationController {
            popover.sourceView = webView
            popover.sourceRect = CGRect(x: webView.bounds.midX, y: webView.bounds.maxY - 120, width: 1, height: 1)
        }
        topController()?.present(sheet, animated: true)
    }

    private func topController() -> UIViewController? {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        let scene = scenes.first { $0.activationState == .foregroundActive } ?? scenes.first
        var controller = scene?.windows.first { $0.isKeyWindow }?.rootViewController
            ?? scene?.windows.first?.rootViewController
        while let presented = controller?.presentedViewController { controller = presented }
        return controller
    }
}

/// Keeps the page's message handler from retaining the host.
@MainActor
final class WeakMessageHandler: NSObject, WKScriptMessageHandler {
    weak var target: WKScriptMessageHandler?
    init(_ target: WKScriptMessageHandler) { self.target = target }
    func userContentController(_ userContentController: WKUserContentController,
                               didReceive message: WKScriptMessage) {
        target?.userContentController(userContentController, didReceive: message)
    }
}

/// Serves files from the app bundle at orreryapp://localhost/<name>.
final class BundleSchemeHandler: NSObject, WKURLSchemeHandler {
    private static let types: [String: String] = [
        "html": "text/html; charset=utf-8", "js": "text/javascript; charset=utf-8",
        "css": "text/css; charset=utf-8", "json": "application/json", "png": "image/png",
        "svg": "image/svg+xml", "woff2": "font/woff2", "ttf": "font/ttf"
    ]

    func webView(_ webView: WKWebView, start urlSchemeTask: WKURLSchemeTask) {
        guard let url = urlSchemeTask.request.url else {
            urlSchemeTask.didFailWithError(URLError(.badURL))
            return
        }
        // Resources are copied flat into the bundle, so only the last path component matters.
        let requested = url.path.isEmpty || url.path == "/" ? "index.html" : (url.path as NSString).lastPathComponent
        let ext = (requested as NSString).pathExtension
        let name = (requested as NSString).deletingPathExtension
        guard let file = Bundle.main.url(forResource: name, withExtension: ext),
              let data = try? Data(contentsOf: file) else {
            urlSchemeTask.didFailWithError(URLError(.fileDoesNotExist))
            return
        }
        let type = BundleSchemeHandler.types[ext.lowercased()] ?? "application/octet-stream"
        let headers = ["Content-Type": type, "Content-Length": String(data.count), "Cache-Control": "no-cache"]
        guard let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: "HTTP/1.1", headerFields: headers) else {
            urlSchemeTask.didFailWithError(URLError(.cannotParseResponse))
            return
        }
        urlSchemeTask.didReceive(response)
        urlSchemeTask.didReceive(data)
        urlSchemeTask.didFinish()
    }

    func webView(_ webView: WKWebView, stop urlSchemeTask: WKURLSchemeTask) {}
}

/// A copy of the page's saved data in Application Support, so iOS clearing web storage never loses it.
final class NativeStore {
    private let fileURL: URL
    private var values: [String: String]
    private let queue = DispatchQueue(label: "orrery.store", qos: .utility)

    init() {
        let directory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        fileURL = directory.appendingPathComponent("orrery-store.json")
        if let data = try? Data(contentsOf: fileURL),
           let saved = try? JSONDecoder().decode([String: String].self, from: data) {
            values = saved
        } else {
            values = [:]
        }
    }

    func set(_ key: String, _ value: String) {
        values[key] = value
        persist()
    }

    func remove(_ key: String) {
        values.removeValue(forKey: key)
        persist()
    }

    private func persist() {
        let snapshot = values
        let url = fileURL
        queue.async {
            if let data = try? JSONEncoder().encode(snapshot) { try? data.write(to: url, options: .atomic) }
        }
    }

    /// Runs before the page's own script: marks the page as native, restores any saved keys
    /// web storage has lost, and mirrors every later write back to the app.
    func bootstrapScript() -> String {
        let data = (try? JSONEncoder().encode(values)) ?? Data("{}".utf8)
        let json = String(decoding: data, as: UTF8.self)
        return """
        (function(){
          window.ORRERY_NATIVE={version:1};
          var saved=\(json);
          try{for(var k in saved){if(localStorage.getItem(k)===null)localStorage.setItem(k,saved[k]);}}catch(e){}
          function post(m){try{window.webkit.messageHandlers.native.postMessage(m);}catch(e){}}
          var proto=Storage.prototype,setItem=proto.setItem,removeItem=proto.removeItem;
          proto.setItem=function(k,v){setItem.call(this,k,v);if(this===window.localStorage&&/^orrery/.test(String(k)))post({type:"store",k:String(k),v:String(v)});};
          proto.removeItem=function(k){removeItem.call(this,k);if(this===window.localStorage&&/^orrery/.test(String(k)))post({type:"store",k:String(k)});};
        })();
        """
    }
}

@MainActor
enum Haptics {
    static func play(_ kind: String) {
        switch kind {
        case "success": UINotificationFeedbackGenerator().notificationOccurred(.success)
        case "medium": UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        case "soft": UIImpactFeedbackGenerator(style: .soft).impactOccurred()
        default: UIImpactFeedbackGenerator(style: .light).impactOccurred()
        }
    }
}
