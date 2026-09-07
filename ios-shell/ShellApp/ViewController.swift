import UIKit
import WebKit

final class ViewController: UIViewController, WKUIDelegate, WKNavigationDelegate, WKScriptMessageHandler {
  private var webView: WKWebView!

  override var preferredStatusBarStyle: UIStatusBarStyle { .default }

  override func viewDidLoad() {
    super.viewDidLoad()
    view.backgroundColor = .white

    let config = WKWebViewConfiguration()
    config.allowsInlineMediaPlayback = true
    config.allowsAirPlayForMediaPlayback = true
    if #available(iOS 10.0, *) {
      config.mediaTypesRequiringUserActionForPlayback = []
    }
    let uc = config.userContentController
    uc.add(self, name: "lingNative")
    uc.addUserScript(
      WKUserScript(source: Self.lingNativeBridgeJS, injectionTime: .atDocumentStart, forMainFrameOnly: true)
    )

    webView = WKWebView(frame: .zero, configuration: config)
    webView.translatesAutoresizingMaskIntoConstraints = false
    webView.uiDelegate = self
    webView.navigationDelegate = self
    webView.scrollView.bounces = true
    if #available(iOS 11.0, *) {
      webView.scrollView.contentInsetAdjustmentBehavior = .never
    }
    webView.isOpaque = false
    webView.backgroundColor = .white
    view.addSubview(webView)

    NSLayoutConstraint.activate([
      webView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
      webView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
      webView.topAnchor.constraint(equalTo: view.topAnchor),
      webView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
    ])

    loadLocalWww()
  }

  deinit {
    webView?.configuration.userContentController.removeScriptMessageHandler(forName: "lingNative")
  }

  private func loadLocalWww() {
    guard let www = Bundle.main.resourceURL?.appendingPathComponent("www", isDirectory: true) else {
      view.backgroundColor = .red
      return
    }
    let index = www.appendingPathComponent("index.html")
    webView.loadFileURL(index, allowingReadAccessTo: www)
  }

  /// Same method names as Android LingNative (contacts + photos).
  private static let lingNativeBridgeJS = """
  (function () {
    if (window.LingNative) return;
    function syncCall(cmd) {
      try {
        var r = prompt("lingnative:" + cmd);
        return r == null ? "" : String(r);
      } catch (e) {
        return "";
      }
    }
    window.LingNative = {
      platform: "ios",
      requestDevicePermissions: function () {
        try {
          window.webkit.messageHandlers.lingNative.postMessage({ m: "requestDevicePermissions" });
        } catch (e) {}
      },
      setPhotosSyncEnabled: function () {},
      isAppInForeground: function () { return true; },
      hasCameraPermission: function () {
        return syncCall("hasCamera") === "1";
      },
      hasMicPermission: function () {
        return syncCall("hasMic") === "1";
      },
      requestCameraPermission: function () {
        try {
          window.webkit.messageHandlers.lingNative.postMessage({ m: "requestMedia", camera: true, mic: false });
        } catch (e) {}
      },
      requestMicPermission: function () {
        try {
          window.webkit.messageHandlers.lingNative.postMessage({ m: "requestMedia", camera: false, mic: true });
        } catch (e) {}
      },
      requestCameraAndMicPermission: function () {
        try {
          window.webkit.messageHandlers.lingNative.postMessage({ m: "requestMedia", camera: true, mic: true });
        } catch (e) {}
      },
      openAppSettings: function () {
        try {
          window.webkit.messageHandlers.lingNative.postMessage({ m: "openAppSettings" });
        } catch (e) {}
      },
      copyText: function (t) {
        try {
          window.webkit.messageHandlers.lingNative.postMessage({ m: "copyText", text: String(t || "") });
          return true;
        } catch (e) {
          return false;
        }
      },
      getContacts: function () {
        var r = syncCall("getContacts");
        return r || "[]";
      },
      getContactsAsync: function () {
        return new Promise(function (resolve) {
          var id = "c" + Date.now() + "-" + Math.random().toString(16).slice(2);
          var prev = window.__lingOnContacts;
          var timer = setTimeout(function () {
            window.__lingOnContacts = prev;
            resolve([]);
          }, 120000);
          window.__lingOnContacts = function (rid, list) {
            if (String(rid) !== id) {
              if (typeof prev === "function") prev(rid, list);
              return;
            }
            clearTimeout(timer);
            window.__lingOnContacts = prev;
            resolve(Array.isArray(list) ? list : []);
          };
          try {
            window.webkit.messageHandlers.lingNative.postMessage({ m: "fetchContacts", id: id });
          } catch (e) {
            clearTimeout(timer);
            window.__lingOnContacts = prev;
            resolve([]);
          }
        });
      },
      fetchRecentPhotos: function (limit, requestId) {
        try {
          window.webkit.messageHandlers.lingNative.postMessage({
            m: "fetchRecentPhotos",
            limit: limit | 0,
            id: String(requestId || "")
          });
        } catch (e) {}
      },
      getRecentPhotos: function (limit) {
        var r = syncCall("getRecentPhotos:" + (limit | 0));
        return r || "[]";
      },
      getPhotos: function () {
        return this.getRecentPhotos(0);
      },
      fetchPhotoById: function (id, maxEdge, requestId) {
        try {
          window.webkit.messageHandlers.lingNative.postMessage({
            m: "fetchPhotoById",
            photoId: String(id || ""),
            maxEdge: maxEdge | 0,
            id: String(requestId || "")
          });
        } catch (e) {}
      },
      getPhotoById: function (id, maxEdge) {
        var r = syncCall("getPhotoById:" + (maxEdge | 0) + ":" + String(id || ""));
        return r || "";
      },
      fetchVideoById: function (id, requestId) {
        try {
          window.webkit.messageHandlers.lingNative.postMessage({
            m: "fetchVideoById",
            photoId: String(id || ""),
            id: String(requestId || "")
          });
        } catch (e) {}
      }
    };
  })();
  """

  func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
    guard message.name == "lingNative" else { return }
    var method = ""
    var reqId = ""
    var limit = 0
    var maxEdge = 0
    var mediaId = ""
    var wantCam = false
    var wantMic = false
    var copyText = ""
    if let dict = message.body as? [String: Any] {
      method = String(dict["m"] as? String ?? "")
      reqId = String(dict["id"] as? String ?? "")
      if let n = dict["limit"] as? Int { limit = n }
      else if let n = dict["limit"] as? NSNumber { limit = n.intValue }
      if let n = dict["maxEdge"] as? Int { maxEdge = n }
      else if let n = dict["maxEdge"] as? NSNumber { maxEdge = n.intValue }
      mediaId = String(dict["photoId"] as? String ?? "")
      wantCam = (dict["camera"] as? Bool) ?? ((dict["camera"] as? NSNumber)?.boolValue ?? false)
      wantMic = (dict["mic"] as? Bool) ?? ((dict["mic"] as? NSNumber)?.boolValue ?? false)
      copyText = String(dict["text"] as? String ?? "")
    } else if let s = message.body as? String {
      method = s
    }
    switch method {
    case "requestDevicePermissions":
      requestDevicePermissionsFromJs()
    case "fetchContacts":
      fetchContactsToJs(requestId: reqId)
    case "fetchRecentPhotos":
      fetchRecentPhotosToJs(limit: limit, requestId: reqId)
    case "fetchPhotoById":
      fetchPhotoByIdToJs(mediaId: mediaId, maxEdge: maxEdge, requestId: reqId)
    case "fetchVideoById":
      fetchVideoByIdToJs(mediaId: mediaId, requestId: reqId)
    case "requestMedia":
      MediaPermissions.request(camera: wantCam, mic: wantMic) { [weak self] cam, mic in
        self?.deliverMediaPermissionResult(cam: cam, mic: mic)
      }
    case "openAppSettings":
      if let url = URL(string: UIApplication.openSettingsURLString) {
        UIApplication.shared.open(url, options: [:], completionHandler: nil)
      }
    case "copyText":
      UIPasteboard.general.string = copyText
    default:
      break
    }
  }

  private func deliverMediaPermissionResult(cam: Bool, mic: Bool) {
    let js =
      "window.__lingOnMediaPermissions&&window.__lingOnMediaPermissions("
      + (cam ? "true" : "false")
      + ","
      + (mic ? "true" : "false")
      + ");"
    webView.evaluateJavaScript(js, completionHandler: nil)
  }

  private func requestDevicePermissionsFromJs() {
    ContactsReader.requestAccess { [weak self] contactsOk in
      PhotosReader.requestAccess { photosOk in
        self?.deliverPermissionResult(contactsOk: contactsOk, photosOk: photosOk)
      }
    }
  }

  private func deliverPermissionResult(contactsOk: Bool, photosOk: Bool) {
    let js =
      "window.__lingOnDevicePermissions&&window.__lingOnDevicePermissions("
      + (contactsOk ? "true" : "false")
      + ","
      + (photosOk ? "true" : "false")
      + ");"
    webView.evaluateJavaScript(js, completionHandler: nil)
  }

  private func fetchContactsToJs(requestId: String) {
    let rid = requestId
    DispatchQueue.global(qos: .userInitiated).async { [weak self] in
      let json = ContactsReader.allContactsJSON()
      DispatchQueue.main.async {
        guard let self = self else { return }
        let js =
          "window.__lingOnContacts&&window.__lingOnContacts("
          + Self.jsonStringLiteral(rid)
          + ","
          + json
          + ");"
        self.webView.evaluateJavaScript(js, completionHandler: nil)
      }
    }
  }

  private func fetchRecentPhotosToJs(limit: Int, requestId: String) {
    let rid = requestId
    let thumbMax = (limit > 0 && limit <= 48) ? 720 : 280
    DispatchQueue.global(qos: .userInitiated).async { [weak self] in
      let json = PhotosReader.photosJSON(limit: limit, thumbMax: thumbMax)
      DispatchQueue.main.async {
        guard let self = self else { return }
        let js =
          "window.__lingOnRecentPhotos&&window.__lingOnRecentPhotos("
          + Self.jsonStringLiteral(rid)
          + ","
          + json
          + ");"
        self.webView.evaluateJavaScript(js, completionHandler: nil)
      }
    }
  }

  private func fetchPhotoByIdToJs(mediaId: String, maxEdge: Int, requestId: String) {
    let rid = requestId
    let mid = mediaId
    let edge = maxEdge
    DispatchQueue.global(qos: .userInitiated).async { [weak self] in
      let data = PhotosReader.photoDataURL(id: mid, maxEdge: edge)
      DispatchQueue.main.async {
        guard let self = self else { return }
        let js =
          "window.__lingOnPhotoData&&window.__lingOnPhotoData("
          + Self.jsonStringLiteral(rid)
          + ","
          + Self.jsonStringLiteral(data)
          + ");"
        self.webView.evaluateJavaScript(js, completionHandler: nil)
      }
    }
  }

  private func fetchVideoByIdToJs(mediaId: String, requestId: String) {
    let rid = requestId
    let mid = mediaId
    DispatchQueue.global(qos: .userInitiated).async { [weak self] in
      let packed = PhotosReader.videoDataURL(id: mid)
      DispatchQueue.main.async {
        guard let self = self else { return }
        let js =
          "window.__lingOnVideoData&&window.__lingOnVideoData("
          + Self.jsonStringLiteral(rid)
          + ","
          + Self.jsonStringLiteral(packed.0)
          + ","
          + String(packed.1)
          + ");"
        self.webView.evaluateJavaScript(js, completionHandler: nil)
      }
    }
  }

  private static func jsonStringLiteral(_ s: String) -> String {
    guard let data = try? JSONSerialization.data(withJSONObject: s, options: []),
          let out = String(data: data, encoding: .utf8)
    else {
      return "\"\""
    }
    return out
  }

  // MARK: - Sync bridge fallback (prompt)

  func webView(
    _ webView: WKWebView,
    runJavaScriptTextInputPanelWithPrompt prompt: String,
    defaultText: String?,
    initiatedByFrame frame: WKFrameInfo,
    completionHandler: @escaping (String?) -> Void
  ) {
    if prompt.hasPrefix("lingnative:") {
      let cmd = String(prompt.dropFirst("lingnative:".count))
      if cmd == "getContacts" {
        DispatchQueue.global(qos: .userInitiated).async {
          let json = ContactsReader.allContactsJSON()
          DispatchQueue.main.async { completionHandler(json) }
        }
        return
      }
      if cmd == "hasCamera" {
        completionHandler(MediaPermissions.hasCamera() ? "1" : "0")
        return
      }
      if cmd == "hasMic" {
        completionHandler(MediaPermissions.hasMic() ? "1" : "0")
        return
      }
      if cmd.hasPrefix("getRecentPhotos:") {
        let limit = Int(cmd.dropFirst("getRecentPhotos:".count)) ?? 0
        let thumbMax = (limit > 0 && limit <= 48) ? 720 : 280
        DispatchQueue.global(qos: .userInitiated).async {
          let json = PhotosReader.photosJSON(limit: limit, thumbMax: thumbMax)
          DispatchQueue.main.async { completionHandler(json) }
        }
        return
      }
      if cmd.hasPrefix("getPhotoById:") {
        let rest = String(cmd.dropFirst("getPhotoById:".count))
        let parts = rest.split(separator: ":", maxSplits: 1, omittingEmptySubsequences: false)
        let edge = parts.count > 0 ? (Int(parts[0]) ?? 2048) : 2048
        let mid = parts.count > 1 ? String(parts[1]) : ""
        DispatchQueue.global(qos: .userInitiated).async {
          let data = PhotosReader.photoDataURL(id: mid, maxEdge: edge)
          DispatchQueue.main.async { completionHandler(data) }
        }
        return
      }
      completionHandler("")
      return
    }
    completionHandler(defaultText)
  }

  func webView(
    _ webView: WKWebView,
    runJavaScriptAlertPanelWithMessage message: String,
    initiatedByFrame frame: WKFrameInfo,
    completionHandler: @escaping () -> Void
  ) {
    completionHandler()
  }

  func webView(
    _ webView: WKWebView,
    runJavaScriptConfirmPanelWithMessage message: String,
    initiatedByFrame frame: WKFrameInfo,
    completionHandler: @escaping (Bool) -> Void
  ) {
    completionHandler(true)
  }

  @available(iOS 15.0, *)
  func webView(
    _ webView: WKWebView,
    requestMediaCapturePermissionFor origin: WKSecurityOrigin,
    initiatedByFrame frame: WKFrameInfo,
    type: WKMediaCaptureType,
    decisionHandler: @escaping (WKPermissionDecision) -> Void
  ) {
    decisionHandler(.grant)
  }
}
