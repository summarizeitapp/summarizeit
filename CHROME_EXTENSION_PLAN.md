# SummarizeIt Chrome Extension - Implementation Plan

## Overview

Create a Chrome extension version of SummarizeIt using Chrome's built-in Gemini Nano AI for on-device summarization and sentiment analysis.

## Project Setup

### New Repository Structure
```
summarize-it-chrome/
├── manifest.json
├── background.js
├── content.js
├── popup.html
├── popup.js
├── styles.css
├── icons/
│   ├── icon16.png
│   ├── icon48.png
│   └── icon128.png
├── lib/
│   └── readability.js (copy from Safari version)
├── support.html
├── privacy.html
├── README.md
└── docs/
    └── SETUP.md (Chrome AI setup instructions)
```

## Key Differences from Safari Version

### ✅ Simpler Architecture
- **No Swift code** - Pure JavaScript
- **No native messaging** - Direct API calls
- **Manifest V3** - Modern Chrome extension format
- **Same UI** - Can reuse most content.js UI code

### ✅ Chrome Built-in AI APIs

**Option 1: Summarization API (Recommended)**
```javascript
// Check availability
const canSummarize = await ai.summarizer.capabilities();

// Create summarizer
const summarizer = await ai.summarizer.create({
  type: 'tl;dr',  // or 'key-points', 'teaser', 'headline'
  format: 'plain-text',
  length: 'medium'
});

// Summarize
const summary = await summarizer.summarize(articleText);
```

**Option 2: Prompt API (More flexible for sentiment)**
```javascript
const session = await ai.languageModel.create({
  systemPrompt: "You are a helpful assistant that summarizes articles."
});

const result = await session.prompt(`
Summarize this article and analyze its sentiment:
${articleText}
`);
```

## Implementation Steps

### 1. manifest.json
```json
{
  "manifest_version": 3,
  "name": "SummarizeIt - AI Article Summarizer",
  "version": "1.0.0",
  "description": "Summarize articles using on-device AI. Privacy-first, no data sent to servers.",
  "permissions": [
    "activeTab",
    "scripting"
  ],
  "host_permissions": [
    "<all_urls>"
  ],
  "action": {
    "default_popup": "popup.html",
    "default_icon": {
      "16": "icons/icon16.png",
      "48": "icons/icon48.png",
      "128": "icons/icon128.png"
    }
  },
  "background": {
    "service_worker": "background.js"
  },
  "content_scripts": [
    {
      "matches": ["<all_urls>"],
      "js": ["lib/readability.js", "content.js"],
      "run_at": "document_idle"
    }
  ],
  "icons": {
    "16": "icons/icon16.png",
    "48": "icons/icon48.png",
    "128": "icons/icon128.png"
  }
}
```

