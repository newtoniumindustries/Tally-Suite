import SwiftUI
import TallyCore

// MARK: - Full Icon & Emoji Picker Sheet ("More")

private enum IconPickerTab: String, CaseIterable, Identifiable {
    case emojis = "Emojis"
    case symbols = "Symbols"

    var id: String { rawValue }
}

struct CountdownIconPickerSheet: View {
    @Environment(\.dismiss) private var dismiss

    @Binding var selectedIcon: String
    let tintColor: Color

    @State private var activeTab: IconPickerTab = .emojis
    @State private var customEmojiInput: String = ""
    @State private var customEmojiError: String?

    private let columns = [GridItem(.adaptive(minimum: 48, maximum: 56), spacing: 10)]

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Picker("Icon Type", selection: $activeTab) {
                    ForEach(IconPickerTab.allCases) { tab in
                        Text(tab.rawValue).tag(tab)
                    }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal)
                .padding(.top, 10)
                .padding(.bottom, 8)

                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        if activeTab == .emojis {
                            customEmojiSection

                            ForEach(CountdownIconCatalog.emojiCategories) { category in
                                VStack(alignment: .leading, spacing: 10) {
                                    Text(category.title)
                                        .font(.subheadline.bold())
                                        .foregroundStyle(.secondary)

                                    LazyVGrid(columns: columns, spacing: 10) {
                                        ForEach(category.emojis, id: \.self) { emoji in
                                            iconTile(icon: emoji)
                                        }
                                    }
                                }
                            }
                        } else {
                            VStack(alignment: .leading, spacing: 10) {
                                Text("SF Symbols")
                                    .font(.subheadline.bold())
                                    .foregroundStyle(.secondary)

                                LazyVGrid(columns: columns, spacing: 10) {
                                    ForEach(CountdownIconCatalog.sfSymbols, id: \.self) { symbol in
                                        iconTile(icon: symbol)
                                    }
                                }
                            }
                        }
                    }
                    .padding()
                }
                .scrollDismissesKeyboard(.interactively)
            }
            .navigationTitle("Choose Icon")
            .navigationBarTitleDisplayMode(.inline)
            .onAppear {
                activeTab = CountdownIconCatalog.isEmoji(selectedIcon) ? .emojis : .symbols
            }
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Done") { TallyKeyboard.dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    private var customEmojiSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Use Any Emoji")
                .font(.subheadline.bold())
                .foregroundStyle(.secondary)

            HStack(spacing: 10) {
                CountdownBadgeIcon(icon: selectedIcon, tint: tintColor, size: 42, cornerRadius: 10)

                TextField("Type or paste any emoji…", text: $customEmojiInput)
                    .textFieldStyle(.roundedBorder)
                    .submitLabel(.done)
                    .onSubmit(applyCustomEmoji)
                    .onChange(of: customEmojiInput) { _, newValue in
                        if let extracted = CountdownIconCatalog.extractFirstEmoji(from: newValue) {
                            customEmojiError = nil
                            selectedIcon = extracted
                            if newValue != extracted {
                                customEmojiInput = extracted
                            }
                        } else if !newValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                            customEmojiError = "Enter an emoji from the emoji keyboard."
                        } else {
                            customEmojiError = nil
                        }
                    }

                Button("Use") {
                    applyCustomEmoji()
                }
                .buttonStyle(.borderedProminent)
                .tint(tintColor)
                .disabled(CountdownIconCatalog.extractFirstEmoji(from: customEmojiInput) == nil)
            }

            if let customEmojiError {
                Text(customEmojiError)
                    .font(.caption)
                    .foregroundStyle(.red)
            }
        }
        .padding(12)
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 12))
    }

    private func applyCustomEmoji() {
        guard let extracted = CountdownIconCatalog.extractFirstEmoji(from: customEmojiInput) else {
            customEmojiError = "Enter an emoji from the emoji keyboard."
            return
        }
        selectedIcon = extracted
        TallyKeyboard.dismiss()
        dismiss()
    }

    private func iconTile(icon: String) -> some View {
        let isSelected = selectedIcon == icon
        return Button {
            selectedIcon = icon
            dismiss()
        } label: {
            Group {
                if CountdownIconCatalog.isEmoji(icon) {
                    Text(icon)
                        .font(.title2)
                } else {
                    Image(systemName: icon)
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(isSelected ? tintColor : .primary)
                }
            }
            .frame(width: 48, height: 48)
            .background(
                isSelected ? tintColor.opacity(0.22) : Color(.secondarySystemBackground),
                in: RoundedRectangle(cornerRadius: 12)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(isSelected ? tintColor : Color.clear, lineWidth: 2)
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(icon)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}
