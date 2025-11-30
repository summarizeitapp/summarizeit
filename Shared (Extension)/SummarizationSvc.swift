//
//  SummaryOnly.swift
//  SummarizeIt
//
//  Created by SN on 5/9/25.
//

import Foundation
import NaturalLanguage
import FoundationModels
import os.log

// MARK: - Output Types

@Generable
struct SummaryOnly: Equatable {
    let summaryText: String
}

@Generable
struct SummaryAndSentiment: Equatable {
    let summaryText: String          // final short summary
    let sentiment: String            // Positive | Neutral | Negative
}

// MARK: - Summarizer
// Optimized token estimator with language-aware ratios
private func estimateTokens(_ s: String) -> Int {
    // Check if text contains significant CJK characters (Chinese, Japanese, Korean)
    let cjkCount = s.unicodeScalars.filter { scalar in
        (0x4E00...0x9FFF).contains(scalar.value) ||  // CJK Unified Ideographs
        (0x3400...0x4DBF).contains(scalar.value) ||  // CJK Extension A
        (0x20000...0x2A6DF).contains(scalar.value)   // CJK Extension B
    }.count
    
    let cjkRatio = Double(cjkCount) / Double(max(1, s.count))
    
    // CJK characters use ~1.5-2 chars per token, Latin uses ~4 chars per token
    let charsPerToken: Double
    if cjkRatio > 0.3 {
        // Mostly CJK text
        charsPerToken = 1.8
    } else if cjkRatio > 0.1 {
        // Mixed text
        charsPerToken = 2.5
    } else {
        // Mostly Latin text
        charsPerToken = 4.0
    }
    
    return max(1, Int(ceil(Double(s.count) / charsPerToken)))
}
final class HierarchicalSummarizer {
    
    // Tune these for your model / prompts
    private let maxContextTokens: Int = 4096           // model limit
    
    // === Optimized defaults for better performance ===
    private let responseTokensBudgetFinal: Int = 400   // reduced for faster generation
    private let responseTokensBudgetChunk: Int = 250   // lower budget for chunk passes
    
    private let promptOverheadTokens: Int = 1100       // safe buffer for prompts
    private let defaultTargetChunkTokens: Int = 700    // balanced for news articles
    private let defaultOverlapTokens: Int = 40         // minimal overlap for context
    
    // Timeouts (seconds) - increased for reliability
    private let chunkTimeout: TimeInterval = 90        // allow slower cold starts
    private let finalTimeout: TimeInterval = 120       // more time for final synthesis
    
    // Session + options (reuse your session)
    private let session: LanguageModelSession
    private var options: GenerationOptions
    
    init() {
        // Initialize session with NO instructions to avoid triggering safety filters
        // Safari's built-in summarization likely uses minimal/no system instructions
        self.session = LanguageModelSession()
        self.options = GenerationOptions(
            sampling: .greedy,
            temperature: 0.0,
            maximumResponseTokens: 400
        )
    }
    
    // Test if the session is actually usable
    func testAvailability() async throws {
        _ = try await session.respond(generating: String.self, options: options) {
            "test"
        }.content
    }
    
    /// Conservative token estimator.
    
    
    /// Ensure `prompt` + response fit under the model window. If not, reduce `variableText` until it fits.
    /// Returns the possibly shrunken `variableText` and the capped `maxResponseTokens`.
    private func fitPromptAndResponse(
        promptPrefix: String,         // the part before the variable text
        variableText: String,         // the large text we can shrink if needed
        promptSuffix: String = "",    // anything after the variable text
        preferredResponseTokens: Int  // your target (e.g., 300 or 500)
    ) -> (text: String, maxResp: Int) {
        let safety: Int = 64 // headroom
        let maxWindow = maxContextTokens
        
        // quick function to compute allowed response budget for a given text
        func allowedResponse(for text: String) -> Int {
            // Build the *actual* prompt that will be sent
            let fullPrompt = promptPrefix + text + promptSuffix
            let promptTokens = estimateTokens(fullPrompt) + promptOverheadTokens // include instructions/formatting buffer
            return max(0, maxWindow - promptTokens - safety)
        }
        
        var text = variableText
        var allowed = allowedResponse(for: text)
        
        // If there is no room even for a tiny response, shrink text iteratively
        while allowed < 64 && text.count > 800 {
            text = shrinkByApproxTokens(text, toApproxTokenBudget: Int(Double(estimateTokens(text)) * 0.8))
            allowed = allowedResponse(for: text)
        }
        
        let capped = max(64, min(preferredResponseTokens, allowed))
        return (text, capped)
    }
    
