import Flutter
import WebKit
import UIKit

public class WebViewSSLPlugin: NSObject, FlutterPlugin {
    public static func register(with registrar: FlutterPluginRegistrar) {
        let factory = WebViewSSLFactory(registrar: registrar)
        registrar.register(factory, withId: "WebViewSSL")
    }
}

class WebViewSSLFactory: NSObject, FlutterPlatformViewFactory {
    private var registrar: FlutterPluginRegistrar
    private var eventSink: FlutterEventSink?

    init(registrar: FlutterPluginRegistrar) {
        self.registrar = registrar
        super.init()
        FlutterEventChannel(name: "com.example.webview_ssl", binaryMessenger: registrar.messenger()).setStreamHandler(self)
    }

    func create(
        withFrame frame: CGRect,
        viewIdentifier viewId: Int64,
        arguments args: Any?
    ) -> FlutterPlatformView {
        return WebViewSSL(
            frame: frame,
            viewIdentifier: viewId,
            arguments: args,
            registrar: registrar,
            eventSink: eventSink
        )
    }

    public func createArgsCodec() -> FlutterMessageCodec & NSObjectProtocol {
          return FlutterStandardMessageCodec.sharedInstance()
    }
}

class WebViewSSL: NSObject, FlutterPlatformView, WKNavigationDelegate {
    private let webView = WKWebView(frame: .zero, configuration: WKWebViewConfiguration())
    private let arrayCert: NSMutableArray = NSMutableArray()
    private var eventSink: FlutterEventSink?

    init(
        frame: CGRect,
        viewIdentifier viewId: Int64,
        arguments args: Any?,
        registrar: FlutterPluginRegistrar,
        eventSink: FlutterEventSink?
    ) {
        super.init()
        self.eventSink = eventSink
        prepareCertificates(arguments: args, registrar: registrar)
        loadUrl(arguments: args)
    }

    func view() -> UIView {
        webView.navigationDelegate = self
        return webView
    }

    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, 
                 decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        if let url = navigationAction.request.url?.absoluteString {
            eventSink?(url)
        }
        decisionHandler(.allow)
    }

    func webView(_ webView: WKWebView, didReceive challenge: URLAuthenticationChallenge, 
                 completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) {
        guard let serverTrust = challenge.protectionSpace.serverTrust
        else { return completionHandler(.performDefaultHandling, nil) }
        
        if checkValidity(of: serverTrust) {
            let cred = URLCredential(trust: serverTrust)
            completionHandler(.useCredential, cred)
        } else {
            completionHandler(.performDefaultHandling, nil)
        }
    }

    private func loadUrl(arguments args: Any?){
        let argumentsDictionary = args as? Dictionary<String, Any> ?? [:]
        let initialUrl = argumentsDictionary["initialUrl"] as? String ?? ""

        let url = URL(string: initialUrl)
        if(!initialUrl.isEmpty && url != nil){
            webView.load(URLRequest(url: url!))
        }
    }

    private func checkValidity(of serverTrust: SecTrust, anchorCertificatesOnly: Bool = false) -> Bool {
        SecTrustSetAnchorCertificates(serverTrust, arrayCert)
        SecTrustSetAnchorCertificatesOnly(serverTrust, anchorCertificatesOnly)

        var error: CFError?
        let isTrusted = SecTrustEvaluateWithError(serverTrust, &error)
        
        return isTrusted
    }

    private func prepareCertificates(arguments args: Any?, registrar: FlutterPluginRegistrar){
        let argumentsDictionary = args as? Dictionary<String, Any> ?? [:]
        let sslAssets = argumentsDictionary["sslAssets"] as? Array<String> ?? []

        for asset in sslAssets{
            let key = registrar.lookupKey(forAsset: asset)
            let path = Bundle.main.url(forResource: key, withExtension: nil)
            if(path==nil) { continue }
            do {
                let certData = try Data(contentsOf: path!)
                let cert = SecCertificateCreateWithData(nil, certData as CFData)
                if(cert==nil) { continue }
                arrayCert.add(cert!)
            } catch {}
        }
    }
}

extension WebViewSSLFactory: FlutterStreamHandler{
    func onListen(withArguments arguments: Any?, eventSink events: @escaping FlutterEventSink) -> FlutterError? {
        self.eventSink = events
        return nil
    }

    func onCancel(withArguments arguments: Any?) -> FlutterError? {
        self.eventSink = nil
        return nil
    }
}
