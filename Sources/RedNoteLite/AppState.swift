import AppKit
import Combine
import Foundation
import RedNoteCore
import SwiftUI

@MainActor
final class AppState: ObservableObject {
    let database: DatabaseStore
    let preferencesStore: PreferencesStore
    let webManager: WebViewManager

    @Published var preferences: AppPreferences {
        didSet {
            preferencesStore.save(preferences)
            webManager.updatePreferences(preferences)
        }
    }

    @Published var mainPane: MainPaneMode = .web {
        didSet {
            if mainPane == .history { reloadHistory() }
            if mainPane == .collections { reloadCollections() }
            if mainPane == .memory { refreshMemorySnapshot() }
        }
    }
    @Published var sidebarCollapsed: Bool = false

    @Published var searchKeyword: String = ""
    @Published var historyItems: [HistoryEntry] = []
    @Published var historyQuery: String = "" {
        didSet { reloadHistory() }
    }

    @Published var collectionItems: [CollectionEntry] = []
    @Published var folders: [String] = ["默认收藏"]
    @Published var selectedFolder: String = "全部" {
        didSet { reloadCollections() }
    }
    @Published var collectionQuery: String = "" {
        didSet { reloadCollections() }
    }

    @Published var isCurrentPageCollected: Bool = false
    @Published var memorySnapshot: MemorySnapshot = MemorySnapshot()
    @Published var showDMBanner: Bool = true

    private var memoryTimer: Timer?
    private var cancellables: Set<AnyCancellable> = []

    init() {
        let prefStore = PreferencesStore()
        let prefs = prefStore.load()
        self.preferencesStore = prefStore
        self.preferences = prefs

        do {
            self.database = try DatabaseStore()
        } catch {
            self.database = try! DatabaseStore(path: ":memory:")
        }

        self.webManager = WebViewManager(preferences: prefs)
        self.webManager.onPageSnapshot = { [weak self] snapshot in
            self?.handlePageSnapshot(snapshot)
        }

        webManager.$currentURL
            .receive(on: RunLoop.main)
            .sink { [weak self] url in
                guard let self else { return }
                self.isCurrentPageCollected = self.database.isCollected(urlString: url)
            }
            .store(in: &cancellables)

        reloadHistory()
        reloadCollections()
        refreshMemorySnapshot()
        startLightweightMemoryPolling()
    }

    deinit {
        memoryTimer?.invalidate()
    }

