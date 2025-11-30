# Future Optimization Ideas

These are additional optimizations you can implement if you need even better performance or want to add new features.

## 1. Smart Caching (High Impact)

### Implementation
```swift
// Add to SafariWebExtensionHandler.swift
private var summaryCache: [String: (summary: SummaryAndSentiment, timestamp: Date)] = [:]
private let cacheExpiryMinutes: TimeInterval = 30

func getCachedOrSummarize(url: String, text: String, language: String) async throws -> SummaryAndSentiment {
    let cacheKey = "\(url)_\(text.count)"
    
    if let cached = summaryCache[cacheKey],
       Date().timeIntervalSince(cached.timestamp) < cacheExpiryMinutes * 60 {
        return cached.summary
    }
    
    let result = try await summarizer.analyzeTextHierarchical(inputText: text, language: language)
    summaryCache[cacheKey] = (result, Date())
    return result
}
```

### Benefits
- Instant results for recently visited pages
- Reduces API calls by 50-70% for typical browsing
- Better battery life

## 2. Progressive Summarization (UX Improvement)

### Implementation
Show chunk summaries as they complete, then update with final summary.

```swift
// Add callback to HierarchicalSummarizer
var onChunkComplete: ((Int, Int, String) -> Void)?

// In chunk loop
for (idx, chunk) in chunks.enumerated() {
    let s = try await summarizeChunkAdaptive(...)
    chunkSummaries.append(s)
    onChunkComplete?(idx + 1, chunks.count, s)
}
```

### Benefits
- Users see progress
- Perceived performance improvement
- Can read partial results while waiting

## 3. Adaptive Chunk Sizing (Performance)

### Implementation
Adjust chunk size based on device performance.

```swift
private func getOptimalChunkSize() -> Int {
    let modelId = currentModelIdentifier()
    
    // M3 chips are faster
    if modelId.contains("Mac15") || modelId.contains("Mac16") {
        return 1500 // larger chunks on M3
    }
    // M2 chips
    else if modelId.contains("Mac14") {
        return 1200 // current default
    }
    // M1 or A17
    else {
        return 1000 // smaller chunks on older hardware
    }
}
```

### Benefits
- Optimal performance per device
- Better user experience across device range

## 4. Background Pre-Summarization (Major UX Improvement)

### Implementation
Start summarization when page loads, not when button clicked.

```javascript
// In content.js
let cachedSummary = null;

// Start extraction on page load
if (document.readyState === 'complete') {
    startBackgroundSummarization();
} else {
    window.addEventListener('load', startBackgroundSummarization);
}

function startBackgroundSummarization() {
    // Only for article-like pages
    if (looksLikeArticle()) {
        const { articleText, articleTitle } = extractArticle();
        browser.runtime.sendMessage({
            action: "sendArticleToSwift",
            articleText,
            articleTitle,
            background: true
        }).then(result => {
            cachedSummary = result;
        });
    }
}

function looksLikeArticle() {
    // Heuristic: has article tag or long text content
    return document.querySelector('article') || 
           document.body.textContent.length > 2000;
}
```

### Benefits
- Near-instant results when user clicks button
- Proactive summarization
- Much better perceived performance

## 5. Parallel Chunk Processing (Advanced)

### Implementation
Process multiple chunks in parallel (carefully).

```swift
// Process 2-3 chunks at a time
let maxParallel = 2
for i in stride(from: 0, to: chunks.count, by: maxParallel) {
    let batch = chunks[i..<min(i + maxParallel, chunks.count)]
    
    let results = try await withThrowingTaskGroup(of: (Int, String).self) { group in
        for (offset, chunk) in batch.enumerated() {
            group.addTask {
                let summary = try await self.summarizeChunkAdaptive(...)
                return (i + offset, summary)
            }
        }
        
        var summaries: [(Int, String)] = []
        for try await result in group {
            summaries.append(result)
        }
        return summaries.sorted { $0.0 < $1.0 }
    }
    
    chunkSummaries.append(contentsOf: results.map { $0.1 })
}
```

