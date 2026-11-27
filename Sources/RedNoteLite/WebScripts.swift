import Foundation

enum WebScripts {
    /// Early style injection at document start so users never see a flash of the redundant
    /// web header, web sidebar, or dimmed floating note modal popup.
    static let earlyStyleScript: String = #"""
    (function() {
        if (window.location.hostname !== "www.xiaohongshu.com") return;

        const headTarget = document.head || document.documentElement;
        ["https://edith.xiaohongshu.com", "https://so.xiaohongshu.com", "https://fe-static.xhscdn.com", "https://sns-webpic-qc.xhscdn.com"].forEach((origin) => {
            const link = document.createElement("link");
            link.rel = "preconnect";
            link.href = origin;
            link.crossOrigin = "anonymous";
            headTarget.appendChild(link);
        });

        // Early first-paint detector running at document-start so launch skeleton hides the exact moment cards paint
        (function watchEarlyFirstPaint() {
            let sent = false;
            let tries = 0;
            const timer = setInterval(() => {
                tries++;
                const card = document.querySelector("section.note-item, #noteContainer, .notification-page, .user-page");
                if (card) {
                    const rect = card.getBoundingClientRect();
                    if (rect.width > 0 && rect.height > 0) {
                        sent = true;
                        clearInterval(timer);
                        try {
                            window.webkit?.messageHandlers?.rednoteBridge?.postMessage({ type: "firstPaintReady" });
                        } catch (_) {}
                        return;
                    }
                }
                if (sent || tries >= 80) clearInterval(timer);
            }, 40);
        })();

        const style = document.createElement("style");
        style.id = "__rednote_native_shell_css";
        style.textContent = `
            :root {
                --rn-page-bg: #ffffff;
                --rn-surface-bg: #f7f7f8;
                --rn-scrollbar: rgba(128, 128, 128, 0.35);
            }
            html[data-rn-dark="true"] {
                --rn-page-bg: #1c1c1e;
                --rn-surface-bg: #252528;
                --rn-scrollbar: rgba(255, 255, 255, 0.25);
            }

            html, body {
                -webkit-font-smoothing: antialiased;
                overscroll-behavior-x: none;
            }

            /* 1. Keep web header & sidebar mounted offscreen (instead of display:none) so Vue's
                  #search-input and /explore SPA router links stay instant-clickable for 0-reload tag switches! */
            #header-container,
            .header-container,
            header.mask-paper,
            .mask-paper,
            .side-bar,
            #side-bar,
            .sidebar-container {
                position: fixed !important;
                top: -9999px !important;
                left: -9999px !important;
                width: 1px !important;
                height: 1px !important;
                min-height: 0 !important;
                max-height: 1px !important;
                overflow: hidden !important;
                opacity: 0 !important;
                pointer-events: none !important;
                margin: 0 !important;
                padding: 0 !important;
                border: none !important;
            }

            /* Keep channel container in DOM on Explore only (so native pills can click it) */
            .feeds-page .channel-container,
            .feeds-page .channel-scroll-container {
                height: 0 !important;
                min-height: 0 !important;
                max-height: 0 !important;
                margin: 0 !important;
                padding: 0 !important;
                overflow: hidden !important;
                opacity: 0 !important;
                pointer-events: none !important;
                border: none !important;
            }

            /* Expand main content full-bleed into our native right pane */
            .main-container,
            .main-container.with-side-bar,
            .with-side-bar,
            .outer-link-container {
                padding-left: 0 !important;
                margin-left: 0 !important;
                padding-top: 0 !important;
                margin-top: 0 !important;
                width: 100% !important;
                max-width: 100% !important;
            }
            .feeds-page {
                padding-top: 12px !important;
                padding-left: 18px !important;
                padding-right: 18px !important;
            }
            .feeds-page:has(.search-layout) {
                padding-top: 0 !important;
                padding-left: 0 !important;
                padding-right: 0 !important;
                overflow: visible !important;
            }
            .user-page,
            .notification-page {
                padding-top: 12px !important;
                margin-top: 0 !important;
            }

            /* Neutralize Xiaohongshu's .reds-sticky-box fixed top:72px/144px behavior that floats over images */
            .search-layout .reds-sticky-box,
            .search-layout .reds-sticky-box.sticky,
            .search-layout .reds-sticky,
            .search-layout .reds-sticky-box.sticky .reds-sticky {
                position: static !important;
                top: auto !important;
                left: auto !important;
                right: auto !important;
                width: 100% !important;
                height: auto !important;
                min-height: 0 !important;
                margin: 0 !important;
                padding: 0 !important;
                transform: none !important;
                z-index: auto !important;
                background: transparent !important;
                box-shadow: none !important;
            }

            /* Topic / search pages: pin sub-tag bar (.search-layout__middle) + 筛选 (.search-layout__top)
               flush at top: 0 (directly beneath our native channel bar) with ZERO blank gap */
            .search-layout {
                display: grid !important;
                grid-template-columns: minmax(0, 1fr) auto !important;
                grid-template-rows: auto auto !important;
                align-items: stretch !important;
                column-gap: 0 !important;
                row-gap: 8px !important;
                padding-top: 0 !important;
                margin-top: 0 !important;
                padding-left: 18px !important;
                padding-right: 18px !important;
                overflow: visible !important;
            }
            .search-layout > .search-layout__middle {
                grid-column: 1 !important;
                grid-row: 1 !important;
                position: sticky !important;
                top: 0 !important;
                z-index: 40 !important;
                min-width: 0 !important;
                width: 100% !important;
                margin: 0 !important;
                padding: 7px 12px 7px 0 !important;
                background: var(--color-background, var(--rn-page-bg)) !important;
                border-bottom: 1px solid rgba(128, 128, 128, 0.12) !important;
                display: flex !important;
                align-items: center !important;
            }
            .search-layout > .search-layout__middle > * {
                margin-top: 0 !important;
                margin-bottom: 0 !important;
                padding-top: 0 !important;
                padding-bottom: 0 !important;
                min-width: 0 !important;
                max-width: 100% !important;
            }
            .search-layout > .search-layout__middle > .divider {
                display: none !important;
            }
            .search-layout > .search-layout__top {
                grid-column: 2 !important;
                grid-row: 1 !important;
                position: sticky !important;
                top: 0 !important;
                z-index: 50 !important;
                width: auto !important;
                min-width: fit-content !important;
                height: auto !important;
                min-height: 0 !important;
                margin: 0 !important;
                padding: 7px 0 7px 8px !important;
                background: var(--color-background, var(--rn-page-bg)) !important;
                border-bottom: 1px solid rgba(128, 128, 128, 0.12) !important;
                overflow: visible !important;
                display: flex !important;
                align-items: center !important;
                justify-content: flex-end !important;
            }
            .search-layout > .search-layout__top .channel-scroll-container {
                display: none !important;
            }
            .search-layout > .search-layout__main {
                grid-column: 1 / -1 !important;
                grid-row: 2 !important;
                width: 100% !important;
                margin-top: 0 !important;
                padding-top: 2px !important;
            }

            /* 2. Full-page immersive note view (NO floating modal popup or dark dimmed backdrop!) */
            @keyframes rnSlideIn {
                from { opacity: 0.92; transform: translateX(18px); }
                to   { opacity: 1; transform: translateX(0); }
            }

            .note-detail-mask {
                position: fixed !important;
                inset: 0 !important;
                top: 0 !important;
                left: 0 !important;
                right: 0 !important;
                bottom: 0 !important;
                width: 100vw !important;
                height: 100vh !important;
                padding: 0 !important;
                margin: 0 !important;
                background: var(--rn-page-bg) !important;
                backdrop-filter: none !important;
                -webkit-backdrop-filter: none !important;
                display: block !important;
                z-index: 90 !important;
                animation: rnSlideIn 0.16s cubic-bezier(0.2, 0.8, 0.2, 1) !important;
            }

            .note-detail-mask #noteContainer,
            .note-detail-mask .note-container {
                position: fixed !important;
                inset: 0 !important;
                top: 0 !important;
                left: 0 !important;
                width: 100vw !important;
                height: 100vh !important;
                max-width: 100vw !important;
                max-height: 100vh !important;
                min-height: 100vh !important;
                border-radius: 0 !important;
                border: none !important;
                box-shadow: none !important;
                margin: 0 !important;
                transform: none !important;
            }

            /* Standalone /explore/<id> or /discovery/item/<id> note page also full-bleed */
            .note-detail-page,
            .note-detail-page #noteContainer,
            .note-detail-page .note-container {
                width: 100% !important;
                max-width: 100% !important;
                height: 100vh !important;
                max-height: 100vh !important;
                border-radius: 0 !important;
                border: none !important;
                box-shadow: none !important;
                margin: 0 !important;
                padding: 0 !important;
            }

            /* Hide floating web modal close X (replaced by native Back button, Swipe-Right, and ESC) */
            .note-detail-mask > .close-circle,
            .note-detail-mask > .close-box,
            .note-detail-mask .close-circle {
                opacity: 0 !important;
                pointer-events: none !important;
            }

            /* Ensure media container fills height smoothly in full-page mode */
            #noteContainer .media-container {
                height: 100vh !important;
                max-height: 100vh !important;
                flex: 1 1 56% !important;
            }
            #noteContainer .interaction-container {
                height: 100vh !important;
                max-height: 100vh !important;
                width: clamp(360px, 38vw, 520px) !important;
                flex: 0 0 auto !important;
            }

            /* Hide non-essential download-app floating widgets */
            .floating-btn-sets .download-btn,
            .download-app-banner,
            .open-app-banner,
            [class*="download-guide"],
            [class*="app-download-bar"] {
                display: none !important;
            }

            /* Native-feeling subtle scrollbars */
            ::-webkit-scrollbar {
                width: 7px;
                height: 7px;
            }
            ::-webkit-scrollbar-track {
                background: transparent;
            }
            ::-webkit-scrollbar-thumb {
                background: var(--rn-scrollbar);
                border-radius: 99px;
            }
        `;
        (document.head || document.documentElement).appendChild(style);
    })();
    """#

    /// Core bridge script injected once per document load.
    static let bridgeScript: String = #"""
    (function() {
        if (window.__rednoteLite) return;

        const BRIDGE_NAME = "rednoteBridge";
        let lastSentKey = "";
        let reportTimer = null;
        let videoObserver = null;
        let ecoEnabled = true;
        let blockAutoplay = true;
        let cleanEnabled = true;

        function post(payload) {
            try {
                if (window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers[BRIDGE_NAME]) {
                    window.webkit.messageHandlers[BRIDGE_NAME].postMessage(payload);
                }
            } catch (_) {}
        }

        function extractNoteId(urlStr) {
            try {
                const u = new URL(urlStr);
                const parts = u.pathname.split("/").filter(Boolean);
                for (let i = 0; i < parts.length; i++) {
                    if ((parts[i] === "explore" || parts[i] === "item") && parts[i + 1] && /^[0-9a-fA-F]{24}$/.test(parts[i + 1])) {
                        return parts[i + 1];
                    }
                }
                const last = parts[parts.length - 1];
                if (last && /^[0-9a-fA-F]{24}$/.test(last)) return last;
            } catch (_) {}
            return null;
        }

        function firstText(selectors) {
            for (const sel of selectors) {
                const el = document.querySelector(sel);
                if (el) {
                    const txt = (el.textContent || "").trim();
                    if (txt.length > 0) return txt;
                }
            }
            return "";
        }

        function firstImage(selectors) {
            for (const sel of selectors) {
                const el = document.querySelector(sel);
                if (!el) continue;
                const src = el.currentSrc || el.getAttribute("src") || el.getAttribute("poster") || el.getAttribute("content");
                if (src && (src.startsWith("http://") || src.startsWith("https://"))) {
                    return src;
                }
            }
            return "";
        }

        function isModalOpen() {
            const mask = document.querySelector(".note-detail-mask");
            if (!mask) return false;
            const style = window.getComputedStyle(mask);
            return style.display !== "none" && style.visibility !== "hidden";
        }

        function collectSnapshot() {
            const url = window.location.href;
            const noteId = extractNoteId(url);
            const modalVisible = isModalOpen();
            const hasDetail = modalVisible || !!noteId || !!document.querySelector("#noteContainer");

            let title = "";
            let author = "";
            let excerpt = "";
            let coverURL = "";

            if (hasDetail) {
                title = firstText([
                    "#detail-title",
                    ".note-content .title",
                    ".note-detail-mask .title",
                    "#noteContainer .title"
                ]);
                author = firstText([
                    ".author-wrapper .username",
                    ".author-container .username",
                    ".author-container .name",
                    ".note-detail-mask .username",
                    ".user-nickname"
                ]);
                excerpt = firstText([
                    "#detail-desc .note-text",
                    "#detail-desc",
                    ".note-content .desc"
                ]).slice(0, 180);
                coverURL = firstImage([
                    ".note-slider-img",
                    ".swiper-slide-active img",
                    "#noteContainer img",
                    "#noteContainer video[poster]",
                    'meta[property="og:image"]'
                ]);
            }

            if (!title) {
                title = (document.title || "")
                    .replace(/\s*[-–—|]\s*小红书.*$/u, "")
                    .trim();
            }
            if (!coverURL) {
                coverURL = firstImage(['meta[property="og:image"]']);
            }
            if (!excerpt) {
                const metaDesc = document.querySelector('meta[name="description"]');
                if (metaDesc && metaDesc.content) {
                    excerpt = metaDesc.content.trim().slice(0, 180);
                }
            }

            return {
                type: "pageSnapshot",
                url: url,
                noteId: noteId || "",
                title: title,
                author: author,
                coverURL: coverURL,
                excerpt: excerpt,
                isNoteDetail: hasDetail
            };
        }

        function scheduleReport(force, delayMs) {
            if (reportTimer) clearTimeout(reportTimer);
            reportTimer = setTimeout(() => {
                const snap = collectSnapshot();
                const key = `${snap.url}|${snap.title}|${snap.author}|${snap.isNoteDetail}`;
                if (force || key !== lastSentKey) {
                    lastSentKey = key;
                    post(snap);
                }
            }, typeof delayMs === "number" ? delayMs : 220);
        }

        function applyAppearance(isDark) {
            const dark = !!isDark;
            document.documentElement.setAttribute("data-rn-dark", dark ? "true" : "false");
            if (window.location.hostname === "www.xiaohongshu.com") {
                document.documentElement.setAttribute("data-theme", dark ? "dark" : "light");
                document.documentElement.style.colorScheme = dark ? "dark" : "light";
            }
        }

        function applyEcoMode(enabled, noAutoplay) {
            ecoEnabled = !!enabled;
            blockAutoplay = !!noAutoplay;

            let style = document.getElementById("__rednote_eco_css");
            if (ecoEnabled) {
                if (!style) {
                    style = document.createElement("style");
                    style.id = "__rednote_eco_css";
                    document.head.appendChild(style);
                }
                style.textContent = `
                    section.note-item,
                    .feeds-container section,
                    .note-item {
                        content-visibility: auto;
                        contain-intrinsic-size: 240px 340px;
                    }
                `;
                setupVideoObserver();
            } else {
                if (style) style.remove();
                if (videoObserver) {
                    videoObserver.disconnect();
                    videoObserver = null;
                }
            }
        }

        function setupVideoObserver() {
            if (videoObserver) videoObserver.disconnect();
            if (typeof IntersectionObserver === "undefined") return;

            videoObserver = new IntersectionObserver((entries) => {
                for (const entry of entries) {
                    const vid = entry.target;
                    if (!entry.isIntersecting && !vid.paused) {
                        try { vid.pause(); } catch (_) {}
                    }
                }
            }, { threshold: 0.05 });

            document.querySelectorAll("video").forEach((v) => {
                if (blockAutoplay) {
                    v.autoplay = false;
                    if (v.getAttribute("preload") !== "none") {
                        v.setAttribute("preload", "metadata");
                    }
                }
                videoObserver.observe(v);
            });
        }

        function applyCleanMode(enabled) {
            cleanEnabled = !!enabled;
            let style = document.getElementById("__rednote_clean_css");
            if (cleanEnabled) {
                if (!style) {
                    style = document.createElement("style");
                    style.id = "__rednote_clean_css";
                    document.head.appendChild(style);
                }
                style.textContent = `
                    .floating-btn-sets,
                    .download-app-banner,
                    .open-app-banner {
                        display: none !important;
                    }
                `;
            } else if (style) {
                style.remove();
            }
        }

        function pauseAllMedia() {
            document.querySelectorAll("video, audio").forEach((m) => {
                try {
                    if (!m.paused) m.pause();
                } catch (_) {}
            });
        }

        function trimMemory() {
            pauseAllMedia();
            document.querySelectorAll("video").forEach((v) => {
                const rect = v.getBoundingClientRect();
                const offscreen = rect.bottom < -300 || rect.top > window.innerHeight + 300;
                if (offscreen) {
                    try {
                        v.pause();
                        v.setAttribute("preload", "none");
                    } catch (_) {}
                }
            });
        }

        function focusCommentInput() {
            const selectors = [
                "#content-textarea",
                ".comment-input-box [contenteditable='true']",
                ".input-box [contenteditable='true']",
                "textarea[placeholder*='评论']",
                "input[placeholder*='评论']",
                ".chat-input [contenteditable='true']",
                "[contenteditable='true'][class*='content']"
            ];
            for (const sel of selectors) {
                const el = document.querySelector(sel);
                if (el) {
                    el.scrollIntoView({ behavior: "smooth", block: "center" });
                    el.click();
                    el.focus();
                    return true;
                }
            }
            const commentBtn = document.querySelector(".chat-wrapper, [class*='comment-wrapper']");
            if (commentBtn) {
                commentBtn.click();
                return true;
            }
            return false;
        }

        function getUserProfileURL() {
            const link = document.querySelector('a[href*="/user/profile/"]');
            if (link && link.href && link.href.includes("/user/profile/")) {
                return link.href;
            }
            return "";
        }

        function openUserProfile() {
            const url = getUserProfileURL();
            if (url) {
                window.location.href = url;
                return true;
            }
            const loginBtn = document.querySelector("#login-btn, .login-btn");
            if (loginBtn) {
                loginBtn.click();
                return "login";
            }
            return false;
        }

        function getVueRouter() {
            try {
                const appEl = document.querySelector("#app");
                const router = appEl && appEl.__vue_app__ && appEl.__vue_app__.config && appEl.__vue_app__.config.globalProperties && appEl.__vue_app__.config.globalProperties.$router;
                if (router && typeof router.push === "function") {
                    return router;
                }
            } catch (_) {}
            return null;
        }

        function selectChannel(channelId, title) {
            const container = document.querySelector(".channel-container, .channel-scroll-container");
            if (!container || container.closest(".search-layout")) return false;
            const byId = document.getElementById(channelId);
            if (byId) {
                byId.click();
                scheduleReport(true, 180);
                return true;
            }
            const candidates = container.querySelectorAll(".channel, [id*='homefeed']");
            for (const el of candidates) {
                if ((el.textContent || "").trim() === title) {
                    el.click();
                    scheduleReport(true, 180);
                    return true;
                }
            }
            return false;
        }

        /// Direct Vue 3 Router SPA switch for topic tags (上海/科技/数码/AI/财经/育儿) and search.
        /// Measured ~150-250ms (15x faster than 3.5s full-page reload!).
        function searchInSPA(keyword) {
            const kw = (keyword || "").trim();
            if (!kw) return "invalid";
            pauseAllMedia();

            const router = getVueRouter();
            if (router) {
                try {
                    const source = window.location.pathname.includes("/search_result")
                        ? "web_search_result_notes"
                        : "web_explore_feed";
                    router.push({
                        path: "/search_result",
                        query: { keyword: kw, source: source, type: "51" }
                    });
                    setTimeout(() => {
                        unstickSearchBars();
                        scheduleReport(true, 80);
                    }, 180);
                    return "router_pushed";
                } catch (_) {}
            }
            return "no_router";
        }

        /// Direct Vue 3 Router SPA switch for official Explore channels (推荐/穿搭/美食/...).
        /// Works instantaneously from both /explore (~150ms) and /search_result (~300ms) with ZERO JS reload.
        function navigateToExploreInSPA(channelId, title) {
            pauseAllMedia();

            // Already on /explore -> direct DOM channel click is instant
            if (selectChannel(channelId, title)) {
                return "dom_clicked";
            }

            const router = getVueRouter();
            if (router) {
                try {
                    const query = channelId ? { channel_id: channelId } : {};
                    router.push({ path: "/explore", query: query });
                    // Confirm channel active state once /explore finishes mounting
                    if (channelId && channelId !== "homefeed_recommend") {
                        let attempts = 0;
                        const poll = setInterval(() => {
                            attempts++;
                            const activeEl = document.querySelector(".feeds-page .channel.active");
                            if ((activeEl && (activeEl.textContent || "").trim() === title) || selectChannel(channelId, title) || attempts >= 16) {
                                clearInterval(poll);
                            }
                        }, 60);
                    }
                    scheduleReport(true, 220);
                    return "router_pushed";
                } catch (_) {}
            }
            return "no_router";
        }

        /// Cleanly exits an open note detail view back to the feed (preserving exact scroll position).
        function closeNoteDetail() {
            pauseAllMedia();
            if (isModalOpen()) {
                const closeBtn = document.querySelector(
                    ".note-detail-mask > .close-circle, .note-detail-mask > .close-box, .note-detail-mask .close-circle"
                );
                if (closeBtn) {
                    closeBtn.click();
                    scheduleReport(true, 160);
                    return "modal_closed";
                }
                // Fallback: dispatch Escape key which Xiaohongshu's modal also listens to
                document.dispatchEvent(new KeyboardEvent("keydown", { key: "Escape", code: "Escape", keyCode: 27, bubbles: true }));
                scheduleReport(true, 180);
                return "modal_escape";
            }
            return "standalone";
        }

        // MARK: - Cloud Collection Sync Helpers

        let suppressPassiveCollectUntil = 0;

        function findCollectButton() {
            const root = document.querySelector("#noteContainer, .note-detail-mask, .interaction-container") || document;
            const selectors = [
                ".engage-bar-container .collect-wrapper",
                ".interact-container .collect-wrapper",
                "#note-page-collect-board-guide",
                ".collect-wrapper",
                '[class*="collect-wrapper"]'
            ];
            for (const sel of selectors) {
                const el = root.querySelector(sel);
                if (el) return el;
            }
            return null;
        }

        function isElementCollected(wrapper) {
            if (!wrapper) return false;
            const cls = (wrapper.className || "").toString().toLowerCase();
            if (cls.includes("active") || cls.includes("collected")) return true;
            if (wrapper.querySelector(".active, .collected, [class*='collected']")) return true;
            const useEl = wrapper.querySelector("use");
            if (useEl) {
                const href = (useEl.getAttribute("xlink:href") || useEl.getAttribute("href") || "").toLowerCase();
                if (href.includes("collected") || href.includes("star-fill") || href.includes("collect_fill")) {
                    return true;
                }
            }
            return false;
        }

        function toggleCloudCollect(desiredCollected) {
            const btn = findCollectButton();
            if (!btn) {
                return { status: "not_found", cloudCollected: false };
            }
            const currentlyCollected = isElementCollected(btn);
            const target = typeof desiredCollected === "boolean" ? desiredCollected : !currentlyCollected;
            if (currentlyCollected === target) {
                return { status: "already_synced", cloudCollected: currentlyCollected };
            }
            suppressPassiveCollectUntil = Date.now() + 900;
            const clickTarget = btn.querySelector("svg, .reds-icon, span") || btn;
            clickTarget.click();
            return { status: "clicked", cloudCollected: target };
        }

        function openCloudCollectionsTab() {
            function tryClick() {
                const tabs = document.querySelectorAll(".reds-tab-item, .tab-item, [class*='tab-item'], [role='tab']");
                for (const tab of tabs) {
                    const text = (tab.textContent || "").trim();
                    if (text === "收藏" || text.startsWith("收藏")) {
                        tab.click();
                        return true;
                    }
                }
                return false;
            }
            if (tryClick()) return true;
            let attempts = 0;
            const poll = setInterval(() => {
                attempts++;
                if (tryClick() || attempts >= 25) {
                    clearInterval(poll);
                }
            }, 80);
            return false;
        }

        function extractVisibleNotes() {
            const cards = document.querySelectorAll("section.note-item, .feeds-container section");
            const items = [];
            const seen = new Set();
            cards.forEach((card) => {
                const link = card.querySelector('a[href*="/explore/"], a[href*="/discovery/item/"], a.cover, a[href*="/user/profile/"]');
                if (!link || !link.href) return;
                const url = link.href;
                const noteId = extractNoteId(url);
                if (!noteId || seen.has(noteId)) return;
                seen.add(noteId);

                const titleEl = card.querySelector(".title span, .title, .footer .title");
                const authorEl = card.querySelector(".author .name, .author-wrapper .name, .name");
                const imgEl = card.querySelector("img");
                const title = (titleEl ? titleEl.textContent : "").trim();
                const author = (authorEl ? authorEl.textContent : "").trim();
                const coverURL = imgEl ? (imgEl.currentSrc || imgEl.getAttribute("src") || "") : "";

                items.push({
                    url,
                    noteId,
                    title: title || ("笔记 " + noteId.slice(0, 8)),
                    author,
                    coverURL
                });
            });
            return items;
        }

        // Right-click outside media/input/selection inside a note detail immediately goes back
        document.addEventListener("contextmenu", (e) => {
            const inNoteDetail = isModalOpen() || !!extractNoteId(window.location.href) || !!document.querySelector("#noteContainer");
            if (!inNoteDetail) return;

            const target = e.target;
            if (!(target instanceof Element)) return;

            // Keep native right-click menu on images/videos/media gallery
            if (target.closest(".media-container, .slider-container, .swiper, img, video, canvas, picture")) {
                return;
            }
            // Keep native right-click menu in editable inputs (paste, etc.)
            if (target.closest('input, textarea, [contenteditable="true"]')) {
                return;
            }
            // Keep native right-click menu if the user has selected text to copy
            const sel = window.getSelection && window.getSelection().toString().trim();
            if (sel && sel.length > 0) {
                return;
            }

            e.preventDefault();
            e.stopPropagation();
            post({ type: "rightClickBack" });
        }, true);

        // Passive listener: clicking Xiaohongshu's in-page star icon also syncs to local collections
        document.addEventListener("click", (e) => {
            if (Date.now() < suppressPassiveCollectUntil) return;
            const target = e.target;
            if (!(target instanceof Element)) return;
            const wrapper = target.closest('.collect-wrapper, #note-page-collect-board-guide, [class*="collect-wrapper"]');
            if (!wrapper) return;

            setTimeout(() => {
                const freshBtn = findCollectButton() || wrapper;
                const collected = isElementCollected(freshBtn);
                post({
                    type: "cloudCollectChanged",
                    collected: collected,
                    snapshot: collectSnapshot()
                });
            }, 450);
        }, true);

        // Hook SPA history transitions
        const origPushState = history.pushState;
        history.pushState = function() {
            const ret = origPushState.apply(this, arguments);
            scheduleReport(false, 180);
            if (ecoEnabled) setTimeout(setupVideoObserver, 400);
            return ret;
        };
        const origReplaceState = history.replaceState;
        history.replaceState = function() {
            const ret = origReplaceState.apply(this, arguments);
            scheduleReport(false, 180);
            return ret;
        };
        window.addEventListener("popstate", () => scheduleReport(true, 150));

        // Ensure .reds-sticky-box inside search-layout never breaks out with inline top:72px/144px styles;
        // our CSS Grid keeps .search-layout__middle + .search-layout__top pinned flush at top:0!
        let unstickScheduled = false;
        function unstickSearchBars() {
            if (unstickScheduled) return;
            const layout = document.querySelector(".search-layout");
            if (!layout) return;
            unstickScheduled = true;
            requestAnimationFrame(() => {
                unstickScheduled = false;
                layout.querySelectorAll(".reds-sticky-box, .reds-sticky").forEach((el) => {
                    el.style.setProperty("position", "static", "important");
                    el.style.setProperty("top", "auto", "important");
                    el.style.setProperty("height", "auto", "important");
                });
            });
        }

        // Notify native shell the instant first feed cards render so launch skeleton fades out immediately
        let firstPaintNotified = false;
        function notifyFirstPaintIfReady() {
            if (firstPaintNotified) return;
            if (document.querySelector("section.note-item, .feeds-container section, #noteContainer, .notification-page, .user-page")) {
                firstPaintNotified = true;
                post({ type: "firstPaintReady" });
            }
        }

        // Watch body children for instant detection when note detail modal opens/closes
        const domObserver = new MutationObserver(() => {
            scheduleReport(false, 120);
            notifyFirstPaintIfReady();
        });
        if (document.body) {
            domObserver.observe(document.body, { childList: true, subtree: false });
        }

        // Fast short poll for first feed card paint during cold startup (stops immediately once painted)
        let paintPollCount = 0;
        const paintPoll = setInterval(() => {
            notifyFirstPaintIfReady();
            unstickSearchBars();
            paintPollCount++;
            if (firstPaintNotified || paintPollCount > 25) {
                clearInterval(paintPoll);
            }
        }, 120);

        window.__rednoteLite = {
            getSnapshot: collectSnapshot,
            reportNow: () => scheduleReport(true, 80),
            applyAppearance,
            applyEcoMode,
            applyCleanMode,
            pauseAllMedia,
            trimMemory,
            focusCommentInput,
            getUserProfileURL,
            openUserProfile,
            selectChannel,
            searchInSPA,
            navigateToExploreInSPA,
            closeNoteDetail,
            toggleCloudCollect,
            openCloudCollectionsTab,
            extractVisibleNotes
        };

        // Apply CSS immediately; defer video IntersectionObserver slightly so Vue hydration gets 100% CPU first
        applyCleanMode(cleanEnabled);
        setTimeout(() => applyEcoMode(ecoEnabled, blockAutoplay), 600);
        scheduleReport(true, 150);
    })();
    """#
}
