//
//  TerminalView.swift
//  Mobile Terminal
//
//  WebView-based terminal connecting to remote ttyd server
//  Enhanced with gestures, voice input, and quick action toolbar
//

import SwiftUI
import WebKit

struct TerminalView: View {
    let server: ServerConnection

    @EnvironmentObject var serverManager: ServerManager
    @StateObject private var sessionManager = TerminalSessionManager.shared
    @StateObject private var voiceService = VoiceCommandService()
    @StateObject private var historyManager = CommandHistoryManager.shared
    @StateObject private var notificationService = NotificationService.shared
    @StateObject private var connectionService = ConnectionService.shared

    @State private var showingConnectionError = false
    @State private var showingSettings = false
    @State private var errorMessage = ""
    @State private var refreshTrigger = UUID()
    @State private var webViewRef: WKWebView?

    // Pinch to zoom
    @State private var currentScale: CGFloat = 1.0
    @State private var lastScale: CGFloat = 1.0

    // Build URL from server config
    private var serverURL: URL? {
        connectionService.buildURL(for: server)
    }

    var body: some View {
        VStack(spacing: 0) {
            ZStack {
                Color.black.ignoresSafeArea()

                if sessionManager.connectionState == .connecting {
                    VStack(spacing: 20) {
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle(tint: .green))
                            .scaleEffect(1.5)

                        Text("Connecting to \(server.name)...")
                            .foregroundStyle(.green)
                            .font(.system(.body, design: .monospaced))
                    }
                }

                if let url = serverURL {
                    terminalWebView(url: url)
                        .opacity(sessionManager.connectionState == .connecting ? 0 : 1)
                } else {
                    Text("Invalid server URL")
                        .foregroundStyle(.red)
                }
            }
            .gesture(pinchGesture)
            .gesture(swipeGestures)

            // Quick action toolbar
            #if os(iOS)
            TerminalToolbar(
                onSendCommand: sendCommand,
                onSendControlKey: sendControlKey,
                onTakeScreenshot: takeScreenshot,
                sessionManager: sessionManager,
                voiceService: voiceService
            )
            #endif
        }
        .navigationTitle(server.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                HStack(spacing: 12) {
                    Button {
                        showingSettings = true
                    } label: {
                        Image(systemName: "gearshape")
                    }

                    Button {
                        sessionManager.didStartConnecting()
                        refreshTrigger = UUID()
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                }
            }

            ToolbarItem(placement: .topBarLeading) {
                HStack(spacing: 4) {
                    Circle()
                        .fill(sessionManager.connectionState.statusColor)
                        .frame(width: 8, height: 8)
                    Text(sessionManager.connectionState.statusText)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .alert("Connection Error", isPresented: $showingConnectionError) {
            Button("Retry") {
                sessionManager.didStartConnecting()
                refreshTrigger = UUID()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(errorMessage)
        }
        .sheet(isPresented: $showingSettings) {
            NavigationStack {
                TerminalSettingsView()
                    .toolbar {
                        ToolbarItem(placement: .confirmationAction) {
                            Button("Done") {
                                showingSettings = false
                            }
                        }
                    }
            }
        }
        .onAppear {
            // Set font size from server config
            sessionManager.fontSize = server.fontSize

            // Request notification permissions on first launch
            Task {
                await notificationService.requestPermission()
                notificationService.setupNotificationCategories()
            }
            // Donate Siri shortcuts
            SiriShortcutsService.shared.donateAllShortcuts()
        }
        .onDisappear {
            // Save any updated font size back to server
            if sessionManager.fontSize != server.fontSize {
                var updatedServer = server
                updatedServer.fontSize = sessionManager.fontSize
                serverManager.updateServer(updatedServer)
            }
        }
    }

    // MARK: - Terminal WebView

    private func terminalWebView(url: URL) -> some View {
        TerminalWebView(
            url: url,
            fontSize: sessionManager.fontSize,
            refreshTrigger: refreshTrigger,
            basicAuthCredentials: basicAuthCredentials,
            onWebViewCreated: { webView in
                self.webViewRef = webView
            },
            onStartLoading: {
                sessionManager.didStartConnecting()
            },
            onFinishLoading: {
                sessionManager.didConnect()
            },
            onError: { error in
                sessionManager.didEncounterError(error)
                errorMessage = error
                showingConnectionError = true
            },
            onTwoFingerSwipeLeft: {
                // Send Ctrl+C on 2-finger swipe left
                sendControlKey(.ctrlC)
            }
        )
    }

    // Build basic auth credentials if needed
    private var basicAuthCredentials: (String, String)? {
        if case .basicAuth(let username) = server.authMethod {
            if let password = CredentialManager.shared.getPassword(for: server.id) {
                return (username, password)
            }
        }
        return nil
    }

    // MARK: - Gestures

    private var pinchGesture: some Gesture {
        MagnificationGesture()
            .onChanged { value in
                let delta = value / lastScale
                lastScale = value

                // Scale font size based on pinch
                let newSize = CGFloat(sessionManager.fontSize) * delta
                if newSize >= 12 && newSize <= 36 {
                    sessionManager.fontSize = Int(newSize)
                }
            }
            .onEnded { _ in
                lastScale = 1.0
                HapticManager.shared.lightTap()
            }
    }

    private var swipeGestures: some Gesture {
        DragGesture(minimumDistance: 50)
            .onEnded { value in
                let horizontalAmount = value.translation.width
                let verticalAmount = value.translation.height

                // Detect swipe direction
                if abs(verticalAmount) > abs(horizontalAmount) {
                    // Vertical swipe
                    if verticalAmount < -50 {
                        // Swipe up - previous command
                        sendControlKey(.upArrow)
                        HapticManager.shared.selection()
                    } else if verticalAmount > 50 {
                        // Swipe down - next command
                        sendControlKey(.downArrow)
                        HapticManager.shared.selection()
                    }
                }
            }
    }


    // MARK: - Actions

    private func sendCommand(_ command: String) {
        guard let webView = webViewRef else { return }

        // Add to history
        historyManager.addCommand(command)

        // Send command followed by Enter
        let js = """
        if (window.term) {
            window.term.paste('\(command.escapedForJS)\\r');
        }
        """
        webView.evaluateJavaScript(js, completionHandler: nil)
        HapticManager.shared.mediumImpact()
    }

    private func sendControlKey(_ key: TerminalToolbar.ControlKey) {
        guard let webView = webViewRef else { return }

        // Get the data to send based on the key
        let data: String
        switch key {
        case .escape:
            data = "\\x1b"
        case .ctrlC:
            data = "\\x03"
        case .ctrlD:
            data = "\\x04"
        case .ctrlZ:
            data = "\\x1a"
        case .ctrlL:
            data = "\\x0c"
        case .ctrlU:
            data = "\\x15"
        case .ctrlW:
            data = "\\x17"
        case .tab:
            data = "\\t"
        case .shiftTab:
            data = "\\x1b[Z"
        case .backspace:
            data = "\\x7f"
        case .upArrow:
            data = "\\x1b[A"
        case .downArrow:
            data = "\\x1b[B"
        case .leftArrow:
            data = "\\x1b[D"
        case .rightArrow:
            data = "\\x1b[C"
        case .enter:
            data = "\\r"
        }

        // Use ttyd's WebSocket to send data directly
        let js = """
        (function() {
            var data = "\(data)";
            if (window.socket && window.socket.readyState === WebSocket.OPEN) {
                window.socket.send(JSON.stringify({type: 'input', data: data}));
                return;
            }
            if (window.ws && window.ws.readyState === WebSocket.OPEN) {
                window.ws.send(JSON.stringify({type: 'input', data: data}));
                return;
            }
            if (window.term && window.term._addonManager) {
                var addons = window.term._addonManager._addons;
                for (var i = 0; i < addons.length; i++) {
                    var addon = addons[i].instance;
                    if (addon && addon._socket && addon._socket.readyState === WebSocket.OPEN) {
                        addon._socket.send(data);
                        return;
                    }
                }
            }
            if (window.term && window.term._core && window.term._core.coreService) {
                window.term._core.coreService.triggerDataEvent(data, true);
                return;
            }
            if (window.term) {
                window.term.paste(data);
            }
        })();
        """

        webView.evaluateJavaScript(js, completionHandler: nil)
    }

    private func takeScreenshot() {
        #if os(iOS)
        guard let webView = webViewRef else { return }

        let config = WKSnapshotConfiguration()
        webView.takeSnapshot(with: config) { image, error in
            if let image = image {
                DispatchQueue.main.async {
                    shareImage(image)
                }
            }
        }
        #endif
    }

    #if os(iOS)
    private func shareImage(_ image: UIImage) {
        let activityVC = UIActivityViewController(
            activityItems: [image],
            applicationActivities: nil
        )

        if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
           let rootVC = windowScene.windows.first?.rootViewController {
            rootVC.present(activityVC, animated: true)
        }

        HapticManager.shared.success()
    }
    #endif
}

// MARK: - String Extension for JS Escaping

extension String {
    var escapedForJS: String {
        self
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "'", with: "\\'")
            .replacingOccurrences(of: "\"", with: "\\\"")
            .replacingOccurrences(of: "\n", with: "\\n")
            .replacingOccurrences(of: "\r", with: "\\r")
            .replacingOccurrences(of: "\t", with: "\\t")
    }
}

// MARK: - Terminal WebView

#if os(iOS)
import UIKit

struct TerminalWebView: UIViewRepresentable {
    let url: URL
    let fontSize: Int
    let refreshTrigger: UUID
    let basicAuthCredentials: (String, String)?
    let onWebViewCreated: (WKWebView) -> Void
    let onStartLoading: () -> Void
    let onFinishLoading: () -> Void
    let onError: (String) -> Void
    var onTwoFingerSwipeLeft: (() -> Void)?

    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.allowsInlineMediaPlayback = true
        config.mediaTypesRequiringUserActionForPlayback = []

        let prefs = WKWebpagePreferences()
        prefs.allowsContentJavaScript = true
        config.defaultWebpagePreferences = prefs

        let webView = WKWebView(frame: .zero, configuration: config)
        webView.navigationDelegate = context.coordinator
        webView.backgroundColor = UIColor.black
        webView.isOpaque = false
        webView.scrollView.backgroundColor = UIColor.black
        webView.scrollView.isScrollEnabled = false

        webView.customUserAgent = "Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15"

        // Add 2-finger swipe left gesture for Ctrl+C
        let twoFingerSwipe = UIPanGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleTwoFingerSwipe(_:)))
        twoFingerSwipe.minimumNumberOfTouches = 2
        twoFingerSwipe.maximumNumberOfTouches = 2
        webView.addGestureRecognizer(twoFingerSwipe)

