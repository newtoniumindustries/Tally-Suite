import SwiftUI

/// Month-by-month interactive streak history calendar allowing users to toggle check-ins
/// for any day from `startDate` through `today`.
struct StreakCalendarView: View {
    let startDay: Date
    let today: Date
    let completedDayKeys: Set<String>
    let tintColor: Color
    let onToggleDay: (Date) -> Void

    @State private var displayedMonth: Date

    private let calendar = Calendar.current
    private let columns = Array(repeating: GridItem(.flexible(), spacing: 6), count: 7)

    init(
        startDay: Date,
        today: Date,
        completedDayKeys: [String],
        tintColor: Color,
        onToggleDay: @escaping (Date) -> Void
    ) {
        self.startDay = Calendar.current.startOfDay(for: startDay)
        self.today = Calendar.current.startOfDay(for: today)
        self.completedDayKeys = Set(completedDayKeys)
        self.tintColor = tintColor
        self.onToggleDay = onToggleDay
        let monthStart = Calendar.current.date(from: Calendar.current.dateComponents([.year, .month], from: today)) ?? today
        self._displayedMonth = State(initialValue: monthStart)
    }

    private var earliestMonth: Date {
        calendar.date(from: calendar.dateComponents([.year, .month], from: startDay)) ?? startDay
    }

    private var latestMonth: Date {
        calendar.date(from: calendar.dateComponents([.year, .month], from: today)) ?? today
    }

    private var canGoBack: Bool {
        displayedMonth > earliestMonth
    }

    private var canGoForward: Bool {
        displayedMonth < latestMonth
    }

    private var weekdaySymbols: [String] {
        let symbols = calendar.veryShortWeekdaySymbols
        let first = max(0, calendar.firstWeekday - 1)
        return Array(symbols[first...]) + Array(symbols[..<first])
    }

    private var monthCells: [Date?] {
        guard let range = calendar.range(of: .day, in: .month, for: displayedMonth),
              let firstOfMonth = calendar.date(from: calendar.dateComponents([.year, .month], from: displayedMonth)) else {
            return []
        }

        let weekday = calendar.component(.weekday, from: firstOfMonth)
        let leadingEmpty = (weekday - calendar.firstWeekday + 7) % 7
        var cells: [Date?] = Array(repeating: nil, count: leadingEmpty)

        for day in range {
            if let date = calendar.date(byAdding: .day, value: day - 1, to: firstOfMonth) {
                cells.append(calendar.startOfDay(for: date))
            }
        }
        return cells
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("History & Edit Past Days", systemImage: "calendar.badge.checkmark")
                    .font(.subheadline.bold())
                    .foregroundStyle(tintColor)
                Spacer()
            }

            HStack {
                Button {
                    if let prev = calendar.date(byAdding: .month, value: -1, to: displayedMonth) {
                        displayedMonth = prev
                    }
                } label: {
                    Image(systemName: "chevron.left.circle.fill")
                        .font(.title3)
                        .foregroundStyle(canGoBack ? tintColor : Color.secondary.opacity(0.35))
                }
                .disabled(!canGoBack)
                .buttonStyle(.plain)
                .accessibilityLabel("Previous month")

                Spacer()

                Text(displayedMonth.formatted(.dateTime.month(.wide).year()))
                    .font(.subheadline.bold())

                Spacer()

                Button {
                    if let next = calendar.date(byAdding: .month, value: 1, to: displayedMonth) {
                        displayedMonth = next
                    }
                } label: {
                    Image(systemName: "chevron.right.circle.fill")
                        .font(.title3)
                        .foregroundStyle(canGoForward ? tintColor : Color.secondary.opacity(0.35))
                }
                .disabled(!canGoForward)
                .buttonStyle(.plain)
                .accessibilityLabel("Next month")
            }

            LazyVGrid(columns: columns, spacing: 6) {
                ForEach(Array(weekdaySymbols.enumerated()), id: \.offset) { _, symbol in
                    Text(symbol)
                        .font(.caption2.bold())
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity)
                }

                ForEach(Array(monthCells.enumerated()), id: \.offset) { _, maybeDate in
                    if let day = maybeDate {
                        dayCell(for: day)
                    } else {
                        Color.clear.frame(height: 36)
                    }
                }
            }

            Text("Tap any day from \(startDay.formatted(date: .abbreviated, time: .omitted)) through today to check in or undo a missed day.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding()
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 14))
    }

    private func dayCell(for day: Date) -> some View {
        let key = CountdownCalculator.dayKey(for: day, calendar: calendar)
        let isCompleted = completedDayKeys.contains(key)
        let isToday = calendar.isDate(day, inSameDayAs: today)
        let isEditable = day >= startDay && day <= today
        let dayNumber = calendar.component(.day, from: day)

        return Button {
            onToggleDay(day)
        } label: {
            ZStack {
                Circle()
                    .fill(isCompleted ? tintColor : (isEditable ? Color(.tertiarySystemFill) : Color.clear))
                    .frame(width: 34, height: 34)
                    .overlay(
                        Circle()
                            .stroke(isToday ? tintColor : Color.clear, lineWidth: 2)
                    )

                if isCompleted {
                    VStack(spacing: 0) {
                        Text("\(dayNumber)")
                            .font(.caption.bold().monospacedDigit())
                            .foregroundStyle(.white)
                    }
                } else {
                    Text("\(dayNumber)")
                        .font(.caption.monospacedDigit().weight(isToday ? .bold : .regular))
                        .foregroundStyle(isEditable ? Color.primary : Color.secondary.opacity(0.35))
                }
            }
            .frame(height: 36)
        }
        .buttonStyle(.plain)
        .disabled(!isEditable)
        .accessibilityLabel("\(day.formatted(date: .abbreviated, time: .omitted)), \(isCompleted ? "Completed" : (isEditable ? "Not completed" : "Outside streak range"))")
    }
}
