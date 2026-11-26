import AppKit
import Combine
import Foundation
import RedNoteCore
import WebKit

private final class WeakScriptMessageHandler: NSObject, WKScriptMessageHandler {
    weak var delegate: WKScriptMessageHandler?
    init(delegate: WKScriptMessageHandler) {
        self.delegate = delegate
    }
    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        delegate?.userContentController(userContentController, didReceive: message)
    }
}

@MainActor
final class WebViewManager: NSObject, ObservableObject {
    static let safariUserAgent =
        "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.2 Safari/605.1.15"

    /// Dedicated Discover feed WebView — preserved untouched when switching to other sidebar sections.
    @Published private(set) var exploreWebView: SwipeBackWebView?
    /// Lazy secondary WebView shared by Notifications, Creator DM, and Profile (0 MB until first opened).
    @Published private(set) var secondaryWebView: SwipeBackWebView?

    @Published var currentURL: String = NavSection.explore.targetURL.absoluteString
    @Published var pageTitle: String = "发现"
    @Published var currentSnapshot: CurrentPageSnapshot = CurrentPageSnapshot(url: NavSection.explore.targetURL.absoluteString)
    @Published var isInNoteDetail: Bool = false
    @Published var canGoBack: Bool = false
    @Published var canGoForward: Bool = false
    @Published var isLoading: Bool = false
    @Published var isInitialColdLoading: Bool = true
    @Published var estimatedProgress: Double = 0
    @Published var isHibernated: Bool = false
    @Published var activeSection: NavSection = .explore
    @Published var activeChannel: ExploreChannel = .recommend
    @Published var swipeBackProgress: CGFloat = 0
    @Published var toastMessage: String?

    var onPageSnapshot: ((CurrentPageSnapshot) -> Void)?
    var onCloudCollectChanged: ((CurrentPageSnapshot, Bool) -> Void)?

    var activeWebView: SwipeBackWebView? {
        if activeSection == .explore {
            return exploreWebView
        }
        return secondaryWebView ?? exploreWebView
    }

    private var preferences: AppPreferences
    private var isDarkAppearance: Bool = false
    private var lastExploreURL: URL = NavSection.explore.targetURL
    private var lastSecondaryURL: URL?
    private var secondaryLoadedSection: NavSection?
    private var pendingExploreChannel: ExploreChannel?
    private var pendingOpenCloudCollectionsTab: Bool = false
    private var switchSequenceToken: Int = 0
    private var telemetryRuleList: WKContentRuleList?

    // Per-WebView cached state so switching tabs never loses state or triggers reloads
    private var exploreSnapshot = CurrentPageSnapshot(url: NavSection.explore.targetURL.absoluteString)
    private var secondarySnapshot = CurrentPageSnapshot(url: NavSection.notifications.targetURL.absoluteString)
    private var exploreIsInDetail = false
    private var secondaryIsInDetail = false

    private var exploreObservations: [NSKeyValueObservation] = []
    private var secondaryObservations: [NSKeyValueObservation] = []
    private var idleHibernateWorkItem: DispatchWorkItem?
    private var toastClearWorkItem: DispatchWorkItem?

