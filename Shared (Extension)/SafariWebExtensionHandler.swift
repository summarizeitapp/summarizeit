//
//  SafariWebExtensionHandler.swift
//  Shared (Extension)
//
//  Created by SN on 5/8/25.
//

import SafariServices
import os.log
import FoundationModels
import NaturalLanguage
import Foundation

private let log = Logger(subsystem: "com.summarizeit.SummarizeIt", category: "WebExt")
class SafariWebExtensionHandler: NSObject, NSExtensionRequestHandling {
    
    
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
    func beginRequest(with context: NSExtensionContext) {
        
        
        // 1. Read input
        guard let item = context.inputItems.first as? NSExtensionItem,
              let userInfo = item.userInfo as? [String: Any],
              let message = userInfo["message"] as? [String: Any],
              let _ = message["action"] as? String else {
            context.completeRequest(returningItems: nil, completionHandler: nil)
            return
        }
        
        
        let responseItem = NSExtensionItem()
        Task{
            
            let languageName = self.detectLanguage(inputText: message["text"] as? String ?? "English")
            
            do{
                let summarizer = HierarchicalSummarizer()
                let output = try await summarizer.analyzeTextHierarchical(inputText: message["text"] as? String ?? "", language: languageName)
                let payload : [String: Any] = ["summary": output.summaryText, "sentiment": output.sentiment, "title":message["title"] ?? "", "url":message["article_url"] ?? ""]
                responseItem.userInfo = [SFExtensionMessageKey: ["response": payload]]
                context.completeRequest(returningItems: [responseItem] , completionHandler: nil)
            }
            catch let error as LanguageModelSession.GenerationError {
                switch error {
                case .unsupportedLanguageOrLocale:
                    // Fallback: retry with English
                    let payload : [String: Any] = ["summary": "Language \(languageName) not supported.", "sentiment": "NA", "title":message["title"] ?? "", "url":message["article_url"] ?? ""]
                    responseItem.userInfo = [SFExtensionMessageKey: ["response": payload]]
                    context.completeRequest(returningItems: [responseItem] , completionHandler: nil)
                default:
                    print("Other generation error: \(error)")
                    
                }
            }
        }
    }
    
    
    
}
