
// background.js

browser.runtime.onMessage.addListener((message, sender, sendResponse) => {
    if (message.action === "sendArticleToSwift") {
        return browser.runtime.sendNativeMessage("com.summarizeit.SummarizeIt.Extension", {
            action: "article",
            text: message.articleText,
            article_url: sender.url,
            title: message.articleTitle
        }).then(response => {
            sendMessageToPopup(sender.tab.id, response)
            return response;
        }).catch(error => {
            return { error: error.message };
        });
    }
    return Promise.resolve({ status: "unknown_action" });
});

function sendMessageToPopup(tabid, data, article_url, articleTitle) {
    chrome.tabs.sendMessage(tabid, {type: 'updatePopup', data:data, tabid, article_url, articleTitle}).catch(error=>{
    });
    
}