    init(preferences: AppPreferences) {
        self.preferences = preferences
        super.init()
        // Keep persistent HTTP cache on SSD so Xiaohongshu's ~6 MB versioned JS/CSS bundles
        // load in milliseconds on subsequent cold starts (cleared on manual cache purge)
        URLCache.shared = URLCache(memoryCapacity: 16 * 1024 * 1024, diskCapacity: 80 * 1024 * 1024)
        self.isDarkAppearance = NSApp.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        setupExploreWebView(loading: NavSection.explore.targetURL)
        prepareTelemetryBlocker()
        // Safety cap: never keep launch skeleton up longer than 2.8s even on slow networks
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.8) { [weak self] in
            self?.isInitialColdLoading = false
        }
    }

    /// Compiles/loads a native WebKit ContentRuleList blocking pure telemetry & survey beacons
    /// (apm-fe, t2 collect, sem_sdk, xhs_pc_nps, racing_report). Cuts ~1s & 15+ junk requests on startup
    /// without affecting auth, feeds, comments, collects, or chat.
    private func prepareTelemetryBlocker() {
        let id = "rednoteTelemetryBlockerV1"
        let rulesJSON = """
        [
          {"trigger":{"url-filter":".*apm-fe\\\\.xiaohongshu\\\\.com.*"},"action":{"type":"block"}},
          {"trigger":{"url-filter":".*t2\\\\.xiaohongshu\\\\.com.*"},"action":{"type":"block"}},
          {"trigger":{"url-filter":".*pages\\\\.xiaohongshu\\\\.com/data/sem_sdk.*"},"action":{"type":"block"}},
          {"trigger":{"url-filter":".*pages\\\\.xiaohongshu\\\\.com/data/xhs_pc_nps.*"},"action":{"type":"block"}},
          {"trigger":{"url-filter":".*edith\\\\.xiaohongshu\\\\.com/api/sns/web/racing_report.*"},"action":{"type":"block"}}
        ]
        """
        guard let store = WKContentRuleListStore.default() else { return }
        store.lookUpContentRuleList(forIdentifier: id) { [weak self] existing, _ in
            if let existing {
                Task { @MainActor in self?.attachTelemetryBlocker(existing) }
                return
            }
            store.compileContentRuleList(forIdentifier: id, encodedContentRuleList: rulesJSON) { [weak self] compiled, _ in
                if let compiled {
                    Task { @MainActor in self?.attachTelemetryBlocker(compiled) }
                }
            }
        }
    }

    private func attachTelemetryBlocker(_ list: WKContentRuleList) {
        telemetryRuleList = list
        exploreWebView?.configuration.userContentController.add(list)
        secondaryWebView?.configuration.userContentController.add(list)
    }

    func updatePreferences(_ newPrefs: AppPreferences) {
        let autoplayChanged = newPrefs.blockAutoplayVideo != preferences.blockAutoplayVideo
        self.preferences = newPrefs
        applyWebPreferences(to: exploreWebView)
        applyWebPreferences(to: secondaryWebView)
        if autoplayChanged {
            let policy: WKAudiovisualMediaTypes = newPrefs.blockAutoplayVideo ? .all : []
            exploreWebView?.configuration.mediaTypesRequiringUserActionForPlayback = policy
            secondaryWebView?.configuration.mediaTypesRequiringUserActionForPlayback = policy
        }
    }

    func syncSystemAppearance(isDark: Bool) {
        isDarkAppearance = isDark
        let flag = isDark ? "true" : "false"
        let js = "window.__rednoteLite && window.__rednoteLite.applyAppearance(\(flag));"
        exploreWebView?.evaluateJavaScript(js, completionHandler: nil)
        secondaryWebView?.evaluateJavaScript(js, completionHandler: nil)
    }

    func showToast(_ message: String) {
        toastClearWorkItem?.cancel()
        toastMessage = message
        let item = DispatchWorkItem { [weak self] in
            self?.toastMessage = nil
        }
        toastClearWorkItem = item
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.2, execute: item)
    }

    // MARK: - WebView Factory & Lifecycle

    private func makeConfiguredWebView() -> SwipeBackWebView {
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .default()
        config.mediaTypesRequiringUserActionForPlayback = preferences.blockAutoplayVideo ? .all : []
        config.preferences.isElementFullscreenEnabled = true
        config.defaultWebpagePreferences.allowsContentJavaScript = true

        let contentController = WKUserContentController()
        contentController.addUserScript(WKUserScript(
            source: WebScripts.earlyStyleScript,
            injectionTime: .atDocumentStart,
            forMainFrameOnly: true
        ))
        contentController.addUserScript(WKUserScript(
            source: WebScripts.bridgeScript,
            injectionTime: .atDocumentEnd,
            forMainFrameOnly: true
        ))
        contentController.add(WeakScriptMessageHandler(delegate: self), name: "rednoteBridge")
        if let telemetryRuleList {
            contentController.add(telemetryRuleList)
        }
        config.userContentController = contentController

        let wv = SwipeBackWebView(frame: .zero, configuration: config)
        wv.customUserAgent = Self.safariUserAgent
        wv.navigationDelegate = self
        wv.uiDelegate = self
        wv.allowsBackForwardNavigationGestures = false
        wv.allowsMagnification = true
        wv.setValue(false, forKey: "drawsBackground")

        wv.shouldHandleSwipeBack = { [weak self] in
            guard let self else { return false }
            return self.isInNoteDetail || self.canGoBack
        }
        wv.onSwipeBackProgress = { [weak self] progress in
            self?.swipeBackProgress = progress
        }
        wv.onSwipeBackTriggered = { [weak self] in
            self?.goBackFromNote()
        }
        return wv
    }

    private func setupExploreWebView(loading url: URL) {
        teardownWebView(&exploreWebView, observations: &exploreObservations)
        let wv = makeConfiguredWebView()
        exploreWebView = wv
        isHibernated = false
        exploreObservations = bindObservations(for: wv, isExplore: true)
        lastExploreURL = url
        wv.load(URLRequest(url: url, cachePolicy: .useProtocolCachePolicy))
    }

    private func setupSecondaryWebView(loading url: URL, for section: NavSection) {
        teardownWebView(&secondaryWebView, observations: &secondaryObservations)
        let wv = makeConfiguredWebView()
        secondaryWebView = wv
        secondaryLoadedSection = section
        lastSecondaryURL = url
        secondaryObservations = bindObservations(for: wv, isExplore: false)
        wv.load(URLRequest(url: url, cachePolicy: .useProtocolCachePolicy))
    }

    private func bindObservations(for wv: WKWebView, isExplore: Bool) -> [NSKeyValueObservation] {
        var obs: [NSKeyValueObservation] = []
        obs.append(wv.observe(\.canGoBack, options: [.new]) { [weak self] view, _ in
            Task { @MainActor in
                guard let self, self.isViewActive(isExplore: isExplore) else { return }
                self.canGoBack = view.canGoBack
            }
        })
        obs.append(wv.observe(\.canGoForward, options: [.new]) { [weak self] view, _ in
            Task { @MainActor in
                guard let self, self.isViewActive(isExplore: isExplore) else { return }
                self.canGoForward = view.canGoForward
            }
        })
        obs.append(wv.observe(\.isLoading, options: [.new]) { [weak self] view, _ in
            Task { @MainActor in
                guard let self, self.isViewActive(isExplore: isExplore) else { return }
                self.isLoading = view.isLoading
            }
        })
        obs.append(wv.observe(\.estimatedProgress, options: [.new]) { [weak self] view, _ in
            Task { @MainActor in
                guard let self, self.isViewActive(isExplore: isExplore) else { return }
                self.estimatedProgress = view.estimatedProgress
            }
        })
        obs.append(wv.observe(\.title, options: [.new]) { [weak self] view, _ in
            Task { @MainActor in
                guard let self, self.isViewActive(isExplore: isExplore) else { return }
                if let title = view.title, !title.isEmpty {
                    self.pageTitle = title.replacingOccurrences(of: " - 小红书", with: "")
                }
            }
        })
        obs.append(wv.observe(\.url, options: [.new]) { [weak self] view, _ in
            Task { @MainActor in
                guard let self, let url = view.url, url.absoluteString != "about:blank" else { return }
                if isExplore {
                    self.lastExploreURL = url
                    if XHSURLClassifier.extractNoteId(from: url.absoluteString) != nil {
                        self.exploreIsInDetail = true
                    }
                } else {
                    self.lastSecondaryURL = url
                    if XHSURLClassifier.extractNoteId(from: url.absoluteString) != nil {
                        self.secondaryIsInDetail = true
                    }
                }
                if self.isViewActive(isExplore: isExplore) {
                    self.currentURL = url.absoluteString
                    self.isInNoteDetail = isExplore ? self.exploreIsInDetail : self.secondaryIsInDetail
                }
            }
        })
        return obs
    }

    private func isViewActive(isExplore: Bool) -> Bool {
        isExplore ? (activeSection == .explore) : (activeSection != .explore)
    }

    private func syncPublishedStateFromActiveWebView() {
        let isExplore = (activeSection == .explore)
        let wv = activeWebView
        canGoBack = wv?.canGoBack ?? false
        canGoForward = wv?.canGoForward ?? false
        isLoading = wv?.isLoading ?? false
        estimatedProgress = wv?.estimatedProgress ?? 0
        if let urlStr = wv?.url?.absoluteString, urlStr != "about:blank" {
            currentURL = urlStr
        }
        if let title = wv?.title, !title.isEmpty {
            pageTitle = title.replacingOccurrences(of: " - 小红书", with: "")
        } else {
            pageTitle = activeSection.title
        }
        currentSnapshot = isExplore ? exploreSnapshot : secondarySnapshot
        isInNoteDetail = isExplore ? exploreIsInDetail : secondaryIsInDetail
    }

    private func teardownWebView(_ slot: inout SwipeBackWebView?, observations: inout [NSKeyValueObservation]) {
        observations.removeAll()
        if let wv = slot {
            wv.stopLoading()
            wv.navigationDelegate = nil
            wv.uiDelegate = nil
            wv.shouldHandleSwipeBack = nil
            wv.onSwipeBackProgress = nil
            wv.onSwipeBackTriggered = nil
            wv.configuration.userContentController.removeScriptMessageHandler(forName: "rednoteBridge")
            wv.configuration.userContentController.removeAllUserScripts()
            wv.loadHTMLString("", baseURL: nil)
            wv.removeFromSuperview()
        }
        slot = nil
    }

    /// Destroys WebViews and releases WebContent memory while preserving login cookies.
    func hibernate() {
        guard !isHibernated else { return }
        if let url = exploreWebView?.url, url.scheme?.hasPrefix("http") == true {
            lastExploreURL = url
        }
        if let url = secondaryWebView?.url, url.scheme?.hasPrefix("http") == true {
            lastSecondaryURL = url
        }
        teardownWebView(&exploreWebView, observations: &exploreObservations)
        teardownWebView(&secondaryWebView, observations: &secondaryObservations)
        secondaryLoadedSection = nil
        URLCache.shared.removeAllCachedResponses()
        ThumbnailCache.shared.clear()
        isHibernated = true
        isLoading = false
        isInNoteDetail = false
        exploreIsInDetail = false
        secondaryIsInDetail = false
        showToast("已进入休眠模式，网页内存已释放")
    }

    func wakeUp(url: URL? = nil) {
        cancelScheduledHibernation()
        if isHibernated || exploreWebView == nil {
            setupExploreWebView(loading: url ?? lastExploreURL)
            activeSection = .explore
            syncPublishedStateFromActiveWebView()
        } else if let url {
            loadInExplore(url: url, ignoreCache: false)
        }
    }

    func handleAppResignActive() {
        guard !isHibernated else { return }
        if preferences.autoPauseMediaInBackground {
            pauseMedia(in: exploreWebView)
            pauseMedia(in: secondaryWebView)
        }
        scheduleIdleHibernationIfNeeded()
    }

    func handleAppBecomeActive() {
        cancelScheduledHibernation()
    }

    private func pauseMedia(in webView: WKWebView?) {
        webView?.evaluateJavaScript("window.__rednoteLite && window.__rednoteLite.pauseAllMedia();", completionHandler: nil)
    }

    private func scheduleIdleHibernationIfNeeded() {
        cancelScheduledHibernation()
        let minutes = preferences.autoHibernateMinutes
        guard minutes > 0 else { return }
        let work = DispatchWorkItem { [weak self] in
            Task { @MainActor in
                guard let self, !NSApp.isActive else { return }
                self.hibernate()
            }
        }
        idleHibernateWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + Double(minutes * 60), execute: work)
    }

    private func cancelScheduledHibernation() {
        idleHibernateWorkItem?.cancel()
        idleHibernateWorkItem = nil
    }

    // MARK: - Sidebar Switching (Zero Auto-Refresh!)

    /// Switches to Discover WITHOUT refreshing when coming from any other section or pane.
    /// ONLY refreshes when the user is ALREADY viewing Discover and clicks Discover again.
    func switchToExplore(wasAlreadyShowingExplore: Bool) {
        if isHibernated || exploreWebView == nil {
            setupExploreWebView(loading: lastExploreURL)
            activeSection = .explore
            syncPublishedStateFromActiveWebView()
            return
        }

        if wasAlreadyShowingExplore {
            // User explicitly clicked "发现" while ALREADY on Discover -> manual refresh!
            if exploreIsInDetail {
                goBackFromNote()
            } else {
                exploreWebView?.reload()
                showToast("正在刷新发现页")
            }
            return
        }

        // Switching BACK to Discover from Notifications / DM / Profile / Collections / History / Settings:
        // NEVER reload! Keep exact page, channel, and scroll position intact.
        pauseMedia(in: secondaryWebView)
        activeSection = .explore
        syncPublishedStateFromActiveWebView()
    }

    /// Opens a non-Discover web section in the lazy secondary WebView so Discover stays untouched.
    func switchToSecondarySection(_ section: NavSection) {
        guard section != .explore else {
            switchToExplore(wasAlreadyShowingExplore: false)
            return
        }

        pauseMedia(in: exploreWebView)
        isHibernated = false
        activeSection = section

        if section == .profile {
            openProfileInSecondary()
            return
        }

        // If secondary WebView already holds this exact section, reveal it with ZERO reload!
        if let secondary = secondaryWebView, secondaryLoadedSection == section, secondary.url?.scheme?.hasPrefix("http") == true {
            syncPublishedStateFromActiveWebView()
            return
        }

        if let secondary = secondaryWebView {
            secondaryLoadedSection = section
            secondaryIsInDetail = false
            lastSecondaryURL = section.targetURL
            secondary.stopLoading()
            secondary.load(URLRequest(url: section.targetURL, cachePolicy: .useProtocolCachePolicy))
            syncPublishedStateFromActiveWebView()
        } else {
            setupSecondaryWebView(loading: section.targetURL, for: section)
            syncPublishedStateFromActiveWebView()
        }
    }

    private func openProfileInSecondary() {
        // If secondary is already showing user profile, just reveal without reloading
        if let secondary = secondaryWebView,
           secondaryLoadedSection == .profile,
           let urlStr = secondary.url?.absoluteString,
           urlStr.contains("/user/profile/") {
            syncPublishedStateFromActiveWebView()
            return
        }

        // Ask exploreWebView for the logged-in user's profile link without touching exploreWebView's navigation
        if let explore = exploreWebView {
            explore.evaluateJavaScript("window.__rednoteLite ? window.__rednoteLite.getUserProfileURL() : ''") { [weak self] result, _ in
                Task { @MainActor in
                    guard let self else { return }
                    if let urlStr = result as? String, !urlStr.isEmpty, let profileURL = URL(string: urlStr) {
                        if let secondary = self.secondaryWebView {
                            self.secondaryLoadedSection = .profile
                            self.secondaryIsInDetail = false
                            secondary.stopLoading()
                            secondary.load(URLRequest(url: profileURL))
                            self.syncPublishedStateFromActiveWebView()
                        } else {
                            self.setupSecondaryWebView(loading: profileURL, for: .profile)
                            self.syncPublishedStateFromActiveWebView()
                        }
                    } else {
                        // Not logged in yet — stay on Explore and open login dialog if available
                        self.activeSection = .explore
                        self.syncPublishedStateFromActiveWebView()
                        _ = try? await explore.evaluateJavaScript("window.__rednoteLite && window.__rednoteLite.openUserProfile();")
                        self.showToast("请先登录小红书账号以访问个人主页")
                    }
                }
            }
        } else {
            setupExploreWebView(loading: NavSection.explore.targetURL)
            activeSection = .explore
            syncPublishedStateFromActiveWebView()
        }
    }

    // MARK: - Top Channel Tag Switching (Explicit User Action -> Always Loads/Refreshes Target Tag)

    func selectChannel(_ channel: ExploreChannel) {
        let wasSameChannel = (activeSection == .explore && activeChannel == channel && !exploreIsInDetail)
        pauseMedia(in: secondaryWebView)
        activeSection = .explore
        activeChannel = channel
        exploreIsInDetail = false
        isInNoteDetail = false
        pendingExploreChannel = nil
        switchSequenceToken += 1
        let myToken = switchSequenceToken

        if isHibernated || exploreWebView == nil {
            if !channel.isTopicChannel {
                pendingExploreChannel = channel
            }
            setupExploreWebView(loading: channel.url)
            syncPublishedStateFromActiveWebView()
            return
        }

        let currentExploreURL = exploreWebView?.url?.absoluteString ?? ""
        let isOnXHS = currentExploreURL.contains("www.xiaohongshu.com")

        if channel.isTopicChannel {
            // Clicking the currently active topic tag manually refreshes it
            if wasSameChannel && currentExploreURL.contains("/search_result") {
                exploreWebView?.reload()
                syncPublishedStateFromActiveWebView()
                return
            }

            // Fast path: switch topic IN-PLACE inside the running Vue SPA (~250ms, zero 6 MB JS reload!)
            if isOnXHS {
                runSPASearchWithFallback(keyword: channel.title, fallbackURL: channel.url, token: myToken)
            } else {
                loadInExplore(url: channel.url, ignoreCache: false)
            }
            syncPublishedStateFromActiveWebView()
            return
        }

        // Official Explore channels (推荐, 穿搭, 美食, ...)
        let isCurrentlyOnExploreFeed = currentExploreURL.contains("/explore") && !currentExploreURL.contains("/search_result")

        if wasSameChannel && isCurrentlyOnExploreFeed {
            exploreWebView?.reload()
            syncPublishedStateFromActiveWebView()
            return
        }

        if isOnXHS {
            let escapedId = jsEscape(channel.rawValue)
            let escapedTitle = jsEscape(channel.title)
            let js = "window.__rednoteLite ? window.__rednoteLite.navigateToExploreInSPA('\(escapedId)', '\(escapedTitle)') : 'no_router'"
            exploreWebView?.evaluateJavaScript(js) { [weak self] result, _ in
                Task { @MainActor in
                    guard let self, self.switchSequenceToken == myToken else { return }
                    let outcome = (result as? String) ?? "no_router"
                    if outcome == "no_router" {
                        self.pendingExploreChannel = channel
                        self.loadInExplore(url: channel.url, ignoreCache: false)
                    }
                }
            }
        } else {
            pendingExploreChannel = channel
            loadInExplore(url: channel.url, ignoreCache: false)
        }
        syncPublishedStateFromActiveWebView()
    }

    private func runSPASearchWithFallback(keyword: String, fallbackURL: URL, token: Int) {
        let escapedKw = jsEscape(keyword)
        let js = "window.__rednoteLite ? window.__rednoteLite.searchInSPA('\(escapedKw)') : 'no_router'"
        exploreWebView?.evaluateJavaScript(js) { [weak self] result, _ in
            Task { @MainActor in
                guard let self, self.switchSequenceToken == token else { return }
                let outcome = (result as? String) ?? "no_router"
                if outcome != "router_pushed" {
                    self.loadInExplore(url: fallbackURL, ignoreCache: false)
                }
            }
        }
    }

    private func jsEscape(_ raw: String) -> String {
        raw
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "'", with: "\\'")
            .replacingOccurrences(of: "\n", with: " ")
    }

    // MARK: - Full-Page Note Back Gesture, Search & Manual Reload

    func goBackFromNote() {
        swipeBackProgress = 0
        guard let wv = activeWebView, !isHibernated else { return }
        let isExplore = (activeSection == .explore)

        if isInNoteDetail {
            wv.evaluateJavaScript("window.__rednoteLite ? window.__rednoteLite.closeNoteDetail() : 'standalone'") { [weak self] result, _ in
                Task { @MainActor in
                    guard let self else { return }
                    let outcome = (result as? String) ?? "standalone"
                    if outcome == "modal_closed" || outcome == "modal_escape" {
                        if isExplore { self.exploreIsInDetail = false } else { self.secondaryIsInDetail = false }
                        self.isInNoteDetail = false
                    } else if wv.canGoBack {
                        wv.goBack()
                    } else {
                        if isExplore { self.exploreIsInDetail = false } else { self.secondaryIsInDetail = false }
                        self.isInNoteDetail = false
                    }
                }
            }
        } else if wv.canGoBack {
            wv.goBack()
        }
    }

    func loadInExplore(url: URL, ignoreCache: Bool = false) {
        if isHibernated || exploreWebView == nil {
            setupExploreWebView(loading: url)
            return
        }
        lastExploreURL = url
        exploreWebView?.stopLoading()
        let policy: URLRequest.CachePolicy = ignoreCache ? .reloadIgnoringLocalCacheData : .useProtocolCachePolicy
        exploreWebView?.load(URLRequest(url: url, cachePolicy: policy))
    }

    func openNoteFromLocal(urlString: String) {
        guard let url = URL(string: urlString) else { return }
        pauseMedia(in: secondaryWebView)
        activeSection = .explore
        loadInExplore(url: url, ignoreCache: false)
        syncPublishedStateFromActiveWebView()
    }

    func search(keyword: String) {
        guard let url = XHSURLClassifier.searchURL(for: keyword) else { return }
        pauseMedia(in: secondaryWebView)
        activeSection = .explore
        exploreIsInDetail = false
        isInNoteDetail = false
        switchSequenceToken += 1
        let myToken = switchSequenceToken

        let currentExploreURL = exploreWebView?.url?.absoluteString ?? ""
        if !isHibernated, exploreWebView != nil, currentExploreURL.contains("www.xiaohongshu.com") {
            runSPASearchWithFallback(keyword: keyword, fallbackURL: url, token: myToken)
        } else {
            loadInExplore(url: url, ignoreCache: false)
        }
        syncPublishedStateFromActiveWebView()
    }

    func goBack() {
        goBackFromNote()
    }

    func goForward() {
        activeWebView?.goForward()
    }

    /// Manual reload triggered ONLY by user clicking Refresh button or pressing ⌘R.
    func reload() {
        if isHibernated {
            wakeUp()
        } else {
            activeWebView?.reload()
        }
    }

    func focusCommentBox() {
        guard !isHibernated, let wv = activeWebView else {
            showToast("请先唤醒页面再发表评论")
            return
        }
        wv.evaluateJavaScript("window.__rednoteLite ? window.__rednoteLite.focusCommentInput() : false") { [weak self] result, _ in
            Task { @MainActor in
                let ok = (result as? Bool) ?? false
                self?.showToast(ok ? "已定位到评论输入框" : "请先打开一条笔记详情页")
            }
        }
    }

    func fetchLiveSnapshot() async -> CurrentPageSnapshot {
        guard let wv = activeWebView, !isHibernated else { return currentSnapshot }
        do {
            let result = try await wv.evaluateJavaScript("window.__rednoteLite ? window.__rednoteLite.getSnapshot() : null")
            if let dict = result as? [String: Any], let snap = parseSnapshot(dict) {
                currentSnapshot = snap
                return snap
            }
        } catch {}
        return currentSnapshot
    }

    /// Triggers Xiaohongshu's native in-page cloud collect button so cloud & local stay in sync.
    func syncCloudCollect(desiredCollected: Bool) async -> String {
        guard let wv = activeWebView, !isHibernated else { return "not_found" }
        let flag = desiredCollected ? "true" : "false"
        do {
            let result = try await wv.evaluateJavaScript(
                "window.__rednoteLite ? window.__rednoteLite.toggleCloudCollect(\(flag)) : null"
            )
            if let dict = result as? [String: Any], let status = dict["status"] as? String {
                return status
            }
        } catch {}
        return "not_found"
    }

    /// Opens the user's official Xiaohongshu profile Cloud Collections tab in the secondary WebView
    /// (keeping Discover feed untouched).
    func openCloudCollections() {
        pendingOpenCloudCollectionsTab = true
        pauseMedia(in: exploreWebView)
        isHibernated = false
        activeSection = .profile

        if let secondary = secondaryWebView,
           secondaryLoadedSection == .profile,
           let urlStr = secondary.url?.absoluteString,
           urlStr.contains("/user/profile/") {
            syncPublishedStateFromActiveWebView()
            secondary.evaluateJavaScript("window.__rednoteLite && window.__rednoteLite.openCloudCollectionsTab();", completionHandler: nil)
            pendingOpenCloudCollectionsTab = false
            return
        }

        openProfileInSecondary()
    }

    /// Extracts visible note cards from the currently displayed page (e.g., user's Cloud Collections tab)
    /// for one-click batch import into local SQLite.
    func extractVisibleCloudNotes() async -> [CurrentPageSnapshot] {
        guard let wv = activeWebView, !isHibernated else { return [] }
        do {
            let result = try await wv.evaluateJavaScript("window.__rednoteLite ? window.__rednoteLite.extractVisibleNotes() : []")
            guard let list = result as? [[String: Any]] else { return [] }
            return list.compactMap { item in
                guard let url = item["url"] as? String, !url.isEmpty else { return nil }
                let noteId = item["noteId"] as? String
                let title = (item["title"] as? String) ?? ""
                let author = (item["author"] as? String) ?? ""
                let cover = (item["coverURL"] as? String) ?? ""
                return CurrentPageSnapshot(
                    url: url,
                    noteId: noteId,
                    title: title,
                    author: author,
                    coverURL: cover.isEmpty ? nil : cover,
                    excerpt: "",
                    isNoteDetail: false
                )
            }
        } catch {
            return []
        }
    }

    /// Releases non-session caches & trims DOM video buffers without logging out the user.
    func purgeMemory(deepReset: Bool = false) async {
        URLCache.shared.removeAllCachedResponses()
        ThumbnailCache.shared.clear()

        if !isHibernated {
            _ = try? await exploreWebView?.evaluateJavaScript("window.__rednoteLite && window.__rednoteLite.trimMemory();")
            _ = try? await secondaryWebView?.evaluateJavaScript("window.__rednoteLite && window.__rednoteLite.trimMemory();")
        }

        let cacheOnlyTypes: Set<String> = [
            WKWebsiteDataTypeMemoryCache,
            WKWebsiteDataTypeDiskCache,
            WKWebsiteDataTypeFetchCache,
            WKWebsiteDataTypeOfflineWebApplicationCache
        ]
        await withCheckedContinuation { continuation in
            WKWebsiteDataStore.default().removeData(ofTypes: cacheOnlyTypes, modifiedSince: .distantPast) {
                continuation.resume()
            }
        }

        if deepReset && !isHibernated {
            // Drop unused secondary WebView to immediately reclaim its memory
            teardownWebView(&secondaryWebView, observations: &secondaryObservations)
            secondaryLoadedSection = nil
            let resumeURL = exploreWebView?.url ?? lastExploreURL
            setupExploreWebView(loading: resumeURL)
            activeSection = .explore
            syncPublishedStateFromActiveWebView()
            showToast("已深度释放网页内存（登录态已保留）")
        } else {
            showToast("已清理缓存并释放闲置内存")
        }
    }

    private func applyWebPreferences(to wv: WKWebView?) {
        guard let wv, !isHibernated else { return }
        let eco = preferences.ecoModeEnabled ? "true" : "false"
        let noAuto = preferences.blockAutoplayVideo ? "true" : "false"
        let clean = preferences.cleanModeEnabled ? "true" : "false"
        let dark = isDarkAppearance ? "true" : "false"
        let js = """
        if (window.__rednoteLite) {
            window.__rednoteLite.applyAppearance(\(dark));
            window.__rednoteLite.applyEcoMode(\(eco), \(noAuto));
            window.__rednoteLite.applyCleanMode(\(clean));
        }
        """
        wv.evaluateJavaScript(js, completionHandler: nil)
    }

    private func parseSnapshot(_ dict: [String: Any]) -> CurrentPageSnapshot? {
        guard let url = dict["url"] as? String, !url.isEmpty, url != "about:blank" else {
            return nil
        }
        let noteIdRaw = (dict["noteId"] as? String) ?? ""
        let noteId = noteIdRaw.isEmpty ? XHSURLClassifier.extractNoteId(from: url) : noteIdRaw
        let title = (dict["title"] as? String) ?? pageTitle
        let author = (dict["author"] as? String) ?? ""
        let coverRaw = (dict["coverURL"] as? String) ?? ""
        let excerpt = (dict["excerpt"] as? String) ?? ""
        let isNoteDetail = (dict["isNoteDetail"] as? Bool) ?? (noteId != nil)

        return CurrentPageSnapshot(
            url: url,
            noteId: noteId,
            title: title,
            author: author,
            coverURL: coverRaw.isEmpty ? nil : coverRaw,
            excerpt: excerpt,
            isNoteDetail: isNoteDetail
        )
    }
}

