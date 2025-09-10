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

final class HierarchicalSummarizer {

    // Tune these for your model / prompts
    private let maxContextTokens: Int = 4096           // model limit
    private let responseTokensBudget: Int = 500        // matches GenerationOptions
    private let promptOverheadTokens: Int = 600        // safety buffer for instructions + formatting
    private let defaultTargetChunkTokens: Int = 1200   // try to keep chunks ~1.2k
    private let defaultOverlapTokens: Int = 200        // sliding window overlap

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

    // Public entrypoint
    func analyzeTextHierarchical(inputText: String, language: String) async throws -> SummaryAndSentiment {
        // If short enough, do your existing single-shot path
        if estimateTokens(inputText) + promptOverheadTokens + responseTokensBudget <= maxContextTokens {
            return try await singleShotSummaryAndSentiment(inputText: inputText, language: language)
        }

        // 1) Split to overlapping chunks
        let chunks = splitIntoTokenBlocks(
            text: inputText,
            targetTokens: defaultTargetChunkTokens,
            overlapTokens: defaultOverlapTokens,
            hardMaxTokens: maxContextTokens - responseTokensBudget - promptOverheadTokens
        )

        // 2) Summarize each chunk (sequential for stability)
        var chunkSummaries: [String] = []
        chunkSummaries.reserveCapacity(chunks.count)

        for (idx, chunk) in chunks.enumerated() {
            let s = try await summarizeChunk(chunk, language: language, ordinal: idx + 1, total: chunks.count)
            chunkSummaries.append(s)
        }

        // 3) Summarize the summaries
        let stitched = chunkSummaries.joined(separator: "\n\n")
        let finalSummary = try await summarizeStitchedSummaries(stitched, language: language)

        // 4) Sentiment from final summary
        let final = try await summaryAndSentiment(from: finalSummary, language: language)
        return final
    }

    // MARK: - Single-shot path (for small inputs)

    private func singleShotSummaryAndSentiment(inputText: String, language: String) async throws -> SummaryAndSentiment {
        try await session.respond(
            generating: SummaryAndSentiment.self,
            options: options
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

    // MARK: - Chunk-level summary

    private func summarizeChunk(_ text: String, language: String, ordinal: Int, total: Int) async throws -> String {
        let result = try await session.respond(
            generating: SummaryOnly.self,
            options: options
        ) {
            """
            You will summarize chunk \(ordinal) of \(total) in \(language) language.

            Rules:
            - Be concise (3–6 sentences).
            - Preserve facts, entities, numbers, and cause-effect.
            - Do not mention this is chunk \(ordinal)/\(total).
            - No speculation, no hallucinations.

            Chunk:
            \(text)
            """
        }.content
        return result.summaryText
    }

    // MARK: - Final summary from stitched chunk summaries

    private func summarizeStitchedSummaries(_ summariesText: String, language: String) async throws -> String {
        let result = try await session.respond(
            generating: SummaryOnly.self,
            options: options
        ) {
            """
            You are given multiple chunk summaries of a larger document. Produce a single cohesive final summary in \(language) language.

            Rules:
            - Synthesize across chunks; avoid repetition.
            - Keep it concise (6–10 sentences).
            - Maintain fidelity to the given content only.
            - Include key facts, numbers, decisions, and outcomes.

            Chunk Summaries:
            \(summariesText)
            """
        }.content
        return result.summaryText
    }

    // MARK: - Sentiment from final summary

    private func summaryAndSentiment(from finalSummary: String, language: String) async throws -> SummaryAndSentiment {
        try await session.respond(
            generating: SummaryAndSentiment.self,
            options: options
        ) {
            """
            Given the final summary (already in \(language)), return:
            - summaryText: a polished concise version (4–7 sentences) in \(language).
            - sentiment: exactly one of Positive, Neutral, Negative based on the overall tone and outcomes.

            Final Summary:
            \(finalSummary)
            """
        }.content
    }

    // MARK: - Chunking

    /// Token estimator: crude but sufficient (≈ 1 token per ~4 chars in English-like text).
    private func estimateTokens(_ s: String) -> Int {
        max(1, s.count / 4)
    }

    /// Sentence-aware splitting with overlap. Respects a hard max per block.
    private func splitIntoTokenBlocks(
        text: String,
        targetTokens: Int,
        overlapTokens: Int,
        hardMaxTokens: Int
    ) -> [String] {
        // Sentence boundaries (more robust than fixed lengths)
        let sentences = sentenceSegments(text)

        var blocks: [String] = []
        var current: [String] = []
        var currentTokens = 0

        let target = max(256, min(targetTokens, hardMaxTokens - 100)) // small buffer
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

            if currentTokens + sTokens <= target {
                current.append(s)
                currentTokens += sTokens
                i += 1
                continue
            }

            // If one sentence itself is huge, hard-split by characters to fit
            if current.isEmpty && sTokens > target {
                let splits = hardSplitLongSentence(s, hardMaxTokens: hardMaxTokens)
                for (j, piece) in splits.enumerated() {
                    if j == 0 {
                        current = [piece]
                        currentTokens = estimateTokens(piece)
                        flushCurrent()
                    } else {
                        blocks.append(piece)
                    }
                }
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
            }
        }

        // Final flush
        flushCurrent()
        return blocks
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
        if ranges.isEmpty { return [text] }
        return ranges.map { String(text[$0]) }
    }

    // If a single sentence is too large, split by character windows respecting hardMax
    private func hardSplitLongSentence(_ sentence: String, hardMaxTokens: Int) -> [String] {
        let maxTokens = max(256, hardMaxTokens - 100)
        let approxCharsPerToken = 4
        let maxChars = maxTokens * approxCharsPerToken

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
}