    // Public entrypoint
    func analyzeTextHierarchical(inputText: String, language: String) async throws -> SummaryAndSentiment {
        let safeText = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !safeText.isEmpty else {
            return SummaryAndSentiment(summaryText: "No readable content.", sentiment: "NA")
        }
        
        // Validate language is not empty
        let safeLang = language.isEmpty ? "English" : language
        
        // If short enough, do your existing single-shot path
        if estimateTokens(safeText) + promptOverheadTokens + responseTokensBudgetFinal <= maxContextTokens {
            return try await withTimeout(finalTimeout) {
                try await self.singleShotSummaryAndSentiment(inputText: safeText, language: safeLang)
            }
        }
        
        // 1) Split to overlapping chunks (respect hard input cap)
        let hardMaxTokensForText = max(512, maxContextTokens - promptOverheadTokens - responseTokensBudgetChunk)
        var chunks = splitIntoTokenBlocks(
            text: safeText,
            targetTokens: defaultTargetChunkTokens,
            overlapTokens: defaultOverlapTokens,
            hardMaxTokens: hardMaxTokensForText
        )
        
        // Emergency fallback: if we somehow got 0 chunks, force-split by chars
        if chunks.isEmpty {
            chunks = forceSplitByChars(safeText, approxTokensPerChunk: defaultTargetChunkTokens)
        }
        
        // Safety: limit maximum number of chunks to prevent runaway processing
        let maxChunks = 12  // Balanced for news article coverage
        if chunks.count > maxChunks {
            os_log(.info, "Too many chunks (%d), truncating to %d", chunks.count, maxChunks)
            chunks = Array(chunks.prefix(maxChunks))
        }
        
        // 2) Summarize each chunk (sequential for stability; adaptive shrinking + timeout)
        var chunkSummaries: [String] = []
        chunkSummaries.reserveCapacity(chunks.count)
        
        os_log(.info, "Processing %d chunks for language: %@", chunks.count, safeLang)
        
        // Test first chunk to detect safety filter issues early
        do {
            os_log(.info, "Testing first chunk for safety filters...")
            let testChunk = chunks[0]
            let testResult = try await summarizeChunkAdaptive(
                testChunk,
                language: safeLang,
                ordinal: 1,
                total: chunks.count
            )
            chunkSummaries.append(testResult)
            os_log(.info, "First chunk successful, continuing with remaining chunks")
        } catch {
            // If first chunk fails, it's likely a safety filter issue
            let errorStr = String(describing: error)
            if errorStr.contains("safety") || errorStr.contains("deny") || errorStr.contains("blocked") {
                os_log(.error, "Safety filter detected on first chunk - content blocked")
                // Create a custom error that will be caught by the handler
                struct SafetyFilterError: LocalizedError {
                    var errorDescription: String? { "Content blocked by safety filters" }
                }
                throw SafetyFilterError()
            }
            throw error
        }
        
        // Process remaining chunks
        for idx in 1..<chunks.count {
            let chunk = chunks[idx]
            os_log(.info, "Processing chunk %d/%d (%d chars)", idx + 1, chunks.count, chunk.count)
            let s = try await summarizeChunkAdaptive(
                chunk,
                language: safeLang,
                ordinal: idx + 1,
                total: chunks.count
            )
            chunkSummaries.append(s)
            os_log(.info, "Completed chunk %d/%d", idx + 1, chunks.count)
        }
        
        // 3) If we have many chunks, do hierarchical reduction
        var stitched = chunkSummaries.joined(separator: "\n\n")
        
        // If stitched summaries are still too large, summarize them in groups first
        if estimateTokens(stitched) > defaultTargetChunkTokens * 2 {
            var groupSummaries: [String] = []
            let groupSize = 3 // summarize 3 chunks at a time
            for i in stride(from: 0, to: chunkSummaries.count, by: groupSize) {
                let end = min(i + groupSize, chunkSummaries.count)
                let group = chunkSummaries[i..<end].joined(separator: "\n\n")
                let groupSummary = try await withTimeout(finalTimeout) {
                    try await self.summarizeStitchedSummaries(group, language: safeLang)
                }
                groupSummaries.append(groupSummary)
            }
            stitched = groupSummaries.joined(separator: "\n\n")
        }
        
        // 4) Analyze sentiment from ORIGINAL first 1-2 chunks (before summarization neutralizes it)
        // Use more text for better context, but not too much to avoid timeout
        let sentimentChunks = chunks.prefix(min(2, chunks.count))
        let sentimentText = sentimentChunks.joined(separator: "\n\n")
        let sentiment = try await withTimeout(finalTimeout) {
            try await self.detectSentiment(from: sentimentText, language: safeLang)
        }
        
        // 5) Final summary (without sentiment, just text)
        let finalSummary = try await withTimeout(finalTimeout) {
            try await self.summarizeStitchedSummaries(stitched, language: safeLang)
        }
        
        return SummaryAndSentiment(summaryText: finalSummary, sentiment: sentiment)
    }
    
