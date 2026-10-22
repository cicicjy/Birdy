/// Invalidates pending capture presentation when the user explicitly returns to Birdy.
/// OCR results may still be saved, but must not hide a newly restored main window.
struct WindowPresentationIntent {
    private var generation: UInt64 = 0
    var captureToken: UInt64 { generation }
    mutating func requestMainWindow() { generation &+= 1 }
    func canPresentCapture(_ token: UInt64) -> Bool { token == generation }
}