### Benefits
- 30-50% faster for large documents
- Better utilization of Neural Engine

### Risks
- May cause memory pressure
- Need careful testing
- May hit rate limits

## 6. Smart Text Extraction (Quality + Performance)

### Implementation
Better filtering of non-content text.

```javascript
// In content.js
function extractArticle() {
    // Remove common noise before Readability
    const noise = document.querySelectorAll(
        'nav, header, footer, aside, .comments, .related, .sidebar, .ad, [role="complementary"]'
    );
    noise.forEach(el => el.remove());
    
    // Then run Readability on cleaner DOM
    const parsed = new Readability(document.cloneNode(true)).parse();
    // ...
}
```

### Benefits
- Cleaner input = better summaries
- Fewer tokens = faster processing
- Less noise in output

## 7. Streaming API (If Available)

### Implementation
If Apple adds streaming support to Foundation Models:

```swift
func streamingSummarize(...) async throws -> AsyncStream<String> {
    AsyncStream { continuation in
        Task {
            for try await chunk in session.respondStreaming(...) {
                continuation.yield(chunk)
            }
            continuation.finish()
        }
    }
}
```

### Benefits
- Show results as they generate
- Much better perceived performance
- Can stop early if needed

## 8. Quality-Speed Trade-off Setting

### Implementation
Let users choose speed vs quality.

```swift
enum SummarizationMode {
    case fast      // fewer chunks, shorter summaries
    case balanced  // current settings
    case quality   // more overlap, longer summaries
}

func getSettings(for mode: SummarizationMode) -> (chunkSize: Int, overlap: Int, responseTokens: Int) {
    switch mode {
    case .fast:
        return (1500, 50, 300)
    case .balanced:
        return (1200, 100, 400)
    case .quality:
        return (900, 200, 600)
    }
}
```

### Benefits
- User control
- Can optimize for their use case
- Better satisfaction

## 9. Intelligent Language Detection

### Implementation
Use page metadata before falling back to NLLanguageRecognizer.

```swift
func detectLanguageOptimized(text: String, pageMetadata: [String: String]) -> String {
    // Check HTML lang attribute first
    if let htmlLang = pageMetadata["lang"],
       aiSupportedLanguageCodes().contains(htmlLang.lowercased()) {
        return englishDisplayName(for: htmlLang)
    }
    
    // Check meta tags
    if let metaLang = pageMetadata["content-language"],
       aiSupportedLanguageCodes().contains(metaLang.lowercased()) {
        return englishDisplayName(for: metaLang)
    }
    
    // Fall back to detection
    return detectSupportedLanguageName(inputText: text)
}
```

### Benefits
- Faster language detection
- More accurate
- Less processing

## 10. Memory-Efficient Chunking

### Implementation
Process and discard chunks instead of keeping all in memory.

```swift
func streamingHierarchicalSummarize(...) async throws -> SummaryAndSentiment {
    var runningContext = ""
    
    for chunk in chunks {
        let summary = try await summarizeChunk(chunk, ...)
        
        // Keep only last 2 summaries in context
        runningContext = combineWithContext(runningContext, summary, maxSummaries: 2)
    }
    
    return try await finalSummarize(runningContext, ...)
}
```

### Benefits
- Lower memory usage
- Better for very long documents
- More stable on older devices

## Priority Ranking

If you can only implement a few, prioritize:

1. **Smart Caching** - Biggest bang for buck, easy to implement
2. **Background Pre-Summarization** - Huge UX improvement
3. **Progressive Summarization** - Better perceived performance
4. **Adaptive Chunk Sizing** - Better cross-device performance
5. **Smart Text Extraction** - Better quality + performance

## Testing Strategy

For each optimization:

1. A/B test with current version
2. Measure actual performance improvement
3. Check summary quality doesn't degrade
4. Test on all supported devices
5. Monitor memory usage
6. Get user feedback

## Metrics to Track

- Average processing time by document size
- Cache hit rate (if caching implemented)
- User satisfaction scores
- Battery impact
- Memory usage
- Error/timeout rate
