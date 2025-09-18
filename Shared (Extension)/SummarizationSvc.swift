//
//  SummaryOnly.swift
//  SummarizeIt
//
//  Created by SN on 5/9/25.
//

import Foundation
import NaturalLanguage
import FoundationModels

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
private func estimateTokens(_ s: String) -> Int {
    max(1, Int(ceil(Double(s.count) / 3.6)))
}
final class HierarchicalSummarizer {
    
    // Tune these for your model / prompts
    private let maxContextTokens: Int = 4096           // model limit
    
    // === Updated defaults (safer) ===
    private let responseTokensBudgetFinal: Int = 500   // keep 500 for final passes
    private let responseTokensBudgetChunk: Int = 300   // lower budget for chunk passes
    
    private let promptOverheadTokens: Int = 900        // safer buffer for instructions + formatting
    private let defaultTargetChunkTokens: Int = 850    // ~0.8–0.9k target per chunk
    private let defaultOverlapTokens: Int = 150        // ~150 token overlap
    
    // Timeouts (seconds)
    private let chunkTimeout: TimeInterval = 60        // allow slower cold starts
    private let finalTimeout: TimeInterval = 90
    
    // Session + options (reuse your session)
    private let session: LanguageModelSession
    private var options: GenerationOptions
    
    init() {
        self.session = LanguageModelSession(instructions: {
            "You are a concise, faithful summarizer. Preserve key facts; avoid speculation."
        })
        self.options = GenerationOptions(
            sampling: .greedy,
            temperature: 0.0,
            maximumResponseTokens: 500
        )
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
        
        // If short enough, do your existing single-shot path
        if estimateTokens(safeText) + promptOverheadTokens + responseTokensBudgetFinal <= maxContextTokens {
            return try await withTimeout(finalTimeout) {
                try await self.singleShotSummaryAndSentiment(inputText: safeText, language: language)
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
        
        // 2) Summarize each chunk (sequential for stability; adaptive shrinking + timeout)
        var chunkSummaries: [String] = []
        chunkSummaries.reserveCapacity(chunks.count)
        
        for (idx, chunk) in chunks.enumerated() {
            let s = try await summarizeChunkAdaptive(
                chunk,
                language: language,
                ordinal: idx + 1,
                total: chunks.count
            )
            chunkSummaries.append(s)
        }
        
        // 3) Summarize the summaries
        let stitched = chunkSummaries.joined(separator: "\n\n")
        let finalSummary = try await withTimeout(finalTimeout) {
            try await self.summarizeStitchedSummaries(stitched, language: language)
        }
        
        // 4) Sentiment from final summary
        let final = try await withTimeout(finalTimeout) {
            try await self.summaryAndSentiment(from: finalSummary, language: language)
        }
        return final
    }
    
    // MARK: - Single-shot path (for small inputs)
    
    private func singleShotSummaryAndSentiment(inputText: String, language: String) async throws -> SummaryAndSentiment {
        let prefix = """
        Summarize and analyze the following text in \(language) language.
        
        Rules:
        - Generate a concise summary (3–6 sentences) in \(language).
        - Then classify the overall sentiment as exactly one of: Positive, Neutral, Negative.
        
        Text:
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
        var targetTokens = defaultTargetChunkTokens
        
        while attempts < 3 {
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
            } catch {
                // Any generation/timeout error → shrink and retry
                attempts += 1
                targetTokens = Int(Double(targetTokens) * 0.7) // shrink ~30%
                current = shrinkByApproxTokens(current, toApproxTokenBudget: targetTokens)
            }
        }
        
        // Last resort: return a trimmed piece so pipeline keeps going
        return String(current.prefix(2000))
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
        You will summarize chunk \(ordinal) of \(total) in \(language) language.
        
        Rules:
        - Be concise (3–6 sentences).
        - Preserve facts, entities, numbers, and cause-effect.
        - Do not mention this is chunk \(ordinal)/\(total).
        - No speculation, no hallucinations.
        
        Chunk:
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
    
    // MARK: - Final summary from stitched chunk summaries
    
    private func summarizeStitchedSummaries(_ summariesText: String, language: String) async throws -> String {
        let prefix = """
        You are given multiple chunk summaries of a larger document. Produce a single cohesive final summary in \(language) language.
        
        Rules:
        - Synthesize across chunks; avoid repetition.
        - Keep it concise (6–10 sentences).
        - Maintain fidelity to the given content only.
        - Include key facts, numbers, decisions, and outcomes.
        
        Chunk Summaries:
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
        Given the final summary (already in \(language)), return:
        - summaryText: a polished concise version (4–7 sentences) in \(language).
        - sentiment: exactly one of Positive, Neutral, Negative based on the overall tone and outcomes.
        
        Final Summary:
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
    
    /// Token estimator: safer (≈ 1 token per ~3.6 chars across EU languages).
    private func estimateTokens(_ s: String) -> Int {
        max(1, Int(ceil(Double(s.count) / 3.6)))
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
        let approxCharsPerToken = 3.6
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
        let approxCharsPerToken = 3.6
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
        let approxCharsPerToken = 3.6
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
