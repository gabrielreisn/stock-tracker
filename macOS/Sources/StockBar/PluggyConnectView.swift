import SwiftUI
import WebKit

/// Pluggy's Connect widget in a window: the user picks MeuPluggy (or another connector), signs in, and the
/// new item comes back. With `updating`, it reconnects that item instead (e.g. after consent expires).
struct PluggyConnectView: View {
    @Environment(PluggyStore.self) private var pluggy
    @Environment(\.dismiss) private var dismiss
    /// The item to reconnect; nil to add a new connection.
    @State private var target: String?
    @State private var alreadyConnected = false

    init(updating: String?) { _target = State(initialValue: updating) }

    @State private var session: (token: String, connectorId: Int?)?
    @State private var error: String?
    @State private var finishing = false
    @State private var lastError: String?

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(target == nil ? "Connect account" : "Renew connection").font(.headline)
                Spacer()
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
            }
            .padding(12)
            Divider()
            if let lastError {
                Label(lastError, systemImage: "info.circle")
                    .font(.caption).foregroundStyle(.secondary).lineLimit(3)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 12).padding(.vertical, 6)
                    .textSelection(.enabled)
                Divider()
            }
            ZStack {
                if let session {
                    ConnectWebView(token: session.token, connectorId: session.connectorId, updating: target) { event in
                        handle(event)
                    }
                    .id(session.token)
                }
                if session == nil || finishing {
                    VStack(spacing: 10) {
                        ProgressView()
                        Text(finishing ? "Syncing your accounts…" : "Opening Pluggy Connect…").foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(.background)
                }
                if let error {
                    VStack(spacing: 10) {
                        Image(systemName: "exclamationmark.triangle").font(.largeTitle).foregroundStyle(.orange)
                        Text(error).multilineTextAlignment(.center).frame(maxWidth: 340)
                        Button("Close") { dismiss() }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(.background)
                }
            }
        }
        .frame(width: 460, height: 720)
        .overlay { if alreadyConnected { alreadyConnectedNotice } }
        .task(id: target) {
            session = nil
            do { session = try await pluggy.connectSession(updating: target) }
            catch { self.error = "Couldn't start Pluggy Connect: \(error.localizedDescription)" }
        }
    }

    /// Pluggy refuses a second connection with the same Meu Pluggy login (it would import everything twice):
    /// one MeuPluggy connection already covers every bank authorized in Meu Pluggy.
    private var alreadyConnectedNotice: some View {
        VStack(spacing: 12) {
            Image(systemName: "checkmark.seal").font(.largeTitle).foregroundStyle(.green)
            Text("This Meu Pluggy account is already connected").font(.headline)
            Text("One MeuPluggy connection covers every bank and broker you authorize in Meu Pluggy. To add another institution, authorize it at meu.pluggy.ai; it shows up on StockBar's next sync.")
                .multilineTextAlignment(.center).foregroundStyle(.secondary)
                .frame(maxWidth: 360)
            HStack {
                Link("Open Meu Pluggy", destination: URL(string: "https://meu.pluggy.ai")!)
                if let existing = pluggy.itemIDs.first {
                    Button("Renew existing connection") {
                        alreadyConnected = false
                        target = existing
                    }
                    .buttonStyle(.borderedProminent)
                }
                Button("Close") { dismiss() }
            }
            .padding(.top, 4)
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.background)
    }

    private func handle(_ event: ConnectWebView.Event) {
        switch event {
        case .success(let itemId):
            finishing = true
            Task {
                await pluggy.connected(itemId: itemId, replacing: target)
                dismiss()
            }
        case .error(let message):
            // The widget shows its own errors and lets the user retry; only a missing script is fatal here.
            if message.hasPrefix("script:") { error = "Pluggy Connect didn't load. Check your connection and try again." }
            else if message == "ITEM_USER_ALREADY_EXISTS", target == nil { alreadyConnected = true }
            else { lastError = message }
        case .close:
            if !finishing { dismiss() }
        }
    }
}

