#if os(macOS)
import SwiftUI
import WebKit
import QuotaCore

struct ClaudeSignIn: NSViewRepresentable {
    let completion: (Credential) -> Void
    func makeCoordinator() -> Coordinator { Coordinator(completion: completion) }
    func makeNSView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        // A fresh cookie store on every attempt permits separate accounts and no shared Safari state.
        configuration.websiteDataStore = .nonPersistent()
        let view = WKWebView(frame: .zero, configuration: configuration)
        view.navigationDelegate = context.coordinator
        view.uiDelegate = context.coordinator
        let cookies = configuration.websiteDataStore.httpCookieStore
        context.coordinator.cookieStore = cookies; cookies.add(context.coordinator)
        view.load(URLRequest(url: URL(string: "https://claude.ai/login")!))
        return view
    }
    func updateNSView(_ view: WKWebView, context: Context) {}
    static func dismantleNSView(_ view: WKWebView, coordinator: Coordinator) {
        view.stopLoading()
        coordinator.cookieStore?.remove(coordinator)
        coordinator.closed = true
    }
    @MainActor
    final class Coordinator: NSObject, WKHTTPCookieStoreObserver, WKNavigationDelegate, WKUIDelegate {
        let completion: (Credential) -> Void
        var cookieStore: WKHTTPCookieStore?
        var finished = false
        var closed = false
        init(completion: @escaping (Credential) -> Void) { self.completion = completion }
        nonisolated func cookiesDidChange(in cookieStore: WKHTTPCookieStore) {
            Task { @MainActor [weak self] in self?.readCookies() }
        }
        private func readCookies() {
            guard let cookieStore else { return }
            cookieStore.getAllCookies { [weak self] cookies in
                guard let self, !self.finished, !self.closed,
                      let cookie = cookies.first(where: {
                          $0.name == "sessionKey" && ["claude.ai", ".claude.ai"].contains($0.domain) && !$0.value.isEmpty
                      }) else { return }
                self.finished = true
                self.completion(Credential(kind: .claudeWeb, secret: cookie.value))
            }
        }
        func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration,
                     for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
            if let url = navigationAction.request.url, ["https", "http"].contains(url.scheme ?? "") {
                webView.load(navigationAction.request)
            }
            return nil
        }
        func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction,
                     decisionHandler: @escaping @MainActor @Sendable (WKNavigationActionPolicy) -> Void) {
            guard let scheme = navigationAction.request.url?.scheme,
                  ["https", "http", "about"].contains(scheme) else { decisionHandler(.cancel); return }
            decisionHandler(.allow)
        }
    }
}
#endif
