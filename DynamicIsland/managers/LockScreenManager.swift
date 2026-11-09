/*
 * Atoll (DynamicIsland)
 * Copyright (C) 2024-2026 Atoll Contributors
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with this program. If not, see <https://www.gnu.org/licenses/>.
 */

import Foundation
import Combine
import AppKit

enum LockScreenAnimationTimings {
    static let lockExpand: TimeInterval = 0.45
    static let unlockCollapse: TimeInterval = 0.82
    static let postUnlockMusicHUDPause: TimeInterval = 1.0
    static let postUnlockMusicHUDReveal: TimeInterval = 0.34
}

/// Session state only. This build has no lock-screen windows, audio or animation.
@MainActor
final class LockScreenManager: ObservableObject {
    static let shared = LockScreenManager()
    @Published var isLocked = false
    @Published var isLockIdle = true
    @Published var shouldDelayPostUnlockMusicHUD = false
    @Published var lastUpdated: Date = .distantPast
    private weak var viewModel: DynamicIslandViewModel?
    private init() {
        DistributedNotificationCenter.default().addObserver(self,selector:#selector(locked),name:.init("com.apple.screenIsLocked"),object:nil)
        DistributedNotificationCenter.default().addObserver(self,selector:#selector(unlocked),name:.init("com.apple.screenIsUnlocked"),object:nil)
    }
    deinit { DistributedNotificationCenter.default().removeObserver(self) }
    @objc private func locked() {
        isLocked = true; isLockIdle = false; lastUpdated = Date()
        viewModel?.closeForLockScreen()
    }
    @objc private func unlocked() {
        isLocked = false; isLockIdle = true; lastUpdated = Date()
    }
    func configure(viewModel: DynamicIslandViewModel) { self.viewModel = viewModel }
    var currentLockStatus: Bool { isLocked }
    var isMonitoringAvailable: Bool { false }
}