### 2. background.js (Service Worker)
```javascript
// Handle extension icon clicks
chrome.action.onClicked.addListener(async (tab) => {
  // Inject content script if needed
  await chrome.scripting.executeScript({
    target: { tabId: tab.id },
    files: ['content.js']
  });
  
  // Send message to content script
  chrome.tabs.sendMessage(tab.id, { action: 'summarize' });
});

// Handle messages from content script
chrome.runtime.onMessage.addListener((request, sender, sendResponse) => {
  if (request.action === 'checkAIAvailability') {
    checkAIAvailability().then(sendResponse);
    return true; // Async response
  }
  
  if (request.action === 'summarizeText') {
    summarizeWithAI(request.text).then(sendResponse);
    return true; // Async response
  }
});

async function checkAIAvailability() {
  try {
    // Check if AI APIs are available
    if (!window.ai || !window.ai.summarizer) {
      return { available: false, reason: 'not_supported' };
    }
    
    const capabilities = await ai.summarizer.capabilities();
    
    if (capabilities.available === 'no') {
      return { available: false, reason: 'not_available' };
    }
    
    if (capabilities.available === 'after-download') {
      return { available: false, reason: 'downloading' };
    }
    
    return { available: true };
  } catch (error) {
    return { available: false, reason: 'error', error: error.message };
  }
}

async function summarizeWithAI(text) {
  try {
    // Create summarizer
    const summarizer = await ai.summarizer.create({
      type: 'tl;dr',
      format: 'plain-text',
      length: 'medium'
    });
    
    // Summarize
    const summary = await summarizer.summarize(text);
    
    // Analyze sentiment using Prompt API
    const session = await ai.languageModel.create();
    const sentimentPrompt = `Analyze the sentiment of this text. Reply with only one word: Positive, Negative, or Neutral.\n\n${text.slice(0, 2000)}`;
    const sentiment = await session.prompt(sentimentPrompt);
    
    // Detect language
    const language = detectLanguage(text);
    
    return {
      success: true,
      summary: summary,
      sentiment: sentiment.trim(),
      language: language
    };
  } catch (error) {
    return {
      success: false,
      error: error.message
    };
  }
}

function detectLanguage(text) {
  // Simple language detection based on character sets
  const cjkRegex = /[\u4E00-\u9FFF\u3400-\u4DBF]/g;
  const cjkMatches = text.match(cjkRegex);
  const cjkRatio = cjkMatches ? cjkMatches.length / text.length : 0;
  
  if (cjkRatio > 0.3) {
    return 'Chinese';
  }
  
  // Add more language detection logic as needed
  return 'English';
}
```

### 3. content.js
```javascript
// Reuse most of your Safari content.js code!
// Key changes:
// 1. Remove Safari-specific browser.runtime calls
// 2. Use chrome.runtime instead
// 3. Remove Swift native messaging
// 4. Call background.js for AI processing

(function() {
  // Extract article (same as Safari version)
  function extractArticle() {
    // Copy from your Safari version
    // Uses Readability.js
  }
  
  // UI panel (same as Safari version)
  function ensurePanel() {
    // Copy from your Safari version
    // Same shadow DOM UI
  }
  
  // Listen for messages
  chrome.runtime.onMessage.addListener((message, sender, sendResponse) => {
    if (message.action === 'summarize') {
      handleSummarize();
    }
  });
  
  async function handleSummarize() {
    // Check AI availability
    const availability = await chrome.runtime.sendMessage({
      action: 'checkAIAvailability'
    });
    
    if (!availability.available) {
      showError(getAvailabilityMessage(availability.reason));
      return;
    }
    
    // Extract article
    const { articleText, articleTitle } = extractArticle();
    
    if (!articleText || articleText.length < 30) {
      showError('No readable content found on this page.');
      return;
    }
    
    // Show loading
    showWorking(articleTitle, location.href);
    
    // Send to background for processing
    const result = await chrome.runtime.sendMessage({
      action: 'summarizeText',
      text: articleText
    });
    
    if (result.success) {
      showSummary({
        summary: result.summary,
        sentiment: result.sentiment,
        language: result.language,
        title: articleTitle,
        url: location.href
      });
    } else {
      showError(result.error);
    }
  }
  
  function getAvailabilityMessage(reason) {
    switch (reason) {
      case 'not_supported':
        return 'Chrome Built-in AI is not available. Please update to Chrome 127+ and enable AI features.';
      case 'downloading':
        return 'AI model is downloading. Please wait a few minutes and try again.';
      case 'not_available':
        return 'AI features are not enabled. Please check chrome://flags/#optimization-guide-on-device-model';
      default:
        return 'AI features are not available on this device.';
    }
  }
})();
```

### 4. popup.html (Optional)
```html
<!DOCTYPE html>
<html>
<head>
  <meta charset="UTF-8">
  <style>
    body {
      width: 300px;
      padding: 20px;
      font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif;
    }
    h1 {
      font-size: 18px;
      margin: 0 0 10px 0;
    }
    button {
      width: 100%;
      padding: 12px;
      background: #1a73e8;
      color: white;
      border: none;
      border-radius: 4px;
      cursor: pointer;
      font-size: 14px;
    }
    button:hover {
      background: #1557b0;
    }
    .status {
      margin-top: 15px;
      padding: 10px;
      background: #f1f3f4;
      border-radius: 4px;
      font-size: 12px;
    }
  </style>
</head>
<body>
  <h1>SummarizeIt</h1>
  <button id="summarize">Summarize This Page</button>
  <div class="status" id="status">Click to summarize the current article</div>
  <script src="popup.js"></script>
</body>
</html>
```

