//
//  AppLocalization.swift
//  MinisApp
//
//  [T-ios-inapp-language-string-localized] Makes the in-app language picker
//  actually apply to every localized string, not just some of them.
//
//  The problem
//  -----------
//  `Bundle.enableLanguageOverride()` (MinisApp.swift) swizzles
//  `Bundle.localizedString(forKey:value:table:)` so the in-app language choice
//  is honoured without an app restart. That works for `Text("…")` and UIKit,
//  which route through that ObjC method — but `String(localized:)` does NOT.
//
//  Measured, not assumed. With the swizzle installed:
//
//      NSLocalizedString("k")   -> Bundle.localizedString hits: 1
//      String(localized: "k")   -> Bundle.localizedString hits: 0
//
//  Three interception strategies were tried against a real bundle and all
//  three failed to redirect `String(localized:)`:
//    1. method swizzling `localizedString(forKey:value:table:)`   — bypassed
//    2. `object_setClass` onto a Bundle subclass overriding it    — bypassed
//    3. overriding `preferredLocalizations` / `localizations`     — bypassed
//  `String(localized:)` resolves the table natively inside Foundation and
//  never calls back into the ObjC entry point, so nothing installed on
//  `Bundle.main` can steer it. Setting `AppleLanguages` does work, but only
//  from the NEXT process launch — verified: `preferredLocalizations` does not
//  change within the running process.
//
//  What DOES work is the one documented seam: `String(localized:bundle:)`
//  honours an explicit bundle. Verified against `es.lproj` / `de.lproj` /
//  `en.lproj` — each returns that language's value.
//
//  The fix
//  -------
//  Route every call through `AppBundle.current`, which is the overridden
//  `.lproj` bundle when the user has picked a language in-app, and
//  `Bundle.main` otherwise. This is deliberately generic: it is keyed off
//  whatever language is selected, so de / fr / ja / ko / ru / zh-Hans /
//  zh-Hant / es all behave the same. Nothing here is Spanish-specific.
//

import Foundation

/// The bundle localized lookups should read from.
///
/// Mirrors `Bundle.main.languageBundle` (set by `Bundle.setLanguage(_:)`), so
/// the in-app picker and this helper can never disagree about which language is
/// active. Falls back to `Bundle.main` when no in-app override is set, which is
/// the normal case — the system language then applies exactly as before.
enum AppBundle {
    static var current: Bundle {
        Bundle.main.languageBundle ?? Bundle.main
    }
}

/// Localized string that follows the in-app language override.
///
/// Drop-in replacement for `String(localized:)`. Prefer this over
/// `String(localized:)` anywhere the result is shown to the user: the bare
/// form silently ignores the in-app language setting (see the file comment),
/// which is what produced mixed-language UI for users whose system language
/// differs from their in-app choice.
///
/// `Text("…")` does not need this — SwiftUI's `Text` routes through
/// `NSLocalizedString`, which the existing swizzle already covers.
///
/// - Parameters:
///   - key: the localization key, i.e. the English source string.
///   - comment: translator context, kept so `genstrings`-style extraction and
///     the String Catalog continue to see it.
func AppLocalized(_ key: String, comment: StaticString? = nil) -> String {
    let bundle = AppBundle.current
    if let hit = LocalizedStringCache.lookup(key, bundle: bundle) { return hit }
    let value = bundle.localizedString(forKey: key, value: key, table: nil)
    LocalizedStringCache.store(value, for: key, bundle: bundle)
    return value
}

/// [T-composer-typing-lag] Process-wide memo for `AppLocalized`, keyed by the
/// localization key and scoped to the bundle it was resolved from, so an
/// in-app language switch (a different `.lproj` bundle) starts a fresh table.
enum LocalizedStringCache {
    private static let lock = NSLock()
    private static var table: [String: String] = [:]
    private static var tableBundle: ObjectIdentifier?
    /// Bounds memory if a caller ever feeds unbounded distinct keys.
    static let capacity = 4096

    static func lookup(_ key: String, bundle: Bundle) -> String? {
        lock.lock(); defer { lock.unlock() }
        guard tableBundle == ObjectIdentifier(bundle) else { return nil }
        return table[key]
    }

    static func store(_ value: String, for key: String, bundle: Bundle) {
        lock.lock(); defer { lock.unlock() }
        let id = ObjectIdentifier(bundle)
        if tableBundle != id || table.count >= capacity {
            table.removeAll(keepingCapacity: true)
            tableBundle = id
        }
        table[key] = value
    }
}

/// `LocalizedStringResource` overload, for call sites that already hold a
/// resource (App Intents build these) rather than a literal key.
///
/// [T-composer-typing-lag] Labeled on purpose. Unlabeled, a string literal can
/// convert to `LocalizedStringResource` too, and overload resolution picked
/// THIS overload for every `AppLocalized("…")` written without `comment:` —
/// most call sites. That bypassed the StaticString cache (the iOS 16 trace
/// still showed AppLocalized at 18% of the main thread while merely typing)
/// and the in-app language bundle alike. With the label, literals can only
/// reach the StaticString (plain) or LocalizationValue (interpolated) forms.
func AppLocalized(resource: LocalizedStringResource) -> String {
    // A LocalizedStringResource carries its own bundle reference, so it cannot
    // be re-pointed the way a literal key can. Resolve it as-is rather than
    // pretending the override applies.
    String(localized: resource)
}
