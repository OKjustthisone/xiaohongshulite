import Foundation

enum WebScripts {
    /// Early style injection at document start so users never see a flash of the redundant
    /// web header, web sidebar, or dimmed floating note modal popup.
    static let earlyStyleScript: String = #"""
    (function() {
        if (window.location.hostname !== "www.xiaohongshu.com") return;
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

            /* 1. Hide redundant web top header & web left sidebar on www.xiaohongshu.com */
            #header-container,
            .header-container,
            header.mask-paper,
            .mask-paper,
            .side-bar,
            #side-bar,
            .sidebar-container {
                display: none !important;
            }

            /* Keep channel container in DOM (so native pills can click it) but visually hidden */
            .feeds-page .channel-container,
            .channel-scroll-container {
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
            .user-page,
            .notification-page,
            .search-layout {
                padding-top: 12px !important;
                margin-top: 0 !important;
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

        function selectChannel(channelId, title) {
            const container = document.querySelector(".channel-container, .channel-scroll-container");
            if (!container) return false;
            const byId = document.getElementById(channelId);
            if (byId) {
                byId.click();
                scheduleReport(true, 260);
                return true;
            }
            const candidates = container.querySelectorAll(".channel, [id*='homefeed']");
            for (const el of candidates) {
                if ((el.textContent || "").trim() === title) {
                    el.click();
                    scheduleReport(true, 260);
                    return true;
                }
            }
            return false;
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

        // Watch body children for instant detection when note detail modal opens or closes
        const domObserver = new MutationObserver(() => {
            scheduleReport(false, 120);
        });
        if (document.body) {
            domObserver.observe(document.body, { childList: true, subtree: false });
        }

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
            closeNoteDetail
        };

        applyEcoMode(ecoEnabled, blockAutoplay);
        applyCleanMode(cleanEnabled);
        scheduleReport(true, 120);
    })();
    """#
}
