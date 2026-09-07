import AVFoundation
import UIKit

enum MediaPermissions {
  static func hasCamera() -> Bool {
    AVCaptureDevice.authorizationStatus(for: .video) == .authorized
  }

  static func hasMic() -> Bool {
    AVCaptureDevice.authorizationStatus(for: .audio) == .authorized
  }

  static func request(camera: Bool, mic: Bool, completion: @escaping (_ cam: Bool, _ mic: Bool) -> Void) {
    func finish() {
      DispatchQueue.main.async {
        completion(hasCamera() || !camera, hasMic() || !mic)
      }
    }

    func askMic(then: @escaping () -> Void) {
      guard mic else {
        then()
        return
      }
      let st = AVCaptureDevice.authorizationStatus(for: .audio)
      if st == .authorized {
        then()
        return
      }
      if st == .denied || st == .restricted {
        then()
        return
      }
      AVCaptureDevice.requestAccess(for: .audio) { _ in
        then()
      }
    }

    func askCam(then: @escaping () -> Void) {
      guard camera else {
        then()
        return
      }
      let st = AVCaptureDevice.authorizationStatus(for: .video)
      if st == .authorized {
        then()
        return
      }
      if st == .denied || st == .restricted {
        then()
        return
      }
      AVCaptureDevice.requestAccess(for: .video) { _ in
        then()
      }
    }

    askCam {
      askMic {
        finish()
      }
    }
  }
}
