import SwiftUI

public struct CustomRuleInputRow: View {
    public let title: String
    @Binding public var value: String

    public init(title: String, value: Binding<String>) {
        self.title = title
        self._value = value
    }

    public var body: some View {
        HStack {
            Text(title)
                .foregroundStyle(.primary)
            Spacer()
            TextField("0", text: $value)
                .keyboardType(.numberPad)
                .multilineTextAlignment(.trailing)
                .textFieldStyle(.roundedBorder)
                .frame(minWidth: 80, maxWidth: 110)
        }
    }
}
