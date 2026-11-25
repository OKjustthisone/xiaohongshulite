import RedNoteCore
import SwiftUI

let xhsRed = Color(red: 1.0, green: 0.141, blue: 0.259) // #FF2442

// MARK: - Full-Pane Native Collections View (Card Grid)

struct CollectionsPaneView: View {
    @ObservedObject var state: AppState
    @State private var editingEntry: CollectionEntry?
    @State private var editFolder: String = ""
    @State private var editMemo: String = ""

    private let columns = [
        GridItem(.adaptive(minimum: 230, maximum: 300), spacing: 14)
    ]

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        folderChip("全部")
                        ForEach(state.folders, id: \.self) { folder in
                            folderChip(folder)
                        }
                    }
                }

                Spacer(minLength: 8)

                HStack(spacing: 6) {
                    Image(systemName: "magnifyingglass")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    TextField("筛选收藏...", text: $state.collectionQuery)
                        .textFieldStyle(.plain)
                        .font(.callout)
                    if !state.collectionQuery.isEmpty {
                        Button { state.collectionQuery = "" } label: {
                            Image(systemName: "xmark.circle.fill")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .frame(width: 200)
                .background(Color.secondary.opacity(0.1), in: Capsule())
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 10)

            Divider()

            if state.collectionItems.isEmpty {
                emptyPaneState(
                    icon: "star.slash",
                    title: "暂无本地收藏",
                    subtitle: "浏览任意小红书帖子时按 ⌘D 或点击顶栏星标，即可保存到本地离线索引并按分类整理。"
                )
            } else {
                ScrollView {
                    LazyVGrid(columns: columns, spacing: 14) {
                        ForEach(state.collectionItems) { entry in
                            CollectionCard(
                                entry: entry,
                                onOpen: { state.openNoteURL(entry.url) },
                                onEdit: {
                                    editingEntry = entry
                                    editFolder = entry.folder
                                    editMemo = entry.memo
                                },
                                onDelete: { state.deleteCollection(entry) }
                            )
                        }
                    }
                    .padding(20)
                }
            }
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .sheet(item: $editingEntry) { entry in
            VStack(alignment: .leading, spacing: 12) {
                Text("编辑收藏信息")
                    .font(.headline)
                Text(entry.title)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)

                VStack(alignment: .leading, spacing: 4) {
                    Text("分类文件夹").font(.caption).foregroundStyle(.secondary)
                    TextField("例如：旅行、穿搭、美食", text: $editFolder)
                        .textFieldStyle(.roundedBorder)
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text("个人备注").font(.caption).foregroundStyle(.secondary)
                    TextField("添加笔记备注...", text: $editMemo)
                        .textFieldStyle(.roundedBorder)
                }

                HStack {
                    Spacer()
                    Button("取消") { editingEntry = nil }
                    Button("保存") {
                        state.updateCollection(entry, folder: editFolder, memo: editMemo)
                        editingEntry = nil
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(xhsRed)
                }
            }
            .padding(18)
            .frame(width: 340)
        }
    }

    private func folderChip(_ name: String) -> some View {
        let selected = state.selectedFolder == name
        return Button {
            state.selectedFolder = name
        } label: {
            Text(name)
                .font(.caption.weight(.medium))
                .padding(.horizontal, 11)
                .padding(.vertical, 5)
                .background(selected ? xhsRed : Color.secondary.opacity(0.1), in: Capsule())
                .foregroundStyle(selected ? .white : .primary)
        }
        .buttonStyle(.plain)
    }
}

