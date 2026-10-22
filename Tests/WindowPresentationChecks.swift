@main
struct WindowPresentationChecks {
    static func main() {
        var intent = WindowPresentationIntent()
        let firstCapture = intent.captureToken
        precondition(intent.canPresentCapture(firstCapture))
        intent.requestMainWindow()
        precondition(!intent.canPresentCapture(firstCapture), "Late capture/OCR must not hide a window reopened from the Dock")
        let secondCapture = intent.captureToken
        precondition(intent.canPresentCapture(secondCapture), "A new capture still works after returning to Birdy")
        intent.requestMainWindow()
        precondition(!intent.canPresentCapture(secondCapture))
        precondition(!intent.canPresentCapture(firstCapture))
        print("WindowPresentationChecks passed: returning to main window wins over stale capture and OCR presentation")
    }
}
