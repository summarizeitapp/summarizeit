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

// MARK: - Localized Error Messages

func getLocalizedErrorMessage(for errorType: String, language: String) -> String {
    let lang = language.lowercased()
    
    switch errorType {
    case "context_window":
        if lang.contains("chinese") || lang.contains("中文") {
            return "文章过长，无法处理。Apple Intelligence 对文章长度有限制。请尝试较短的文章。"
        } else if lang.contains("japanese") || lang.contains("日本") {
            return "記事が長すぎて処理できません。Apple Intelligenceには記事の長さに制限があります。短い記事をお試しください。"
        } else if lang.contains("korean") || lang.contains("한국") {
            return "기사가 너무 길어서 처리할 수 없습니다. Apple Intelligence는 기사 길이에 제한이 있습니다. 더 짧은 기사를 시도해 주세요."
        } else if lang.contains("spanish") || lang.contains("español") {
            return "El artículo es demasiado largo para procesar. Apple Intelligence tiene límites en la longitud del artículo. Intente con un artículo más corto."
        } else if lang.contains("french") || lang.contains("français") {
            return "L'article est trop long pour être traité. Apple Intelligence a des limites sur la longueur des articles. Essayez un article plus court."
        } else if lang.contains("german") || lang.contains("deutsch") {
            return "Der Artikel ist zu lang zum Verarbeiten. Apple Intelligence hat Grenzen für die Artikellänge. Versuchen Sie einen kürzeren Artikel."
        } else {
            return "Article too long to process. Apple Intelligence has limits on article length. Please try a shorter article."
        }
        
    case "safety_filter":
        if lang.contains("chinese") || lang.contains("中文") {
            return "Apple Intelligence 安全过滤器阻止了此内容。该文章可能包含敏感内容（暴力、灾难等）无法处理。"
        } else if lang.contains("japanese") || lang.contains("日本") {
            return "Apple Intelligenceの安全フィルターがこのコンテンツをブロックしました。この記事には処理できない機密コンテンツ（暴力、災害など）が含まれている可能性があります。"
        } else if lang.contains("korean") || lang.contains("한국") {
            return "Apple Intelligence 안전 필터가 이 콘텐츠를 차단했습니다. 이 기사에는 처리할 수 없는 민감한 콘텐츠(폭력, 재해 등)가 포함되어 있을 수 있습니다."
        } else if lang.contains("spanish") || lang.contains("español") {
            return "Los filtros de seguridad de Apple Intelligence bloquearon este contenido. Este artículo puede contener contenido sensible (violencia, desastres, etc.) que no se puede procesar."
        } else if lang.contains("french") || lang.contains("français") {
            return "Les filtres de sécurité d'Apple Intelligence ont bloqué ce contenu. Cet article peut contenir du contenu sensible (violence, catastrophes, etc.) qui ne peut pas être traité."
        } else if lang.contains("german") || lang.contains("deutsch") {
            return "Die Sicherheitsfilter von Apple Intelligence haben diesen Inhalt blockiert. Dieser Artikel kann sensible Inhalte (Gewalt, Katastrophen usw.) enthalten, die nicht verarbeitet werden können."
        } else {
            return "Content blocked by Apple Intelligence safety filters. This article may contain sensitive content (violence, disasters, etc.) that cannot be processed."
        }
        
    default:
        return "An error occurred while processing this article."
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
        
        // Validate text
        guard !text.isEmpty, text.count > 30 else {
            let payload: [String: Any] = [
                "summary": "No readable content found.",
                "sentiment": "NA",
                "title": title,
                "url": url,
                "aiAvailable": true,
                "language": "English",
                "error": "empty_text"
            ]
            responseItem.userInfo = [SFExtensionMessageKey: ["response": payload]]
            context.completeRequest(returningItems: [responseItem], completionHandler: nil)
            return
        }
        
        let languageName = detectLanguage(inputText: text)
        os_log(.info, "Summarizing text: %d chars, language: %@", text.count, languageName)
        
        Task {
            
            do {
                // Test if Foundation Models are actually available (not just device check)
                #if targetEnvironment(simulator)
                os_log(.info, "Running in simulator - Foundation Models may not be available")
                #endif
                
                // Your existing summarizer
                let summarizer = HierarchicalSummarizer()
                
                // Quick availability test (will throw if models not available)
                do {
                    try await summarizer.testAvailability()
                } catch {
                    os_log(.error, "Foundation Models test failed: %@", String(describing: error))
                    // Re-throw the original error to be caught below
                    throw error
                }
                
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
                os_log(.error, "Generation error: %@", String(describing: genErr))
                
                // Check error type
                let errorStr = String(describing: genErr)
                let isSafetyError = errorStr.contains("safety") || errorStr.contains("deny") || errorStr.contains("blocked")
                let isContextError = errorStr.contains("context window") || errorStr.contains("token") || errorStr.contains("size")
                
                switch genErr {
                case .unsupportedLanguageOrLocale:
                    let payload: [String: Any] = [
                        "summary": "Language \(languageName) is not supported.",
                        "sentiment": "NA",
                        "title": title,
                        "url": url,
                        "aiAvailable": true,
                        "language": languageName,
                        "error": "unsupported_language"
                    ]
                    responseItem.userInfo = [SFExtensionMessageKey: ["response": payload]]
                    context.completeRequest(returningItems: [responseItem], completionHandler: nil)
                    
                @unknown default:
                    // Provide localized user-friendly messages
                    let errorMessage: String
                    let errorType: String
                    
                    if isContextError {
                        errorMessage = getLocalizedErrorMessage(for: "context_window", language: languageName)
                        errorType = "context_window"
                    } else if isSafetyError {
                        errorMessage = getLocalizedErrorMessage(for: "safety_filter", language: languageName)
                        errorType = "safety_filter"
                    } else {
                        errorMessage = "Generation failed: \(genErr.localizedDescription)"
                        errorType = "generation_error"
                    }
                    
                    let payload: [String: Any] = [
                        "summary": errorMessage,
                        "sentiment": "NA",
                        "title": title,
                        "url": url,
                        "aiAvailable": true,
                        "language": languageName,
                        "error": errorType
                    ]
                    responseItem.userInfo = [SFExtensionMessageKey: ["response": payload]]
                    context.completeRequest(returningItems: [responseItem], completionHandler: nil)
                }
                
            } catch {
                os_log(.error, "Summarization error: %@", String(describing: error))
                
                // Check error type - be very aggressive about detecting safety errors
                let errorStr = String(describing: error)
                let errorLocalizedStr = error.localizedDescription.lowercased()
                
                let isSafetyError = errorStr.contains("safety") || 
                                   errorStr.contains("deny") || 
                                   errorStr.contains("blocked") ||
                                   errorStr.contains("SafetyFilterError") ||
                                   errorLocalizedStr.contains("safety") ||
                                   errorLocalizedStr.contains("blocked")
                
                let isContextError = errorStr.contains("context window") || 
                                    errorStr.contains("token") || 
                                    errorStr.contains("size")
                
                let errorMsg: String
                let errorType: String
                let aiAvailable: Bool
                
                #if targetEnvironment(simulator)
                errorMsg = "Foundation Models not available in simulator. Test on real device."
                errorType = "simulator"
                aiAvailable = false
                #else
                if isSafetyError {
                    // Prioritize safety filter detection
                    errorMsg = getLocalizedErrorMessage(for: "safety_filter", language: languageName)
                    errorType = "safety_filter"
                    os_log(.error, "Safety filter blocked content")
                } else if isContextError {
                    errorMsg = getLocalizedErrorMessage(for: "context_window", language: languageName)
                    errorType = "context_window"
                } else {
                    errorMsg = "Unexpected error: \(error.localizedDescription)"
                    errorType = "unknown"
                }
                aiAvailable = true
                #endif
                
                let payload: [String: Any] = [
                    "summary": errorMsg,
                    "sentiment": "NA",
                    "title": title,
                    "url": url,
                    "aiAvailable": aiAvailable,
                    "language": languageName,
                    "error": errorType
                ]
                responseItem.userInfo = [SFExtensionMessageKey: ["response": payload]]
                context.completeRequest(returningItems: [responseItem], completionHandler: nil)
            }
        }
    }
}

