 (function () {
     document.addEventListener("DOMContentLoaded", async () => {
         const contentBox = document.getElementById("summarized");
         const shareBtn = document.getElementById("shareBtn");
         const fallbackMsg = document.getElementById("fallback");
         const [tab] = await chrome.tabs.query({ active: true, currentWindow: true });
         chrome.tabs.sendMessage(tab.id, { action: "relayArticleToSwift" }, response => {

         });
         
         shareBtn.onclick = async () => {
             const text = contentBox.value;
             if (navigator.share) {
                 try {
                     await navigator.share({
                         title: "Shared from Safari",
                         text: text
                     });
                 } catch (err) {
                 }
             } else {
                 fallbackMsg.style.display = "block";
             }
         };
     });
     
     browser.runtime.onMessage.addListener((msg, sender, sendResponse) => {
         if (msg.type === "updatePopup") {
             document.getElementById("summarized").value = "Title: " + msg.msg.data.response.title + "\nUrl: " + msg.msg.data.response.url +"\nSummary: " + msg.msg.data.response.summary +"\nSentiment: " + msg.msg.data.response.sentiment;
         }
     });
     
     
 })();
