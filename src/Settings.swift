import SwiftUI

enum DateDisplayMode: Int, CaseIterable {
    case never = 0
    case fromYesterday = 1
    case afterHours = 2
    case always = 3

    var label: String {
        switch self {
        case .never: return "Never"
        case .fromYesterday: return "Yesterday onward"
        case .afterHours: return "After threshold"
        case .always: return "Always"
        }
    }
}

class ShelfSettings: ObservableObject {
    static let shared = ShelfSettings()

    @Published var showLineCount: Bool {
        didSet { UserDefaults.standard.set(showLineCount, forKey: "showLineCount") }
    }
    @Published var showCharCount: Bool {
        didSet { UserDefaults.standard.set(showCharCount, forKey: "showCharCount") }
    }
    @Published var dateDisplayMode: DateDisplayMode {
        didSet { UserDefaults.standard.set(dateDisplayMode.rawValue, forKey: "dateDisplayMode") }
    }
    @Published var dateAfterHours: Int {
        didSet { UserDefaults.standard.set(dateAfterHours, forKey: "dateAfterHours") }
    }

    private init() {
        let d = UserDefaults.standard
        self.showLineCount = d.object(forKey: "showLineCount") as? Bool ?? true
        self.showCharCount = d.object(forKey: "showCharCount") as? Bool ?? true
        let raw = d.object(forKey: "dateDisplayMode") as? Int ?? DateDisplayMode.fromYesterday.rawValue
        self.dateDisplayMode = DateDisplayMode(rawValue: raw) ?? .fromYesterday
        self.dateAfterHours = d.object(forKey: "dateAfterHours") as? Int ?? 23
    }

    private static let clockFmt: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "h:mma"
        f.amSymbol = "a"
        f.pmSymbol = "p"
        return f
    }()

    private static let dateFmt: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "M/d"
        return f
    }()

    func formatTimestamp(_ date: Date) -> String {
        let interval = Date().timeIntervalSince(date)

        var result: String
        if interval < 60 { result = "now" }
        else if interval < 3600 { result = "\(Int(interval / 60))m" }
        else if interval < 86400 { result = "\(Int(interval / 3600))h" }
        else { result = "\(Int(interval / 86400))d" }

        if interval >= 7200 {
            result += " " + Self.clockFmt.string(from: date)
        }

        let showDate: Bool
        switch dateDisplayMode {
        case .never:
            showDate = false
        case .fromYesterday:
            showDate = !Calendar.current.isDateInToday(date)
        case .afterHours:
            showDate = interval >= Double(dateAfterHours) * 3600
        case .always:
            showDate = true
        }

        if showDate {
            result += " " + Self.dateFmt.string(from: date)
        }

        return result
    }
}

// MARK: - Settings View

struct SettingsView: View {
    @ObservedObject var settings = ShelfSettings.shared

    var body: some View {
        Form {
            Section("Card Info") {
                Toggle("Line count", isOn: $settings.showLineCount)
                Toggle("Character count", isOn: $settings.showCharCount)
            }

            Section("Timestamp") {
                Picker("Show date", selection: $settings.dateDisplayMode) {
                    ForEach(DateDisplayMode.allCases, id: \.self) { mode in
                        Text(mode.label).tag(mode)
                    }
                }
                .pickerStyle(.radioGroup)

                if settings.dateDisplayMode == .afterHours {
                    Stepper("After \(settings.dateAfterHours)h",
                            value: $settings.dateAfterHours, in: 1...168)
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 300, height: 240)
    }
}
