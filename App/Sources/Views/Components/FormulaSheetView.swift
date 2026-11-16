import SwiftUI
import BakeCore

/// The baker's sheet: total dough and starter up top, then total flour and total water with
/// their parts indented beneath, then salt and adjuncts. What you weigh for the build (each flour
/// and the water you add, the starter, the salt, and adjuncts that go in the mix) is bold;
/// adjuncts added later, in bulk or final proof, are not. Rows alternate between two light greys
/// (placeholder styling until the design pass).
///
/// Put it in a List row with `.listRowInsets(EdgeInsets())` so the shading runs edge to edge.
struct FormulaSheetView: View {
    let sheet: FormulaSheet
    /// Off when the screen shows its own editable total just above.
    var showsTotal = true

    private let percentWidth: CGFloat = 56
    private let gramsWidth: CGFloat = 80

    var body: some View {
        VStack(spacing: 0) {
            if showsTotal {
                HStack {
                    Text("Total dough")
                    Spacer()
                    Text(sheet.displayTotalDough).monospacedDigit()
                }
                .font(.headline)
                .padding(.horizontal, 16)
                .padding(.top, 12)
                .padding(.bottom, sheet.starter == nil ? 12 : 4)
            }
            if let starter = sheet.starter {
                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Starter").bold()
                        Text(starter.summary)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Text(starter.displayGrams).monospacedDigit().bold()
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
            }

            HStack {
                Spacer()
                Text("%").frame(width: percentWidth, alignment: .trailing)
                Text("Grams").frame(width: gramsWidth, alignment: .trailing)
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            .padding(.horizontal, 16)
            .padding(.vertical, 4)

            ForEach(Array(sheet.rows.enumerated()), id: \.element.id) { index, row in
                HStack {
                    Text(row.label)
                        .padding(.leading, row.kind == .component ? 16 : 0)
                    Spacer(minLength: 8)
                    Text(row.displayPercent)
                        .monospacedDigit()
                        .frame(width: percentWidth, alignment: .trailing)
                    Text(row.displayGrams)
                        .monospacedDigit()
                        .frame(width: gramsWidth, alignment: .trailing)
                }
                .font(row.isWeighed ? .body.weight(.bold) : .body)
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(index.isMultiple(of: 2) ? Color(uiColor: .systemGray6) : Color(uiColor: .systemGray5))
            }
        }
    }
}

/// The process plan as list sections, in bake order.
struct ProcessSections: View {
    let sections: [DetailSection]

    var body: some View {
        ForEach(sections) { section in
            Section(section.title) {
                ForEach(section.items) { item in
                    LabeledContent(item.label, value: item.value)
                }
            }
        }
    }
}
