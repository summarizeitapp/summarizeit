# Localized Error Messages & Aggressive Limits

## Changes Made

### 1. Localized Error Messages

Added support for error messages in the user's language:

**Supported Languages:**
- English
- Chinese (中文)
- Japanese (日本語)
- Korean (한국어)
- Spanish (Español)
- French (Français)
- German (Deutsch)

**Error Types:**

#### Context Window Error (Article Too Long)
- **English**: "Article too long to process. Apple Intelligence has limits on article length. Please try a shorter article."
- **Chinese**: "文章过长，无法处理。Apple Intelligence 对文章长度有限制。请尝试较短的文章。"
- **Japanese**: "記事が長すぎて処理できません。Apple Intelligenceには記事の長さに制限があります。短い記事をお試しください。"
- **Korean**: "기사가 너무 길어서 처리할 수 없습니다. Apple Intelligence는 기사 길이에 제한이 있습니다. 더 짧은 기사를 시도해 주세요."

#### Safety Filter Error (Sensitive Content)
- **English**: "Content blocked by Apple Intelligence safety filters. This article may contain sensitive content (violence, disasters, etc.) that cannot be processed."
- **Chinese**: "Apple Intelligence 安全过滤器阻止了此内容。该文章可能包含敏感内容（暴力、灾难等）无法处理。"
- **Japanese**: "Apple Intelligenceの安全フィルターがこのコンテンツをブロックしました。この記事には処理できない機密コンテンツ（暴力、災害など）が含まれている可能性があります。"
- **Korean**: "Apple Intelligence 안전 필터가 이 콘텐츠를 차단했습니다. 이 기사에는 처리할 수 없는 민감한 콘텐츠(폭력, 재해 등)가 포함되어 있을 수 있습니다."

### 2. More Aggressive Limits

To prevent context window errors, we've made the limits much more conservative:

#### Input Limits (content.js):
**Before:**
- CJK: 50,000 chars (~28K tokens)
- Mixed: 70,000 chars (~28K tokens)
- Latin: 100,000 chars (~25K tokens)

**After:**
- CJK: 35,000 chars (~19K tokens) ✅
- Mixed: 50,000 chars (~20K tokens) ✅
- Latin: 80,000 chars (~20K tokens) ✅

#### Chunk Configuration (SummarizationSvc.swift):
**Before:**
- Target chunk: 1000 tokens
- Prompt overhead: 900 tokens
- Overlap: 80 tokens

**After:**
- Target chunk: 800 tokens ✅
- Prompt overhead: 1000 tokens ✅
- Overlap: 50 tokens ✅

### 3. Better Error Detection

Now detects and handles three types of errors:

1. **Context Window Errors**
   - Detects: "context window", "token", "size"
   - Shows: Localized "article too long" message

2. **Safety Filter Errors**
   - Detects: "safety", "deny", "blocked"
   - Shows: Localized "content blocked" message

3. **Other Errors**
   - Shows: Generic error message

## Implementation

### Helper Function

```swift
func getLocalizedErrorMessage(for errorType: String, language: String) -> String {
    let lang = language.lowercased()
    
    switch errorType {
    case "context_window":
        if lang.contains("chinese") || lang.contains("中文") {
            return "文章过长，无法处理。Apple Intelligence 对文章长度有限制。请尝试较短的文章。"
        }
        // ... other languages
        
    case "safety_filter":
        if lang.contains("chinese") || lang.contains("中文") {
            return "Apple Intelligence 安全过滤器阻止了此内容。该文章可能包含敏感内容（暴力、灾难等）无法处理。"
        }
        // ... other languages
    }
}
```

### Error Handling

```swift
let errorStr = String(describing: error)
let isContextError = errorStr.contains("context window") || errorStr.contains("token")
let isSafetyError = errorStr.contains("safety") || errorStr.contains("deny")

if isContextError {
    errorMsg = getLocalizedErrorMessage(for: "context_window", language: languageName)
} else if isSafetyError {
    errorMsg = getLocalizedErrorMessage(for: "safety_filter", language: languageName)
}
```

## Expected Behavior

### For the BBC Fire Article:

**Before:**
```
Input: 50,000 chars
Result: "Exceeded model context window size"
Language: English (wrong)
```

**After:**
```
Input: 35,000 chars (truncated)
Result: Should work, or if still too long:
"文章过长，无法处理。Apple Intelligence 对文章长度有限制。请尝试较短的文章。"
Language: Chinese (correct)
```

## Why These Limits?

### Token Budget Breakdown:

