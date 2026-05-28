//
//  UITerminalView+Selection.swift
//  libghostty-spm
//
//  Minimal iOS selection workflow:
//
//  - Long-press → libghostty selection (PRESS / POS / RELEASE on the
//    mouse API). On release the edit menu pops up at the touch point.
//  - Any tap while libghostty has a selection → synthetic left click
//    to clear it (no inside/outside distinction; without handles there
//    is no robust way to draw or hit-test a selection rect from the
//    Swift side, and libghostty offers no geometry for the live
//    selection beyond `tl_px_*` which is in baseline-shifted display
//    points — not useful for hit testing).
//  - Tap with no libghostty selection → toggle keyboard focus.
//
//  The non-Catalyst-only `@preconcurrency UIEditMenuInteractionDelegate`
//  conformance is the same shape AppKit's NSTextInputClient uses for
//  IME — UIKit only invokes these on main even though the header isn't
//  annotated.
//

#if canImport(UIKit) && !targetEnvironment(macCatalyst)
    import GhosttyKit
    import UIKit

    extension UITerminalView: @preconcurrency UIEditMenuInteractionDelegate {
        func setupSelectionGesture() {
            let longPress = UILongPressGestureRecognizer(
                target: self,
                action: #selector(handleSelectionLongPress(_:))
            )
            longPress.minimumPressDuration = 0.5
            addGestureRecognizer(longPress)

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
                // IME composition holds a marked-text range. Letting the
                // selection drag run here would force libghostty to drop
                // composition mid-stroke. Skip the gesture instead.
                if inputHandler.hasMarkedText {
                    longPressSuppressedForIME = true
                    return
                }
                longPressSuppressedForIME = false

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
                guard !longPressSuppressedForIME else { return }
                surface.sendMousePos(
                    x: Double(location.x),
                    y: Double(location.y),
                    mods: mods
                )

            case .ended, .cancelled, .failed:
                guard !longPressSuppressedForIME else {
                    longPressSuppressedForIME = false
                    return
                }
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
                if gesture.state == .ended, surface.hasSelection {
                    presentEditMenu(at: location)
                }

            default:
                break
            }
        }

        /// Send a synthetic left click to libghostty so it drops any
        /// active selection. A press+release at the same point without
        /// drag is libghostty's standard deselect.
        func clearLibghosttySelection(at point: CGPoint) {
            guard let surface, surface.hasSelection else { return }
            let mods = ghostty_input_mods_e(rawValue: 0)
            surface.sendMousePos(x: Double(point.x), y: Double(point.y), mods: mods)
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