    // MARK: - Single-shot path (for small inputs)
    
    private func singleShotSummaryAndSentiment(inputText: String, language: String) async throws -> SummaryAndSentiment {
        let prefix = """
        Summarize the following text in \(language) and classify its sentiment as Positive, Neutral, or Negative:
        
        """
        let suffix = "" // nothing after
        let (fitText, maxResp) = fitPromptAndResponse(
            promptPrefix: prefix + "\n",
            variableText: inputText,
            promptSuffix: suffix,
            preferredResponseTokens: responseTokensBudgetFinal
        )
        
        let prompt = prefix + "\n" + fitText + suffix
        
        return try await session.respond(
            generating: SummaryAndSentiment.self,
            options: optionsWith(maxTokens: maxResp)
        ) { prompt }.content
    }
    private func singleShotSummaryAndSentiment2(inputText: String, language: String) async throws -> SummaryAndSentiment {
        try await session.respond(
            generating: SummaryAndSentiment.self,
            options: optionsWith(maxTokens: responseTokensBudgetFinal)
        ) {
            """
            Summarize and analyze the following text in \(language) language.
            
            Rules:
            - Generate a concise summary (3–6 sentences) in \(language).
            - Then classify the overall sentiment as exactly one of: Positive, Neutral, Negative.
            
            Text:
            \(inputText)
            """
        }.content
    }
    
    // MARK: - Chunk-level summary (ADAPTIVE)
    
    /// Adaptive wrapper: if a chunk trips context/other errors, shrink and retry.
    private func summarizeChunkAdaptive(_ text: String, language: String, ordinal: Int, total: Int) async throws -> String {
        var current = text
        var attempts = 0
        var targetTokens = estimateTokens(text)
        
        while attempts < 4 {
            do {
                return try await withTimeout(chunkTimeout) {
                    try await self.summarizeChunk(
                        current,
                        language: language,
                        ordinal: ordinal,
                        total: total,
                        maxResponseTokens: self.responseTokensBudgetChunk
                    )
                }
            } catch let error as LanguageModelSession.GenerationError {
                // Check error type
                let errorStr = String(describing: error)
                let isSafetyError = errorStr.contains("safety") || errorStr.contains("deny") || errorStr.contains("blocked")
                
                // Safety errors cannot be retried - propagate immediately
                if isSafetyError {
                    os_log(.error, "Safety filter blocked content in chunk %d/%d", ordinal, total)
                    throw error
                }
                
                // Context window errors - aggressively shrink
                if errorStr.contains("context window") || errorStr.contains("token") {
                    attempts += 1
                    targetTokens = Int(Double(targetTokens) * 0.5) // shrink 50%
                    current = shrinkByApproxTokens(current, toApproxTokenBudget: targetTokens)
                } else {
                    // Other errors, try smaller shrink
                    attempts += 1
                    targetTokens = Int(Double(targetTokens) * 0.7)
                    current = shrinkByApproxTokens(current, toApproxTokenBudget: targetTokens)
                }
            } catch {
                // Check if this is a safety error in generic catch
                let errorStr = String(describing: error)
                let isSafetyError = errorStr.contains("safety") || errorStr.contains("deny") || errorStr.contains("blocked")
                
                if isSafetyError {
                    os_log(.error, "Safety filter blocked content in chunk %d/%d", ordinal, total)
                    throw error
                }
                
                // Timeout or other error - retry with smaller chunk
                attempts += 1
                targetTokens = Int(Double(targetTokens) * 0.7)
                current = shrinkByApproxTokens(current, toApproxTokenBudget: targetTokens)
            }
        }
        
        // Last resort: return a very short summary so pipeline keeps going
        let charsPerToken = getCharsPerToken(for: current)
        let maxChars = Int(200.0 * charsPerToken) // ~200 tokens worth
        return String(current.prefix(maxChars))
    }
    
