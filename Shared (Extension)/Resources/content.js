
//// content.js
(function () {
    // === Extraction ===
    function extractArticle() {
        let articleText = "";
        let articleTitle = document.title || "";
        
        try {
            if (typeof Readability === "function") {
                const parsed = new Readability(document.cloneNode(true)).parse();
                if (parsed?.textContent) {
                    articleText = parsed.textContent;
                    articleTitle = parsed.title || articleTitle;
                }
            }
        } catch (_) {
            // ignore readability errors
        }
        
        // Fallback when Readability missing/short
        if (!articleText || articleText.trim().length < 30) {
            articleText = Array.from(document.querySelectorAll("article p, main p, p, h1, h2, h3, li"))
            .map((el) => (el && el.innerText ? el.innerText.trim() : ""))
            .filter(Boolean)
            .join("\n");
        }
        
        if (articleText.length > 200000) {
            articleText = articleText.slice(0, 200000);
        }
        
        return { articleText, articleTitle };
    }
    
    // === Overlay UI ===
    let panelRoot;
    function ensurePanel() {
        if (panelRoot && document.body.contains(panelRoot.host)) return panelRoot;
        
        const host = document.createElement("div");
        host.id = "__ai_summary_host__";
        host.style.position = "fixed";
        host.style.top = "16px";
        host.style.right = "16px";
        host.style.zIndex = "2147483647";
        host.style.width = "min(520px, 92vw)";
        host.style.maxHeight = "80vh";
        host.style.boxShadow = "0 8px 24px rgba(0,0,0,.2)";
        host.style.borderRadius = "12px";
        host.style.overflow = "hidden";
        document.body.appendChild(host);
        
        const root = host.attachShadow({ mode: "open" });
        root.innerHTML = `
        <style>
          .card { font: 14px -apple-system,BlinkMacSystemFont,"Segoe UI",Roboto,sans-serif; background:#fff; color:#111; border:1px solid #ddd; }
          .hdr { display:flex; align-items:center; justify-content:space-between; padding:10px 12px; background:#f7f7f7; gap:8px; }
          .left { display:flex; align-items:center; gap:8px; min-width:0; }
          .ttl { font-weight:600; font-size:14px; margin-right:8px; overflow:hidden; text-overflow:ellipsis; white-space:nowrap; }
          .badge { display:inline-block; padding:2px 6px; font-size:11px; border-radius:6px; background:#eee; color:#111;}
          .right { display:flex; gap:6px; align-items:center; }
          button { border:0; background:#fff; border:1px solid #ccc; padding:4px 8px; border-radius:8px; cursor:pointer; font-size:12px; color:#111; }
          button:hover { background:#f0f0f0; }
          #close { border:0; background:transparent; font-size:16px; line-height:1; padding:2px 6px; }
          .meta { font-size:12px; color:#555; padding:6px 12px 0; }
          .body { padding:12px; line-height:1.45; overflow:auto; max-height:60vh; white-space:pre-wrap; }
          .err { color:#b00020; }
        </style>
        <div class="card" role="dialog" aria-label="AI Summary Panel">
          <div class="hdr">
            <div class="left">
              <span class="ttl" id="ttl">Summary</span>
              
            </div>
            <div class="right">
              <button id="copy" title="Copy summary">Copy</button>
              <button id="share" title="Share summary">Share</button>
              <button id="close" title="Close panel" aria-label="Close">X</button>
            </div>
          </div>
          <div id="meta" class="meta"></div>
          <div id="body" class="body">Working…</div>
        </div>
      `;
        // handlers
        root.getElementById("close").onclick = () => host.remove();
        
        // ESC to close
        const escListener = (e) => { if (e.key === "Escape") host.remove(); };
        document.addEventListener("keydown", escListener, { once: true });
        
        // Copy
        root.getElementById("copy").onclick = async () => {
            const text = root.getElementById("body").textContent || "";
            try {
                await navigator.clipboard.writeText(text);
                flashBadge(root.getElementById("copy"), "Copied");
            } catch {
                flashBadge(root.getElementById("copy"), "Copy failed");
            }
        };
        
        // Share (with graceful fallback)
        root.getElementById("share").onclick = async () => {
            const summary = root.getElementById("body").textContent || "";
            const meta = root.getElementById("meta").textContent || "";
            const title = root.getElementById("ttl").textContent || "Summary";
            try {
                if (navigator.share) {
                    await navigator.share({ title, text: `${meta}\n\n${summary}` });
                    flashBadge(root.getElementById("share"), "Shared");
                } else {
                    await navigator.clipboard.writeText(`${meta}\n\n${summary}`);
                    flashBadge(root.getElementById("share"), "Copied");
                }
            } catch {
                // user canceled or share unsupported
            }
        };
        
        function flashBadge(btn, text) {
            const original = btn.textContent;
            btn.textContent = text;
            setTimeout(() => (btn.textContent = original), 1200);
        }
        
        panelRoot = root;
        return root;
    }
    
    function showWorking(title, url) {
        const root = ensurePanel();
        root.getElementById("body").textContent = "Working…";
        root.getElementById("body").classList.remove("err");
        root.getElementById("ttl").textContent = "Summary";
    }
    
    function showSummary({ summary, sentiment, language, title, url }) {
        const root = ensurePanel();
        var output = "Title: " + title + "\n" + "URL: " + url + "\n" + "Language: " + language + "\n" + "Sentiment: " + sentiment + "\n" + "Summary:" + summary;
        root.getElementById("body").textContent = output || "(No content)";
        root.getElementById("body").classList.remove("err");
        root.getElementById("ttl").textContent = "Summary";
    }
    
    function showError(message) {
        const root = ensurePanel();
        root.getElementById("body").textContent = message || "Error";
        root.getElementById("body").classList.add("err");
        root.getElementById("ttl").textContent = "Summary";
    }
    
    // === Receive results from background
    browser.runtime.onMessage.addListener((msg) => {
        if (!msg || msg.type !== "updatePopup") return;
        
        const { data, article_url, articleTitle } = msg;
        
        if (!data || (!data.summary && !data.error && data.aiAvailable !== false)) {
            showError("Summarization failed (empty payload). Check console for native response.");
//            console.log("[AI] updatePopup no summary; payload:", data);
            return;
        }
        
        if (data.aiAvailable === false) {
            showError("Apple Intelligence is not available on this device.");
            return;
        }
        
        if (data.error && !data.summary) {
            showError(data.error);
            return;
        }
        
        showSummary({
            summary: data.summary,
            sentiment: data.sentiment,
            language: data.language,
            title: data.title || articleTitle,
            url: data.url || article_url
        });
    });
    
    // === Entry point from popup
    browser.runtime.onMessage.addListener((message, _sender, sendResponse) => {
        if (message && message.action === "relayArticleToSwift") {
            const { articleText, articleTitle } = extractArticle();
            showWorking(articleTitle, location.href);
            browser.runtime
            .sendMessage({
                action: "sendArticleToSwift",
                articleText,
                articleTitle
            })
            .catch((e) => {
                showError(`Error: ${e?.message || e}`);
            });
            sendResponse({ ok: true });
            return true; // async
        }
    });
})();
