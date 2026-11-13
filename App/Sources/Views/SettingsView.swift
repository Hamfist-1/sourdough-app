import SwiftUI
import BakeCore

struct SettingsView: View {
    @AppStorage("temperatureUnit") private var unit: TemperatureUnit = .default

    var body: some View {
        Form {
            Section {
                Picker("Temperature", selection: $unit) {
                    ForEach(TemperatureUnit.allCases, id: \.self) { unit in
                        Text(unit.name).tag(unit)
                    }
                }
            } footer: {
                Text("Weights are always in grams.")
            }
            Section("About") {
                LabeledContent(
                    "Version",
                    value: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "–"
                )
            }
        }
        .navigationTitle("Settings")
    }
}

#Preview {
    NavigationStack { SettingsView() }
}