// MARK: - WKScriptMessageHandler

extension WebViewManager: WKScriptMessageHandler {
    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        guard message.name == "rednoteBridge",
              let body = message.body as? [String: Any],
              let msgType = body["type"] as? String else {
            return
        }

        switch msgType {
        case "firstPaintReady":
            isInitialColdLoading = false

        case "rightClickBack":
            if message.webView === activeWebView {
                goBackFromNote()
            }

        case "cloudCollectChanged":
            if let snapDict = body["snapshot"] as? [String: Any],
               let snap = parseSnapshot(snapDict),
               let collected = body["collected"] as? Bool {
                onCloudCollectChanged?(snap, collected)
            }

        case "pageSnapshot":
            guard let snap = parseSnapshot(body) else { return }
            let fromExplore = (message.webView === exploreWebView)
            if fromExplore {
                exploreSnapshot = snap
                exploreIsInDetail = snap.isNoteDetail
            } else {
                secondarySnapshot = snap
                secondaryIsInDetail = snap.isNoteDetail
            }
            if isViewActive(isExplore: fromExplore) {
                currentSnapshot = snap
                currentURL = snap.url
                isInNoteDetail = snap.isNoteDetail
                if !snap.title.isEmpty {
                    pageTitle = snap.title
                }
            }
            onPageSnapshot?(snap)

        default:
            break
        }
    }
}

