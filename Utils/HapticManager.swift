//
//  HapticManager.swift
//  Mobile Terminal
//
//  Haptic feedback manager for terminal interactions
//

import SwiftUI
#if os(iOS)
import UIKit

final class HapticManager {
    static let shared = HapticManager()

    private let lightGenerator = UIImpactFeedbackGenerator(style: .light)
    private let mediumGenerator = UIImpactFeedbackGenerator(style: .medium)
    private let heavyGenerator = UIImpactFeedbackGenerator(style: .heavy)
    private let selectionGenerator = UISelectionFeedbackGenerator()
    private let notificationGenerator = UINotificationFeedbackGenerator()

    private init() {
        prepareGenerators()
    }

    func prepareGenerators() {
        lightGenerator.prepare()
        mediumGenerator.prepare()
        heavyGenerator.prepare()
        selectionGenerator.prepare()
        notificationGenerator.prepare()
    }

    /// Light tap - for button presses
    func lightTap() {
        lightGenerator.impactOccurred()
    }

    /// Medium impact - for command sends
    func mediumImpact() {
        mediumGenerator.impactOccurred()
    }

    /// Heavy impact - for significant actions
    func heavyImpact() {
        heavyGenerator.impactOccurred()
    }

    /// Selection feedback - for scrolling through options
    func selection() {
        selectionGenerator.selectionChanged()
    }

    /// Success vibration
    func success() {
        notificationGenerator.notificationOccurred(.success)
    }

    /// Error vibration
    func error() {
        notificationGenerator.notificationOccurred(.error)
    }

    /// Warning vibration
    func warning() {
        notificationGenerator.notificationOccurred(.warning)
    }
}

#else
// macOS stub
final class HapticManager {
    static let shared = HapticManager()
    private init() {}

    func prepareGenerators() {}
    func lightTap() {}
    func mediumImpact() {}
    func heavyImpact() {}
    func selection() {}
    func success() {}
    func error() {}
    func warning() {}
}
#endif