### 5. popup.js
```javascript
document.getElementById('summarize').addEventListener('click', async () => {
  const [tab] = await chrome.tabs.query({ active: true, currentWindow: true });
  
  chrome.tabs.sendMessage(tab.id, { action: 'summarize' });
  
  window.close();
});
```

## Setup Instructions for Users

Create `docs/SETUP.md`:

```markdown
# Chrome AI Setup Instructions

SummarizeIt uses Chrome's built-in AI features. Follow these steps to enable them:

## Requirements
- Chrome 127 or newer
- Desktop only (Windows, Mac, Linux)
- Android support coming in 2025

## Enable AI Features

1. **Update Chrome**
   - Go to `chrome://settings/help`
   - Ensure you're on version 127 or newer

2. **Enable AI Flags**
   - Go to `chrome://flags`
   - Search for and enable these flags:
     - `#optimization-guide-on-device-model` → Enabled BypassPerfRequirement
     - `#prompt-api-for-gemini-nano` → Enabled
     - `#summarization-api-for-gemini-nano` → Enabled

3. **Restart Chrome**
   - Click "Relaunch" button

4. **Download AI Model**
   - Open DevTools (F12)
   - Run: `await ai.summarizer.create()`
   - Wait for model to download (~1-2 GB)
   - This only happens once

5. **Install Extension**
   - Go to `chrome://extensions`
   - Enable "Developer mode"
   - Click "Load unpacked"
   - Select the extension folder

## Verify It Works

1. Open any article
2. Click the SummarizeIt icon
3. Wait 10-30 seconds
4. See your summary!
```

## Reusable Code from Safari Version

### ✅ Can Reuse Directly
- `content.js` UI code (shadow DOM, panel, buttons)
- `readability.js` library
- `support.html` and `privacy.html` (with minor edits)
- Article extraction logic
- TTS implementation
- Language detection

### ❌ Cannot Reuse
- Swift code (SafariWebExtensionHandler.swift)
- Native messaging
- Apple Intelligence API calls
- Xcode project files

## Testing Checklist

- [ ] AI availability detection works
- [ ] Model downloads successfully
- [ ] Summarization works on various articles
- [ ] Sentiment analysis is accurate
- [ ] Multi-language support works
- [ ] TTS feature works
- [ ] Error messages are clear
- [ ] UI is responsive
- [ ] Works on different websites

## Distribution

### Chrome Web Store
1. Create developer account ($5 one-time fee)
2. Package extension as .zip
3. Upload to Chrome Web Store
4. Fill out listing details
5. Submit for review (1-3 days)

### Pricing
- Free (same as Safari version)
- No backend costs (on-device AI)

## Limitations to Document

1. **Desktop only** - Android support coming later in 2025
2. **Chrome 127+** - Older versions not supported
3. **Setup required** - Users must enable flags
4. **Model download** - 1-2 GB one-time download
5. **Experimental** - API may change

## Future Enhancements

1. **Automatic flag detection** - Guide users through setup
2. **Fallback to cloud API** - For unsupported devices
3. **Android support** - When Google releases it
4. **Better language detection** - Use Chrome's language API
5. **Offline mode indicator** - Show when AI is ready

## Estimated Development Time

- **Setup & structure**: 1 hour
- **Port Safari code**: 2-3 hours
- **AI integration**: 2-3 hours
- **Testing**: 2 hours
- **Documentation**: 1 hour
- **Total**: 8-10 hours

## Next Steps

1. Create new GitHub repo: `summarize-it-chrome`
2. Set up project structure
3. Copy reusable code from Safari version
4. Implement Chrome AI integration
5. Test on Chrome 127+
6. Create setup documentation
7. Submit to Chrome Web Store

Would you like me to help you get started with any specific part?