    /// Original chunk summarizer (unchanged prompt). Allows passing a per-call max tokens.
    private func summarizeChunk(
        _ text: String,
        language: String,
        ordinal: Int,
        total: Int,
        maxResponseTokens: Int
    ) async throws -> String {
        
        let prefix = """
        Summarize the following text in \(language):
        
        """
        let suffix = ""
        
        let (fitText, maxResp) = fitPromptAndResponse(
            promptPrefix: prefix + "\n",
            variableText: text,
            promptSuffix: suffix,
            preferredResponseTokens: maxResponseTokens // usually 300 (or your current chunk budget)
        )
        
        let prompt = prefix + "\n" + fitText + suffix
        
        let result = try await session.respond(
            generating: SummaryOnly.self,
            options: optionsWith(maxTokens: maxResp)
        ) { prompt }.content
        
        return result.summaryText
    }
    
    // MARK: - Sentiment detection from original text
    
    private func detectSentiment(from text: String, language: String) async throws -> String {
        let prefix = """
        Analyze the overall sentiment of this text based on the main events and their impact.
        
        Guidelines:
        - Positive: Peace agreements, breakthroughs, resolutions, improvements, good outcomes, humanitarian aid success
        - Negative: Active violence, attacks, casualties, disasters, crises, deteriorating situations, threats
        - Neutral: Analysis, commentary, political appointments, routine updates, mixed developments
        
        For mixed content, prioritize the most significant or immediate event.
        
        Respond with only: Positive, Negative, or Neutral
        
        Text:
        """
        let suffix = ""
        
        let (fitText, maxResp) = fitPromptAndResponse(
            promptPrefix: prefix + "\n",
            variableText: text,
            promptSuffix: suffix,
            preferredResponseTokens: 150  // Need more tokens for reasoning
        )
        
        let prompt = prefix + "\n" + fitText + suffix
        
        // Use simple string response for just sentiment
        let result = try await session.respond(
            generating: String.self,
            options: optionsWith(maxTokens: maxResp)
        ) { prompt }.content
        
        // Extract sentiment from response (should be "Positive", "Neutral", or "Negative")
        let cleaned = result.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        
        // Check for explicit classification first
        if cleaned.contains("positive") && !cleaned.contains("not positive") && !cleaned.contains("no positive") {
            return "Positive"
        } else if cleaned.contains("negative") && !cleaned.contains("not negative") && !cleaned.contains("no negative") {
            return "Negative"
        } else {
            return "Neutral"
        }
    }
    
    // MARK: - Final summary from stitched chunk summaries
    
    private func summarizeStitchedSummaries(_ summariesText: String, language: String) async throws -> String {
        let prefix = """
        Combine these summaries into one summary in \(language):
        
        """
        let suffix = ""
        
        let (fitText, maxResp) = fitPromptAndResponse(
            promptPrefix: prefix + "\n",
            variableText: summariesText,
            promptSuffix: suffix,
            preferredResponseTokens: responseTokensBudgetFinal // 500 for final
        )
        
        let prompt = prefix + "\n" + fitText + suffix
        
        let result = try await session.respond(
            generating: SummaryOnly.self,
            options: optionsWith(maxTokens: maxResp)
        ) { prompt }.content
        
        return result.summaryText
    }
    
