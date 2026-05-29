//
//  UITerminalView+PublicInput.swift
//  libghostty-spm
//
//  Public wrappers around `TerminalSurface` binding-action paths so iOS
//  hosts can drive named Ghostty actions without reaching for internal
//  API. Mirrors `AppTerminalView+PublicInput.swift` (AppKit).
//

#if canImport(UIKit) && !targetEnvironment(macCatalyst)
    import Foundation
    import UIKit

    @MainActor
    public extension UITerminalView {
        /// Invoke a named Ghostty binding action (e.g. "copy_to_clipboard",
        /// "scroll_to_bottom"). Returns true when the action dispatched.
        /// No-op (returns false) when the surface has not been created yet.
        @discardableResult
        func performBindingAction(_ action: String) -> Bool {
            surface?.performBindingAction(action) ?? false
        }

        /// Scroll the viewport to the bottom (most recent output), as if the
        /// user pressed a `scroll_to_bottom`-bound key. Handy for hosts whose
        /// text input lives in a *separate* view — typing there never reaches
        /// the surface, so the viewport won't auto-pin to the bottom on its
        /// own. Returns true when the action dispatched.
        @discardableResult
        func scrollToBottom() -> Bool {
            performBindingAction("scroll_to_bottom")
        }
    }
#endif
