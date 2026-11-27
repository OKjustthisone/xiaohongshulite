import AppKit
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate {
    var onResignActive: (() -> Void)?
    var onBecomeActive: (() -> Void)?
    var onEscapePressed: (() -> Bool)?

    private var keyMonitor: Any?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)

        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            // ESC key (53) exits full-page note cleanly back to feed
            if event.keyCode == 53, self?.onEscapePressed?() == true {
                return nil
            }
            return event
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        if let keyMonitor {
            NSEvent.removeMonitor(keyMonitor)
        }
    }

    func applicationDidResignActive(_ notification: Notification) {
        onResignActive?()
    }

    func applicationDidBecomeActive(_ notification: Notification) {
        onBecomeActive?()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }
}

@main
struct RedNoteLiteApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var appState = AppState()

    var body: some Scene {
        WindowGroup("RedNote Lite") {
            ContentView(state: appState, webManager: appState.webManager)
                .onAppear {
                    appDelegate.onResignActive = { [weak manager = appState.webManager] in
                        Task { @MainActor in manager?.handleAppResignActive() }
                    }
                    appDelegate.onBecomeActive = { [weak manager = appState.webManager] in
                        Task { @MainActor in manager?.handleAppBecomeActive() }
                    }
                    appDelegate.onEscapePressed = { [weak state = appState] in
                        guard let state, state.mainPane == .web, state.webManager.isInNoteDetail else {
                            return false
                        }
                        state.webManager.goBackFromNote()
                        return true
                    }
                }
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 1240, height: 820)
        .commands {
            CommandGroup(replacing: .newItem) {}

            CommandMenu("导航") {
                Button("发现首页") { appState.openWebSection(.explore) }
                    .keyboardShortcut("1", modifiers: .command)
                Button("互动通知") { appState.openWebSection(.notifications) }
                    .keyboardShortcut("2", modifiers: .command)
                Button("创作者私信") { appState.openWebSection(.directMessages) }
                    .keyboardShortcut("3", modifiers: .command)
                Button("个人主页") { appState.openProfile() }
                    .keyboardShortcut("4", modifiers: .command)
                Divider()
                Button("返回列表 / 上一页") { appState.webManager.goBackFromNote() }
                    .keyboardShortcut("[", modifiers: .command)
                Button("前进") { appState.webManager.goForward() }
                    .keyboardShortcut("]", modifiers: .command)
                Button("刷新") { appState.webManager.reload() }
                    .keyboardShortcut("r", modifiers: .command)
                Divider()
                Button("展开 / 收起左侧边栏") { appState.sidebarCollapsed.toggle() }
                    .keyboardShortcut("\\", modifiers: .command)
                Button("搜索笔记") {
                    NotificationCenter.default.post(name: .focusSearchField, object: nil)
                }
                .keyboardShortcut("k", modifiers: .command)
                Button("定位评论输入框") { appState.webManager.focusCommentBox() }
                    .keyboardShortcut("j", modifiers: .command)
            }

            CommandMenu("收藏与历史") {
                Button("收藏 / 取消本地收藏当前帖子") {
                    appState.toggleCollectCurrentPage()
                }
                .keyboardShortcut("d", modifiers: .command)

                Button("收藏（小红书云端）") {
                    appState.openCloudCollections()
                }
                .keyboardShortcut("b", modifiers: .command)

                Button("本地收藏夹") {
                    appState.toggleMainPane(.collections)
                }
                .keyboardShortcut("b", modifiers: [.command, .shift])

                Button("浏览历史") {
                    appState.toggleMainPane(.history)
                }
                .keyboardShortcut("y", modifiers: .command)

                Divider()

                Button("导出本地收藏为 Markdown...") {
                    appState.exportCollectionsToMarkdown()
                }
            }

            CommandMenu("内存优化") {
                Button("打开内存监控面板") {
                    appState.toggleMainPane(.memory)
                }
                .keyboardShortcut("m", modifiers: .command)

                Button("轻量释放缓存") {
                    appState.purgeMemory(deepReset: false)
                }
                .keyboardShortcut("k", modifiers: [.command, .shift])

                Button("深度重置网页进程（保留登录）") {
                    appState.purgeMemory(deepReset: true)
                }

                Divider()

                Button("休眠 / 唤醒网页视图") {
                    appState.toggleHibernate()
                }
                .keyboardShortcut("h", modifiers: [.command, .shift])
            }
        }
    }
}
