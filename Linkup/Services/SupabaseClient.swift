// SupabaseClient.swift
// Thin singleton wrapper around the `supabase-swift` SDK. Reads SUPABASE_URL
// and SUPABASE_ANON_KEY from Info.plist and gracefully degrades to `nil` when
// the anon key is still the ####### placeholder. Callers that need live auth
// check `LinkupSupabase.shared` before invoking it; AuthService falls back to
// the legacy local-UserDefaults path when this is nil so a single-device demo
// still works.
//
// MARK: - REQUIRES SPM
//
// Before this compiles, Josh must add the Supabase Swift SDK in Xcode:
//   File -> Add Package Dependencies...
//   URL:  https://github.com/supabase-community/supabase-swift
//   Version: Up to Next Major, starting from 2.0.0
//   Products to add to the `Linkup` target: `Supabase`, `Auth`
//
// All Supabase imports below are wrapped in `#if canImport(Supabase)` so the
// project keeps compiling until the package is added — the live path simply
// stays disabled and the fallback runs.

import Foundation

#if canImport(Supabase)
import Supabase
import Auth
#endif

enum LinkupSupabaseConfigError: Error {
    case missingURL
    case missingAnonKey
}

/// Singleton holder. `shared` is nil whenever Supabase is unconfigured (either
/// the SPM package hasn't been added yet, or the anon key in Info.plist is
/// still the `#######` placeholder). Callers branch on this.
@MainActor
final class LinkupSupabase {
    static let shared: LinkupSupabase? = LinkupSupabase.bootstrap()

    #if canImport(Supabase)
    let client: SupabaseClient
    var auth: AuthClient { client.auth }
    #endif

    let supabaseURL: URL
    let anonKey: String

    private init(url: URL, anonKey: String) {
        self.supabaseURL = url
        self.anonKey = anonKey
        #if canImport(Supabase)
        self.client = SupabaseClient(supabaseURL: url, supabaseKey: anonKey)
        #endif
    }

    private static func bootstrap() -> LinkupSupabase? {
        guard let url = readURL("SUPABASE_URL") else {
            #if DEBUG
            print("[Linkup] Supabase disabled: SUPABASE_URL missing from Info.plist")
            #endif
            return nil
        }
        guard let anonKey = readKey("SUPABASE_ANON_KEY") else {
            #if DEBUG
            print("[Linkup] Supabase disabled: SUPABASE_ANON_KEY is still a placeholder. Auth will fall back to local UserDefaults.")
            #endif
            return nil
        }
        #if !canImport(Supabase)
        #if DEBUG
        print("[Linkup] Supabase SDK not linked — add the supabase-swift SPM package in Xcode to enable cross-device auth.")
        #endif
        return nil
        #else
        return LinkupSupabase(url: url, anonKey: anonKey)
        #endif
    }

    private static func readURL(_ key: String) -> URL? {
        guard let raw = Bundle.main.object(forInfoDictionaryKey: key) as? String else { return nil }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              !trimmed.contains("#######"),
              !trimmed.contains("REPLACE_WITH"),
              let url = URL(string: trimmed) else {
            return nil
        }
        return url
    }

    private static func readKey(_ key: String) -> String? {
        guard let raw = Bundle.main.object(forInfoDictionaryKey: key) as? String else { return nil }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              !trimmed.contains("#######"),
              !trimmed.contains("REPLACE_WITH") else {
            return nil
        }
        return trimmed
    }
}
