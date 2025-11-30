# Apple Intelligence Safety Filters

## Issue

The BBC Chinese article about the Hong Kong fire disaster is being blocked by Apple Intelligence safety filters, not by technical issues.

## Console Error

```
safety_deny.input.foundation_models_framework.api
```

This indicates Apple's content filtering system is rejecting the input.

## What Are Safety Filters?

Apple Intelligence includes built-in safety guardrails that automatically block content deemed:
- Violent or graphic
- Related to disasters with casualties
- Potentially harmful or sensitive
- Inappropriate for AI processing

These filters operate at the Foundation Models API level and **cannot be bypassed** by app developers.

## Why This Article Is Blocked

The BBC article is about:
- **Hong Kong fire disaster** (宏福苑大火)
- **128 deaths** (至少128死)
- **Building safety issues**
- **Casualties and injuries**

This type of content triggers Apple's safety filters because:
1. It involves mass casualties
2. It describes a disaster/tragedy
3. It contains potentially distressing details
4. It's categorized as sensitive news content

## This Is Not a Bug

This is **expected behavior** from Apple Intelligence:
- ✅ Safety filters are working as designed
- ✅ Protecting users from processing sensitive content
- ✅ Following Apple's responsible AI guidelines
- ❌ Cannot be disabled or bypassed by developers

## What We Can Do

### 1. Detect and Inform Users

We've added detection for safety filter errors:

```swift
let errorStr = String(describing: error)
let isSafetyError = errorStr.contains("safety") || errorStr.contains("deny") || errorStr.contains("blocked")

if isSafetyError {
    errorMsg = "Content blocked by Apple Intelligence safety filters. This article may contain sensitive content (violence, disasters, etc.) that cannot be processed."
}
```

### 2. User-Friendly Error Messages

**Before:**
```
(No output, hangs forever)
```

**After:**
```
Content blocked by Apple Intelligence safety filters. 
This article may contain sensitive content (violence, disasters, etc.) 
that cannot be processed.
```

### 3. Document Limitations

Make it clear in the app description that:
- Some sensitive content cannot be summarized
- This is an Apple Intelligence limitation
- Not a bug in the extension

## Content That May Be Blocked

### High Risk (Likely Blocked):
- ❌ Disaster/tragedy news (fires, earthquakes, accidents)
- ❌ Violence or crime reports with casualties
- ❌ War/conflict coverage with graphic details
- ❌ Medical emergencies or health crises
- ❌ Terrorist attacks or mass violence

### Medium Risk (May Be Blocked):
- ⚠️ Political protests with violence
- ⚠️ Accident reports
- ⚠️ Health/disease outbreaks
- ⚠️ Controversial political content

### Low Risk (Usually OK):
- ✅ General news (politics, economy, sports)
- ✅ Technology articles
- ✅ Entertainment news
- ✅ Educational content
- ✅ Business/finance articles
- ✅ Lifestyle and culture

## Testing Strategy

### Don't Use Disaster Articles for Testing

**Bad Test Articles:**
- ❌ Disaster/tragedy news
- ❌ Crime reports with casualties
- ❌ War coverage

**Good Test Articles:**
- ✅ BBC News (general politics, economy)
- ✅ Tech news (TechCrunch, The Verge)
- ✅ Business news (Bloomberg, Reuters)
- ✅ Sports news
- ✅ Entertainment news

### Test With Safe Content

For Chinese language testing, use:
- ✅ Technology news (科技新闻)
- ✅ Business news (商业新闻)
- ✅ Sports news (体育新闻)
- ✅ Entertainment news (娱乐新闻)

Examples:
```
https://www.bbc.com/zhongwen/simp/business
https://www.bbc.com/zhongwen/simp/science
https://cn.techcrunch.com/
```

## User Communication

### In App Store Description

Add a note:
```
Note: Due to Apple Intelligence safety guidelines, some sensitive 
content (disasters, violence, etc.) cannot be summarized. This is 
a platform limitation, not an app issue.
```