        // Notify parent of webView reference
        DispatchQueue.main.async {
            onWebViewCreated(webView)
        }

        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
        context.coordinator.parent = self

        // Check if we need to reload (triggered by refreshTrigger change)
        if context.coordinator.lastTrigger != refreshTrigger {
            context.coordinator.lastTrigger = refreshTrigger
            onStartLoading()
            var request = URLRequest(url: url)
            request.timeoutInterval = 30

            // Add basic auth header if credentials provided
            if let (username, password) = basicAuthCredentials {
                let credentials = "\(username):\(password)"
                if let credentialData = credentials.data(using: .utf8) {
                    let base64Credentials = credentialData.base64EncodedString()
                    request.setValue("Basic \(base64Credentials)", forHTTPHeaderField: "Authorization")
                }
            }

            webView.load(request)
        }

        // Update font size if changed
        if context.coordinator.lastFontSize != fontSize {
            context.coordinator.lastFontSize = fontSize
            updateFontSize(webView, fontSize: fontSize)
        }
    }

    private func updateFontSize(_ webView: WKWebView, fontSize: Int) {
        let js = """
        (function() {
            var style = document.getElementById('custom-font-style');
            if (!style) {
                style = document.createElement('style');
                style.id = 'custom-font-style';
                document.head.appendChild(style);
            }
            style.textContent = `
                .terminal, .xterm, .xterm-viewport, .xterm-screen {
                    font-size: \(fontSize)px !important;
                    line-height: 1.4 !important;
                }
                .xterm-rows {
                    font-size: \(fontSize)px !important;
                }
            `;
            if (window.term) {
                window.term.options.fontSize = \(fontSize);
                window.term.refresh(0, window.term.rows - 1);
            }
        })();
        """
        webView.evaluateJavaScript(js, completionHandler: nil)
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    class Coordinator: NSObject, WKNavigationDelegate {
        var parent: TerminalWebView
        var lastTrigger: UUID?
        var lastFontSize: Int = 22

        init(_ parent: TerminalWebView) {
            self.parent = parent
        }

        @objc func handleTwoFingerSwipe(_ gesture: UIPanGestureRecognizer) {
            guard gesture.state == .ended else { return }

            let velocity = gesture.velocity(in: gesture.view)
            // Check for left swipe (negative X velocity)
            if velocity.x < -500 && abs(velocity.y) < abs(velocity.x) {
                parent.onTwoFingerSwipeLeft?()
                HapticManager.shared.mediumImpact()
            }
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            DispatchQueue.main.async {
                self.parent.onFinishLoading()
            }

            // Inject CSS to improve terminal appearance on mobile
            let js = """
            (function() {
                setTimeout(function() {
                    var style = document.createElement('style');
                    style.id = 'custom-font-style';
                    style.textContent = `
                        .terminal, .xterm, .xterm-viewport, .xterm-screen {
                            font-size: \(parent.fontSize)px !important;
                            line-height: 1.4 !important;
                        }
                        .xterm-rows {
                            font-size: \(parent.fontSize)px !important;
                        }
                        body {
                            background: #000 !important;
                            margin: 0 !important;
                            padding: 4px !important;
                        }
                    `;
                    document.head.appendChild(style);

                    if (window.term) {
                        window.term.options.fontSize = \(parent.fontSize);
                    }
                }, 500);
            })();
            """
            webView.evaluateJavaScript(js, completionHandler: nil)
        }

        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            DispatchQueue.main.async {
                self.parent.onError("Failed to load: \(error.localizedDescription)")
            }
        }

        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
            DispatchQueue.main.async {
                self.parent.onError("Connection failed: \(error.localizedDescription)\n\nMake sure the server is running and accessible.")
            }
        }
    }
}
#else
// macOS version
import AppKit