private struct CollectionCard: View {
    let entry: CollectionEntry
    let onOpen: () -> Void
    let onEdit: () -> Void
    let onDelete: () -> Void
    @State private var isHovered = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 10) {
                AsyncThumbnailView(urlString: entry.coverURL, width: 64, height: 64, cornerRadius: 10)

                VStack(alignment: .leading, spacing: 4) {
                    Text(entry.title)
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(2)
                        .foregroundStyle(.primary)

                    if !entry.author.isEmpty {
                        Text("@\(entry.author)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }

                    Text(entry.folder)
                        .font(.caption2.weight(.medium))
                        .padding(.horizontal, 7)
                        .padding(.vertical, 2)
                        .background(xhsRed.opacity(0.12), in: Capsule())
                        .foregroundStyle(xhsRed)
                }
                Spacer(minLength: 0)
            }

            if !entry.memo.isEmpty {
                Text(entry.memo)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 5)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.secondary.opacity(0.07), in: RoundedRectangle(cornerRadius: 6))
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color(nsColor: .controlBackgroundColor))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(isHovered ? xhsRed.opacity(0.45) : Color.primary.opacity(0.08), lineWidth: 1)
        )
        .shadow(color: .black.opacity(isHovered ? 0.08 : 0.03), radius: isHovered ? 8 : 3, y: 2)
        .contentShape(Rectangle())
        .onHover { isHovered = $0 }
        .onTapGesture { onOpen() }
        .contextMenu {
            Button("全屏打开笔记", action: onOpen)
            Button("编辑分类与备注", action: onEdit)
            Button("复制链接") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(entry.url, forType: .string)
            }
            Divider()
            Button("删除收藏", role: .destructive, action: onDelete)
        }
    }
}

// MARK: - Full-Pane Native History View

struct HistoryPaneView: View {
    @ObservedObject var state: AppState
    @State private var confirmClear = false

    private var groupedHistory: [(String, [HistoryEntry])] {
        let cal = Calendar.current
        let now = Date()
        var buckets: [(String, [HistoryEntry])] = [
            ("今天", []),
            ("昨天", []),
            ("本周", []),
            ("更早", [])
        ]
        for item in state.historyItems {
            if cal.isDateInToday(item.visitedAt) {
                buckets[0].1.append(item)
            } else if cal.isDateInYesterday(item.visitedAt) {
                buckets[1].1.append(item)
            } else if let days = cal.dateComponents([.day], from: item.visitedAt, to: now).day, days < 7 {
                buckets[2].1.append(item)
            } else {
                buckets[3].1.append(item)
            }
        }
        return buckets.filter { !$0.1.isEmpty }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                HStack(spacing: 6) {
                    Image(systemName: "magnifyingglass")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    TextField("搜索浏览历史标题或作者...", text: $state.historyQuery)
                        .textFieldStyle(.plain)
                        .font(.callout)
                    if !state.historyQuery.isEmpty {
                        Button { state.historyQuery = "" } label: {
                            Image(systemName: "xmark.circle.fill")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .frame(maxWidth: 320)
                .background(Color.secondary.opacity(0.1), in: Capsule())

                Spacer()

                Text("共 \(state.historyItems.count) 条记录")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Button("清空历史") {
                    confirmClear = true
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .disabled(state.historyItems.isEmpty)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 10)

            Divider()

            if state.historyItems.isEmpty {
                emptyPaneState(
                    icon: "clock",
                    title: "暂无浏览历史",
                    subtitle: "打开任意小红书帖子、博主主页或搜索结果后，会自动静默记录到这里。"
                )
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 18) {
                        ForEach(groupedHistory, id: \.0) { sectionTitle, items in
                            VStack(alignment: .leading, spacing: 8) {
                                Text(sectionTitle)
                                    .font(.headline)
                                    .foregroundStyle(.secondary)
                                    .padding(.horizontal, 4)

                                VStack(spacing: 1) {
                                    ForEach(items) { entry in
                                        HistoryRow(
                                            entry: entry,
                                            onOpen: { state.openNoteURL(entry.url) },
                                            onCollect: { state.collectHistoryEntry(entry) },
                                            onDelete: { state.deleteHistory(entry) }
                                        )
                                    }
                                }
                                .background(
                                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                                        .fill(Color(nsColor: .controlBackgroundColor))
                                )
                                .overlay(
                                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                                        .strokeBorder(Color.primary.opacity(0.07), lineWidth: 1)
                                )
                            }
                        }
                    }
                    .padding(20)
                    .frame(maxWidth: 820)
                    .frame(maxWidth: .infinity)
                }
            }
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .confirmationDialog("确定清空所有本地浏览历史？", isPresented: $confirmClear) {
            Button("清空历史记录", role: .destructive) {
                state.clearAllHistory()
            }
            Button("取消", role: .cancel) {}
        }
    }
}

private struct HistoryRow: View {
    let entry: HistoryEntry
    let onOpen: () -> Void
    let onCollect: () -> Void
    let onDelete: () -> Void
    @State private var isHovered = false

    private static let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "MM-dd HH:mm"
        return f
    }()

