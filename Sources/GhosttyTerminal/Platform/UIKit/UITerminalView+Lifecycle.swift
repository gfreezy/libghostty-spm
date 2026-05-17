//
//  UITerminalView+Lifecycle.swift
//  libghostty-spm
//
//  Created by Lakr233 on 2026/3/17.
//

#if canImport(UIKit)
    import UIKit

    public extension UITerminalView {
        override func didMoveToWindow() {
            super.didMoveToWindow()
            TerminalDebugLog.log(
                .lifecycle,
                "didMoveToWindow attached=\(window != nil)"
            )
            updateDisplayScale()
            if window != nil {
                core.rebuildIfReady()
                updateColorScheme()
                core.startDisplayLink()
                // Defer sublayer frame and metrics sync to the next runloop
                // so that AutoLayout has resolved final bounds.
                DispatchQueue.main.async { [weak self] in
                    guard let self, window != nil else { return }
                    updateSublayerFrames()
                    core.synchronizeMetrics()
                }
            } else {
                core.stopDisplayLink()
                core.freeSurface()
            }
        }

        override func layoutSubviews() {
            super.layoutSubviews()
            TerminalDebugLog.log(
                .metrics,
                "layoutSubviews bounds=\(NSCoder.string(for: bounds))"
            )
            updateSublayerFrames()
            core.synchronizeMetrics()
        }

        internal func resolvedDisplayScale() -> CGFloat {
            if let screen = window?.screen {
                return screen.nativeScale
            }
            if traitCollection.displayScale > 0 {
                return traitCollection.displayScale
            }
            return UIScreen.main.nativeScale
        }

        internal func updateDisplayScale() {
            let scale = resolvedDisplayScale()
            TerminalDebugLog.log(
                .metrics,
                "updateDisplayScale scale=\(String(format: "%.2f", scale))"
            )
            contentScaleFactor = scale
            layer.contentsScale = scale
            updateSublayerFrames()
        }

        internal func updateSublayerFrames() {
            let scale = resolvedDisplayScale()
            contentScaleFactor = scale
            layer.contentsScale = scale
            guard let sublayers = layer.sublayers else { return }
            for sublayer in sublayers {
                sublayer.frame = bounds
                sublayer.contentsScale = scale
            }
        }

        internal func enforceSublayerScale() {
            let scale = resolvedDisplayScale()
            guard let sublayers = layer.sublayers else { return }
            for sublayer in sublayers {
                if sublayer.contentsScale != scale {
                    sublayer.contentsScale = scale
                }
                if sublayer.frame != bounds {
                    sublayer.frame = bounds
                }
            }
        }

        func fitToSize() {
            core.fitToSize()
        }

        override func traitCollectionDidChange(
            _ previousTraitCollection: UITraitCollection?
        ) {
            super.traitCollectionDidChange(previousTraitCollection)
            updateDisplayScale()
            if traitCollection.hasDifferentColorAppearance(
                comparedTo: previousTraitCollection
            ) {
                updateColorScheme()
            }
        }

        internal func updateColorScheme() {
            let style = traitCollection.userInterfaceStyle
            let scheme: TerminalColorScheme = style == .dark ? .dark : .light
            TerminalDebugLog.log(.lifecycle, "updateColorScheme scheme=\(scheme)")
            surface?.setColorScheme(scheme.ghosttyValue)
            controller?.setColorScheme(scheme)
        }

        @discardableResult
        open override func becomeFirstResponder() -> Bool {
            let result = super.becomeFirstResponder()
            core.setFocus(true)
            return result
        }

        @discardableResult
        open override func resignFirstResponder() -> Bool {
            let result = super.resignFirstResponder()
            core.setFocus(false)
            #if !targetEnvironment(macCatalyst)
                if result {
                    // Another responder (e.g. a sibling SwiftUI TextField) just took
                    // over the keyboard. iOS hands the keyboard to the new FR without
                    // firing keyboardDidHide, so without this reset
                    // softwareKeyboardVisible would stay `true` — and the next tap on
                    // the terminal would route into the "dismiss-on-touchEnd" branch
                    // of touchesBegan instead of calling becomeFirstResponder,
                    // leaving the terminal unable to reclaim focus.
                    softwareKeyboardVisible = false
                    pendingKeyboardDismissOnTouchEnd = false
                }
            #endif
            return result
        }
    }
#endif
