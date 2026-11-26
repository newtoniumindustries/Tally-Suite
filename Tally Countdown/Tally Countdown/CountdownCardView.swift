import SwiftUI
import TallyCore

struct CountdownCardView: View {
    let item: CountdownItem
    let now: Date

    @ScaledMetric(relativeTo: .title2) private var primaryFontSize: CGFloat = 24

    var body: some View {
        let snap = item.snapshot(at: now)
        let themeColor = item.colorTheme.color

        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .center, spacing: 12) {
                Image(systemName: item.symbolName)
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(themeColor)
                    .frame(width: 40, height: 40)
                    .background(themeColor.opacity(0.15), in: RoundedRectangle(cornerRadius: 10))
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Text(item.title)
                            .font(.headline)
                            .foregroundStyle(.primary)
                            .lineLimit(1)

                        if item.isPinned {
                            Image(systemName: "pin.fill")
                                .font(.caption2)
                                .foregroundStyle(.orange)
                                .accessibilityHidden(true)
                        }
                    }

                    HStack(spacing: 6) {
                        Label(item.mode.displayName, systemImage: item.mode.systemImage)
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(themeColor)

                        if let repeatLabel = item.repeatRule.badgeLabel(customDays: item.customRepeatDays) {
                            Label(repeatLabel, systemImage: "repeat")
                                .font(.caption2.weight(.medium))
                                .foregroundStyle(.secondary)
                        }

                        if item.alertsEnabled && (item.mode == .countdown || item.hasTargetDate) {
                            Image(systemName: "bell.fill")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .accessibilityHidden(true)
                        }
                    }
                }

                Spacer(minLength: 4)
            }

            HStack(alignment: .firstTextBaseline) {
                Text(snap.primaryHeadline)
                    .font(.system(size: min(primaryFontSize, 34), weight: .heavy, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(snap.isComplete ? Color.green : Color.primary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.65)
                    .contentTransition(.numericText())

                Spacer()

                Text(dateSubtitle(for: snap))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            if let progress = snap.progress {
                ProgressView(value: progress)
                    .tint(snap.isComplete ? .green : themeColor)
            }

            if !item.notes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Text(item.notes)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .padding(14)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 14))
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(snap.isComplete ? Color.green.opacity(0.6) : Color.clear, lineWidth: 1.5)
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilitySummary(for: snap))
    }

    private func dateSubtitle(for snap: CountdownSnapshot) -> String {
        switch snap.mode {
        case .countdown:
            guard let target = snap.effectiveTargetDate else { return "" }
            return formattedDate(target, isAllDay: snap.isAllDay)
        case .countup:
            if snap.hasGoal, let target = snap.effectiveTargetDate {
                return "Goal: \(formattedDate(target, isAllDay: snap.isAllDay))"
            }
            return "Since \(formattedDate(snap.effectiveStartDate, isAllDay: snap.isAllDay))"
        }
    }

    private func formattedDate(_ date: Date, isAllDay: Bool) -> String {
        if isAllDay {
            return date.formatted(date: .abbreviated, time: .omitted)
        }
        return date.formatted(date: .abbreviated, time: .shortened)
    }

    private func accessibilitySummary(for snap: CountdownSnapshot) -> String {
        var parts = [item.title, item.mode.displayName, snap.primaryHeadline, dateSubtitle(for: snap)]
        if let repeatLabel = item.repeatRule.badgeLabel(customDays: item.customRepeatDays) {
            parts.append("Repeats \(repeatLabel)")
        }
        if item.alertsEnabled {
            parts.append("Alerts enabled")
        }
        return parts.filter { !$0.isEmpty }.joined(separator: ", ")
    }
}
