import RedNoteCore
import SwiftUI

struct ContentView: View {
    @ObservedObject var state: AppState
    @ObservedObject var webManager: WebViewManager
    @FocusState private var searchFocused: Bool
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        HStack(spacing: 0) {
            if !state.sidebarCollapsed {
                frostedSidebar
                    .frame(width: 212)
                    .transition(.move(edge: .leading))
                Divider()
            }

            rightWorkspace
        }
        .ignoresSafeArea(.container, edges: .top)
        .frame(minWidth: 960, minHeight: 650)
        .onAppear {
            webManager.syncSystemAppearance(isDark: colorScheme == .dark)
        }
        .onChange(of: colorScheme) { _, newScheme in
            webManager.syncSystemAppearance(isDark: newScheme == .dark)
        }
        .onReceive(NotificationCenter.default.publisher(for: .focusSearchField)) { _ in
            if state.sidebarCollapsed {
                withAnimation(.easeInOut(duration: 0.18)) {
                    state.sidebarCollapsed = false
                }
            }
            searchFocused = true
        }
        .animation(.easeInOut(duration: 0.18), value: state.sidebarCollapsed)
    }

    // MARK: - macOS Native Frosted Sidebar

    private var frostedSidebar: some View {
        ZStack {
            VisualEffectBackground(material: .sidebar, blendingMode: .behindWindow)

            VStack(alignment: .leading, spacing: 0) {
                // Traffic light safe drag zone
                WindowDragRegion()
                    .frame(height: 36)

                // App Brand Header
                HStack(spacing: 8) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 7, style: .continuous)
                            .fill(
                                LinearGradient(
                                    colors: [xhsRed, Color(red: 0.88, green: 0.08, blue: 0.20)],
                                    startPoint: .top,
                                    endPoint: .bottom
                                )
                            )
                            .frame(width: 24, height: 24)
                        Image(systemName: "bookmark.fill")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(.white)
                    }
                    Text("小红书 Lite")
                        .font(.system(size: 14, weight: .bold))
                    Spacer()
                }
                .padding(.horizontal, 14)
                .padding(.bottom, 10)

                // Native Search Field inside Sidebar
                HStack(spacing: 6) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                    TextField("搜索笔记 (⌘K)", text: $state.searchKeyword)
                        .textFieldStyle(.plain)
                        .font(.system(size: 12.5))
                        .focused($searchFocused)
                        .onSubmit {
                            state.submitSearch()
                        }
                    if !state.searchKeyword.isEmpty {
                        Button {
                            state.searchKeyword = ""
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 9)
                .padding(.vertical, 6)
                .background(Color.primary.opacity(0.07), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                .padding(.horizontal, 12)
                .padding(.bottom, 14)

                // Navigation List
                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 3) {
                        sidebarSectionLabel("内容")

                        sidebarNavRow(
                            title: "发现",
                            icon: "safari.fill",
                            selected: state.mainPane == .web && webManager.activeSection == .explore
                        ) {
                            state.openWebSection(.explore)
                        }

                        sidebarNavRow(
                            title: "互动通知",
                            icon: "bell.fill",
                            selected: state.mainPane == .web && webManager.activeSection == .notifications
                        ) {
                            state.openWebSection(.notifications)
                        }

                        sidebarNavRow(
                            title: "创作者私信",
                            icon: "bubble.left.and.bubble.right.fill",
                            selected: state.mainPane == .web && webManager.activeSection == .directMessages
                        ) {
                            state.openWebSection(.directMessages)
                        }

                        sidebarNavRow(
                            title: "我的主页",
                            icon: "person.crop.circle.fill",
                            selected: state.mainPane == .web && webManager.activeSection == .profile
                        ) {
                            state.openProfile()
                        }

                        sidebarSectionLabel("本地空间")
                            .padding(.top, 14)

                        sidebarNavRow(
                            title: "本地收藏",
                            icon: "star.fill",
                            badge: state.collectionItems.isEmpty ? nil : "\(state.collectionItems.count)",
                            selected: state.mainPane == .collections
                        ) {
                            state.mainPane = .collections
                        }

                        sidebarNavRow(
                            title: "浏览历史",
                            icon: "clock.arrow.circlepath",
                            badge: state.historyItems.isEmpty ? nil : "\(state.historyItems.count)",
                            selected: state.mainPane == .history
                        ) {
                            state.mainPane = .history
                        }
                    }
                    .padding(.horizontal, 10)
                }

                Spacer(minLength: 8)
                Divider().padding(.horizontal, 12)

                // Compact Bottom Memory & Utility Bar
                HStack(spacing: 6) {
                    Button {
                        state.toggleMainPane(.memory)
                    } label: {
                        HStack(spacing: 5) {
                            Circle()
                                .fill(webManager.isHibernated ? Color.green : (state.memorySnapshot.appFootprintMB < 120 ? Color.green : Color.orange))
                                .frame(width: 7, height: 7)
                            Text(webManager.isHibernated ? "休眠中" : String(format: "%.0f MB", state.memorySnapshot.appFootprintMB))
                                .font(.caption.monospacedDigit().weight(.medium))
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 5)
                        .background(
                            state.mainPane == .memory ? xhsRed.opacity(0.16) : Color.primary.opacity(0.07),
                            in: Capsule()
                        )
                        .foregroundStyle(state.mainPane == .memory ? xhsRed : .primary)
                    }
                    .buttonStyle(.plain)
                    .help("内存监控与释放 (⌘M)")

                    Spacer()

                    Button {
                        state.toggleHibernate()
                    } label: {
                        Image(systemName: webManager.isHibernated ? "sun.max.fill" : "moon.zzz")
                            .font(.system(size: 12.5))
                            .foregroundStyle(webManager.isHibernated ? xhsRed : .secondary)
                            .frame(width: 26, height: 26)
                            .background(Color.primary.opacity(0.05), in: Circle())
                    }
                    .buttonStyle(.plain)
                    .help(webManager.isHibernated ? "唤醒网页视图 (⌘⇧H)" : "立即休眠省内存 (⌘⇧H)")

                    Button {
                        state.toggleMainPane(.settings)
                    } label: {
                        Image(systemName: "gearshape")
                            .font(.system(size: 12.5))
                            .foregroundStyle(state.mainPane == .settings ? xhsRed : .secondary)
                            .frame(width: 26, height: 26)
                            .background(
                                state.mainPane == .settings ? xhsRed.opacity(0.14) : Color.primary.opacity(0.05),
                                in: Circle()
                            )
                    }
                    .buttonStyle(.plain)
                    .help("偏好设置")
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
            }
        }
    }

    private func sidebarSectionLabel(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(.secondary.opacity(0.8))
            .padding(.horizontal, 10)
            .padding(.bottom, 4)
    }

    private func sidebarNavRow(
        title: String,
        icon: String,
        badge: String? = nil,
        selected: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 9) {
                Image(systemName: icon)
                    .font(.system(size: 13.5, weight: .medium))
                    .foregroundStyle(selected ? .white : xhsRed.opacity(0.85))
                    .frame(width: 18)
                Text(title)
                    .font(.system(size: 13, weight: selected ? .semibold : .regular))
                    .foregroundStyle(selected ? .white : .primary)
                Spacer()
                if let badge {
                    Text(badge)
                        .font(.caption2.monospacedDigit().weight(.medium))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 1)
                        .background(selected ? Color.white.opacity(0.24) : Color.primary.opacity(0.08), in: Capsule())
                        .foregroundStyle(selected ? .white : .secondary)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(selected ? xhsRed : Color.clear)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: - Right Content Workspace

    private var rightWorkspace: some View {
        VStack(spacing: 0) {
            adaptiveHeaderBar

            // Thin Loading Progress Line
            GeometryReader { geo in
                if state.mainPane == .web && webManager.isLoading && !webManager.isHibernated {
                    Rectangle()
                        .fill(xhsRed)
                        .frame(width: geo.size.width * max(0.06, webManager.estimatedProgress), height: 2)
                        .animation(.easeOut(duration: 0.2), value: webManager.estimatedProgress)
                }
            }
            .frame(height: 2)

            Divider()

            // Optional compact banner for Creator DM
            if state.mainPane == .web && webManager.activeSection == .directMessages && state.showDMBanner {
                HStack(spacing: 8) {
                    Image(systemName: "info.circle.fill")
                        .foregroundStyle(xhsRed)
                    Text("当前为小红书创作服务平台私信入口（与主站共享登录态）。互动评论提醒可在左侧切换「互动通知」。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button {
                        state.showDMBanner = false
                    } label: {
                        Image(systemName: "xmark")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 6)
                .background(xhsRed.opacity(0.06))
                Divider()
            }

            // Main Content Layer (Discover WebView stays mounted & untouched across all sidebar switches)
            ZStack(alignment: .bottom) {
                Group {
                    if webManager.isHibernated {
                        hibernatedView
                    } else {
                        ZStack {
                            WebViewContainer(webView: webManager.exploreWebView)
                                .opacity(webManager.activeSection == .explore ? 1 : 0)
                                .allowsHitTesting(webManager.activeSection == .explore)

                            if let secondary = webManager.secondaryWebView {
                                WebViewContainer(webView: secondary)
                                    .opacity(webManager.activeSection != .explore ? 1 : 0)
                                    .allowsHitTesting(webManager.activeSection != .explore)
                            }
                        }
                    }
                }
                .opacity(state.mainPane == .web ? 1 : 0)
                .allowsHitTesting(state.mainPane == .web)

                // Swipe-Right-to-Go-Back Native Edge Indicator
                if state.mainPane == .web && webManager.swipeBackProgress > 0.03 {
                    swipeBackOverlay
                }

                // Native Full-Pane Views
                switch state.mainPane {
                case .web:
                    EmptyView()
                case .collections:
                    CollectionsPaneView(state: state)
                case .history:
                    HistoryPaneView(state: state)
                case .memory:
                    MemoryPaneView(state: state)
                case .settings:
                    SettingsPaneView(state: state)
                }

                // Floating Toast Pill
                if let toast = webManager.toastMessage {
                    Text(toast)
                        .font(.caption.weight(.medium))
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .background(.ultraThinMaterial, in: Capsule())
                        .overlay(Capsule().strokeBorder(Color.primary.opacity(0.1), lineWidth: 0.5))
                        .shadow(radius: 6, y: 2)
                        .padding(.bottom, 18)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .animation(.easeInOut(duration: 0.18), value: webManager.toastMessage)
        }
        .background(Color(nsColor: .windowBackgroundColor))
    }

    // MARK: - Context-Adaptive Native Top Bar (Zero Browser Clutter!)

    private var adaptiveHeaderBar: some View {
        HStack(spacing: 10) {
            // When sidebar is collapsed, leave clean space for macOS traffic lights
            if state.sidebarCollapsed {
                WindowDragRegion()
                    .frame(width: 66)
            }

            // Sidebar toggle
            Button {
                state.sidebarCollapsed.toggle()
            } label: {
                Image(systemName: "sidebar.left")
                    .font(.system(size: 13.5, weight: .medium))
                    .foregroundStyle(.secondary)
                    .frame(width: 28, height: 26)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("展开 / 收起侧边栏 (⌘\\)")

            if state.mainPane == .web {
                if webManager.isInNoteDetail {
                    noteDetailHeaderContent
                } else if webManager.activeSection == .explore {
                    exploreChannelsHeaderContent
                } else {
                    sectionHeaderContent
                }
            } else {
                nativePaneHeaderContent
            }
        }
        .padding(.horizontal, 12)
        .frame(height: 44)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    @ViewBuilder
    private var noteDetailHeaderContent: some View {
        Button {
            webManager.goBackFromNote()
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "chevron.left")
                    .font(.system(size: 12, weight: .bold))
                Text("返回")
                    .font(.system(size: 12.5, weight: .semibold))
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(Color.primary.opacity(0.08), in: Capsule())
        }
        .buttonStyle(.plain)
        .help("返回列表（支持双指右拉、右侧空白处右键或按 ESC）")

        VStack(alignment: .leading, spacing: 1) {
            Text(webManager.currentSnapshot.title.isEmpty ? webManager.pageTitle : webManager.currentSnapshot.title)
                .font(.system(size: 13, weight: .semibold))
                .lineLimit(1)
            if !webManager.currentSnapshot.author.isEmpty {
                Text("@\(webManager.currentSnapshot.author) · 右拉 / 右键返回")
                    .font(.system(size: 10.5))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .frame(maxWidth: 420, alignment: .leading)

        Spacer(minLength: 8)

        HStack(spacing: 6) {
            Button {
                webManager.focusCommentBox()
            } label: {
                Label("评论", systemImage: "text.bubble")
                    .font(.caption.weight(.medium))
                    .padding(.horizontal, 9)
                    .padding(.vertical, 5)
                    .background(Color.primary.opacity(0.07), in: Capsule())
            }
            .buttonStyle(.plain)
            .help("快速定位评论输入框 (⌘J)")

            Button {
                state.toggleCollectCurrentPage()
            } label: {
                Label(
                    state.isCurrentPageCollected ? "已收藏" : "收藏",
                    systemImage: state.isCurrentPageCollected ? "star.fill" : "star"
                )
                .font(.caption.weight(.medium))
                .padding(.horizontal, 9)
                .padding(.vertical, 5)
                .background(state.isCurrentPageCollected ? xhsRed.opacity(0.15) : Color.primary.opacity(0.07), in: Capsule())
                .foregroundStyle(state.isCurrentPageCollected ? xhsRed : .primary)
            }
            .buttonStyle(.plain)
            .help("同步小红书云端收藏并保存到本地 (⌘D)")

            Button {
                state.copyCurrentURL()
            } label: {
                Image(systemName: "square.and.arrow.up")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                    .frame(width: 28, height: 26)
            }
            .buttonStyle(.plain)
            .help("复制帖子链接")
        }
    }

    @ViewBuilder
    private var exploreChannelsHeaderContent: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(ExploreChannel.allCases) { channel in
                    let active = webManager.activeChannel == channel
                    Button {
                        webManager.selectChannel(channel)
                    } label: {
                        Text(channel.title)
                            .font(.system(size: 12.5, weight: active ? .semibold : .regular))
                            .padding(.horizontal, 11)
                            .padding(.vertical, 5)
                            .background(active ? xhsRed.opacity(0.14) : Color.clear, in: Capsule())
                            .foregroundStyle(active ? xhsRed : .secondary)
                            .contentShape(Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.vertical, 4)
        }

        WindowDragRegion()
            .frame(minWidth: 16, maxWidth: 60)

        Button {
            webManager.reload()
        } label: {
            Image(systemName: "arrow.clockwise")
                .font(.system(size: 12.5))
                .foregroundStyle(.secondary)
                .frame(width: 28, height: 26)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("手动刷新当前页 (⌘R)")
    }

    @ViewBuilder
    private var sectionHeaderContent: some View {
        if webManager.canGoBack {
            Button {
                webManager.goBackFromNote()
            } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 12.5, weight: .semibold))
                    .frame(width: 26, height: 26)
            }
            .buttonStyle(.plain)
        }

        Text(webManager.activeSection.title)
            .font(.system(size: 14, weight: .semibold))

        Spacer()

        if webManager.activeSection == .profile {
            Button {
                state.openCloudCollections()
            } label: {
                Label("云端收藏", systemImage: "icloud")
                    .font(.caption.weight(.medium))
            }
            .buttonStyle(.bordered)
            .controlSize(.small)

            Button {
                state.importVisibleCloudCollections()
            } label: {
                Label("同步本页到本地", systemImage: "arrow.triangle.2.circlepath")
                    .font(.caption.weight(.medium))
            }
            .buttonStyle(.borderedProminent)
            .tint(xhsRed)
            .controlSize(.small)
            .help("把当前页面显示的云端收藏卡片批量导入到本地收藏夹")
        }

        Button {
            webManager.reload()
        } label: {
            Image(systemName: "arrow.clockwise")
                .font(.system(size: 12.5))
                .foregroundStyle(.secondary)
                .frame(width: 26, height: 26)
        }
        .buttonStyle(.plain)
        .help("刷新 (⌘R)")
    }

    @ViewBuilder
    private var nativePaneHeaderContent: some View {
        switch state.mainPane {
        case .collections:
            Text("收藏夹（云端双向同步）")
                .font(.system(size: 14, weight: .semibold))
            Spacer()
            Button {
                state.openCloudCollections()
            } label: {
                Label("查看云端收藏", systemImage: "icloud")
                    .font(.caption.weight(.medium))
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .help("打开小红书账号云端收藏页，支持一键同步到本地")

            Button {
                state.toggleCollectCurrentPage()
            } label: {
                Label("收藏当前帖子", systemImage: "plus")
                    .font(.caption.weight(.medium))
            }
            .buttonStyle(.borderedProminent)
            .tint(xhsRed)
            .controlSize(.small)

            Button {
                state.exportCollectionsToMarkdown()
            } label: {
                Label("导出 Markdown", systemImage: "square.and.arrow.up")
                    .font(.caption)
            }
            .buttonStyle(.bordered)
            .controlSize(.small)

        case .history:
            Text("本地浏览历史")
                .font(.system(size: 14, weight: .semibold))
            Spacer()

        case .memory:
            Text("内存监控与优化")
                .font(.system(size: 14, weight: .semibold))
            Spacer()
            Button {
                state.refreshMemorySnapshot()
            } label: {
                Label("刷新数据", systemImage: "arrow.clockwise")
                    .font(.caption)
            }
            .buttonStyle(.bordered)
            .controlSize(.small)

        case .settings:
            Text("偏好设置")
                .font(.system(size: 14, weight: .semibold))
            Spacer()

        case .web:
            EmptyView()
        }
    }

    // MARK: - Swipe-Right-to-Go-Back Visual Pill

    private var swipeBackOverlay: some View {
        let p = webManager.swipeBackProgress
        let ready = p >= 0.95
        return HStack {
            HStack(spacing: 6) {
                Image(systemName: "chevron.left")
                    .font(.system(size: 13, weight: .bold))
                Text(ready ? "松手返回" : "继续右拉")
                    .font(.system(size: 12, weight: .semibold))
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .foregroundStyle(ready ? .white : .primary)
            .background(
                Capsule()
                    .fill(ready ? AnyShapeStyle(xhsRed) : AnyShapeStyle(.ultraThinMaterial))
            )
            .overlay(
                Capsule().strokeBorder(Color.primary.opacity(ready ? 0 : 0.12), lineWidth: 0.6)
            )
            .shadow(color: .black.opacity(0.16), radius: 10, y: 3)
            .offset(x: -16 + p * 34)
            .opacity(min(1, Double(p) * 1.5))

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .allowsHitTesting(false)
        .animation(.interactiveSpring(response: 0.18, dampingFraction: 0.85), value: p)
    }

    // MARK: - Hibernated Placeholder

    private var hibernatedView: some View {
        VStack(spacing: 16) {
            Image(systemName: "moon.zzz.fill")
                .font(.system(size: 48))
                .foregroundStyle(xhsRed.opacity(0.85))
            Text("小红书 Lite 已休眠省内存")
                .font(.title2.weight(.semibold))
            Text("网页渲染进程已彻底释放，当前主进程仅占约 \(String(format: "%.1f", state.memorySnapshot.appFootprintMB)) MB 内存。您的登录态、本地收藏和浏览历史均已完整保留。")
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 420)
            Button {
                state.toggleHibernate()
            } label: {
                Label("唤醒并恢复上次浏览", systemImage: "sun.max.fill")
                    .padding(.horizontal, 12)
                    .padding(.vertical, 4)
            }
            .buttonStyle(.borderedProminent)
            .tint(xhsRed)
            .controlSize(.large)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(nsColor: .windowBackgroundColor))
    }
}

extension Notification.Name {
    static let focusSearchField = Notification.Name("com.rednotelite.focusSearchField")
}
