
//// content.js
(function () {
    // === Global Speech Manager (outside shadow DOM for reliability) ===
    let globalSpeechState = {
        isSpeaking: false,
        currentLang: 'en-US',
        currentText: '',
        chunks: [],
        currentChunkIndex: 0,
        keepaliveTimer: null
    };
    
    // === Extraction ===
    function extractArticle() {
        let articleText = "";
        let articleTitle = "";
        
        // Helper function to check if element is in viewport
        function isInViewport(element) {
            const rect = element.getBoundingClientRect();
            const windowHeight = window.innerHeight || document.documentElement.clientHeight;
            const windowWidth = window.innerWidth || document.documentElement.clientWidth;
            
            // Element is in viewport if at least 30% is visible
            const vertInView = (rect.top <= windowHeight * 0.7) && ((rect.top + rect.height) >= windowHeight * 0.3);
            const horInView = (rect.left <= windowWidth) && ((rect.left + rect.width) >= 0);
            
            return vertInView && horInView;
        }
        
        // Helper function to find article container in viewport
        function findArticleInViewport() {
            const articleSelectors = [
                'article[role="article"]',
                'article.article',
                'article',
                '[role="article"]',
                '.article-container',
                '.post',
                '.entry'
            ];
            
            for (const selector of articleSelectors) {
                const articles = document.querySelectorAll(selector);
                for (const article of articles) {
                    if (isInViewport(article)) {
                        return article;
                    }
                }
            }
            
            return null;
        }
        
        // Helper function to extract title from container
        function extractTitleFromContainer(container) {
            const titleSelectors = [
                'h1[class*="title"]',
                'h1[class*="headline"]',
                'h1',
                'h2[class*="title"]',
                'h2[class*="headline"]',
                '[class*="article-title"]',
                '[class*="post-title"]'
            ];
            
            for (const selector of titleSelectors) {
                const titleEl = container.querySelector(selector);
                if (titleEl && titleEl.innerText && titleEl.innerText.trim().length > 10) {
                    return titleEl.innerText.trim();
                }
            }
            
            return null;
        }
        
        // FIRST: Try to find article in viewport (for continuous scroll pages)
        const viewportArticle = findArticleInViewport();
        
        if (viewportArticle) {
            // Extract from viewport article
            articleTitle = extractTitleFromContainer(viewportArticle);
            articleText = Array.from(viewportArticle.querySelectorAll("p, h1, h2, h3, h4, li"))
                .map((el) => (el && el.innerText ? el.innerText.trim() : ""))
                .filter(Boolean)
                .join("\n");
            
            console.log("Extracted article from viewport:", articleTitle);
        }
        
        // FALLBACK: Use Readability if viewport detection didn't work
        if (!articleText || articleText.trim().length < 30) {
            try {
                if (typeof Readability === "function") {
                    const parsed = new Readability(document.cloneNode(true)).parse();
                    if (parsed?.textContent) {
                        articleText = parsed.textContent;
                        if (!articleTitle) {
                            articleTitle = parsed.title || document.title || "";
                        }
                    }
                }
            } catch (_) {
                // ignore readability errors
            }
        }
        
        // LAST RESORT: Manual extraction
        if (!articleText || articleText.trim().length < 30) {
            const mainSelectors = [
                'main article',
                '[role="main"] article',
                'article',
                'main',
                '[role="main"]',
                '.article-body',
                '.post-content',
                '.entry-content'
            ];
            
            let mainContainer = null;
            for (const selector of mainSelectors) {
                mainContainer = document.querySelector(selector);
                if (mainContainer) break;
            }
            
            if (mainContainer) {
                if (!articleTitle) {
                    articleTitle = extractTitleFromContainer(mainContainer) || document.title;
                }
                
                articleText = Array.from(mainContainer.querySelectorAll("p, h1, h2, h3, h4, li"))
                    .map((el) => (el && el.innerText ? el.innerText.trim() : ""))
                    .filter(Boolean)
                    .join("\n");
            } else {
                // Very last resort: filtered paragraphs
                articleText = Array.from(document.querySelectorAll("p"))
                    .filter((el) => {
                        const parent = el.closest('aside, footer, header, nav, [class*="sidebar"], [class*="related"], [class*="recommend"], [id*="sidebar"], [id*="related"], [id*="recommend"], [class*="ad-"], [id*="ad-"]');
                        return !parent && el.innerText && el.innerText.trim().length > 20;
                    })
                    .map((el) => el.innerText.trim())
                    .join("\n");
                
                if (!articleTitle) {
                    articleTitle = document.title;
                }
            }
        }
        
        // Limit based on character type (CJK uses more tokens)
        // Check if text is mostly CJK (Chinese, Japanese, Korean)
        const cjkRegex = /[\u4E00-\u9FFF\u3400-\u4DBF]/g;
        const cjkMatches = articleText.match(cjkRegex);
        const cjkRatio = cjkMatches ? cjkMatches.length / articleText.length : 0;
        
        let maxChars;
        if (cjkRatio > 0.3) {
            // Mostly CJK: 28K chars (~15.5K tokens) - balanced for news
            maxChars = 28000;
        } else if (cjkRatio > 0.1) {
            // Mixed: 40K chars (~16K tokens) - good coverage
            maxChars = 40000;
        } else {
            // Mostly Latin: 60K chars (~15K tokens) - comprehensive
            maxChars = 60000;
        }
        
        if (articleText.length > maxChars) {
            articleText = articleText.slice(0, maxChars);
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
          button.speaking { background:#007AFF; color:#fff; border-color:#007AFF; }
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
              <button id="speak" title="Read summary aloud">🔊 Listen</button>
              <button id="copy" title="Copy summary">Copy</button>
              <button id="share" title="Share summary">Share</button>
              <button id="close" title="Close panel" aria-label="Close">X</button>
            </div>
          </div>
          <div id="meta" class="meta"></div>
          <div id="body" class="body">Working…</div>
        </div>
      `;
        // Language mapping
        function getLanguageCode(languageName) {
            const map = {
                'English': 'en-US',
                'Chinese': 'zh-CN',
                'Japanese': 'ja-JP',
                'Korean': 'ko-KR',
                'Spanish': 'es-ES',
                'French': 'fr-FR',
                'German': 'de-DE',
                'Italian': 'it-IT',
                'Portuguese': 'pt-PT',
                'Russian': 'ru-RU',
                'Arabic': 'ar-SA',
                'Hindi': 'hi-IN',
                'Dutch': 'nl-NL',
                'Polish': 'pl-PL',
                'Turkish': 'tr-TR'
            };
            return map[languageName] || 'en-US';
        }
        
        // Speech button handler - chunked approach for Safari reliability
        root.getElementById("speak").onclick = () => {
            const speakBtn = root.getElementById("speak");
            const bodyText = root.getElementById("body").textContent || "";
            
            // If currently speaking, stop
            if (globalSpeechState.isSpeaking) {
                window.speechSynthesis.cancel();
                speakBtn.textContent = "🔊 Listen";
                speakBtn.classList.remove("speaking");
                globalSpeechState.isSpeaking = false;
                globalSpeechState.chunks = [];
                globalSpeechState.currentChunkIndex = 0;
                if (globalSpeechState.keepaliveTimer) {
                    clearInterval(globalSpeechState.keepaliveTimer);
                    globalSpeechState.keepaliveTimer = null;
                }
                return;
            }
            
            // Extract just the summary part (after "Summary:")
            const summaryMatch = bodyText.match(/Summary:(.+)/s);
            const textToSpeak = summaryMatch ? summaryMatch[1].trim() : bodyText;
            
            if (!textToSpeak || textToSpeak.length < 10) {
                flashBadge(speakBtn, "No content");
                return;
            }
            
            // Cancel any existing speech and wait for it to clear
            window.speechSynthesis.cancel();
            
            // Function to initialize and start speech
            const initSpeech = () => {
                // Give Safari a moment to clear the queue after cancel
                setTimeout(() => {
                    startSpeaking();
                }, 100);
            };
            
            const startSpeaking = () => {
                // SIMPLE APPROACH: Speak entire summary as ONE utterance with keepalive
                console.log(`Speaking entire text: ${textToSpeak.length} characters`);
                
                // Start keepalive timer to prevent Safari from sleeping
                if (globalSpeechState.keepaliveTimer) {
                    clearInterval(globalSpeechState.keepaliveTimer);
                }
                globalSpeechState.keepaliveTimer = setInterval(() => {
                    if (globalSpeechState.isSpeaking && window.speechSynthesis.paused) {
                        console.log("Keepalive: Resuming paused speech");
                        window.speechSynthesis.resume();
                    }
                }, 50); // Check every 50ms
                
                // Get voices
                const voices = window.speechSynthesis.getVoices();
                if (voices.length === 0) {
                    flashBadge(speakBtn, "No voices");
                    return;
                }
                
                const langCode = globalSpeechState.currentLang;
                const langBase = langCode.split('-')[0];
                
                const selectedVoice = voices.find(v => v.lang === langCode) ||
                                     voices.find(v => v.lang.startsWith(langBase)) ||
                                     voices.find(v => v.default) ||
                                     voices[0];
                
                // Create single utterance for entire text
                const utterance = new window.SpeechSynthesisUtterance(textToSpeak);
                
                if (selectedVoice) {
                    utterance.voice = selectedVoice;
                }
                utterance.lang = langCode;
                utterance.rate = 1.0;
                utterance.pitch = 1.0;
                utterance.volume = 1.0;
                
                // Update UI
                speakBtn.textContent = "⏸️ Stop";
                speakBtn.classList.add("speaking");
                globalSpeechState.isSpeaking = true;
                
                utterance.onend = () => {
                    // All done - cleanup
                    speakBtn.textContent = "🔊 Listen";
                    speakBtn.classList.remove("speaking");
                    globalSpeechState.isSpeaking = false;
                    if (globalSpeechState.keepaliveTimer) {
                        clearInterval(globalSpeechState.keepaliveTimer);
                        globalSpeechState.keepaliveTimer = null;
                    }
                    console.log("Speech completed");
                };
                
                utterance.onerror = (e) => {
                    console.error("Speech error:", e.error);
                    
                    // Cleanup on any error
                    speakBtn.textContent = "🔊 Listen";
                    speakBtn.classList.remove("speaking");
                    globalSpeechState.isSpeaking = false;
                    if (globalSpeechState.keepaliveTimer) {
                        clearInterval(globalSpeechState.keepaliveTimer);
                        globalSpeechState.keepaliveTimer = null;
                    }
                    
                    if (e.error !== 'canceled') {
                        flashBadge(speakBtn, "Error");
                    }
                };
                
                // Speak it
                window.speechSynthesis.speak(utterance);
                console.log("Started speaking");
            }; // end startSpeaking
            
            // Ensure voices are loaded before starting
            const voices = window.speechSynthesis.getVoices();
            if (voices.length > 0) {
                initSpeech();
            } else {
                // Wait for voices to load
                window.speechSynthesis.onvoiceschanged = () => {
                    initSpeech();
                    window.speechSynthesis.onvoiceschanged = null;
                };
                // Fallback timeout
                setTimeout(() => {
                    if (window.speechSynthesis.getVoices().length > 0) {
                        initSpeech();
                    } else {
                        flashBadge(speakBtn, "No voices");
                        speakBtn.textContent = "🔊 Listen";
                        speakBtn.classList.remove("speaking");
                        globalSpeechState.isSpeaking = false;
                    }
                }, 1000);
            }
        };
        
        // handlers
        root.getElementById("close").onclick = () => {
            // Stop speech if playing and cleanup everything
            if (globalSpeechState.isSpeaking) {
                window.speechSynthesis.cancel();
                globalSpeechState.isSpeaking = false;
                globalSpeechState.chunks = [];
                globalSpeechState.currentChunkIndex = 0;
                globalSpeechState.currentText = '';
                if (globalSpeechState.keepaliveTimer) {
                    clearInterval(globalSpeechState.keepaliveTimer);
                    globalSpeechState.keepaliveTimer = null;
                }
            }
            host.remove();
        };
        
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
        
        // Listen for language updates
        host.addEventListener('updateLanguage', (e) => {
            if (e.detail && e.detail.language) {
                // Stop any ongoing speech when new content arrives
                if (globalSpeechState.isSpeaking) {
                    window.speechSynthesis.cancel();
                    globalSpeechState.isSpeaking = false;
                    globalSpeechState.chunks = [];
                    globalSpeechState.currentChunkIndex = 0;
                    
                    const speakBtn = root.getElementById("speak");
                    if (speakBtn) {
                        speakBtn.textContent = "🔊 Listen";
                        speakBtn.classList.remove("speaking");
                    }
                }
                
                globalSpeechState.currentLang = getLanguageCode(e.detail.language);
            }
        });
        
        panelRoot = root;
        return root;
    }
    
    function showWorking(title, url) {
        const root = ensurePanel();
        root.getElementById("body").textContent = "Analyzing content... This may take 30-90 seconds for long articles.";
        root.getElementById("body").classList.remove("err");
        root.getElementById("ttl").textContent = "Summary";
    }
    
    function showSummary({ summary, sentiment, language, title, url }) {
        const root = ensurePanel();
        
        // Stop any ongoing speech from previous summary and reset state completely
        if (typeof speechSynthesis !== 'undefined') {
            speechSynthesis.cancel();
        }
        globalSpeechState.isSpeaking = false;
        globalSpeechState.chunks = [];
        globalSpeechState.currentChunkIndex = 0;
        
        var output = "Title: " + title + "\n" + "URL: " + url + "\n" + "Language: " + language + "\n" + "Sentiment: " + sentiment + "\n" + "Summary:" + summary;
        root.getElementById("body").textContent = output || "(No content)";
        root.getElementById("body").classList.remove("err");
        root.getElementById("ttl").textContent = "Summary";
        
        // Reset speech button state
        const speakBtn = root.getElementById("speak");
        if (speakBtn) {
            speakBtn.textContent = "🔊 Listen";
            speakBtn.classList.remove("speaking");
        }
        
        // Update language for speech by dispatching custom event
        if (language) {
            const event = new CustomEvent('updateLanguage', { detail: { language } });
            root.host.dispatchEvent(event);
        }
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
