# Safari-Compatible Prompts

## Key Discovery

Safari's built-in summarization (iOS 18+) successfully summarizes the BBC fire article, which means:
- ✅ The content itself is NOT blocked
- ✅ Apple allows summarization of news articles
- ❌ Our prompts/instructions were triggering safety filters

## Root Cause

The safety filters were likely triggered by:
1. **System instructions**: "Concise, factual summarizer" might flag content analysis
2. **Detailed prompts**: Explicit instructions about facts, numbers, sentiment
3. **Structured output**: Requesting specific format might trigger analysis mode

## Solution: Minimal, Neutral Prompts

Changed to extremely simple prompts similar to what Safari likely uses:

### Before (Triggered Safety Filters):

```swift
// Session
LanguageModelSession(instructions: {
    "Concise, factual summarizer."
})

// Prompt
"""
Summarize in Chinese (4-6 sentences). Preserve key facts and numbers.

Chunk:
[text]
"""
```

### After (Safari-Compatible):

```swift
// Session - NO instructions
LanguageModelSession()

// Prompt - Minimal
"""
Summarize the following text in Chinese:

[text]
"""
```

## All Prompt Changes

### 1. Session Instructions
**Before**: `"Concise, factual summarizer."`
**After**: None (empty)

### 2. Chunk Summarization
**Before**: `"Summarize in Chinese (4-6 sentences). Preserve key facts and numbers."`
**After**: `"Summarize the following text in Chinese:"`

### 3. Stitched Summaries
**Before**: `"Synthesize these chunk summaries into one cohesive summary in Chinese (6-8 sentences). Include key facts and numbers."`
**After**: `"Combine these summaries into one summary in Chinese:"`

### 4. Final Summary + Sentiment
**Before**: `"Polish this summary (4-6 sentences in Chinese). Classify sentiment: Positive, Neutral, or Negative."`
**After**: `"Refine this summary in Chinese and classify sentiment as Positive, Neutral, or Negative:"`

### 5. Single-Shot
**Before**: `"Summarize in Chinese (4-6 sentences). Classify sentiment: Positive, Neutral, or Negative."`
**After**: `"Summarize the following text in Chinese and classify its sentiment as Positive, Neutral, or Negative:"`

## Why This Works

### Safari's Approach:
- Minimal system instructions
- Simple, direct prompts
- No explicit content analysis instructions
- Lets the model decide how to summarize

### Our Old Approach:
- Explicit system role ("summarizer")
- Detailed instructions (preserve facts, numbers)
- Specific format requirements (4-6 sentences)
- Might trigger "content analysis" safety checks

## Expected Behavior

### For BBC Fire Article:

**Before:**
```
Safety filter blocks on first chunk
Error: "Apple Intelligence 安全过滤器阻止了此内容..."
```

**After:**
```
✅ Processes successfully
✅ Generates summary
✅ Works like Safari's built-in feature
```

## Trade-offs

### Pros:
- ✅ Works with sensitive news content
- ✅ Compatible with Safari's approach
- ✅ Less likely to trigger safety filters
- ✅ Simpler prompts = faster processing

### Cons:
- ⚠️ Less control over output format
- ⚠️ May get longer/shorter summaries
- ⚠️ Less explicit about preserving facts
- ⚠️ Model decides summary style

## Testing

### Test the BBC Fire Article Again:

1. **Open**: https://www.bbc.com/zhongwen/articles/clykevkpvz7o/simp
2. **Click**: Summarize
3. **Expected**: Should now work and generate summary

### Compare with Safari:

1. Open same article in Safari
2. Use Safari's built-in "Summarize" (iOS 18+)
3. Compare output with your extension
4. Should be similar quality

## Implementation Details

### No System Instructions

```swift
// Old
self.session = LanguageModelSession(instructions: {
    "Concise, factual summarizer."
})

// New - matches Safari's likely approach
self.session = LanguageModelSession()
```

### Minimal Prompts

```swift
// Just state what you want, no detailed instructions
let prompt = "Summarize the following text in \(language):\n\n\(text)"
```

### Let Model Decide

- Don't specify sentence count
- Don't specify what to preserve
- Don't specify format details
- Trust the model's training

## Why Safari Works

Safari's summarization likely:
1. Uses no/minimal system instructions
2. Uses simple prompts
3. Doesn't trigger "content analysis" mode
4. Treats all content neutrally

By matching this approach, we avoid safety filter triggers.

## Files Modified

**SummarizationSvc.swift:**
- Removed session instructions
- Simplified all prompts
- Removed explicit formatting requirements
- Removed "preserve facts" instructions

## Monitoring

After this change, monitor:
- Success rate on news articles
- Summary quality (may vary more)
- Length of summaries (less controlled)
- User feedback

## If Issues Persist

If safety filters still trigger:

1. **Remove sentiment analysis**:
   ```swift
   // Just summarize, don't analyze sentiment
   "Summarize the following text in \(language):"
   ```

2. **Use even simpler language**:
   ```swift
   "Summary in \(language):"
   ```

3. **Remove language specification**:
   ```swift
   "Summarize:"
   ```

## Summary

By using minimal, neutral prompts similar to Safari's approach, we should be able to summarize the same content that Safari can handle, including news articles about disasters.

The key insight: **It's not what you summarize, it's how you ask for it.**

Test the BBC fire article now - it should work!
