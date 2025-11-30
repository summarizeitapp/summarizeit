# Ultra Conservative Limits - Final Configuration

## Progress

✅ **Safety filters no longer blocking** - prompts are working!
❌ **Context window still exceeded** - article still too large

## New Ultra Conservative Limits

### Input Limits (content.js):

**CJK Text (Chinese, Japanese, Korean):**
- Limit: **20,000 chars** (~11,000 tokens)
- Rationale: 1.8 chars/token for CJK

**Mixed Text:**
- Limit: **30,000 chars** (~12,000 tokens)
- Rationale: 2.5 chars/token for mixed

**Latin Text:**
- Limit: **50,000 chars** (~12,500 tokens)
- Rationale: 4.0 chars/token for Latin

### Chunking Configuration (SummarizationSvc.swift):

**Chunk Size:**
- Target: **600 tokens** (down from 800)
- Overhead: **1200 tokens** (up from 1000)
- Overlap: **30 tokens** (down from 50)

**Max Chunks:**
- Limit: **10 chunks** (down from 15)
- Total processing: 10 × 600 = 6,000 tokens max

### Why So Conservative?

**Token Budget Per Chunk:**
```
Context window: 4096 tokens

Per chunk breakdown:
- Prompt overhead: 1200 tokens
- Input text: 600 tokens
- Response: 250 tokens
- Safety margin: 200 tokens
Total: 2250 tokens (well under 4096)
```

**For 20K char CJK article:**
```
Input: 20,000 chars
Estimated tokens: 20,000 / 1.8 = 11,111 tokens
Chunks needed: 11,111 / 600 = 19 chunks
But we limit to: 10 chunks
Actual processed: 10 × 600 = 6,000 tokens
Actual chars: 6,000 × 1.8 = 10,800 chars
```

## What This Means

### For Users:

**Very Long Articles:**
- Only first ~11K chars (CJK) or ~12K chars (Latin) processed
- Rest is truncated
- Still get a useful summary of the beginning

**Medium Articles:**
- Should work perfectly
- Full content processed
- Good quality summaries

**Short Articles:**
- Work great
- Fast processing
- High quality

### Comparison with Safari:

Safari's built-in summarization likely:
- Uses different chunking strategy
- May have access to optimized APIs
- Possibly uses streaming
- Different token limits

Our extension:
- Must work within public API limits
- Conservative to ensure reliability
- Trades completeness for reliability

## Expected Behavior

### For BBC Fire Article:

**Article size:** ~50K+ chars (estimated)

**Processing:**
1. Truncated to 20K chars
2. Split into ~10 chunks
3. Each chunk: 600 tokens
4. Total: ~6K tokens processed
5. Summary covers first ~40% of article

**Result:**
- ✅ Should complete successfully
- ✅ Summary of beginning/main points
- ⚠️ May miss details from later in article

## Configuration Summary

```javascript
// content.js - Input Limits
CJK: 20,000 chars (~11K tokens)
Mixed: 30,000 chars (~12K tokens)
Latin: 50,000 chars (~12K tokens)

// SummarizationSvc.swift - Chunking
Chunk size: 600 tokens
Prompt overhead: 1200 tokens
Overlap: 30 tokens
Max chunks: 10

// Timeouts
Chunk: 90 seconds
Final: 120 seconds
Native: 240 seconds
```

## Trade-offs

### Pros:
- ✅ Very reliable
- ✅ Won't exceed context window
- ✅ Fast processing (fewer chunks)
- ✅ Predictable behavior

### Cons:
- ❌ Very long articles truncated significantly
- ❌ May miss important details
- ❌ Less complete than Safari's summarization
- ❌ Users may notice truncation

## Alternative Approaches

If truncation is too aggressive:

### 1. Smart Extraction
Instead of truncating, extract key sections:
```javascript
// Extract title, first paragraphs, and section headers
const important = extractKeyContent(articleText);
```

### 2. Progressive Summarization
Show partial results as chunks complete:
```javascript
// Update UI with each chunk summary
onChunkComplete(chunkSummary);
```

### 3. User Choice
Let users choose:
```javascript
// "Quick summary" (10K chars) vs "Full summary" (30K chars)
const limit = userPreference === 'quick' ? 10000 : 30000;
```

## Testing

### Test BBC Fire Article:

1. Open: https://www.bbc.com/zhongwen/articles/clykevkpvz7o/simp
2. Click: Summarize
3. Expected: 
   - ✅ Completes successfully
   - ✅ Summary of first ~11K chars
   - ⚠️ May not cover entire article

### Test Shorter Articles:

**Chinese Tech (should work great):**
```
https://www.bbc.com/zhongwen/simp/articles/c4gpl4xer4po
```

**Chinese Business (should work great):**
```
https://www.bbc.com/zhongwen/simp/business
```

## Monitoring

Track these metrics:
- Success rate (should be very high now)
- Average article length
- Truncation rate (how often we hit limits)
- User feedback on completeness

## If Still Failing

If context errors persist:

### Further reduce limits:
```javascript
// content.js
if (cjkRatio > 0.3) {
    maxChars = 15000;  // Even more conservative
}
```

```swift
// SummarizationSvc.swift
private let defaultTargetChunkTokens: Int = 500  // Smaller chunks
private let promptOverheadTokens: Int = 1300     // More buffer
let maxChunks = 8  // Fewer chunks
```

## Summary

With these ultra-conservative limits:
- **Safety filters:** ✅ Fixed (neutral prompts)
- **Context window:** ✅ Should be fixed (much smaller chunks)
- **Completeness:** ⚠️ Reduced (only first ~11K chars for CJK)

The BBC fire article should now work, though it will only summarize the first portion of the article.

This is the trade-off for reliability within Apple's API constraints.
