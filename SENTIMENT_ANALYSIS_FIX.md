# Sentiment Analysis Fix

## Problem

War/conflict articles were showing "Neutral" sentiment when they should be "Negative".

**Example:**
- Article: Ukraine war - Russia attacks Kyiv and energy sector
- Expected: Negative
- Got: Neutral ❌

## Root Cause

Sentiment was analyzed on the **final summary** instead of the **original content**.

### The Issue:

```
Original text → Summarize chunks → Combine summaries → Final summary → Analyze sentiment
                    ↓                      ↓                ↓              ↓
                Neutral tone          Neutral tone     Neutral tone    "Neutral" ❌
```

**Why this happens:**
1. Summarization naturally neutralizes emotional language
2. Summaries use factual, objective tone
3. "Russia attacks Ukraine" becomes "Conflict continues"
4. Sentiment analysis on neutral summary = "Neutral"

## Solution

Analyze sentiment on **original text** (first chunk) before summarization neutralizes it.

### New Flow:

```
Original text → Analyze sentiment (from first chunk)
                    ↓
                "Negative" ✅

Original text → Summarize chunks → Combine → Final summary
                                                  ↓
                                    Return: (summary, sentiment)
```

## Implementation

### Before:

```swift
// 4) Final summary
let finalSummary = try await summarizeStitchedSummaries(...)

// 5) Sentiment from final summary ❌
let final = try await summaryAndSentiment(from: finalSummary, ...)
```

### After:

```swift
// 4) Sentiment from ORIGINAL first chunk ✅
let sentimentText = chunks[0]  // Original text, not summary
let sentiment = try await detectSentiment(from: sentimentText, ...)

// 5) Final summary (just text, no sentiment)
let finalSummary = try await summarizeStitchedSummaries(...)

return SummaryAndSentiment(summaryText: finalSummary, sentiment: sentiment)
```

### New Function:

```swift
private func detectSentiment(from text: String, language: String) async throws -> String {
    let prompt = "Classify the sentiment of this text as Positive, Neutral, or Negative:\n\n\(text)"
    
    let result = try await session.respond(generating: String.self) { prompt }.content
    
    // Extract sentiment
    if result.lowercased().contains("positive") {
        return "Positive"
    } else if result.lowercased().contains("negative") {
        return "Negative"
    } else {
        return "Neutral"
    }
}
```

## Why This Works

### Original Text Preserves Emotion:

**War article first chunk:**
```
"Russia attacks Kyiv and energy infrastructure. 
Explosions reported. Civilians killed. 
Emergency services responding to damage."
```
→ Sentiment: **Negative** ✅

**After summarization:**
```
"Russia conducted military operations in Kyiv 
targeting energy infrastructure."
```
→ Sentiment: **Neutral** ❌

### Benefits:

1. **Accurate sentiment** - Captures emotional tone of original content
2. **Fast** - Only analyzes first chunk (~700 tokens)
3. **Reliable** - Before neutralization happens
4. **Consistent** - Works for all article types

## Expected Results

### War/Conflict Articles:
- **Before**: Neutral
- **After**: Negative ✅

### Disaster Articles:
- **Before**: Neutral
- **After**: Negative ✅

### Economic Crisis:
- **Before**: Neutral
- **After**: Negative ✅

### Positive News (achievements, breakthroughs):
- **Before**: Neutral
- **After**: Positive ✅

### Factual Reports (statistics, data):
- **Before**: Neutral
- **After**: Neutral ✅ (correct)

## Testing

### Test Articles:

**Negative (should be Negative):**
```
https://www.dw.com/de/ukrainekrieg-russland-greift-kyjiw-und-energiesektor-an/a-74949258
https://www.bbc.com/news (disaster/conflict articles)
```

**Positive (should be Positive):**
```
Technology breakthroughs
Scientific discoveries
Economic growth reports
```

**Neutral (should be Neutral):**
```
Statistical reports
Factual announcements
Routine updates
```

## Trade-offs

### Pros:
- ✅ More accurate sentiment
- ✅ Captures emotional tone
- ✅ Works for all article types
- ✅ Fast (only first chunk)

### Cons:
- ⚠️ Sentiment based on beginning of article
- ⚠️ May miss sentiment shift later in article
- ⚠️ First chunk might not be representative

### Why This is OK:

1. **News structure**: Most important info (and tone) is at the beginning
2. **Inverted pyramid**: Emotional impact is usually in the lead
3. **Consistency**: Better to be consistent than occasionally more accurate
4. **Speed**: Analyzing entire article would be too slow

## Alternative Approaches Considered

### 1. Average Sentiment Across Chunks
```swift
// Analyze each chunk, average results
let sentiments = chunks.map { detectSentiment($0) }
let avgSentiment = mostCommon(sentiments)
```
**Rejected**: Too slow, summaries still neutralize

### 2. Sentiment from Multiple Chunks
```swift
// Analyze first 3 chunks
let sentiments = chunks.prefix(3).map { detectSentiment($0) }
let sentiment = mostCommon(sentiments)
```
**Rejected**: Slower, diminishing returns

### 3. Sentiment Keywords
```swift
// Count positive/negative keywords
let score = countKeywords(text)
```
**Rejected**: Not language-aware, less accurate

## Files Modified

**SummarizationSvc.swift:**
- Added `detectSentiment()` function
- Changed sentiment analysis to use original first chunk
- Removed sentiment from final summary step

## Summary

Sentiment is now analyzed on **original content** (first chunk) before summarization neutralizes the emotional tone. This provides much more accurate sentiment classification for news articles, especially negative news like wars, disasters, and crises.

**Test the Ukraine war article now** - it should show "Negative" sentiment instead of "Neutral".
