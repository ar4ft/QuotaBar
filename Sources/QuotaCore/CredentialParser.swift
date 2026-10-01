import Foundation

public enum CredentialParser {
    public static func parse(_ data: Data, provider: Provider, ownsLogin: Bool = false) throws -> Credential {
        guard data.count <= 1_048_576,
              let root = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw QuotaError.invalidCredentials
        }
        switch provider {
        case .openAI:
            guard let tokens = root["tokens"] as? [String: Any],
                  let token = tokens["access_token"] as? String, !token.isEmpty else {
                throw QuotaError.invalidCredentials
            }
            let claims = jwtClaims(tokens["id_token"] as? String ?? token)
            let auth = claims?["https://api.openai.com/auth"] as? [String: Any]
            var credential = Credential(kind: .codex, secret: token,
                              accountID: tokens["account_id"] as? String ?? auth?["chatgpt_account_id"] as? String,
                              email: claims?["email"] as? String,
                              refreshToken: ownsLogin ? tokens["refresh_token"] as? String : nil)
            credential.nativeSession = data
            return credential
        case .claude:
            let oauth = root["claudeAiOauth"] as? [String: Any] ?? root
            guard let token = oauth["accessToken"] as? String, !token.isEmpty else {
                throw QuotaError.invalidCredentials
            }
            var credential = Credential(kind: .claudeOAuth, secret: token)
            if root["claudeAiOauth"] != nil { credential.nativeSession = data }
            return credential
        }
    }
    // Claims are used only as display metadata, never as a signature or authorization check.
    private static func jwtClaims(_ token: String) -> [String: Any]? {
        let parts = token.split(separator: ".")
        guard parts.count == 3 else { return nil }
        var payload = String(parts[1]).replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        payload += String(repeating: "=", count: (4 - payload.count % 4) % 4)
        guard let data = Data(base64Encoded: payload) else { return nil }
        return (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
    }
}
