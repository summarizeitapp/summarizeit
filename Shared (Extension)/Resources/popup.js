
// popup.js
(function () {
  document.addEventListener("DOMContentLoaded", async () => {
    const contentBox  = document.getElementById("summarized");
    const shareBtn    = document.getElementById("shareBtn");
    const fallbackMsg = document.getElementById("fallback");

    setText("Working...");

    // Ask content script to extract + kick off summarize
    const [tab] = await chrome.tabs.query({ active: true, currentWindow: true });
    chrome.tabs.sendMessage(tab.id, { action: "relayArticleToSwift" }, () => { /* no-op */ });

    // Share button
    shareBtn.onclick = async () => {
      const text = contentBox.value || "";
      if (navigator.share) {
        try { await navigator.share({ title: "Shared from Safari", text }); } catch (_) {}
      } else {
        fallbackMsg.style.display = "block";
      }
    };
  });

  // Receive final result from background (broadcast)
  browser.runtime.onMessage.addListener((msg) => {
    if (!msg || msg.type !== "updatePopup") return;
    const data = msg.data || {};
    const title = data.title || msg.articleTitle || "";
    const url   = data.url   || msg.article_url || "";

    if (data.aiAvailable === false) {
      setText(`Apple Intelligence is not available on this device.\n\nTitle: ${title}\nUrl: ${url}`);
      return;
    }
    if (data.error && !data.summary) {
      setText(`Error: ${data.error}\n\nTitle: ${title}\nUrl: ${url}`);
      return;
    }

    const summary   = data.summary || "(No content)";
    const sentiment = data.sentiment || "—";
    const language  = data.language  || "English";

    setText(
      `Title: ${title}\n` +
      `Url: ${url}\n` +
      `Language: ${language}\n` +
      `Sentiment: ${sentiment}\n\n` +
      `Summary: ${summary}`
    );
  });

  function setText(s) {
    const box = document.getElementById("summarized");
    if (box) box.value = s || "";
  }
})();