    // MARK: - Sentiment from final summary
    
    private func summaryAndSentiment(from finalSummary: String, language: String) async throws -> SummaryAndSentiment {
        let prefix = """
        Refine this summary in \(language) and classify sentiment as Positive, Neutral, or Negative:
        
        """
        let suffix = ""
        
        let (fitText, maxResp) = fitPromptAndResponse(
            promptPrefix: prefix + "\n",
            variableText: finalSummary,
            promptSuffix: suffix,
            preferredResponseTokens: responseTokensBudgetFinal
        )
        
        let prompt = prefix + "\n" + fitText + suffix
        
        return try await session.respond(
            generating: SummaryAndSentiment.self,
            options: optionsWith(maxTokens: maxResp)
        ) { prompt }.content
    }
    
    // MARK: - Options helper
    
    private func optionsWith(maxTokens: Int) -> GenerationOptions {
        var o = options
        o.maximumResponseTokens = maxTokens
        return o
    }
    
    // MARK: - Chunking
    
    // Note: estimateTokens is defined at the top of the class
    
    // Helper to get chars-per-token ratio for a text
    private func getCharsPerToken(for text: String) -> Double {
        let cjkCount = text.unicodeScalars.filter { scalar in
            (0x4E00...0x9FFF).contains(scalar.value) ||
            (0x3400...0x4DBF).contains(scalar.value) ||
            (0x20000...0x2A6DF).contains(scalar.value)
        }.count
        
        let cjkRatio = Double(cjkCount) / Double(max(1, text.count))
        
        if cjkRatio > 0.3 {
            return 1.8  // Mostly CJK
        } else if cjkRatio > 0.1 {
            return 2.5  // Mixed
        } else {
            return 4.0  // Mostly Latin
        }
    }
    
    /// Sentence-aware splitting with overlap. Respects a hard max per block (input text tokens only).
    private func splitIntoTokenBlocks(
        text: String,
        targetTokens: Int,
        overlapTokens: Int,
        hardMaxTokens: Int
    ) -> [String] {
        let sentences = sentenceSegments(text)
        
        // If tokenizer yields nothing, force split by chars
        if sentences.isEmpty {
            return forceSplitByChars(text, approxTokensPerChunk: targetTokens)
        }
        
        var blocks: [String] = []
        var current: [String] = []
        var currentTokens = 0
        
        let target = max(256, min(targetTokens, hardMaxTokens - 50)) // small buffer
        let overlap = max(0, min(overlapTokens, target / 3))
        
        func flushCurrent() {
            guard !current.isEmpty else { return }
            blocks.append(current.joined())
            current.removeAll(keepingCapacity: true)
            currentTokens = 0
        }
        
        var i = 0
        while i < sentences.count {
            let s = sentences[i]
            let sTokens = estimateTokens(s)
            
            // If this one sentence is larger than the hard max, split it
            if sTokens > hardMaxTokens {
                // Flush whatever we have first
                flushCurrent()
                let splits = hardSplitLongSentence(s, hardMaxTokens: hardMaxTokens)
                blocks.append(contentsOf: splits)
                i += 1
                continue
            }
            
            if currentTokens + sTokens <= min(target, hardMaxTokens) {
                current.append(s)
                currentTokens += sTokens
                i += 1
                continue
            }
            
            // Flush current block
            flushCurrent()
            
            // Add overlap from previous block end
            if overlap > 0, !blocks.isEmpty {
                let backfill = tokensFromTail(sentences: sentences, endIndexExclusive: i, desiredTokens: overlap)
                current = backfill
                currentTokens = estimateTokens(current.joined())
                // If overlap itself exceeds hardMax, trim
                while currentTokens > hardMaxTokens && !current.isEmpty {
                    _ = current.removeFirst()
                    currentTokens = estimateTokens(current.joined())
                }
            }
        }
        
        // Final flush
        flushCurrent()
        
        // As a guard, if we somehow produced a single giant block over hardMax, force split
        if let only = blocks.first, blocks.count == 1, estimateTokens(only) > hardMaxTokens {
            return forceSplitByChars(only, approxTokensPerChunk: targetTokens)
        }
        
        return blocks
    }
    
