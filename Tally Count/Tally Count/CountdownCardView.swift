import SwiftUI
import TallyCore

struct CountdownCardView: View {
    let item: CountdownItem
    let now: Date
    var onToggleStreakToday: (() -> Void)? = nil

    @ScaledMetric(relativeTo: .title2) private var primaryFontSize: CGFloat = 24

    var body: some View {
        let snap = item.snapshot(at: now)
        let themeColor = item.colorTheme.color

        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .center, spacing: 12) {
                CountdownBadgeIcon(icon: item.symbolName, tint: themeColor, size: 40, cornerRadius: 10)

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

                        if item.alertsEnabled && (item.mode != .countup || item.hasTargetDate) {
                            Image(systemName: "bell.fill")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .accessibilityHidden(true)
                        }
                    }
                }

                Spacer(minLength: 4)

                if let streak = snap.streak, let onToggle = onToggleStreakToday {
                    let canCheckIn = !snap.isUpcomingStart
                    Button {
                        onToggle()
                    } label: {
                        Label(
                            streak.isCompletedToday ? "Done" : "Check In",
                            systemImage: streak.isCompletedToday ? "checkmark.circle.fill" : "circle"
                        )
                        .font(.caption.bold())
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(
                            streak.isCompletedToday ? Color.green : themeColor.opacity(0.18),
                            in: Capsule()
                        )
                        .foregroundStyle(streak.isCompletedToday ? Color.white : themeColor)
                    }
                    .buttonStyle(.borderless)
                    .disabled(!canCheckIn)
                    .sensoryFeedback(.success, trigger: streak.isCompletedToday)
                    .accessibilityLabel(streak.isCompletedToday ? "Completed today for \(item.title), tap to undo" : "Check in today for \(item.title)")
                }
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

            if let streak = snap.streak {
                HStack(spacing: 6) {
                    ForEach(streak.recentSevenDays) { day in
                        Circle()
                            .fill(day.isCompleted ? themeColor : (day.isEditable ? Color(.tertiarySystemFill) : Color.clear))
                            .frame(width: 10, height: 10)
                            .overlay(
                                Circle()
                                    .stroke(
                                        day.isToday
                                            ? themeColor
                                            : (day.isEditable ? Color.secondary.opacity(0.25) : Color.secondary.opacity(0.12)),
                                        lineWidth: day.isToday ? 1.5 : 1
                                    )
                            )
                    }

                    Spacer()

                    Text("Best: \(streak.longestStreak)d")
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(.secondary)
                }
            }

            if let progress = snap.progress {
                HStack(spacing: 8) {
                    ProgressView(value: progress)
                        .tint(snap.isComplete ? .green : themeColor)

                    Text(CountdownCalculator.formatProgressPercent(progress, isComplete: snap.isComplete))
                        .font(.caption2.bold().monospacedDigit())
                        .foregroundStyle(snap.isComplete ? Color.green : Color.secondary)
                }
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
        .accessibilityElement(children: .contain)
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
        case .streak:
            if let end = snap.effectiveTargetDate {
                return "Ends \(formattedDate(end, isAllDay: true))"
            }
            return "Open-ended"
        }
    }

    private func formattedDate(_ date: Date, isAllDay: Bool) -> String {
        if isAllDay {
            return date.formatted(date: .abbreviated, time: .omitted)
        }
        return date.formatted(date: .abbreviated, time: .shortened)
    }
}