```
Total context window: 4096 tokens

Per chunk:
- Prompt overhead: 1000 tokens
- Input text: 800 tokens
- Response: 250 tokens
- Safety margin: 100 tokens
Total: 2150 tokens (well under 4096)

For 35K char CJK article:
- Estimated tokens: 35000 / 1.8 = 19,444 tokens
- Chunks needed: 19444 / 800 = 24 chunks
- But we limit to 15 chunks max
- So we process: 15 × 800 = 12,000 tokens
- Actual chars processed: 12000 × 1.8 = 21,600 chars
```

### Trade-offs:

**Pros:**
- ✅ Much more reliable
- ✅ Fewer context errors
- ✅ Faster processing (fewer chunks)
- ✅ Better user experience

**Cons:**
- ⚠️ Very long articles truncated more aggressively
- ⚠️ May miss content beyond 35K chars for CJK
- ⚠️ Some users may want longer summaries

## Testing

### Test the BBC Article Again:

1. **Open**: https://www.bbc.com/zhongwen/articles/clykevkpvz7o/simp
2. **Click**: Summarize
3. **Expected**: One of two outcomes:
   - ✅ Success: Summary generated
   - ✅ Clear error in Chinese: "文章过长，无法处理..."

### Test Other Languages:

**Japanese:**
```
https://www3.nhk.or.jp/news/
```

**Korean:**
```
https://www.yonhapnews.co.kr/
```

**Spanish:**
```
https://elpais.com/
```

Should see localized error messages if articles are too long.

## Configuration Summary

```javascript
// content.js - Input Limits
CJK text: 35,000 chars (~19K tokens)
Mixed text: 50,000 chars (~20K tokens)
Latin text: 80,000 chars (~20K tokens)

// SummarizationSvc.swift - Chunking
Target chunk: 800 tokens
Prompt overhead: 1000 tokens
Overlap: 50 tokens
Max chunks: 15

// Timeouts
Chunk: 90 seconds
Final: 120 seconds
Native messaging: 240 seconds
```

## If Still Having Issues

### Further Reduce Limits:

```javascript
// content.js
if (cjkRatio > 0.3) {
    maxChars = 25000;  // Even more conservative
}
```

```swift
// SummarizationSvc.swift
private let defaultTargetChunkTokens: Int = 600  // Smaller chunks
private let promptOverheadTokens: Int = 1100     // More buffer
```

### Reduce Max Chunks:

```swift
let maxChunks = 12  // Process less content
```

## Adding More Languages

To add support for more languages:

```swift
func getLocalizedErrorMessage(for errorType: String, language: String) -> String {
    let lang = language.lowercased()
    
    switch errorType {
    case "context_window":
        // Add new language
        if lang.contains("italian") || lang.contains("italiano") {
            return "L'articolo è troppo lungo per essere elaborato..."
        }
        // ... existing languages
    }
}
```

## Files Modified

1. **SafariWebExtensionHandler.swift**
   - Added `getLocalizedErrorMessage()` function
   - Updated error handling to detect error types
   - Returns localized messages based on detected language

2. **SummarizationSvc.swift**
   - Reduced `defaultTargetChunkTokens`: 1000 → 800
   - Increased `promptOverheadTokens`: 900 → 1000
   - Reduced `defaultOverlapTokens`: 80 → 50

3. **content.js**
   - Reduced CJK limit: 50K → 35K chars
   - Reduced mixed limit: 70K → 50K chars
   - Reduced Latin limit: 100K → 80K chars

## Benefits

1. **Better User Experience**
   - Users see errors in their own language
   - Clear explanation of what went wrong
   - Actionable advice (try shorter article)

2. **More Reliable**
   - Fewer context window errors
   - More predictable behavior
   - Faster processing

3. **Professional**
   - Shows attention to internationalization
   - Respects user's language preference
   - Better than generic English errors

## Limitations

### Cannot Bypass Apple's Restrictions

We **cannot**:
- ❌ Bypass safety filters
- ❌ Increase context window size
- ❌ Process blocked content
- ❌ Override Apple's limits

We **can**:
- ✅ Detect errors and explain them
- ✅ Provide localized messages
- ✅ Optimize within constraints
- ✅ Set realistic expectations

### Guardrails Are Intentional

Apple's safety filters are:
- Part of responsible AI design
- Required for App Store approval
- Cannot be disabled by developers
- Apply to all Foundation Models apps

## Summary

The BBC fire article should now either:
1. **Work** (if 35K chars is enough after truncation)
2. **Show clear Chinese error** (if still too long)

Either way, users get a professional, localized experience instead of cryptic errors.
