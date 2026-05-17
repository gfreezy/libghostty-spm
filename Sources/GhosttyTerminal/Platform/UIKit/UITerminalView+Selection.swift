//
//  UITerminalView+Selection.swift
//  libghostty-spm
//
//  Hold-and-drag selection + iOS edit menu (Copy / Select All / Paste).
//  AppKit gets selection for free from mouse drag; on iOS the same C
//  API (`ghostty_surface_mouse_*`) needs a gesture to feed it touches.
//

#if canImport(UIKit) && !targetEnvironment(macCatalyst)
    import GhosttyKit
    import UIKit

    // UIEditMenuInteractionDelegate isn't @MainActor-annotated in UIKit
    // headers, but UITerminalView is — UIKit only calls these on main
    // anyway, so flag the conformance `@preconcurrency` to defer the
    // strict-isolation check at the protocol witness boundary.
    extension UITerminalView: @preconcurrency UIEditMenuInteractionDelegate {
        func setupSelectionGesture() {
            // Long-press-and-drag drives a libghostty selection by
            // synthesizing mouse PRESS / MOVE / RELEASE at the touch
            // point. Coexists with the scroll pan because pan needs
            // movement to recognize (~10pt) while long-press needs
            // duration without movement (~0.5s) — first recognizer to
            // fire claims the touch, so a quick drag still scrolls.
            let longPress = UILongPressGestureRecognizer(
                target: self,
                action: #selector(handleSelectionLongPress(_:))
            )
            longPress.minimumPressDuration = 0.5
            addGestureRecognizer(longPress)

            // A plain tap with an existing selection clears it via a
            // synthetic left click — matches every other terminal app
            // and prevents stale highlights from sticking around after
            // the user moves on.
            let tap = UITapGestureRecognizer(
                target: self,
                action: #selector(handleSelectionTap(_:))
            )
            // Keep the touch flowing to `touchesBegan` so the tap-to-
            // focus / keyboard-raise logic in UITerminalView+Interaction
            // still runs.
            tap.cancelsTouchesInView = false
            addGestureRecognizer(tap)

            let interaction = UIEditMenuInteraction(delegate: self)
            addInteraction(interaction)
            editMenuInteraction = interaction
        }

        @objc func handleSelectionLongPress(_ gesture: UILongPressGestureRecognizer) {
            guard let surface else { return }
            let location = gesture.location(in: self)
            let mods = ghostty_input_mods_e(rawValue: 0)

            switch gesture.state {
            case .began:
                surface.sendMousePos(
                    x: Double(location.x),
                    y: Double(location.y),
                    mods: mods
                )
                surface.sendMouseButton(
                    state: GHOSTTY_MOUSE_PRESS,
                    button: GHOSTTY_MOUSE_LEFT,
                    mods: mods
                )

            case .changed:
                surface.sendMousePos(
                    x: Double(location.x),
                    y: Double(location.y),
                    mods: mods
                )

            case .ended, .cancelled, .failed:
                surface.sendMousePos(
                    x: Double(location.x),
                    y: Double(location.y),
                    mods: mods
                )
                surface.sendMouseButton(
                    state: GHOSTTY_MOUSE_RELEASE,
                    button: GHOSTTY_MOUSE_LEFT,
                    mods: mods
                )
                // Only present the menu on a clean end; .cancelled
                // typically means the system pulled the touch out from
                // under us (e.g. responder change), and popping a menu
                // there would feel like a glitch.
                if gesture.state == .ended {
                    presentEditMenu(at: location)
                }

            default:
                break
            }
        }

        @objc func handleSelectionTap(_ gesture: UITapGestureRecognizer) {
            guard let surface, surface.hasSelection else { return }
            // libghostty treats a left click without drag as "clear
            // selection (and move the mouse-tracking cursor)" — same
            // behavior as a desktop terminal.
            let p = gesture.location(in: self)
            let mods = ghostty_input_mods_e(rawValue: 0)
            surface.sendMousePos(x: Double(p.x), y: Double(p.y), mods: mods)
            surface.sendMouseButton(
                state: GHOSTTY_MOUSE_PRESS,
                button: GHOSTTY_MOUSE_LEFT,
                mods: mods
            )
            surface.sendMouseButton(
                state: GHOSTTY_MOUSE_RELEASE,
                button: GHOSTTY_MOUSE_LEFT,
                mods: mods
            )
        }

        func presentEditMenu(at point: CGPoint) {
            guard let interaction = editMenuInteraction else { return }
            let config = UIEditMenuConfiguration(
                identifier: nil,
                sourcePoint: point
            )
            interaction.presentEditMenu(with: config)
        }

        // MARK: - UIEditMenuInteractionDelegate

        public func editMenuInteraction(
            _: UIEditMenuInteraction,
            menuFor _: UIEditMenuConfiguration,
            suggestedActions _: [UIMenuElement]
        ) -> UIMenu? {
            var children: [UIMenuElement] = []
            if canPerformAction(
                #selector(UIResponderStandardEditActions.copy(_:)),
                withSender: nil
            ) {
                children.append(UIAction(title: NSLocalizedString("Copy", comment: "")) { [weak self] _ in
                    self?.copy(nil)
                })
            }
            if canPerformAction(
                #selector(UIResponderStandardEditActions.paste(_:)),
                withSender: nil
            ) {
                children.append(UIAction(title: NSLocalizedString("Paste", comment: "")) { [weak self] _ in
                    self?.paste(nil)
                })
            }
            if canPerformAction(
                #selector(UIResponderStandardEditActions.selectAll(_:)),
                withSender: nil
            ) {
                children.append(UIAction(title: NSLocalizedString("Select All", comment: "")) { [weak self] _ in
                    self?.selectAll(nil)
                })
            }
            return UIMenu(children: children)
        }

        // MARK: - UIResponderStandardEditActions

        open override func copy(_: Any?) {
            _ = surface?.performBindingAction("copy_to_clipboard")
        }

        open override func paste(_: Any?) {
            _ = surface?.performBindingAction("paste_from_clipboard")
        }

        open override func selectAll(_: Any?) {
            _ = surface?.performBindingAction("select_all")
        }

        open override func canPerformAction(
            _ action: Selector,
            withSender sender: Any?
        ) -> Bool {
            switch action {
            case #selector(UIResponderStandardEditActions.copy(_:)):
                return surface?.hasSelection ?? false
            case #selector(UIResponderStandardEditActions.paste(_:)):
                return UIPasteboard.general.hasStrings
            case #selector(UIResponderStandardEditActions.selectAll(_:)):
                return surface != nil
            default:
                return super.canPerformAction(action, withSender: sender)
            }
        }
    }
#endif
