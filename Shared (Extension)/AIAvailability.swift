//
//  AIAvailability.swift
//  SummarizeIt
//
//  Created by Satish Nagdev on 16/9/25.
//


import Foundation
#if canImport(UIKit)
import UIKit
#endif
enum AIAvailability {

    // --- WARNING: Simulator device checks pass, but Foundation Models APIs are NOT available
    // --- This flag only allows the extension to load in simulator for UI testing
    // --- Actual summarization will fail with "unavailable" error
    static let allowInSimulatorForDev = true

    /// Main gate - checks if device SHOULD support Apple Intelligence
    /// Note: In simulator, this returns true but actual APIs will fail
    static func isAppleIntelligenceAvailable() -> Bool {
        guard #available(iOS 26, macOS 26, *) else { return false }

        #if targetEnvironment(simulator)
        if !allowInSimulatorForDev { return false }
        // Device check passes, but actual Foundation Models are NOT available in simulator
        #endif

        #if os(iOS)
        return isiPhoneA17OrNewer() || isiPadMSeries()
        #elseif os(macOS)
        return isAppleSiliconMac()
        #else
        return false
        #endif
    }

    // MARK: - iPhone (A17 Pro and newer)
    #if os(iOS)
    private static func isiPhoneA17OrNewer() -> Bool {
        guard UIDevice.current.userInterfaceIdiom == .phone else { return false }
        let id = currentModelIdentifier()

        let iphonePrefixes = [
            "iPhone16,1", "iPhone16,2",        // 15 Pro / Pro Max – A17 Pro
            "iPhone17,1", "iPhone17,2", "iPhone17,3", "iPhone17,4", "iPhone17,5" ,// 16 family (A18/A18 Pro)
            "iPhone18,1", "iPhone18,2", "iPhone18,3", "iPhone18,4",
            // Add “iPhone18,” etc. as Apple ships newer chips
        ]
        return iphonePrefixes.contains(where: { id.hasPrefix($0) })
    }

    // MARK: - iPad (M-series only)
    private static func isiPadMSeries() -> Bool {
        guard UIDevice.current.userInterfaceIdiom == .pad else { return false }
        let id = currentModelIdentifier()

        // M-series iPads (current Apple Intelligence floor)
        let ipadPrefixes = [
            // iPad Pro Air/Mini/11"/12.9" (2021) – M1 Gen5
            "iPad13,4", "iPad13,5", "iPad13,6","iPad13,7", "iPad13,8", "iPad13,9", "iPad13,10", "iPad13,11", "iPad13,16", "iPad13,17",
            // iPad Air (2024) – M2
            "iPad14,5", "iPad14,6", "iPad14,8","iPad14,9", "iPad14,10","iPad14,11",
            //iPad Air/Pro M3
            "iPad15,3","iPad15,4","iPad15,5","iPad15,6", "iPad15,7","iPad15,8",
            // iPad Pro/Mini (2024) – M4
            "iPad16,1", "iPad16,2", "iPad16,3","iPad16,4" ,"iPad16,5","iPad16,6"
        ]
        return ipadPrefixes.contains(where: { id.hasPrefix($0) })
    }

    private static func currentModelIdentifier() -> String {
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
    #endif

    // MARK: - Mac (Apple-silicon only)
    #if os(macOS)
    private static func isAppleSiliconMac() -> Bool {
        guard let brand = sysctlString(for: "machdep.cpu.brand_string") else { return false }
        return brand.contains("Apple M1")
            || brand.contains("Apple M2")
            || brand.contains("Apple M3")
            || brand.contains("Apple M4")
    }

    private static func sysctlString(for key: String) -> String? {
        var size: size_t = 0
        sysctlbyname(key, nil, &size, nil, 0)
        guard size > 0 else { return nil }
        var buf = [CChar](repeating: 0, count: size)
        if sysctlbyname(key, &buf, &size, nil, 0) == 0 {
            return String(cString: buf)
        }
        return nil
    }
    #endif
}