    var body: some View {
        HStack(spacing: 12) {
            AsyncThumbnailView(urlString: entry.coverURL, width: 48, height: 48, cornerRadius: 8)

            VStack(alignment: .leading, spacing: 3) {
                Text(entry.title)
                    .font(.subheadline.weight(.medium))
                    .lineLimit(1)

                HStack(spacing: 8) {
                    if !entry.author.isEmpty {
                        Text("@\(entry.author)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Text(Self.timeFormatter.string(from: entry.visitedAt))
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                    if entry.visitCount > 1 {
                        Text("浏览 \(entry.visitCount) 次")
                            .font(.caption2)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 1)
                            .background(Color.secondary.opacity(0.1), in: Capsule())
                            .foregroundStyle(.secondary)
                    }
                }
            }

            Spacer()

            HStack(spacing: 8) {
                Button(action: onCollect) {
                    Image(systemName: "star")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help("加入本地收藏夹")

                Button(action: onDelete) {
                    Image(systemName: "trash")
                        .font(.caption)
                        .foregroundStyle(.secondary.opacity(0.75))
                }
                .buttonStyle(.plain)
                .help("删除此条历史")
            }
            .opacity(isHovered ? 1 : 0.4)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .background(isHovered ? Color.primary.opacity(0.04) : Color.clear)
        .contentShape(Rectangle())
        .onHover { isHovered = $0 }
        .onTapGesture { onOpen() }
        .contextMenu {
            Button("全屏打开笔记", action: onOpen)
            Button("加入本地收藏", action: onCollect)
            Button("复制链接") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(entry.url, forType: .string)
            }
            Divider()
            Button("删除记录", role: .destructive, action: onDelete)
        }
    }
}

// MARK: - Full-Pane Native Memory Optimizer View

struct MemoryPaneView: View {
    @ObservedObject var state: AppState

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                HStack(spacing: 20) {
                    VStack(alignment: .leading, spacing: 6) {
                        HStack(spacing: 8) {
                            Text("原生主进程物理内存")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                            Text(state.webManager.isHibernated ? "休眠省内存中" : "轻量运行中")
                                .font(.caption2.weight(.semibold))
                                .padding(.horizontal, 8)
                                .padding(.vertical, 2)
                                .background(
                                    (state.webManager.isHibernated ? Color.green : xhsRed).opacity(0.15),
                                    in: Capsule()
                                )
                                .foregroundStyle(state.webManager.isHibernated ? .green : xhsRed)
                        }

                        HStack(alignment: .firstTextBaseline, spacing: 5) {
                            Text(String(format: "%.1f", state.memorySnapshot.appFootprintMB))
                                .font(.system(size: 40, weight: .bold, design: .rounded))
                            Text("MB")
                                .font(.title3)
                                .foregroundStyle(.secondary)
                        }

                        Text("全局仅保留 1 个 WebKit 渲染实例；休眠时彻底销毁渲染进程并保留登录态。")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    VStack(spacing: 8) {
                        Button {
                            state.purgeMemory(deepReset: false)
                        } label: {
                            Label("轻量释放缓存", systemImage: "sparkles")
                                .frame(width: 170)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(xhsRed)

                        Button {
                            state.purgeMemory(deepReset: true)
                        } label: {
                            Label("深度重置渲染进程", systemImage: "arrow.triangle.2.circlepath")
                                .frame(width: 170)
                        }
                        .buttonStyle(.bordered)

                        Button {
                            state.toggleHibernate()
                        } label: {
                            Label(
                                state.webManager.isHibernated ? "唤醒页面" : "立即休眠省内存",
                                systemImage: state.webManager.isHibernated ? "sun.max" : "moon.zzz"
                            )
                            .frame(width: 170)
                        }
                        .buttonStyle(.bordered)
                    }
                }
                .padding(20)
                .background(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(Color(nsColor: .controlBackgroundColor))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .strokeBorder(Color.primary.opacity(0.08), lineWidth: 1)
                )

                VStack(alignment: .leading, spacing: 14) {
                    Text("自动省内存策略")
                        .font(.headline)

                    Toggle("省内存渲染模式（离屏瀑布流卡片自动跳过重绘）", isOn: $state.preferences.ecoModeEnabled)
                    Toggle("禁止视频自动预加载与自动播放", isOn: $state.preferences.blockAutoplayVideo)
                    Toggle("应用切到后台时自动暂停音视频", isOn: $state.preferences.autoPauseMediaInBackground)

                    HStack {
                        Text("后台空闲自动休眠")
                        Spacer()
                        Picker("", selection: $state.preferences.autoHibernateMinutes) {
                            Text("关闭").tag(0)
                            Text("3 分钟").tag(3)
                            Text("5 分钟").tag(5)
                            Text("15 分钟").tag(15)
                        }
                        .labelsHidden()
                        .frame(width: 110)
                    }
                }
                .padding(20)
                .background(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(Color(nsColor: .controlBackgroundColor))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .strokeBorder(Color.primary.opacity(0.08), lineWidth: 1)
                )
            }
            .padding(24)
            .frame(maxWidth: 720)
            .frame(maxWidth: .infinity)
        }
        .background(Color(nsColor: .windowBackgroundColor))
    }
}

// MARK: - Full-Pane Native Settings View

struct SettingsPaneView: View {
    @ObservedObject var state: AppState

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                settingsCard(title: "阅读与界面") {
                    Toggle("清爽模式（隐藏下载 App 等浮窗干扰）", isOn: $state.preferences.cleanModeEnabled)
                    Toggle("自动静默记录本地浏览历史", isOn: $state.preferences.recordHistoryEnabled)

                    HStack {
                        Text("本地历史保留上限")
                        Spacer()
                        Picker("", selection: $state.preferences.maxHistoryItems) {
                            Text("200 条").tag(200)
                            Text("500 条").tag(500)
                            Text("1000 条").tag(1000)
                        }
                        .labelsHidden()
                        .frame(width: 110)
                    }
                }

