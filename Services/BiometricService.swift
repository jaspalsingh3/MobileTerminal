//
//  BiometricService.swift
//  Mobile Terminal
//
//  Face ID / Touch ID authentication for secure server access
//

import Foundation
import LocalAuthentication

final class BiometricService: ObservableObject {
    static let shared = BiometricService()

    @Published var isAvailable = false
    @Published var biometricType: BiometricType = .none

    enum BiometricType {
        case none
        case touchID
        case faceID

        var displayName: String {
            switch self {
            case .none: return "Biometrics"
            case .touchID: return "Touch ID"
            case .faceID: return "Face ID"
            }
        }

        var iconName: String {
            switch self {
            case .none: return "lock"
            case .touchID: return "touchid"
            case .faceID: return "faceid"
            }
        }
    }

    private init() {
        checkAvailability()
    }

    /// Check if biometric authentication is available
    func checkAvailability() {
        let context = LAContext()
        var error: NSError?

        isAvailable = context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error)

        if isAvailable {
            switch context.biometryType {
            case .touchID:
                biometricType = .touchID
            case .faceID:
                biometricType = .faceID
            default:
                biometricType = .none
            }
        } else {
            biometricType = .none
        }
    }

    /// Authenticate using biometrics
    /// - Parameters:
    ///   - reason: The reason shown to the user for authentication
    ///   - completion: Callback with success or error
    func authenticate(reason: String) async -> Result<Void, BiometricError> {
        guard isAvailable else {
            return .failure(.notAvailable)
        }

        let context = LAContext()
        context.localizedFallbackTitle = "Enter Password"

        do {
            let success = try await context.evaluatePolicy(
                .deviceOwnerAuthenticationWithBiometrics,
                localizedReason: reason
            )

            if success {
                return .success(())
            } else {
                return .failure(.failed)
            }
        } catch let error as LAError {
            switch error.code {
            case .userCancel:
                return .failure(.userCancelled)
            case .userFallback:
                return .failure(.userFallback)
            case .biometryLockout:
                return .failure(.lockout)
            case .biometryNotAvailable:
                return .failure(.notAvailable)
            case .biometryNotEnrolled:
                return .failure(.notEnrolled)
            default:
                return .failure(.failed)
            }
        } catch {
            return .failure(.failed)
        }
    }

    /// Quick authenticate for server connection
    func authenticateForServer(_ serverName: String) async -> Result<Void, BiometricError> {
        return await authenticate(reason: "Authenticate to connect to \(serverName)")
    }

    enum BiometricError: Error, LocalizedError {
        case notAvailable
        case notEnrolled
        case userCancelled
        case userFallback
        case lockout
        case failed

        var errorDescription: String? {
            switch self {
            case .notAvailable:
                return "Biometric authentication is not available on this device"
            case .notEnrolled:
                return "No biometric data enrolled. Please set up Face ID or Touch ID in Settings"
            case .userCancelled:
                return "Authentication was cancelled"
            case .userFallback:
                return "User chose to enter password instead"
            case .lockout:
                return "Biometric authentication is locked. Please use your passcode"
            case .failed:
                return "Authentication failed"
            }
        }
    }
}
