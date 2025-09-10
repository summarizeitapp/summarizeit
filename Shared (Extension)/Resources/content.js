
(function () {
    
    browser.runtime.onMessage.addListener((message, sender) => {
        if (message.action === "relayArticleToSwift") {
            const article = extractArticle();
            browser.runtime.sendMessage({
                action: "sendArticleToSwift",
                articleText: article["articleText"],
                articleTitle: article["articleTitle"]
            }).then(response => {
                return response;
            });
        }
    });
    
    function extractArticle(){
        var articleText = '';
        var articleTitle = '';
        try {
            
            if (typeof Readability !== "function") {
                sendResponse({ error: "Readability not loaded" });
                return true;
            }
            
            const article = new Readability(document.cloneNode(true)).parse();
            
            if (article?.textContent) {
                articleText = article.textContent;
                articleTitle = article.title;
            } else {
                articleText = '';
                articleTitle = '';
            }
        } catch (err) {
            
        }
        return {"articleText":articleText, "articleTitle":articleTitle};
    };
    browser.runtime.onMessage.addListener((msg, sender, sendResponse) => {
        if (msg.type === "updatePopup") {
            browser.runtime.sendMessage({type:"updatePopup", msg});
        }
    });
})();



