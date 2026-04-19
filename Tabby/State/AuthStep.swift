import Foundation

enum AuthStep: Equatable {
    case launching
    case needApiCreds
    case needPhoneNumber
    case needAuthCode
    case needPassword(hint: String?)
    case needBotSelection
    case authenticated
    case error(String)

    var isWizardStep: Bool {
        switch self {
        case .needApiCreds, .needPhoneNumber, .needAuthCode, .needPassword, .needBotSelection:
            return true
        default:
            return false
        }
    }
}
