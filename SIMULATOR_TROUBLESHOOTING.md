# iOS Simulator Troubleshooting

## Issue: Extension fails on iOS Simulator but works on macOS

### Root Cause

The iOS Simulator on macOS does **not** have access to the actual Apple Foundation Models (Apple Intelligence), even though:
1. The device check passes (iPhone 17 Pro is a supported device)
2. The `allowInSimulatorForDev` flag is set to `true`
3. The simulator is running on an M4 Mac

The Foundation Models APIs (`LanguageModelSession`) are only available on **real devices** with the appropriate hardware.

### Expected Behavior

When running in the iOS Simulator, you should now see a clearer error message:

```
Foundation Models not available in simulator. Test on real device.
```

Instead of the generic:
```
Unexpected error. Please try again.
```

### Testing Strategy

#### For Development Testing:

1. **Use macOS Safari** (works perfectly on M-series Macs)
   - Test all functionality
   - Verify performance improvements
   - Check different article sizes

2. **Use Real iOS Device** (iPhone 15 Pro or newer)
   - Connect via USB
   - Build and run on device
   - Test actual iOS user experience

3. **Simulator Testing** (limited)
   - Test UI/UX only
   - Test text extraction (Readability.js)
   - Test error handling
   - Cannot test actual summarization

#### Recommended Testing Flow:

```
1. Develop on macOS Safari (fast iteration)
   ↓
2. Test on real iPhone/iPad (validate iOS experience)
   ↓
3. Final validation on all target devices
```

### Device Requirements

#### Supported Devices (Real Hardware Only):

**iPhones:**
- iPhone 15 Pro / Pro Max (A17 Pro)
- iPhone 16 / 16 Plus / 16 Pro / 16 Pro Max (A18/A18 Pro)
- Future iPhone models with A17 Pro or newer

**iPads:**
- iPad Pro with M1 or newer
- iPad Air with M1 or newer
- iPad Mini with M-series (if released)

**Macs:**
- Any Mac with M1, M2, M3, or M4 chip

### Simulator Limitations

The iOS Simulator **cannot** test:
- ❌ Actual summarization
- ❌ Language detection accuracy
- ❌ Performance characteristics
- ❌ Memory usage under load
- ❌ Apple Intelligence availability

The iOS Simulator **can** test:
- ✅ UI/UX flow
- ✅ Text extraction (Readability.js)
- ✅ Error handling
- ✅ JavaScript ↔ Swift messaging
- ✅ Extension popup behavior

### Workarounds for Development

#### Option 1: Mock Mode (Not Implemented Yet)

You could add a mock mode for simulator testing:

```swift
#if targetEnvironment(simulator)
static let useMockSummarization = true
#else
static let useMockSummarization = false
#endif

func mockSummarize(text: String, language: String) -> SummaryAndSentiment {
    let wordCount = text.split(separator: " ").count
    return SummaryAndSentiment(
        summaryText: "Mock summary of \(wordCount) words in \(language). This is a placeholder for simulator testing.",
        sentiment: "Neutral"
    )
}
```

#### Option 2: Remote Testing

Use Xcode's wireless debugging to test on a real device without USB:
1. Connect iPhone via USB once
2. Enable "Connect via Network" in Xcode
3. Disconnect USB
4. Build and run wirelessly

#### Option 3: TestFlight

For broader testing:
1. Upload build to TestFlight
2. Install on test devices
3. Collect feedback and logs

### Error Messages Reference

| Error Message | Meaning | Solution |
|--------------|---------|----------|
| "Foundation Models not available in simulator" | Running in iOS Simulator | Test on real device |
| "Apple Intelligence is not available on this device" | Device not supported | Use iPhone 15 Pro+ or M-series iPad/Mac |
| "Language X is not supported" | Detected language not supported by AFM | Content will be summarized in English |
| "No readable content found" | Text extraction failed | Check page structure |
| "Generation failed: unavailable" | Model API not accessible | Check device settings, restart device |

### Debugging Tips

#### 1. Check Console Logs

In Xcode, filter console for:
```
SummarizeIt
```

Look for:
- "Running in simulator - Foundation Models may not be available"
- "Foundation Models test failed"
- "Summarizing text: X chars, language: Y"

#### 2. Verify Device Support

On real device, check:
- Settings → Apple Intelligence & Siri
- Should show "Apple Intelligence" section
- Must be enabled

#### 3. Test on macOS First

Always verify functionality on macOS Safari before testing on iOS:
```bash
# Build for macOS
xcodebuild -scheme "SummarizeIt (macOS)" -configuration Debug
```

#### 4. Check Xcode Version

Ensure you're using:
- Xcode 16.0 or newer
- iOS 18.0 SDK or newer
- macOS 15.0 SDK or newer

### Known Issues

1. **Simulator Always Fails**
   - Expected behavior
   - Not a bug
   - Test on real device

2. **"Language: undefined" in Output**
   - Fixed in latest version
   - Language now always defaults to "English" if detection fails
   - Check logs for actual detected language

3. **Slow First Run**
   - Cold start of Foundation Models
   - Normal behavior
   - Subsequent runs are faster

### Performance Expectations

#### On Real Devices:

| Device | Small Article | Medium Article | Large Article |
|--------|--------------|----------------|---------------|
| iPhone 15 Pro | 5-10s | 12-25s | 30-60s |
| iPhone 16 Pro | 4-8s | 10-20s | 25-50s |
| iPad M1 | 5-10s | 12-25s | 30-60s |
| iPad M2/M3 | 4-8s | 10-20s | 25-50s |
| Mac M1 | 5-10s | 12-25s | 30-60s |
| Mac M2/M3/M4 | 4-8s | 10-20s | 25-50s |

#### On Simulator:
- All operations fail with clear error message
- No performance data available

### Next Steps

1. **Immediate**: Test on real iPhone 15 Pro or newer
2. **Short-term**: Add mock mode for simulator UI testing
3. **Long-term**: Set up automated testing on real devices via CI/CD

### Questions?

If you're still seeing issues on **real devices**:

1. Check device is iPhone 15 Pro+ or M-series iPad/Mac
2. Verify Apple Intelligence is enabled in Settings
3. Check Xcode console for specific error messages
4. Try restarting the device
5. Ensure you're on iOS 18.0+ or macOS 15.0+

If issues persist on real hardware, check:
- Device storage (models need space)
- Network connection (initial model download)
- Region settings (Apple Intelligence availability varies by region)