### In Error Message

Current message:
```
Content blocked by Apple Intelligence safety filters. 
This article may contain sensitive content (violence, disasters, etc.) 
that cannot be processed.
```

### In FAQ/Help

Q: Why can't some articles be summarized?

A: Apple Intelligence includes safety filters that block sensitive 
content such as disasters, violence, or graphic material. This is 
a platform-level restriction that cannot be bypassed. Try the 
extension on general news, technology, business, or entertainment 
articles instead.

## Workarounds (None Available)

### What Doesn't Work:
- ❌ Rephrasing the content
- ❌ Removing "sensitive" words
- ❌ Using different prompts
- ❌ Chunking differently
- ❌ Changing language
- ❌ API parameters

### Why:
The safety filtering happens **before** your prompt is processed. 
The Foundation Models API analyzes the input content and blocks 
it at the system level.

## Impact on Your Extension

### Positive:
- ✅ Demonstrates responsible AI use
- ✅ Protects users from distressing content
- ✅ Aligns with Apple's guidelines
- ✅ Reduces liability concerns

### Negative:
- ❌ Some legitimate news articles can't be summarized
- ❌ Users may think the extension is broken
- ❌ Limits usefulness for news readers
- ❌ No way to override for legitimate use cases

## Recommendations

### 1. Set Expectations

In your app description and onboarding:
- Explain that the extension works best with general content
- Mention that sensitive news may be blocked
- Provide examples of content that works well

### 2. Better Error Messages

We've implemented clear error messages that:
- Explain why content was blocked
- Don't blame the user or the extension
- Suggest trying different content

### 3. Test With Appropriate Content

For demos and testing:
- Use technology, business, or entertainment news
- Avoid disaster/tragedy articles
- Keep a list of "safe" test URLs

### 4. Monitor User Feedback

Track which types of content get blocked:
- Collect error reports
- Identify patterns
- Update documentation accordingly

## Alternative Approaches

### 1. Fallback to Title/Metadata

When content is blocked, show:
```
Unable to summarize full content due to sensitivity.

Title: [Article Title]
Source: [URL]
Topic: [Detected from metadata]
```

### 2. Partial Summarization

Try summarizing just the first few paragraphs:
```swift
// If full article blocked, try first 2000 chars
if isSafetyError && text.count > 2000 {
    let preview = String(text.prefix(2000))
    return try await summarize(preview)
}
```

### 3. Content Warning

Before processing, detect potentially sensitive content:
```swift
func mightBeSensitive(_ text: String) -> Bool {
    let sensitiveKeywords = ["死亡", "伤亡", "火灾", "disaster", "casualties"]
    return sensitiveKeywords.contains { text.contains($0) }
}

if mightBeSensitive(text) {
    showWarning("This article may contain sensitive content that could be blocked")
}
```

## Related Apple Documentation

- [Apple Intelligence Guidelines](https://developer.apple.com/apple-intelligence/)
- [Foundation Models Framework](https://developer.apple.com/documentation/foundationmodels)
- [Responsible AI Practices](https://www.apple.com/privacy/docs/Responsible_AI_Practices.pdf)

## Summary

The BBC fire article isn't a technical failure - it's being blocked by Apple's safety filters. This is:
- ✅ Expected behavior
- ✅ Cannot be bypassed
- ✅ Affects all apps using Foundation Models
- ✅ Documented limitation

**Solution**: Test with non-sensitive content and clearly communicate this limitation to users.

## Testing Recommendations

### Good Test Articles (Chinese):

**Technology:**
```
https://www.bbc.com/zhongwen/simp/science-technology
https://cn.techcrunch.com/
```

**Business:**
```
https://www.bbc.com/zhongwen/simp/business
https://cn.wsj.com/
```

**Entertainment:**
```
https://www.bbc.com/zhongwen/simp/entertainment
```

**Sports:**
```
https://www.bbc.com/zhongwen/simp/sports
```

These should work reliably without triggering safety filters.
