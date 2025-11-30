# Testing Checklist

## Quick Reference: Where to Test What

| Test Type | macOS Safari | iOS Simulator | Real iPhone/iPad |
|-----------|--------------|---------------|------------------|
| **Summarization** | ✅ Works | ❌ Fails (expected) | ✅ Works |
| **Performance** | ✅ Accurate | ❌ N/A | ✅ Accurate |
| **UI/UX** | ✅ Works | ✅ Works | ✅ Works |
| **Text Extraction** | ✅ Works | ✅ Works | ✅ Works |
| **Error Handling** | ✅ Works | ✅ Works | ✅ Works |
| **Language Detection** | ✅ Works | ⚠️ Detects but can't summarize | ✅ Works |

## Pre-Release Testing Checklist

### Phase 1: Development (macOS Safari)
- [ ] Extension loads without errors
- [ ] Text extraction works on various websites
- [ ] Short articles (< 2000 words) summarize in 5-10s
- [ ] Medium articles (2000-5000 words) summarize in 12-25s
- [ ] Long articles (5000+ words) summarize in 30-60s
- [ ] Language detection works for English
- [ ] Language detection works for other supported languages
- [ ] Sentiment classification is reasonable
- [ ] Error messages are clear
- [ ] Copy button works
- [ ] Share button works
- [ ] Close button works
- [ ] ESC key closes panel

### Phase 2: iOS Simulator (UI Only)
- [ ] Extension loads without errors
- [ ] Shows clear error: "Foundation Models not available in simulator"
- [ ] Language is detected (not "undefined")
- [ ] Error message is user-friendly
- [ ] UI elements render correctly
- [ ] Popup layout looks good on iPhone screen
- [ ] No console errors (except expected model unavailable)

### Phase 3: Real iPhone (Full Testing)
- [ ] Extension loads without errors
- [ ] Text extraction works
- [ ] Summarization completes successfully
- [ ] Performance is acceptable (see targets below)
- [ ] Language detection works
- [ ] Sentiment classification works
- [ ] UI looks good on device
- [ ] Copy button works
- [ ] Share sheet works on iOS
- [ ] No crashes or hangs
- [ ] Battery usage is reasonable

### Phase 4: Real iPad (Full Testing)
- [ ] Extension loads without errors
- [ ] Text extraction works
- [ ] Summarization completes successfully
- [ ] Performance is acceptable
- [ ] UI scales well to iPad screen
- [ ] All functionality works

## Performance Targets

### Small Articles (< 2000 words / ~500 tokens)
- **Target**: 5-10 seconds
- **Acceptable**: Up to 15 seconds
- **Issue if**: > 20 seconds

### Medium Articles (2000-5000 words / ~2000 tokens)
- **Target**: 12-25 seconds
- **Acceptable**: Up to 35 seconds
- **Issue if**: > 45 seconds

### Large Articles (5000+ words / ~5000+ tokens)
- **Target**: 30-60 seconds
- **Acceptable**: Up to 90 seconds
- **Issue if**: > 120 seconds or timeout

## Test URLs

### Short Articles (Quick Tests)
```
https://www.bbc.com/news (most articles)
https://techcrunch.com (most articles)
```

### Medium Articles
```
https://arstechnica.com (most articles)
https://www.theverge.com (most articles)
```

### Long Articles
```
https://www.newyorker.com (long-form)
https://www.theatlantic.com (long-form)
```

### Multi-Language
```
https://www.lemonde.fr (French)
https://www.spiegel.de (German)
https://elpais.com (Spanish)
```

## Common Issues & Solutions

### Issue: "Language: undefined"
**Status**: ✅ Fixed
**Solution**: Language now defaults to "English" if detection fails

### Issue: "Unexpected error" on simulator
**Status**: ✅ Fixed
**Solution**: Now shows clear message about simulator limitations

### Issue: Slow on first run
**Status**: ⚠️ Expected behavior
**Solution**: Cold start of Foundation Models, subsequent runs faster

### Issue: Timeout on very long articles
**Status**: ✅ Improved
**Solution**: Hierarchical reduction, increased timeouts

### Issue: Summary too short
**Status**: ⚠️ By design
**Solution**: Increase `responseTokensBudgetFinal` if needed

## Device Requirements

### Minimum Requirements
- **iPhone**: 15 Pro or newer (A17 Pro+)
- **iPad**: Any with M1 or newer chip
- **Mac**: Any with M1 or newer chip
- **iOS**: 18.0+
- **macOS**: 15.0+

### Optimal Performance
- **iPhone**: 16 Pro (A18 Pro)
- **iPad**: M2 or newer
- **Mac**: M3 or M4

## Sign-Off Checklist

Before submitting to App Store:

- [ ] Tested on macOS (M1/M2/M3/M4)
- [ ] Tested on real iPhone 15 Pro or newer
- [ ] Tested on real iPad with M-series chip
- [ ] All performance targets met
- [ ] No crashes or hangs
- [ ] Error messages are user-friendly
- [ ] Privacy policy updated (local processing)
- [ ] App Store description mentions device requirements
- [ ] Screenshots from real devices (not simulator)
- [ ] TestFlight beta testing completed
- [ ] User feedback addressed

## Regression Testing

After any code changes, re-test:

- [ ] Basic summarization still works
- [ ] Performance hasn't degraded
- [ ] Error handling still works
- [ ] UI still renders correctly
- [ ] No new console errors

## Automated Testing (Future)

Consider adding:
- Unit tests for chunking logic
- Unit tests for token estimation
- Integration tests with mock responses
- UI tests for extension popup
- Performance benchmarks

## Notes

- Always test on **real devices** for actual functionality
- Simulator is **only** for UI testing
- macOS Safari is best for **development iteration**
- Keep test articles bookmarked for quick regression testing
- Monitor App Store reviews for real-world issues
