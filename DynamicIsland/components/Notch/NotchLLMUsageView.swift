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

import SwiftUI
import Defaults

struct NotchLLMUsageView: View {
    @ObservedObject private var manager = LLMUsageManager.shared

    private func isEnabled(_ provider: ProviderID) -> Bool { Defaults[provider.enabledKey] }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(BtollL10n.isEnglish ? "AI limits" : "AI 额度")
                    .font(.system(size: 16, weight: .semibold, design: .rounded))
                Spacer()
                Button {
                    manager.refreshAll(force: true)
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .buttonStyle(.plain)
                .disabled(manager.isRefreshing)
                .accessibilityLabel(BtollL10n.isEnglish ? "Refresh AI limits" : "刷新 AI 额度")
            }
            ScrollView(.horizontal) {
                HStack(alignment: .top, spacing: 10) {
                    ForEach(ProviderID.allCases.filter { isEnabled($0) }) { provider in
                        card(for: provider)
                            .frame(width: 248)
                    }
                }
            }
            .scrollIndicators(.hidden)
            if ProviderID.allCases.allSatisfy({ !isEnabled($0) }) {
                Text(BtollL10n.isEnglish ? "Enable an AI provider in Settings → Stats." : "请在设置 → 性能中启用 AI 服务。")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .environment(\.colorScheme, .dark)
        .task {
            manager.refreshAll()
            while !Task.isCancelled {
                do { try await Task.sleep(for: .seconds(60)) } catch { break }
                manager.refreshAll()
            }
        }
    }

    @ViewBuilder
    private func card(for provider: ProviderID) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(provider.displayName).font(.headline)
            switch manager.results[provider] ?? .loading {
            case .loading:
                ProgressView().controlSize(.small)
            case .failure(let reason):
                Text(BtollL10n.isEnglish ? reason : "周额度暂不可读取；请打开对应应用查看用量。")
                    .font(.caption).foregroundStyle(.secondary).lineLimit(2)
            case .success(let snap):
                success(snap, provider: provider)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 12))
    }

    @ViewBuilder
    private func success(_ snap: UsageSnapshot, provider: ProviderID) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            if let limit = snap.weekLimit {
                quotaGauge(BtollL10n.isEnglish ? "Weekly remaining" : "周额度剩余", limit)
            } else {
                Text(BtollL10n.isEnglish ? "Weekly limit unavailable" : "周额度暂不可读取")
                    .font(.caption).foregroundStyle(.secondary)
            }
            HStack {
                Text(provider == .grok
                     ? (BtollL10n.isEnglish ? "Grok Bot cache" : "Grok Bot 缓存")
                     : (BtollL10n.isEnglish ? "Account reading" : "账户读数"))
                Spacer()
                Text(observed(snap.lastUpdated))
            }
            .font(.caption2)
            .foregroundStyle(Date().timeIntervalSince(snap.lastUpdated) > 600 ? .orange : .secondary)
        }
    }

    @ViewBuilder
    private func quotaGauge(_ label: String, _ limit: UsageLimit) -> some View {
        let usedPct = Int(limit.used.rounded())
        let leftPct = max(0, 100 - usedPct)
        VStack(alignment: .leading, spacing: 3) {
            HStack {
                Text(label).font(.caption2.weight(.semibold)).foregroundStyle(.secondary)
                Spacer()
                if let resets = resetsIn(limit.resetsAt) {
                    Text(resets).font(.caption2).foregroundStyle(.secondary)
                }
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(.white.opacity(0.15))
                    Capsule().fill(gaugeTint(1 - limit.fraction)).frame(width: geo.size.width * (1 - limit.fraction))
                }
            }
            .frame(height: 6)
            HStack {
                Text("\(leftPct)%").font(.caption2.weight(.semibold)).monospacedDigit()
                Spacer()
                Text(BtollL10n.isEnglish ? "\(usedPct)% used" : "已用 \(usedPct)%")
                    .font(.caption2).foregroundStyle(.secondary).monospacedDigit()
            }
        }
    }

    private func gaugeTint(_ remaining: Double) -> Color {
        if remaining < 0.05 { return .red }
        if remaining < 0.2 { return .orange }
        return .green
    }

    private func resetsIn(_ date: Date?) -> String? {
        guard let date else { return nil }
        let seconds = Int(date.timeIntervalSinceNow)
        guard seconds > 0 else { return nil }
        let hours = seconds / 3600
        let minutes = (seconds % 3600) / 60
        if BtollL10n.isEnglish {
            return hours > 0 ? "resets in \(hours)h \(minutes)m" : "resets in \(minutes)m"
        }
        return hours > 0 ? "\(hours)时\(minutes)分后重置" : "\(minutes)分后重置"
    }

    private func observed(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = Calendar.current.isDateInToday(date) ? "HH:mm" : "M/d HH:mm"
        return (BtollL10n.isEnglish ? "updated " : "更新于 ") + formatter.string(from: date)
    }

}
