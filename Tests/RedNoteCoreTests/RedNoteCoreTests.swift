import Foundation
import Testing
@testable import RedNoteCore

@Suite("RedNoteCore Tests")
struct RedNoteCoreTests {
    @Test("URL classifier extracts note ID and deduplicates canonical keys")
    func urlClassifierExtractsNoteIdAndCanonicalKey() {
        let url1 = "https://www.xiaohongshu.com/explore/65a1b2c3d4e5f60718293a4b?xsec_token=abc&source=web"
        let url2 = "https://www.xiaohongshu.com/discovery/item/65a1b2c3d4e5f60718293a4b"

        #expect(XHSURLClassifier.extractNoteId(from: url1) == "65a1b2c3d4e5f60718293a4b")
        #expect(XHSURLClassifier.extractNoteId(from: url2) == "65a1b2c3d4e5f60718293a4b")
        #expect(XHSURLClassifier.canonicalKey(for: url1) == XHSURLClassifier.canonicalKey(for: url2))
        #expect(XHSURLClassifier.shouldAutoRecordHistory(urlString: url1))
        #expect(!XHSURLClassifier.shouldAutoRecordHistory(urlString: "https://www.xiaohongshu.com/explore"))
    }

    @Test("URL classifier validates Xiaohongshu domains and infers navigation sections")
    func urlClassifierDomainAndSectionInference() {
        #expect(XHSURLClassifier.isAllowedInApp(URL(string: "https://www.xiaohongshu.com/explore")!))
        #expect(XHSURLClassifier.isAllowedInApp(URL(string: "https://creator.xiaohongshu.com/creator/chat")!))
        #expect(!XHSURLClassifier.isAllowedInApp(URL(string: "https://example.com/test")!))

        #expect(XHSURLClassifier.inferredSection(for: "https://creator.xiaohongshu.com/creator/chat") == .directMessages)
        #expect(XHSURLClassifier.inferredSection(for: "https://www.xiaohongshu.com/notification") == .notifications)
        #expect(XHSURLClassifier.inferredSection(for: "https://www.xiaohongshu.com/explore") == .explore)
    }

    @Test("Search URL builder encodes keywords and ignores blank queries")
    func searchURLBuilder() {
        let url = XHSURLClassifier.searchURL(for: "京都 咖啡")
        #expect(url != nil)
        #expect(url?.absoluteString.contains("search_result") == true)
        #expect(XHSURLClassifier.searchURL(for: "   ") == nil)
    }

    @Test("SQLite history upserts, increments visit count, searches, and prunes oldest rows")
    func databaseHistoryUpsertSearchAndPrune() throws {
        let db = try DatabaseStore(path: ":memory:")
        let t1 = Date(timeIntervalSince1970: 1_700_000_100)
        let t2 = Date(timeIntervalSince1970: 1_700_000_200)
        let t3 = Date(timeIntervalSince1970: 1_700_000_300)

        try db.recordHistory(
            url: "https://www.xiaohongshu.com/explore/aaaaaaaaaaaaaaaaaaaaaaaa",
            title: "东京探店攻略",
            author: "旅行家",
            visitedAt: t1,
            maxItems: 2
        )
        try db.recordHistory(
            url: "https://www.xiaohongshu.com/explore/aaaaaaaaaaaaaaaaaaaaaaaa?xsec_token=new",
            title: "东京探店攻略（更新）",
            author: "旅行家",
            visitedAt: t2,
            maxItems: 2
        )
        var all = try db.fetchHistory()
        #expect(all.count == 1)
        #expect(all.first?.visitCount == 2)
        #expect(all.first?.title == "东京探店攻略（更新）")

        try db.recordHistory(
            url: "https://www.xiaohongshu.com/explore/bbbbbbbbbbbbbbbbbbbbbbbb",
            title: "手冲咖啡技巧",
            author: "咖啡师",
            isVideo: true,
            visitedAt: t3,
            maxItems: 2
        )
        try db.recordHistory(
            url: "https://www.xiaohongshu.com/explore/cccccccccccccccccccccccc",
            title: "极简桌面改造",
            author: "效率控",
            isVideo: false,
            visitedAt: t3.addingTimeInterval(50),
            maxItems: 2
        )
        all = try db.fetchHistory()
        #expect(all.count == 2)
        #expect(all.first?.title == "极简桌面改造")
        #expect(all.first?.isVideo == false)

        let filtered = try db.fetchHistory(query: "咖啡")
        #expect(filtered.count == 1)
        #expect(filtered.first?.author == "咖啡师")
        #expect(filtered.first?.isVideo == true)

        try db.clearHistory()
        #expect(try db.fetchHistory().isEmpty)
    }

    @Test("SQLite collections manage folders, memos, search, and Markdown export")
    func databaseCollectionsFoldersMemoAndMarkdownExport() throws {
        let db = try DatabaseStore(path: ":memory:")
        let noteURL = "https://www.xiaohongshu.com/explore/111111111111111111111111"

        #expect(!db.isCollected(urlString: noteURL))
        let saved = try db.upsertCollection(
            url: noteURL,
            title: "macOS 低内存优化实践",
            author: "开发日记",
            folder: "技术",
            memo: "周末参考"
        )
        #expect(db.isCollected(urlString: noteURL))

        try db.updateCollection(id: saved.id, folder: "开发", memo: "重点必看")
        let folders = try db.fetchFolders()
        #expect(folders.contains("开发"))

        let results = try db.fetchCollections(folder: "开发", query: "必看")
        #expect(results.count == 1)
        #expect(results.first?.memo == "重点必看")

        let markdown = try db.exportCollectionsMarkdown()
        #expect(markdown.contains("## 开发"))
        #expect(markdown.contains("macOS 低内存优化实践"))
        #expect(markdown.contains("重点必看"))

        try db.deleteCollection(id: saved.id)
        #expect(!db.isCollected(urlString: noteURL))
    }

    @Test("Explore channels include custom topics and valid HTTPS trailing-slash search URLs")
    func exploreChannelsIncludeCustomTopics() {
        let customChannels: [ExploreChannel] = [.shanghai, .tech, .digital, .ai, .finance, .parenting]
        for channel in customChannels {
            #expect(channel.isTopicChannel)
            #expect(channel.url.absoluteString.contains("/search_result/?"))
            #expect(channel.url.absoluteString.contains("type=51"))
        }
        #expect(!ExploreChannel.recommend.isTopicChannel)
        #expect(ExploreChannel.recommend.url.absoluteString.contains("channel_id=homefeed_recommend"))
        #expect(AppPreferences().autoHibernateMinutes == 0)
    }

    @Test("Memory profiler reports positive physical footprint")
    func memoryProfilerReturnsPositiveFootprint() {
        let footprint = MemoryProfiler.currentProcessFootprintMB()
        #expect(footprint > 0.1)
    }
}
