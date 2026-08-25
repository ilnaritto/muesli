import Foundation
import MuesliCore

/// Backs `ConfiguredModel.keychainRef`. The field keeps that name for
/// forward-compatibility with a real Keychain-backed implementation later —
/// swapping the backing store here would not require touching
/// `ConfiguredModel` or any call site.
///
/// For now secrets live in a single owner-only (0600), backup-excluded JSON
/// file — the same pattern `ChatGPTAuthManager` already uses for OAuth
/// tokens. A prior audit pass deliberately moved those OFF Keychain to avoid
/// the system access-prompt UX cost (see
/// docs/reports/2026-03-19-audit-hardening-report.md); the product decision
/// on whether the model registry should use real Keychain instead is still
/// open — do not change this without checking first.
enum ModelSecretsStore {
    private static var fileURL: URL {
        AppIdentity.supportDirectoryURL.appendingPathComponent("model-secrets.json")
    }

    private static func readAll() -> [String: String] {
        guard let data = try? Data(contentsOf: fileURL),
              let dict = try? JSONDecoder().decode([String: String].self, from: data) else {
            return [:]
        }
        return dict
    }

    private static func writeAll(_ dict: [String: String]) {
        do {
            let dir = fileURL.deletingLastPathComponent()
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            let data = try JSONEncoder().encode(dict)
            try data.write(to: fileURL, options: .atomic)
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: fileURL.path)
            var url = fileURL
            var resourceValues = URLResourceValues()
            resourceValues.isExcludedFromBackup = true
            try? url.setResourceValues(resourceValues)
        } catch {
            fputs("[model-secrets] failed to save: \(error)\n", stderr)
        }
    }

    /// Stores `secret` under a freshly generated reference and returns it.
    @discardableResult
    static func save(_ secret: String) -> String {
        var all = readAll()
        let ref = UUID().uuidString
        all[ref] = secret
        writeAll(all)
        return ref
    }

    /// Overwrites the secret at an existing reference (editing a model).
    static func update(ref: String, secret: String) {
        var all = readAll()
        all[ref] = secret
        writeAll(all)
    }

    static func read(ref: String?) -> String? {
        guard let ref else { return nil }
        return readAll()[ref]
    }

    static func delete(ref: String?) {
        guard let ref else { return }
        var all = readAll()
        all.removeValue(forKey: ref)
        writeAll(all)
    }
}
