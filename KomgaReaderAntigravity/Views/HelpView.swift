import SwiftUI
import WebKit

struct HelpView: View {
    var body: some View {
        WebView(fileName: "manual")
            .ignoresSafeArea()
            .background(Color.black)
    }
}

struct WebView: UIViewRepresentable {
    let fileName: String
    
    func makeUIView(context: Context) -> WKWebView {
        let webView = WKWebView()
        webView.isOpaque = false
        webView.backgroundColor = UIColor.clear
        webView.scrollView.backgroundColor = UIColor.black
        return webView
    }
    
    func updateUIView(_ uiView: WKWebView, context: Context) {
        if let url = Bundle.main.url(forResource: fileName, withExtension: "html") {
            uiView.loadFileURL(url, allowingReadAccessTo: url)
        } else {
            // Fallback if not in bundle yet (e.g. during dev if file isn't added to target automatically)
            // Try loading from Documents or just show error HTML
             uiView.loadHTMLString("<html><body style='background:#1a1a1a;color:white'><h1>Manual Not Found</h1><p>Could not locate \(fileName).html in Bundle.</p></body></html>", baseURL: nil)
        }
    }
}