    private func startLightweightMemoryPolling() {
        memoryTimer = Timer.scheduledTimer(withTimeInterval: 6.0, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.refreshMemorySnapshot()
            }
        }
    }

    func refreshMemorySnapshot() {
        memorySnapshot = MemoryProfiler.sample(isHibernated: webManager.isHibernated)
    }

    func openWebSection(_ section: NavSection) {
        let wasAlreadyOnExplore = (mainPane == .web && webManager.activeSection == .explore)
        mainPane = .web
        if section == .explore {
            webManager.switchToExplore(wasAlreadyShowingExplore: wasAlreadyOnExplore)
        } else {
            webManager.switchToSecondarySection(section)
        }
    }

    func openProfile() {
        openWebSection(.profile)
    }

    func openNoteURL(_ urlString: String) {
        mainPane = .web
        webManager.openNoteFromLocal(urlString: urlString)
    }

    func toggleMainPane(_ pane: MainPaneMode) {
        if mainPane == pane {
            mainPane = .web
        } else {
            mainPane = pane
        }
    }

    // MARK: - Snapshot & History

    private func handlePageSnapshot(_ snapshot: CurrentPageSnapshot) {
        isCurrentPageCollected = database.isCollected(urlString: snapshot.url)

        guard preferences.recordHistoryEnabled else { return }
        guard XHSURLClassifier.shouldAutoRecordHistory(urlString: snapshot.url) else { return }

        do {
            try database.recordHistory(
                url: snapshot.url,
                noteId: snapshot.noteId,
                title: snapshot.title,
                author: snapshot.author,
                coverURL: snapshot.coverURL,
                excerpt: snapshot.excerpt,
                maxItems: preferences.maxHistoryItems
            )
            reloadHistory()
        } catch {}
    }

    func reloadHistory() {
        historyItems = (try? database.fetchHistory(query: historyQuery, limit: preferences.maxHistoryItems)) ?? []
    }

    func deleteHistory(_ entry: HistoryEntry) {
        try? database.deleteHistory(id: entry.id)
        reloadHistory()
    }

    func clearAllHistory() {
        try? database.clearHistory()
        reloadHistory()
        webManager.showToast("已清空本地浏览历史")
    }

    // MARK: - Local Collections

    func reloadCollections() {
        folders = (try? database.fetchFolders()) ?? ["默认收藏"]
        collectionItems = (try? database.fetchCollections(folder: selectedFolder, query: collectionQuery)) ?? []
        isCurrentPageCollected = database.isCollected(urlString: webManager.currentURL)
    }

    func toggleCollectCurrentPage() {
        Task { @MainActor in
            let snap = await webManager.fetchLiveSnapshot()
            let key = XHSURLClassifier.canonicalKey(for: snap.url)
            if database.isCollected(urlString: snap.url) {
                try? database.deleteCollection(id: key)
                isCurrentPageCollected = false
                reloadCollections()
                webManager.showToast("已从本地收藏夹移除")
            } else {
                _ = try? database.upsertCollection(
                    url: snap.url,
                    noteId: snap.noteId,
                    title: snap.title.isEmpty ? webManager.pageTitle : snap.title,
                    author: snap.author,
                    coverURL: snap.coverURL,
                    excerpt: snap.excerpt,
                    folder: selectedFolder == "全部" ? "默认收藏" : selectedFolder
                )
                isCurrentPageCollected = true
                reloadCollections()
                webManager.showToast("已保存到本地收藏夹")
            }
        }
    }

    func collectHistoryEntry(_ entry: HistoryEntry) {
        _ = try? database.upsertCollection(
            url: entry.url,
            noteId: entry.noteId,
            title: entry.title,
            author: entry.author,
            coverURL: entry.coverURL,
            excerpt: entry.excerpt,
            folder: "默认收藏"
        )
        reloadCollections()
        webManager.showToast("已加入本地收藏夹")
    }

    func updateCollection(_ entry: CollectionEntry, folder: String, memo: String) {
        try? database.updateCollection(id: entry.id, folder: folder, memo: memo)
        reloadCollections()
        webManager.showToast("已更新收藏分类与备注")
    }

    func deleteCollection(_ entry: CollectionEntry) {
        try? database.deleteCollection(id: entry.id)
        reloadCollections()
    }

    func exportCollectionsToMarkdown() {
        guard let md = try? database.exportCollectionsMarkdown() else { return }
        let panel = NSSavePanel()
        panel.title = "导出本地收藏夹"
        panel.nameFieldStringValue = "RedNoteLite-收藏夹.md"
        panel.allowedContentTypes = [.plainText]
        if panel.runModal() == .OK, let url = panel.url {
            do {
                try md.write(to: url, atomically: true, encoding: .utf8)
                webManager.showToast("已导出收藏到 \(url.lastPathComponent)")
            } catch {
                webManager.showToast("导出失败：\(error.localizedDescription)")
            }
        }
    }

    // MARK: - Memory & Storage Maintenance

    func purgeMemory(deepReset: Bool = false) {
        Task { @MainActor in
            await webManager.purgeMemory(deepReset: deepReset)
            try? database.vacuum()
            refreshMemorySnapshot()
        }
    }

    func toggleHibernate() {
        if webManager.isHibernated {
            webManager.wakeUp()
            mainPane = .web
        } else {
            webManager.hibernate()
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { [weak self] in
            self?.refreshMemorySnapshot()
        }
    }

    func openDataDirectoryInFinder() {
        let url = URL(fileURLWithPath: database.path).deletingLastPathComponent()
        NSWorkspace.shared.open(url)
    }

    func submitSearch() {
        let kw = searchKeyword.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !kw.isEmpty else { return }
        mainPane = .web
        webManager.search(keyword: kw)
    }

    func copyCurrentURL() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(webManager.currentURL, forType: .string)
        webManager.showToast("已复制当前链接")
    }
}