// MARK: - WKNavigationDelegate

extension WebViewManager: WKNavigationDelegate {
    func webView(
        _ webView: WKWebView,
        decidePolicyFor navigationAction: WKNavigationAction,
        decisionHandler: @escaping (WKNavigationActionPolicy) -> Void
    ) {
        guard let url = navigationAction.request.url else {
            decisionHandler(.allow)
            return
        }

        // Automatically upgrade any accidental http:// redirect on Xiaohongshu domains to https://
        // so macOS ATS never silently aborts search_result or internal redirects!
        if url.scheme?.lowercased() == "http",
           XHSURLClassifier.isAllowedInApp(url),
           var comps = URLComponents(url: url, resolvingAgainstBaseURL: false) {
            comps.scheme = "https"
            if let httpsURL = comps.url {
                decisionHandler(.cancel)
                webView.load(URLRequest(url: httpsURL))
                return
            }
        }

        if navigationAction.navigationType == .linkActivated && !XHSURLClassifier.isAllowedInApp(url) {
            if url.scheme == "http" || url.scheme == "https" {
                NSWorkspace.shared.open(url)
            }
            decisionHandler(.cancel)
            return
        }

        decisionHandler(.allow)
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        if webView === exploreWebView {
            isInitialColdLoading = false
        }
        applyWebPreferences(to: webView)
        webView.evaluateJavaScript("window.__rednoteLite && window.__rednoteLite.reportNow();", completionHandler: nil)

        if webView === secondaryWebView && pendingOpenCloudCollectionsTab {
            pendingOpenCloudCollectionsTab = false
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak webView] in
                webView?.evaluateJavaScript(
                    "window.__rednoteLite && window.__rednoteLite.openCloudCollectionsTab();",
                    completionHandler: nil
                )
            }
        }

        // If returning from a topic channel to a specific official channel, confirm the channel tab is clicked
        if webView === exploreWebView, let pending = pendingExploreChannel, !pending.isTopicChannel {
            pendingExploreChannel = nil
            if pending != .recommend {
                let escapedId = pending.rawValue.replacingOccurrences(of: "'", with: "\\'")
                let escapedTitle = pending.title.replacingOccurrences(of: "'", with: "\\'")
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { [weak webView] in
                    webView?.evaluateJavaScript(
                        "window.__rednoteLite && window.__rednoteLite.selectChannel('\(escapedId)', '\(escapedTitle)');",
                        completionHandler: nil
                    )
                }
            }
        }
    }

    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        // Do not auto-reload silently; only inform user so manual refresh stays under user control
        if webView === activeWebView {
            showToast("网页渲染进程已回收，可按 ⌘R 重新加载")
        }
    }
}

// MARK: - WKUIDelegate

extension WebViewManager: WKUIDelegate {
    func webView(
        _ webView: WKWebView,
        createWebViewWith configuration: WKWebViewConfiguration,
        for navigationAction: WKNavigationAction,
        windowFeatures: WKWindowFeatures
    ) -> WKWebView? {
        if let url = navigationAction.request.url {
            if XHSURLClassifier.isAllowedInApp(url) {
                webView.load(navigationAction.request)
            } else if url.scheme == "http" || url.scheme == "https" {
                NSWorkspace.shared.open(url)
            }
        }
        return nil
    }
}
