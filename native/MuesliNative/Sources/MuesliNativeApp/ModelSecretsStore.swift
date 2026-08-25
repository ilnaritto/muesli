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
    /// Tests only: redirects the store to a temp file so test runs never
    /// touch the real app-support directory (or race each other through it).
    /// Production code must never set this.
    nonisolated(unsafe) static var fileURLOverride: URL?

    private static var fileURL: URL {
        fileURLOverride ?? AppIdentity.supportDirectoryURL.appendingPathComponent("model-secrets.json")
    }

    private static func readAll(at fileURL: URL) -> [String: String] {
        guard let data = try? Data(contentsOf: fileURL),
              let dict = try? JSONDecoder().decode([String: String].self, from: data) else {
            return [:]
        }
        return dict
    }

    private static func writeAll(_ dict: [String: String], at fileURL: URL) {
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
    static func save(_ secret: String, in explicitFileURL: URL? = nil) -> String {
        let url = explicitFileURL ?? fileURL
        var all = readAll(at: url)
        let ref = UUID().uuidString
        all[ref] = secret
        writeAll(all, at: url)
        return ref
    }

    /// Overwrites the secret at an existing reference (editing a model).
    static func update(ref: String, secret: String, in explicitFileURL: URL? = nil) {
        let url = explicitFileURL ?? fileURL
        var all = readAll(at: url)
        all[ref] = secret
        writeAll(all, at: url)
    }

    static func read(ref: String?, in explicitFileURL: URL? = nil) -> String? {
        guard let ref else { return nil }
        return readAll(at: explicitFileURL ?? fileURL)[ref]
    }

    static func delete(ref: String?, in explicitFileURL: URL? = nil) {
        guard let ref else { return }
        let url = explicitFileURL ?? fileURL
        var all = readAll(at: url)
        all.removeValue(forKey: ref)
        writeAll(all, at: url)
    }
}
