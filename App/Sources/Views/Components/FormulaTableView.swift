import SwiftUI
import BakeCore

/// The combined baker's table: ingredient, % of total flour, grams.
/// Flour and water inside the starter are shown indented and dimmed; they aren't weighed separately.
struct FormulaTableView: View {
    let sections: [FormulaSection]

    var body: some View {
        Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 6) {
            GridRow {
                Text("")
                Text("%").gridColumnAlignment(.trailing)
                Text("Grams").gridColumnAlignment(.trailing)
            }
            .font(.caption)
            .foregroundStyle(.secondary)

            ForEach(sections) { section in
                GridRow {
                    Text(section.title.uppercased())
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .padding(.top, 6)
                        .gridCellColumns(3)
                }
                ForEach(section.rows) { row in
                    GridRow {
                        Text(row.label)
                            .padding(.leading, row.kind == .fromStarter ? 14 : 0)
                        Text(row.displayPercent)
                            .monospacedDigit()
                        Text(row.displayGrams)
                            .monospacedDigit()
                    }
                    .font(row.kind == .total ? .body.weight(.semibold) : .body)
                    .foregroundStyle(row.kind == .fromStarter ? .secondary : .primary)
                }
            }
        }
        .padding(.vertical, 4)
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
