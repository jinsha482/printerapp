import Cocoa
import FlutterMacOS

@main
class AppDelegate: FlutterAppDelegate {
  override func applicationDidFinishLaunching(_ notification: Notification) {
    super.applicationDidFinishLaunching(notification)
    
    // Capture the "Cmd + P" (Print) event
    NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { event in
      if event.modifierFlags.contains(.command) && event.keyCode == 35 { // Cmd + P
        self.invokePrintEvent()
      }
    }
  }

  // Method to invoke the print event on Flutter
  func invokePrintEvent() {
    let channel = FlutterMethodChannel(name: "com.example.print", binaryMessenger: self.registrar(forPlugin: "FlutterApp")!.messenger)
    channel.invokeMethod("onPrint", arguments: nil)
  }
}
