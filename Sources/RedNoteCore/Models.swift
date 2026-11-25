import Foundation

public enum ExploreChannel: String, CaseIterable, Identifiable, Sendable {
    case recommend = "homefeed_recommend"
    case shanghai = "topic.shanghai"
    case tech = "topic.tech"
    case digital = "topic.digital"
    case ai = "topic.ai"
    case finance = "topic.finance"
    case parenting = "topic.parenting"
    case fashion = "homefeed.fashion_v3"
    case food = "homefeed.food_v3"
    case cosmetics = "homefeed.cosmetics_v3"
    case movie = "homefeed.movie_and_tv_v3"
    case career = "homefeed.career_v3"
    case love = "homefeed.love_v3"
    case household = "homefeed.household_product_v3"
    case gaming = "homefeed.gaming_v3"
    case travel = "homefeed.travel_v3"
    case fitness = "homefeed.fitness_v3"

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .recommend: return "推荐"
        case .shanghai: return "上海"
        case .tech: return "科技"
        case .digital: return "数码"
        case .ai: return "AI"
        case .finance: return "财经"
        case .parenting: return "育儿"
        case .fashion: return "穿搭"
        case .food: return "美食"
        case .cosmetics: return "彩妆"
        case .movie: return "影视"
        case .career: return "职场"
        case .love: return "情感"
        case .household: return "家居"
        case .gaming: return "游戏"
        case .travel: return "旅行"
        case .fitness: return "健身"
        }
    }

    /// True for custom topic/city channels powered by Xiaohongshu's topic feed search.
    public var isTopicChannel: Bool {
        rawValue.hasPrefix("topic.")
    }

    public var url: URL {
        if isTopicChannel {
            return XHSURLClassifier.searchURL(for: title)
                ?? URL(string: "https://www.xiaohongshu.com/explore")!
        }
        return URL(string: "https://www.xiaohongshu.com/explore?channel_id=\(rawValue)")!
    }
}

public enum NavSection: String, CaseIterable, Identifiable, Sendable {
    case explore
    case notifications
    case directMessages
    case profile
    case creatorCenter

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .explore: return "发现"
        case .notifications: return "互动通知"
        case .directMessages: return "创作者私信"
        case .profile: return "我的主页"
        case .creatorCenter: return "创作中心"
        }
    }

    public var systemImage: String {
        switch self {
        case .explore: return "safari"
        case .notifications: return "bell"
        case .directMessages: return "bubble.left.and.bubble.right"
        case .profile: return "person.crop.circle"
        case .creatorCenter: return "sparkles.rectangle.stack"
        }
    }

    public var targetURL: URL {
        switch self {
        case .explore:
            return URL(string: "https://www.xiaohongshu.com/explore")!
        case .notifications:
            return URL(string: "https://www.xiaohongshu.com/notification")!
        case .directMessages:
            return URL(string: "https://creator.xiaohongshu.com/creator/chat")!
        case .profile:
            return URL(string: "https://www.xiaohongshu.com/explore")!
        case .creatorCenter:
            return URL(string: "https://creator.xiaohongshu.com/new/home")!
        }
    }
}

public enum MainPaneMode: Equatable, Sendable {
    case web
    case collections
    case history
    case memory
    case settings
}

public enum SidebarPanel: String, CaseIterable, Identifiable, Sendable {
    case collections
    case history
    case memory
    case settings

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .collections: return "本地收藏"
        case .history: return "浏览历史"
        case .memory: return "内存优化"
        case .settings: return "设置"
        }
    }

    public var systemImage: String {
        switch self {
        case .collections: return "star"
        case .history: return "clock.arrow.circlepath"
        case .memory: return "memorychip"
        case .settings: return "gearshape"
        }
    }
}

public struct HistoryEntry: Identifiable, Hashable, Codable, Sendable {
    public let id: String
    public let noteId: String?
    public let url: String
    public let title: String
    public let author: String
    public let coverURL: String?
    public let excerpt: String
    public let visitedAt: Date
    public let visitCount: Int