/// Hosts Pluggy's web SDK. Its callbacks come back through a script message handler; OAuth sign-ins that open
/// a pop-up get a real child window so they can report back to the widget.
private struct ConnectWebView: NSViewRepresentable {
    enum Event { case success(String), error(String), close }

    let token: String
    let connectorId: Int?
    let updating: String?
    let onEvent: (Event) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(onEvent: onEvent) }

    func makeNSView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.userContentController.add(context.coordinator, name: "pluggy")
        configuration.preferences.javaScriptCanOpenWindowsAutomatically = true
        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.uiDelegate = context.coordinator
        context.coordinator.widget = webView
        webView.setValue(false, forKey: "drawsBackground")
        webView.loadHTMLString(html, baseURL: URL(string: "https://stockbar.local/"))
        return webView
    }

    func updateNSView(_ nsView: WKWebView, context: Context) {}

    static func dismantleNSView(_ nsView: WKWebView, coordinator: Coordinator) {
        nsView.configuration.userContentController.removeScriptMessageHandler(forName: "pluggy")
        coordinator.closePopups()
    }

    private var html: String {
        func json(_ value: Any?) -> String {
            guard let value, let data = try? JSONSerialization.data(withJSONObject: [value]),
                  let text = String(data: data, encoding: .utf8) else { return "undefined" }
            return String(text.dropFirst().dropLast())
        }
        return """
        <!doctype html>
        <html><head><meta charset="utf-8">
        <style>html, body { margin: 0; height: 100%; background: transparent; }</style>
        <script src="https://cdn.pluggy.ai/pluggy-connect/latest/pluggy-connect.js"
                onerror="window.webkit.messageHandlers.pluggy.postMessage({ type: 'error', message: 'script: failed to load' })"></script>
        </head><body><script>
          const post = (message) => window.webkit.messageHandlers.pluggy.postMessage(message);
          // Pluggy's SDK hands OAuth sign-ins to Cordova's in-app browser instead of opening a pop-up
          // (pop-ups from its iframe fail in an embedded web view). StockBar plays that part: it opens the
          // sign-in in a window and reports each page load back, like InAppBrowser's 'loadstop' events.
          const loadstop = [];
          window.cordova = { InAppBrowser: { open: (url, target) => {
            if (target === '_system') { post({ type: 'external', url }); return null; }
            loadstop.length = 0;
            post({ type: 'oauth', url });
            return {
              addEventListener: (name, listener) => { if (name === 'loadstop') loadstop.push(listener); },
              close: () => post({ type: 'oauthClose' }),
            };
          } } };
          window.stockbarLoadstop = (url) => loadstop.forEach((listener) => listener({ url }));
          const describe = (value) => { try { return JSON.stringify(value); } catch (e) { return String(value); } };
          const options = {
            connectToken: \(json(token)),
            includeSandbox: false,
            onSuccess: (data) => post({ type: 'success', itemId: data && data.item && data.item.id }),
            onError: (error) => post({ type: 'error', message: (error && error.message) || 'Unknown error', detail: describe(error) }),
            onEvent: (event) => post({ type: 'event', detail: describe(event) }),
            onClose: () => post({ type: 'close' }),
          };
          const update = \(json(updating));
          const connector = \(json(connectorId));
          if (update) options.updateItem = update;
          else if (connector) options.connectorIds = [connector];
          if (window.PluggyConnect) new PluggyConnect(options).init();
        </script></body></html>
        """
    }

    final class Coordinator: NSObject, WKScriptMessageHandler, WKUIDelegate, WKNavigationDelegate {
        let onEvent: (Event) -> Void
        weak var widget: WKWebView?
        private var popups: [NSWindow] = []
        private var oauthWindow: NSWindow?

        init(onEvent: @escaping (Event) -> Void) { self.onEvent = onEvent }

        func userContentController(_ controller: WKUserContentController, didReceive message: WKScriptMessage) {
            guard let body = message.body as? [String: Any], let type = body["type"] as? String else { return }
            Self.log(type, body["detail"] as? String ?? body["message"] as? String ?? body["url"] as? String ?? "")
            switch type {
            case "success": if let id = body["itemId"] as? String { onEvent(.success(id)) }
            case "error": onEvent(.error(body["message"] as? String ?? ""))
            case "close": onEvent(.close)
            case "oauth": if let url = (body["url"] as? String).flatMap(URL.init(string:)) { openOAuth(url) }
            case "oauthClose": closeOAuth()
            case "external": if let url = (body["url"] as? String).flatMap(URL.init(string:)) { NSWorkspace.shared.open(url) }
            default: break
            }
        }

        // MARK: OAuth window

        private func openOAuth(_ url: URL) {
            closeOAuth()
            let webView = WKWebView(frame: NSRect(x: 0, y: 0, width: 520, height: 760))
            webView.navigationDelegate = self
            webView.uiDelegate = self
            let window = NSWindow(contentRect: webView.frame, styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
            window.title = "Sign in to \(url.host ?? "Pluggy")"
            window.contentView = webView
            window.isReleasedWhenClosed = false
            window.center()
            window.makeKeyAndOrderFront(nil)
            oauthWindow = window
            webView.load(URLRequest(url: url))
        }

        private func closeOAuth() {
            oauthWindow?.close()
            oauthWindow = nil
        }

        /// Every finished load goes back to the SDK, which looks for Pluggy's oauthCallback page and takes the result from it.
        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            guard let url = webView.url?.absoluteString else { return }
            oauthWindow?.title = "Sign in to \(webView.url?.host ?? "Pluggy")"
            let literal = (try? JSONSerialization.data(withJSONObject: [url])).flatMap { String(data: $0, encoding: .utf8) }.map { String($0.dropFirst().dropLast()) } ?? "''"
            widget?.evaluateJavaScript("window.stockbarLoadstop(\(literal))")
            if url.contains("/oauthCallback.html") { Self.log("oauth", "callback reached") }
        }

        /// Appends to ~/Library/Caches/StockBar/pluggy-connect.log, to see what Pluggy Connect reported when something fails.
        static func log(_ type: String, _ detail: String) {
            let url = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0].appendingPathComponent("StockBar/pluggy-connect.log")
            // Tokens and callback codes stay out of the log.
            let redacted = detail.replacingOccurrences(of: #"(token|code|state)=[^&"\s]+"#, with: "$1=…", options: .regularExpression)
            let line = "\(Date.now.formatted(.iso8601)) \(type) \(redacted.prefix(2000))\n"
            if let handle = try? FileHandle(forWritingTo: url) {
                handle.seekToEndOfFile()
                handle.write(Data(line.utf8))
                try? handle.close()
            } else {
                try? Data(line.utf8).write(to: url)
            }
        }

        /// A sign-in pop-up: shown in its own window with the configuration WebKit hands over, so it stays
        /// connected to the widget that opened it.
        func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration,
                     for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
            let popup = WKWebView(frame: NSRect(x: 0, y: 0, width: 480, height: 720), configuration: configuration)
            popup.uiDelegate = self
            let window = NSWindow(contentRect: popup.frame, styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
            window.title = "Sign in"
            window.contentView = popup
            window.isReleasedWhenClosed = false
            window.center()
            window.makeKeyAndOrderFront(nil)
            popups.append(window)
            return popup
        }

        func webViewDidClose(_ webView: WKWebView) {
            popups.filter { $0.contentView === webView }.forEach { $0.close() }
            popups.removeAll { $0.contentView === webView }
        }

        func closePopups() {
            popups.forEach { $0.close() }
            popups.removeAll()
            closeOAuth()
        }
    }
}
