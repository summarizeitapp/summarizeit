//
//  SafariWebExtensionHandler.swift
//  Shared (Extension)
//
//  Created by SN on 5/8/25.
//

import SafariServices
import NaturalLanguage
import FoundationModels
import os.log

// MARK: - AI availability & language helpers

@inline(__always)
func aiSupportedLanguageCodes() -> Set<String> {
    // Lower-cased base language codes like "en", "fr"
    Set(SystemLanguageModel.default.supportedLanguages.compactMap { $0.languageCode?.identifier.lowercased() })
}


@inline(__always)
func isAppleIntelligenceAvailable() -> Bool {
    AIAvailability.isAppleIntelligenceAvailable()
}

@inline(__always)
func englishDisplayName(for code: String) -> String {
    let locale = Locale(identifier: "en")
    return locale.localizedString(forLanguageCode: code) ?? "English"
}

func detectLanguage(inputText: String) -> String {
    let recognizer = NLLanguageRecognizer()
    recognizer.processString(inputText)
    if let language = recognizer.dominantLanguage {
        let languageCode = language.rawValue  // e.g., "pl"
        let locale = Locale(identifier: "en") // display in English
        guard let languageName = locale.localizedString(forLanguageCode: languageCode) else { return "English" }
        return languageName
    } else {
        return "English"
    }
}
/// Detect dominant language but **return only supported names**; otherwise "English".
func detectSupportedLanguageName(inputText: String) -> String {
    let english = "English"
    guard isAppleIntelligenceAvailable() else { return english }
    let supported = aiSupportedLanguageCodes()
    
    let recognizer = NLLanguageRecognizer()
    recognizer.processString(inputText)
    
    guard let lang = recognizer.dominantLanguage else { return english }
    let code = lang.rawValue.lowercased()
    return supported.contains(code) ? englishDisplayName(for: code) : english
}

func currentModelIdentifier() -> String {
    #if targetEnvironment(simulator)
    if let sim = ProcessInfo.processInfo.environment["SIMULATOR_MODEL_IDENTIFIER"] {
        return sim
    }
    #endif
    var info = utsname()
    uname(&info)
    return withUnsafePointer(to: &info.machine) {
        $0.withMemoryRebound(to: CChar.self, capacity: 1) { String(cString: $0) }
    }
}
// MARK: - Handler


final class SafariWebExtensionHandler: NSObject, NSExtensionRequestHandling {
    
    func beginRequest(with context: NSExtensionContext) {
        
        guard let item = context.inputItems.first as? NSExtensionItem,
              let userInfo = item.userInfo as? [String: Any] else {
            context.completeRequest(returningItems: nil, completionHandler: nil)
            return
        }
        
       
        // Unwrap Safari envelope if present
        let envelope = (userInfo[SFExtensionMessageKey] as? [String: Any]) ?? userInfo
        
        // Support both:
        //  A) { message: { action: "summarize", ... } }
        //  B) { action: "summarize", ... }
        let message = (envelope["message"] as? [String: Any]) ?? envelope
        
        guard let action = message["action"] as? String else {
            // Pre-warm or unknown — return fast, no heavy work.
            context.completeRequest(returningItems: nil, completionHandler: nil)
            return
        }
        
        switch action {
        case "summarize":
            handleSummarize(message: message, context: context)
            
        case "probe":
            let responseItem = NSExtensionItem()
            let payload: [String: Any] = ["aiAvailable": isAppleIntelligenceAvailable()]
            responseItem.userInfo = [SFExtensionMessageKey: ["response": payload]]
            context.completeRequest(returningItems: [responseItem], completionHandler: nil)
            
        default:
            context.completeRequest(returningItems: nil, completionHandler: nil)
        }
    }
    
    private func handleSummarize(message: [String: Any], context: NSExtensionContext) {
        let responseItem = NSExtensionItem()
        
        // Device gate: fail fast on devices without Apple Intelligence
        guard isAppleIntelligenceAvailable() else {
            let payload: [String: Any] = [
                "summary": "Apple Intelligence is not available on this device.",
                "sentiment": "NA",
                "title": message["title"] ?? "",
                "url": message["article_url"] ?? "",
                "aiAvailable": false
            ]
            responseItem.userInfo = [SFExtensionMessageKey: ["response": payload]]
            context.completeRequest(returningItems: [responseItem], completionHandler: nil)
            return
        }
        
        // Inputs
        let text = (message["text"] as? String) ?? ""
        let title = message["title"] ?? ""
        let url = message["article_url"] ?? ""
        let languageName = detectLanguage(inputText: text)
        Task {
            
            do {
                // Optional micro warm-up to reduce M1 cold-start jitter
                let warm = LanguageModelSession(instructions: { "ping" })
                _ = try? await warm.respond(generating: String.self) { "ok" }.content
                
                // Your existing summarizer (kept intact)
                let summarizer = HierarchicalSummarizer()
                let output = try await summarizer.analyzeTextHierarchical(
                    inputText: text,
                    language: languageName
                )
                
                let payload: [String: Any] = [
                    "summary": output.summaryText,
                    "sentiment": output.sentiment,
                    "title": title,
                    "url": url,
                    "aiAvailable": true,
                    "language": languageName
                ]
                responseItem.userInfo = [SFExtensionMessageKey: ["response": payload]]
                context.completeRequest(returningItems: [responseItem], completionHandler: nil)
                
            } catch let genErr as LanguageModelSession.GenerationError {
                switch genErr {
                case .unsupportedLanguageOrLocale:
                    let payload: [String: Any] = [
                        "summary": "Language \(languageName) is not supported.",
                        "sentiment": "NA",
                        "title": title,
                        "url": url,
                        "aiAvailable": true,
                        "error": "unsupported_language_retry_failed"
                    ]
                    responseItem.userInfo = [SFExtensionMessageKey: ["response": payload]]
                    context.completeRequest(returningItems: [responseItem], completionHandler: nil)
            
                default:
                    let payload: [String: Any] = [
                        "summary": "Generation failed. Please try again.",
                        "sentiment": "NA",
                        "title": title,
                        "url": url,
                        "aiAvailable": true,
                        "error": "\(genErr)"
                    ]
                    responseItem.userInfo = [SFExtensionMessageKey: ["response": payload]]
                    context.completeRequest(returningItems: [responseItem], completionHandler: nil)
                }
                
            } catch {
                let payload: [String: Any] = [
                    "summary": "Unexpected error. Please try again.",
                    "sentiment": "NA",
                    "title": title,
                    "url": url,
                    "aiAvailable": true,
                    "error": "\(error)"
                ]
                responseItem.userInfo = [SFExtensionMessageKey: ["response": payload]]
                context.completeRequest(returningItems: [responseItem], completionHandler: nil)
            }
        }
    }
}

