import SwiftUI
import WebKit

/// Browser-based sign-in for classic Skyward districts that authenticate through Google, Microsoft, ClassLink, or Clever.
struct WebSignInSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    let address: String
    let districtName: String

    @State private var statusText = "Sign in through your district's login page…"
    @State private var errorMessage: String?

    var body: some View {
        VStack(spacing: 0) {
            if let errorMessage {
                HStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(Palette.bad)
                    Text(errorMessage).font(.footnote)
                    Spacer()
                }
                .padding(10)
                .background(Palette.bad.opacity(0.12))
            } else {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text(statusText).font(.footnote).foregroundStyle(.secondary)
                    Spacer()
                }
                .padding(10)
                .background(.bar)
            }

            if let endpoint = SkywardEndpoint.parse(address) {
                SkywardWebView(url: endpoint.loginURL) { html, finalURL in
                    handlePage(html: html, url: finalURL)
                }
            } else {
                EmptyState(symbol: "globe", title: "Invalid Address", message: "Enter a valid Skyward login address first.")
            }
        }
        .navigationTitle("Web Sign-In")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") { dismiss() }
            }
        }
    }

    private func handlePage(html: String, url: URL) {
        guard let extracted = WebSignInExtractor.extract(from: html) else { return }
        statusText = "Connected to Skyward! Loading your classes…"
        Task {
            do {
                let resolvedAddress = url.deletingLastPathComponent().appendingPathComponent("seplog01.w").absoluteString
                try await model.adoptWebSignIn(
                    address: resolvedAddress.isEmpty ? address : resolvedAddress,
                    districtName: districtName,
                    codes: extracted.codes,
                    home: extracted.home
                )
                dismiss()
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }
}

enum WebSignInExtractor {
    static func extract(from html: String) -> (codes: SkywardSession.Codes, home: SkywardParser.HomeInfo)? {
        let home = SkywardParser.home(html)
        guard let sessionID = home.sessionID, !sessionID.isEmpty,
              let encses = home.encses, !encses.isEmpty else {
            return nil
        }
        let doc = HTMLNode.parse(html)
        func field(_ name: String) -> String {
            if let groups = Str.match("sff\\.sv\\(\\s*'\(name)'\\s*,\\s*'([^']*)'", in: html, options: []) {
                return groups[1]
            }
            if let input = doc.first(where: { $0.tag == "input" && ($0.attr("name") ?? "").caseInsensitiveCompare(name) == .orderedSame }) {
                return input.attr("value") ?? ""
            }
            return ""
        }
        let dwd = field("dwd")
        let wfaacl = field("wfaacl")
        guard !dwd.isEmpty || !wfaacl.isEmpty || html.contains("sf_utilUser") else { return nil }
        let codes = SkywardSession.Codes(
            dwd: dwd,
            wfaacl: wfaacl,
            encses: encses,
            sessionid: sessionID,
            userType: field("User-Type").isEmpty ? "2" : field("User-Type"),
            nameid: field("nameid"),
            duserid: field("duserid")
        )
        return (codes, home)
    }
}

#if os(macOS)
private struct SkywardWebView: NSViewRepresentable {
    let url: URL
    let onPageLoaded: (String, URL) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onPageLoaded: onPageLoaded)
    }

    func makeNSView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .default()
        config.preferences.javaScriptCanOpenWindowsAutomatically = true
        let webView = WKWebView(frame: .zero, configuration: config)
        webView.navigationDelegate = context.coordinator
        webView.uiDelegate = context.coordinator
        webView.load(URLRequest(url: url))
        return webView
    }

    func updateNSView(_ nsView: WKWebView, context: Context) {}
}
#else
private struct SkywardWebView: UIViewRepresentable {
    let url: URL
    let onPageLoaded: (String, URL) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onPageLoaded: onPageLoaded)
    }

    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .default()
        config.preferences.javaScriptCanOpenWindowsAutomatically = true
        let webView = WKWebView(frame: .zero, configuration: config)
        webView.navigationDelegate = context.coordinator
        webView.uiDelegate = context.coordinator
        webView.load(URLRequest(url: url))
        return webView
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {}
}
#endif

private final class Coordinator: NSObject, WKNavigationDelegate, WKUIDelegate {
    let onPageLoaded: (String, URL) -> Void
    private var completed = false

    init(onPageLoaded: @escaping (String, URL) -> Void) {
        self.onPageLoaded = onPageLoaded
    }

    func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration, for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
        if navigationAction.targetFrame == nil, let req = navigationAction.request.url {
            webView.load(URLRequest(url: req))
        }
        return nil
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        guard !completed else { return }
        webView.evaluateJavaScript("document.documentElement.outerHTML") { [weak self] result, _ in
            guard let self, !self.completed, let html = result as? String, let currentURL = webView.url else { return }
            if WebSignInExtractor.extract(from: html) != nil {
                self.completed = true
                DispatchQueue.main.async {
                    self.onPageLoaded(html, currentURL)
                }
            }
        }
    }
}