    public init(
        id: String,
        noteId: String?,
        url: String,
        title: String,
        author: String,
        coverURL: String? = nil,
        excerpt: String = "",
        visitedAt: Date = Date(),
        visitCount: Int = 1
    ) {
        self.id = id
        self.noteId = noteId
        self.url = url
        self.title = title
        self.author = author
        self.coverURL = coverURL
        self.excerpt = excerpt
        self.visitedAt = visitedAt
        self.visitCount = visitCount
    }
}

public struct CollectionEntry: Identifiable, Hashable, Codable, Sendable {
    public let id: String
    public let noteId: String?
    public let url: String
    public let title: String
    public let author: String
    public let coverURL: String?
    public let excerpt: String
    public var folder: String
    public var memo: String
    public let createdAt: Date
    public var updatedAt: Date

    public init(
        id: String,
        noteId: String?,
        url: String,
        title: String,
        author: String,
        coverURL: String? = nil,
        excerpt: String = "",
        folder: String = "默认收藏",
        memo: String = "",
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.noteId = noteId
        self.url = url
        self.title = title
        self.author = author
        self.coverURL = coverURL
        self.excerpt = excerpt
        self.folder = folder
        self.memo = memo
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

public struct CurrentPageSnapshot: Equatable, Sendable {
    public let url: String
    public let noteId: String?
    public let title: String
    public let author: String
    public let coverURL: String?
    public let excerpt: String
    public let isNoteDetail: Bool

    public init(
        url: String,
        noteId: String? = nil,
        title: String = "",
        author: String = "",
        coverURL: String? = nil,
        excerpt: String = "",
        isNoteDetail: Bool = false
    ) {
        self.url = url
        self.noteId = noteId
        self.title = title
        self.author = author
        self.coverURL = coverURL
        self.excerpt = excerpt
        self.isNoteDetail = isNoteDetail
    }
}

public struct MemorySnapshot: Equatable, Sendable {
    public let appFootprintMB: Double
    public let webContentFootprintMB: Double
    public let webProcessCount: Int
    public let isHibernated: Bool
    public let timestamp: Date

    public var totalFootprintMB: Double {
        appFootprintMB + webContentFootprintMB
    }

    public init(
        appFootprintMB: Double = 0,
        webContentFootprintMB: Double = 0,
        webProcessCount: Int = 0,
        isHibernated: Bool = false,
        timestamp: Date = Date()
    ) {
        self.appFootprintMB = appFootprintMB
        self.webContentFootprintMB = webContentFootprintMB
        self.webProcessCount = webProcessCount
        self.isHibernated = isHibernated
        self.timestamp = timestamp
    }
}

public struct AppPreferences: Equatable, Codable, Sendable {
    public var ecoModeEnabled: Bool
    public var cleanModeEnabled: Bool
    public var autoPauseMediaInBackground: Bool
    public var blockAutoplayVideo: Bool
    public var recordHistoryEnabled: Bool
    public var autoHibernateMinutes: Int
    public var maxHistoryItems: Int

    public init(
        ecoModeEnabled: Bool = true,
        cleanModeEnabled: Bool = true,
        autoPauseMediaInBackground: Bool = true,
        blockAutoplayVideo: Bool = true,
        recordHistoryEnabled: Bool = true,
        autoHibernateMinutes: Int = 0,
        maxHistoryItems: Int = 500
    ) {
        self.ecoModeEnabled = ecoModeEnabled
        self.cleanModeEnabled = cleanModeEnabled
        self.autoPauseMediaInBackground = autoPauseMediaInBackground
        self.blockAutoplayVideo = blockAutoplayVideo
        self.recordHistoryEnabled = recordHistoryEnabled
        self.autoHibernateMinutes = autoHibernateMinutes
        self.maxHistoryItems = maxHistoryItems
    }
}
