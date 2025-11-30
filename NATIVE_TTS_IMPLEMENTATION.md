# Improved Web Speech API TTS Implementation

## Problem
Safari's Web Speech API (`window.speechSynthesis`) was unreliable:
- Randomly stopped after a few words or sentences
- Inconsistent behavior across different summaries
- Poor voice initialization
- No proper error handling or recovery

## Solution
Improved Web Speech API implementation with proper initialization, voice selection, and error handling.

Note: Native Swift AVSpeechSynthesizer cannot be used in Safari Web Extensions due to sandboxing limitations.

## Implementation

### JavaScript Side (content.js)

**Key Improvements:**

1. **Proper Voice Loading**
   - Waits for voices to load before speaking
   - Handles `onvoiceschanged` event
   - Fallback timeout if event doesn't fire

2. **Smart Voice Selection**
   - Tries exact language match first (e.g., 'en-US')
   - Falls back to language base (e.g., 'en')
   - Uses default voice if no match
   - Ensures a voice is always selected

3. **Single Utterance Approach**
   - Speaks entire summary as one utterance
   - More reliable than chunking in Safari
   - Proper rate, pitch, and volume settings

4. **Error Handling with Retry**
   - Catches and logs all errors
   - Automatic retry once on non-cancel errors
   - Proper UI reset on failure
   - Distinguishes between user cancel and errors

5. **Safari-Specific Workarounds**
   - Calls `cancel()` before speaking to clear queue
   - Checks for paused state and resumes (Safari bug fix)
   - 100ms delay for resume check

6. **Clean State Management**
   - Proper cleanup on stop
   - Reset UI on completion
   - No lingering state between summaries

## Benefits

✅ **More Reliable** - Proper initialization prevents random stops
✅ **Better Voice Selection** - Finds best voice for each language
✅ **Error Recovery** - Automatic retry on failures
✅ **Safari Optimized** - Workarounds for known Safari bugs
✅ **Clean State** - No corruption between summaries
✅ **Simple** - Single utterance is more reliable than chunking

## Usage

Click "🔊 Listen" button to start, "⏸️ Stop" to cancel.

## Known Limitations

- Web Speech API in Safari is still not perfect
- May occasionally stop on very long summaries
- Voice quality depends on system voices
- Cannot use native AVSpeechSynthesizer due to extension sandboxing

## Technical Notes

- Waits for voices to load before first use
- Uses `speechSynthesis.cancel()` to clear queue
- Checks for Safari's pause bug and resumes
- Retry logic handles transient errors
- Normal speech rate (1.0) for best reliability