                settingsCard(title: "全屏帖子与手势说明") {
                    Text("• 点击任意帖子自动全屏展开正文与评论（无浮窗遮罩）。\n• 触控板双指右滑、鼠标从左侧边缘右拉、点击顶部「‹ 返回」或按 ESC 键，均可即时返回信息流原位置。\n• 自动跟随 macOS 系统浅色 / 深色外观切换。")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                settingsCard(title: "私信与消息说明") {
                    Text("• 「互动通知」直达评论、点赞、收藏与 @ 提醒。\n• 「创作者私信」直达小红书创作服务平台私信页面，与主站共享登录态；普通账号若未开放网页私信属小红书官方网页限制。")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                settingsCard(title: "键盘快捷键") {
                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], alignment: .leading, spacing: 8) {
                        shortcutRow("⌘K", "搜索笔记")
                        shortcutRow("⌘D", "本地收藏当前帖子")
                        shortcutRow("⌘J", "聚焦评论输入框")
                        shortcutRow("ESC / ⌘[", "返回信息流")
                        shortcutRow("⌘\\", "折叠 / 展开左侧边栏")
                        shortcutRow("⌘B / ⌘Y", "打开本地收藏 / 历史")
                        shortcutRow("⌘⇧K", "一键释放内存缓存")
                        shortcutRow("⌘⇧H", "立即休眠 / 唤醒")
                    }
                }

                settingsCard(title: "本地数据库") {
                    HStack {
                        Text("SQLite 本地存储您的收藏与历史元数据，页缓存上限 1 MB。")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Button("在访达中打开") {
                            state.openDataDirectoryInFinder()
                        }
                        .buttonStyle(.bordered)
                    }
                }
            }
            .padding(24)
            .frame(maxWidth: 720)
            .frame(maxWidth: .infinity)
        }
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private func settingsCard<Content: View>(title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.headline)
            content()
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color(nsColor: .controlBackgroundColor))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.08), lineWidth: 1)
        )
    }

    private func shortcutRow(_ key: String, _ desc: String) -> some View {
        HStack(spacing: 8) {
            Text(key)
                .font(.caption.monospaced().weight(.medium))
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(Color.secondary.opacity(0.14), in: RoundedRectangle(cornerRadius: 5))
            Text(desc)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}

private func emptyPaneState(icon: String, title: String, subtitle: String) -> some View {
    VStack(spacing: 12) {
        Spacer()
        Image(systemName: icon)
            .font(.system(size: 38))
            .foregroundStyle(.secondary.opacity(0.5))
        Text(title)
            .font(.title3.weight(.semibold))
        Text(subtitle)
            .font(.callout)
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.center)
            .frame(maxWidth: 360)
        Spacer()
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
}