struct TerminalWebView: NSViewRepresentable {
    let url: URL
    let fontSize: Int
    let refreshTrigger: UUID
    let basicAuthCredentials: (String, String)?
    let onWebViewCreated: (WKWebView) -> Void
    let onStartLoading: () -> Void
    let onFinishLoading: () -> Void
    let onError: (String) -> Void
    var onTwoFingerSwipeLeft: (() -> Void)? = nil

    func makeNSView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        let prefs = WKWebpagePreferences()
        prefs.allowsContentJavaScript = true
        config.defaultWebpagePreferences = prefs

        let webView = WKWebView(frame: .zero, configuration: config)
        webView.navigationDelegate = context.coordinator

        DispatchQueue.main.async {
            onWebViewCreated(webView)
        }

        return webView
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        context.coordinator.parent = self

        if context.coordinator.lastTrigger != refreshTrigger {
            context.coordinator.lastTrigger = refreshTrigger
            onStartLoading()
            var request = URLRequest(url: url)
            request.timeoutInterval = 30
            webView.load(request)
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    class Coordinator: NSObject, WKNavigationDelegate {
        var parent: TerminalWebView
        var lastTrigger: UUID?

        init(_ parent: TerminalWebView) {
            self.parent = parent
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            DispatchQueue.main.async {
                self.parent.onFinishLoading()
            }
        }

        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            DispatchQueue.main.async {
                self.parent.onError("Failed: \(error.localizedDescription)")
            }
        }

        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
            DispatchQueue.main.async {
                self.parent.onError("Connection failed: \(error.localizedDescription)")
            }
        }
    }
}
#endif

#Preview {
    NavigationStack {
        TerminalView(server: .sample)
            .environmentObject(ServerManager.shared)
    }
}
