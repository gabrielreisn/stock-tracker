import SwiftUI
import WebKit
import AuthenticationServices

struct BankConnectScreen: View {
    @Environment(PluggyStore.self) private var pluggy
    @Environment(\.dismiss) private var dismiss
    let updating: String?
    @State private var session: (token: String, connectorId: Int?)?
    @State private var error: String?
    @State private var finishing = false
    var body: some View {
        NavigationStack {
            ZStack {
                if let session {
                    BankWebView(token: session.token, connectorID: session.connectorId, updating: updating) { id in
                        guard !finishing else { return }
                        finishing = true
                        Task { _ = await pluggy.connected(itemId: id, replacing: updating); dismiss() }
                    } failure: { error = $0 } close: { dismiss() }
                } else { ProgressView("Opening Pluggy Connect…") }
                if finishing { ProgressView("Syncing your accounts…").padding().background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12)) }
            }
            .safeAreaInset(edge: .bottom) { if let error { Text(error).font(.caption).foregroundStyle(.orange).padding().background(.bar) } }
            .navigationTitle("Connect account").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() } } }
            .task {
                do { session = try await pluggy.connectSession(updating: updating) }
                catch { self.error = error.localizedDescription }
            }
        }
    }
}

struct BankWebView: UIViewRepresentable {
    let token: String
    let connectorID: Int?
    let updating: String?
    let success: (String) -> Void
    let failure: (String) -> Void
    let close: () -> Void
    func makeCoordinator() -> Coordinator { Coordinator(parent: self) }
    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.userContentController.add(context.coordinator, name: "pluggy")
        config.preferences.javaScriptCanOpenWindowsAutomatically = true
        let web = WKWebView(frame: .zero, configuration: config)
        web.uiDelegate = context.coordinator
        context.coordinator.web = web
        func json(_ value: Any) -> String { String(decoding: try! JSONSerialization.data(withJSONObject: value, options: [.fragmentsAllowed]), as: UTF8.self) }
        let html = """
        <!doctype html><html><head><meta name="viewport" content="width=device-width,initial-scale=1,maximum-scale=1"><meta charset="utf-8">
        <script src="https://cdn.pluggy.ai/pluggy-connect/latest/pluggy-connect.js" onerror="window.webkit.messageHandlers.pluggy.postMessage({type:'error',message:'Could not load Pluggy Connect. Check your connection.'})"></script>
        </head><body><script>
        const post = m => window.webkit.messageHandlers.pluggy.postMessage(m);
        const listeners = [];
        window.cordova = {InAppBrowser:{open:(url,target)=>{
          if(target === '_system'){post({type:'external',url});return null;}
          listeners.length=0;post({type:'oauth',url});return {
            addEventListener:(name,fn)=>{if(name==='loadstop')listeners.push(fn);},
            close:()=>post({type:'oauthClose'})
          };
        }}};
        window.stockbarCallback = url => listeners.forEach(fn=>fn({url}));
        const options={connectToken:\(json(token)),includeSandbox:false,
          onSuccess:data=>post({type:'success',id:data.item.id}),
          onError:error=>post({type:'error',message:error.message||'Connection failed'}),
          onClose:()=>post({type:'close'})};
        \(updating.map { "options.updateItem=\(json($0));" } ?? connectorID.map { "options.connectorIds=[\($0)];" } ?? "")
        if(window.PluggyConnect)new PluggyConnect(options).init();
        </script></body></html>
        """
        web.loadHTMLString(html, baseURL: URL(string: "https://stockbar.local/"))
        return web
    }
    func updateUIView(_ view: WKWebView, context: Context) {}
    static func dismantleUIView(_ view: WKWebView, coordinator: Coordinator) {
        view.configuration.userContentController.removeScriptMessageHandler(forName: "pluggy")
        coordinator.auth?.cancel()
    }
    final class Coordinator: NSObject, WKScriptMessageHandler, WKUIDelegate, ASWebAuthenticationPresentationContextProviding {
        let parent: BankWebView
        weak var web: WKWebView?
        var auth: ASWebAuthenticationSession?
        init(parent: BankWebView) { self.parent = parent }
        func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor { web?.window ?? ASPresentationAnchor() }
        func userContentController(_ controller: WKUserContentController, didReceive message: WKScriptMessage) {
            guard let body = message.body as? [String: Any], let type = body["type"] as? String else { return }
            switch type {
            case "success": if let id = body["id"] as? String { parent.success(id) }
            case "error": parent.failure(body["message"] as? String ?? "Connection failed")
            case "close": parent.close()
            case "oauth": if let raw = body["url"] as? String, let url = URL(string: raw) { authenticate(url) }
            case "external": if let raw = body["url"] as? String, let url = URL(string: raw), url.scheme == "https" { UIApplication.shared.open(url) }
            case "oauthClose": auth?.cancel(); auth = nil
            default: break
            }
        }
        func authenticate(_ url: URL) {
            guard url.scheme == "https" else { return }
            auth = ASWebAuthenticationSession(url: url, callbackURLScheme: "cymba-native") { [weak self] callback, error in
                Task { @MainActor in
                    guard let self else { return }
                    if let callback, let data = try? JSONSerialization.data(withJSONObject: [callback.absoluteString]), let text = String(data: data, encoding: .utf8) {
                        // The widget continues polling the item; the redirect alone never imports a connection.
                        self.web?.evaluateJavaScript("window.stockbarCallback(\(text.dropFirst().dropLast()));")
                    } else if let error, (error as NSError).code != ASWebAuthenticationSessionError.canceledLogin.rawValue { self.parent.failure(error.localizedDescription) }
                    self.auth = nil
                }
            }
            auth?.presentationContextProvider = self
            if auth?.start() != true { parent.failure("Could not open bank authentication.") }
        }
        func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration, for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
            if let url = navigationAction.request.url { authenticate(url) }
            return nil
        }
    }
}