    // Force split by character windows (tries to cut on sentence boundary)
    private func forceSplitByChars(_ text: String, approxTokensPerChunk: Int) -> [String] {
        // Use conservative estimate for CJK text
        let approxCharsPerToken = getCharsPerToken(for: text)
        let maxChars = max(800, Int(Double(approxTokensPerChunk) * approxCharsPerToken))
        var out: [String] = []
        var start = text.startIndex
        
        while start < text.endIndex {
            let hardEnd = text.index(start, offsetBy: maxChars, limitedBy: text.endIndex) ?? text.endIndex
            var end = hardEnd
            
            // Try to cut at a sentence boundary within the last 15% of the window
            let window = text[start..<hardEnd]
            if let lastDot = window.lastIndex(of: ".") {
                let cutoff = text.distance(from: lastDot, to: hardEnd)
                if cutoff <= max(20, maxChars / 6) {
                    end = text.index(after: lastDot)
                }
            }
            
            out.append(String(text[start..<end]))
            if end >= text.endIndex { break }
            
            // Overlap ~ 20% of window
            let back = maxChars / 5
            start = text.index(end, offsetBy: -back, limitedBy: text.startIndex) ?? end
        }
        return out
    }
    
    // Sentence segmentation using NaturalLanguage
    private func sentenceSegments(_ text: String) -> [String] {
        let tokenizer = NLTokenizer(unit: .sentence)
        tokenizer.string = text
        var ranges: [Range<String.Index>] = []
        tokenizer.enumerateTokens(in: text.startIndex..<text.endIndex) { range, _ in
            ranges.append(range)
            return true
        }
        if ranges.isEmpty { return [] }
        return ranges.map { String(text[$0]) }
    }
    
    // If a single sentence is too large, split by character windows respecting hard max
    private func hardSplitLongSentence(_ sentence: String, hardMaxTokens: Int) -> [String] {
        let maxTokens = max(256, hardMaxTokens - 50)
        let approxCharsPerToken = getCharsPerToken(for: sentence)
        let maxChars = Int(Double(maxTokens) * approxCharsPerToken)
        
        guard sentence.count > maxChars else { return [sentence] }
        
        var pieces: [String] = []
        var start = sentence.startIndex
        
        while start < sentence.endIndex {
            let end = sentence.index(start, offsetBy: maxChars, limitedBy: sentence.endIndex) ?? sentence.endIndex
            let piece = String(sentence[start..<end])
            pieces.append(piece)
            start = end
        }
        return pieces
    }
    
    // Build an overlap tail (by sentences) that approximates desired token count
    private func tokensFromTail(sentences: [String], endIndexExclusive: Int, desiredTokens: Int) -> [String] {
        var acc: [String] = []
        var tokens = 0
        var i = endIndexExclusive - 1
        while i >= 0, tokens < desiredTokens {
            let s = sentences[i]
            let t = estimateTokens(s)
            tokens += t
            acc.append(s)
            i -= 1
        }
        return acc.reversed()
    }
    
    // Shrink a text by approximate token budget; prefers cutting at sentence boundary.
    private func shrinkByApproxTokens(_ s: String, toApproxTokenBudget budget: Int) -> String {
        let approxCharsPerToken = getCharsPerToken(for: s)
        let maxChars = max(800, Int(Double(budget) * approxCharsPerToken))
        guard s.count > maxChars else { return s }
        
        let cut = s.index(s.startIndex, offsetBy: maxChars, limitedBy: s.endIndex) ?? s.endIndex
        let slice = s[..<cut]
        if let lastDot = slice.lastIndex(of: ".") {
            return String(slice[..<s.index(after: lastDot)])
        }
        return String(slice)
    }
    
    // MARK: - Timeout utility
    
    private func withTimeout<T>(_ seconds: TimeInterval, operation: @escaping () async throws -> T) async throws -> T {
        try await withThrowingTaskGroup(of: T.self) { group in
            group.addTask { try await operation() }
            group.addTask {
                try await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
                throw CancellationError()
            }
            let result = try await group.next()!
            group.cancelAll()
            return result
        }
    }
}
