import SwiftUI
import WebKit

/// A tutor answer with its formulas typeset (KaTeX, bundled in the app so it works offline). The answers wrap math in $...$
/// exactly as the website's chat does. The web view reports its content height so the bubble sizes itself.
struct MathText: View {
    let text: String
    @State private var height: CGFloat = 28

    var body: some View {
        MathWebView(text: text, height: $height).frame(height: height)
    }
}

enum MathHTML {
    /// Escapes the text, keeps **bold** and line breaks, and wraps it in a page that typesets $...$ and $$...$$.
    static func page(_ raw: String) -> String {
        var s = raw
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
        s = s.replacingOccurrences(of: "\\*\\*(.+?)\\*\\*", with: "<b>$1</b>", options: .regularExpression)
        // A display formula is a block of its own: the blank lines around it would only add empty space.
        s = s.replacingOccurrences(of: "\\s*(\\$\\$[\\s\\S]+?\\$\\$)\\s*", with: "$1", options: .regularExpression)
        s = s.replacingOccurrences(of: "\n", with: "<br>")
        return """
        <!doctype html><html dir="rtl" lang="he"><head>
        <meta name="viewport" content="width=device-width, initial-scale=1, maximum-scale=1">
        <link rel="stylesheet" href="katex/katex.min.css">
        <style>
          html,body{margin:0;padding:0;background:transparent}
          body{font:16px/1.6 -apple-system,"Heebo",sans-serif;color:#0F172A;word-wrap:break-word;overflow-wrap:anywhere}
          .katex{font-size:1.05em;direction:ltr;unicode-bidi:isolate;display:inline-block;max-width:100%;overflow-x:auto;overflow-y:hidden;vertical-align:middle}
          .katex-display{margin:.5em 0;overflow-x:auto;overflow-y:hidden}
        </style></head><body><div id="c">\(s)</div>
        <script src="katex/katex.min.js"></script><script src="katex/auto-render.min.js"></script>
        <script>
        function post(){window.webkit.messageHandlers.h.postMessage(document.getElementById('c').getBoundingClientRect().height)}
        try{renderMathInElement(document.getElementById('c'),{delimiters:[{left:'$$',right:'$$',display:true},{left:'$',right:'$',display:false}],throwOnError:false})}catch(e){}
        post();
        if(window.ResizeObserver){new ResizeObserver(post).observe(document.body)}
        if(document.fonts&&document.fonts.ready){document.fonts.ready.then(post)}
        setTimeout(post,300);
        </script></body></html>
        """
    }
}

struct MathWebView: UIViewRepresentable {
    let text: String
    @Binding var height: CGFloat

    func makeCoordinator() -> Coordinator { Coordinator(height: $height) }

    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.userContentController.add(WeakHandler(context.coordinator), name: "h")
        let web = WKWebView(frame: .zero, configuration: config)
        web.isOpaque = false
        web.backgroundColor = .clear
        web.scrollView.backgroundColor = .clear
        web.scrollView.isScrollEnabled = false
        web.scrollView.bounces = false
        context.coordinator.loaded = text
        web.loadHTMLString(MathHTML.page(text), baseURL: Bundle.main.resourceURL)
        return web
    }

    func updateUIView(_ web: WKWebView, context: Context) {
        if context.coordinator.loaded != text {
            context.coordinator.loaded = text
            web.loadHTMLString(MathHTML.page(text), baseURL: Bundle.main.resourceURL)
        }
    }

    final class Coordinator: NSObject, WKScriptMessageHandler {
        var height: Binding<CGFloat>
        var loaded = ""
        init(height: Binding<CGFloat>) { self.height = height }

        func userContentController(_ ucc: WKUserContentController, didReceive message: WKScriptMessage) {
            guard let h = (message.body as? NSNumber)?.doubleValue, h > 0 else { return }
            let value = CGFloat(h).rounded(.up) + 2
            DispatchQueue.main.async {
                if abs(self.height.wrappedValue - value) > 0.5 { self.height.wrappedValue = value }
            }
        }
    }

    /// WKUserContentController retains its handlers; this breaks the cycle.
    private final class WeakHandler: NSObject, WKScriptMessageHandler {
        weak var target: WKScriptMessageHandler?
        init(_ target: WKScriptMessageHandler) { self.target = target }
        func userContentController(_ ucc: WKUserContentController, didReceive message: WKScriptMessage) {
            target?.userContentController(ucc, didReceive: message)
        }
    }
}

/// Text that goes through the web view only when it has a formula in it. Most hints and short answers are plain Hebrew, and those are
/// drawn by SwiftUI itself (instant, selectable, no web view to start up).
struct RichText: View {
    let text: String
    var font: Font = .heebo(16, 600)
    var color: Color = Theme.ink

    var body: some View {
        if text.contains("$") {
            MathText(text: text)
        } else {
            Text(Self.attributed(text)).font(font).foregroundStyle(color)
                .lineSpacing(4).multilineTextAlignment(.leading)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    /// **bold** and line breaks, nothing else.
    static func attributed(_ raw: String) -> AttributedString {
        let options = AttributedString.MarkdownParsingOptions(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        return (try? AttributedString(markdown: raw, options: options)) ?? AttributedString(raw)
    }
}
