// background.js — overlay-only mode
const NATIVE_HOST = "com.summarizeit.SummarizeIt.Extension";
const NATIVE_TIMEOUT_MS = 60000;
const SF_KEY = "com.apple.Safari.web-extension-message";

function unwrapNativeResponse(nativeResponse) {
    if (!nativeResponse) return {};
    if (nativeResponse.response) return nativeResponse.response;
    const env = nativeResponse[SF_KEY];
    if (env && env.response) return env.response;
    return nativeResponse;
}

// Toolbar button → ask the page to collect text and kick off summarize
browser.action.onClicked.addListener(async (tab) => {
    try {
        await browser.tabs.sendMessage(tab.id, { action: "relayArticleToSwift" });
    } catch (e) {
        // If content script isn’t injected yet (rare), you could inject it here.
        // But with content_scripts in manifest, this usually isn’t needed.
    }
});

// Content → Background: send article to native
browser.runtime.onMessage.addListener((message, sender) => {
    if (message.action !== "sendArticleToSwift") {
        return Promise.resolve({ status: "unknown_action" });
    }
    
    const articleText = message.articleText || "";
    const articleTitle = message.articleTitle || "";
    const articleUrl = (sender && sender.url) || "";
    
    if (!articleText || articleText.trim().length < 30) {
        sendToContent(sender?.tab?.id, { error: "No readable content on this page." }, articleUrl, articleTitle);
        return Promise.resolve({ error: "no_content" });
    }
    
    const payload = {
        message: {
            action: "summarize",
            text: articleText,
            article_url: articleUrl,
            title: articleTitle
            // langCode: "en" // optional
        }
    };
    
    const nativeCall = browser.runtime.sendNativeMessage(NATIVE_HOST, payload);
    const timeout = new Promise((_, reject) => setTimeout(() => reject(new Error("timeout")), NATIVE_TIMEOUT_MS));
    
    return Promise.race([nativeCall, timeout])
    .then((nativeResponse) => {
        const data = unwrapNativeResponse(nativeResponse);
        sendToContent(sender?.tab?.id, data, articleUrl, articleTitle);
        return data;
    })
    .catch((error) => {
        const data = { error: error.message || String(error) };
        sendToContent(sender?.tab?.id, data, articleUrl, articleTitle);
        return data;
    });
});

function sendToContent(tabId, data, article_url, articleTitle) {
    if (tabId == null) return;
    try {
        chrome.tabs.sendMessage(tabId, {
            type: "updatePopup",
            data,
            tabId,
            article_url,
            articleTitle
        });
    } catch (_) {}
}
