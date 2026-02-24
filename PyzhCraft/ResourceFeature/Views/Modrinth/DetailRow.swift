import SwiftUI

struct DetailRow: View, Equatable {
    let label: LocalizedStringKey
    let value: String

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(label)
                .font(.callout.bold())
                .fixedSize(horizontal: false, vertical: true)

            Spacer(minLength: 8)

            FilterChip(
                title: value,
                isSelected: false
            ) {}
        }
        .frame(minHeight: 20)
    }

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.label == rhs.label && lhs.value == rhs.value
    }
}
