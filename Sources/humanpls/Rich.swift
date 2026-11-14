import SwiftUI
import AppKit
import WebKit
import JavaScriptCore
import HumanplsCore

/// Markdown and code to HTML. marked and highlight.js run inside JavaScriptCore (no network, no web view needed
/// for this step). The result is shown in a web view that has JavaScript turned off, so the content cannot run code.
@MainActor
enum RichRenderer {
    static let glue = #"""
    function esc(s){return String(s).replace(/&/g,'&amp;').replace(/</g,'&lt;').replace(/>/g,'&gt;').replace(/"/g,'&quot;');}
    function codeBlock(code, lang){
      var l = (lang || '').split(/\s+/)[0], out;
      try { out = (l && hljs.getLanguage(l)) ? hljs.highlight(code, {language: l, ignoreIllegals: true}).value : hljs.highlightAuto(code).value; }
      catch (e) { out = esc(code); }
      return '<pre><code class="hljs">' + out + '</code></pre>';
    }
    marked.use({ renderer: {
      html: function(a){ return esc(typeof a === 'object' ? a.text : a); },
      code: function(a, b){ return typeof a === 'object' ? codeBlock(a.text, a.lang) : codeBlock(a, b); }
    }});
    function renderMarkdown(md){ return marked.parse(md, {gfm: true}); }
    function renderCode(code, lang){ return codeBlock(code, lang); }
    """#

    static let context: JSContext? = {
        guard let c = JSContext() else { return nil }
        c.exceptionHandler = { _, e in FileHandle.standardError.write(Data("humanpls js: \(e?.toString() ?? "?")\n".utf8)) }
        c.evaluateScript("var window = this; var self = this; var exports = undefined; var module = undefined; var define = undefined;")
        c.evaluateScript(Vendor.marked)
        c.evaluateScript(Vendor.highlight)
        c.evaluateScript(glue)
        return c
    }()

    static func call(_ fn: String, _ args: [Any]) -> String? {
        context?.objectForKeyedSubscript(fn)?.call(withArguments: args)?.toString()
    }

    static func escape(_ s: String) -> String {
        s.replacingOccurrences(of: "&", with: "&amp;").replacingOccurrences(of: "<", with: "&lt;").replacingOccurrences(of: ">", with: "&gt;")
    }

    static let css = #"""
    :root { color-scheme: light dark; }
    body { font: 14px/1.6 -apple-system, "SF Pro Text", sans-serif; margin: 0; padding: 18px 22px; word-wrap: break-word; }
    h1,h2,h3 { line-height: 1.25; margin: 1.2em 0 .5em; } h1 { font-size: 1.6em; } h2 { font-size: 1.3em; } h3 { font-size: 1.1em; }
    h1:first-child, h2:first-child, h3:first-child, p:first-child { margin-top: 0; }
    a { color: #0a84ff; text-decoration: none; }
    code { font: 12.5px/1.5 ui-monospace, "SF Mono", Menlo, monospace; }
    :not(pre) > code { background: rgba(127,127,127,.18); padding: .12em .35em; border-radius: 4px; }
    pre { background: rgba(127,127,127,.12); border-radius: 8px; padding: 12px 14px; overflow-x: auto; margin: .8em 0; }
    pre code.hljs { background: transparent; padding: 0; }
    blockquote { margin: .8em 0; padding: 0 1em; border-left: 3px solid rgba(127,127,127,.4); color: gray; }
    table { border-collapse: collapse; margin: .8em 0; } th, td { border: 1px solid rgba(127,127,127,.35); padding: 5px 10px; }
    th { background: rgba(127,127,127,.12); } img { max-width: 100%; border-radius: 6px; } hr { border: 0; border-top: 1px solid rgba(127,127,127,.3); }
    ul, ol { padding-left: 1.6em; } li > p { margin: .2em 0; }
    pre.plain { white-space: pre-wrap; font: 12.5px/1.5 ui-monospace, "SF Mono", Menlo, monospace; }
    .note { color: gray; font-size: 12px; margin-top: 1em; }
    """#

    static func page(body: String) -> String {
        let hl = "@media (prefers-color-scheme: light) { \(Vendor.cssLight) } @media (prefers-color-scheme: dark) { \(Vendor.cssDark) }"
        return "<!doctype html><meta charset=utf-8><style>\(css)\n\(hl)</style><body>\(body)</body>"
    }

    /// Local images in markdown (relative paths) are read in place and shown inline, so nothing is copied to disk.
    static func inlineImages(_ html: String, baseDir: String?) -> String {
        guard let baseDir, let re = try? NSRegularExpression(pattern: #"(<img\s[^>]*?src=")([^"]+)(")"#) else { return html }
        var out = html
        for m in re.matches(in: html, range: NSRange(html.startIndex..., in: html)).reversed() {
            guard let r = Range(m.range(at: 2), in: out) else { continue }
            let src = String(out[r])
            if src.hasPrefix("http") || src.hasPrefix("data:") { continue }
            let p = src.hasPrefix("/") ? src : (baseDir as NSString).appendingPathComponent(src.removingPercentEncoding ?? src)
            guard let d = FileManager.default.contents(atPath: p), d.count < 8_000_000 else { continue }
            let mime = ["png": "image/png", "jpg": "image/jpeg", "jpeg": "image/jpeg", "gif": "image/gif", "svg": "image/svg+xml", "webp": "image/webp"][(p as NSString).pathExtension.lowercased()] ?? "application/octet-stream"
            out.replaceSubrange(r, with: "data:\(mime);base64,\(d.base64EncodedString())")
        }
        return out
    }

    static let maxChars = 600_000

    static func html(for item: Item, text: String) -> String {
        var t = text
        var note = ""
        if t.count > maxChars { t = String(t.prefix(maxChars)); note = "<p class=note>Showing the first \(maxChars / 1000)k characters.</p>" }
        let base = item.path.map { ($0 as NSString).deletingLastPathComponent }
        switch item.kind {
        case .markdown:
            let body = call("renderMarkdown", [t]) ?? "<pre class=plain>\(escape(t))</pre>"
            return page(body: inlineImages(body, baseDir: base) + note)
        case .code:
            let body = call("renderCode", [t, item.language ?? ""]) ?? "<pre class=plain>\(escape(t))</pre>"
            return page(body: body + note)
        default:
            return page(body: "<pre class=plain>\(escape(t))</pre>" + note)
        }
    }

    static func loadText(_ item: Item) -> String {
        if let t = item.text { return t }
        guard let p = item.path, let d = FileManager.default.contents(atPath: p) else { return "" }
        return String(data: d, encoding: .utf8) ?? String(decoding: d, as: UTF8.self)
    }
}

/// A web view with JavaScript off. Links open in the browser.
struct RichWeb: NSViewRepresentable {
    let html: String

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> WKWebView {
        let cfg = WKWebViewConfiguration()
        cfg.defaultWebpagePreferences.allowsContentJavaScript = false
        let w = WKWebView(frame: .zero, configuration: cfg)
        w.setValue(false, forKey: "drawsBackground")
        w.navigationDelegate = context.coordinator
        w.loadHTMLString(html, baseURL: nil)
        context.coordinator.loaded = html
        return w
    }

    func updateNSView(_ w: WKWebView, context: Context) {
        if context.coordinator.loaded != html { w.loadHTMLString(html, baseURL: nil); context.coordinator.loaded = html }
    }

    final class Coordinator: NSObject, WKNavigationDelegate {
        var loaded = ""
        func webView(_ w: WKWebView, decidePolicyFor action: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
            if action.navigationType == .linkActivated, let u = action.request.url {
                if u.scheme == "http" || u.scheme == "https" || u.scheme == "mailto" { NSWorkspace.shared.open(u) }
                decisionHandler(.cancel); return
            }
            decisionHandler(.allow)
        }
    }
}

/// Markdown, code and plain text with colors. Rendered once, then cached.
struct RichText: View {
    let item: Item
    @State var html: String? = nil

    var body: some View {
        Group {
            if let html { RichWeb(html: html) } else { Color.clear }
        }
        .background(.background.secondary)
        .task(id: item.key + (item.path ?? "")) {
            html = RichRenderer.html(for: item, text: RichRenderer.loadText(item))
        }
    }
}
