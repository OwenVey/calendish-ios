import Foundation

enum HouseholdCredentials {
    case email(String, password: String), signUp(String, password: String), google
    case password(String), passwordReset(String)
}
