//
//  PremiumFeatureManagers.swift
//  Sapphire
//
//  Created by Shariq Charolia on 2026-09-15

#if !SAPPHIRE_FULL_BUILD
import Combine
import Foundation


final class SystemEnhanceContextMenu {
    static let shared = SystemEnhanceContextMenu()
    private init() {}
    func installIfNeeded() {}
}

final class SystemEnhanceHingeAnimationManager {
    static let shared = SystemEnhanceHingeAnimationManager()
    private init() {}
    func start() {}
    func stop() {}
}






#endif
