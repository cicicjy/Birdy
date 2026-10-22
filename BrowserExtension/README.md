# Birdy Chrome context-menu extension

This adds **Birdy 精读** as a top-level item in Chrome's selection context menu.

1. Build and launch `dist/Birdy.app` once so macOS registers the `birdy://` URL scheme.
2. Open `chrome://extensions` in Chrome and turn on **Developer mode**.
3. Choose **Load unpacked** and select the `BrowserExtension` folder inside `Birdy.app/Contents/Resources` (or this project folder if you are running from source).
4. Select text on a webpage, right-click, and choose **Birdy 精读**.

The extension sends only the selected text and the current page URL to Birdy. The app then saves the excerpt and starts the existing close-reading flow. The native macOS **Services → Birdy 精读** entry remains available too.
