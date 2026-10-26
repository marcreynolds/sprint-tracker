import AppKit
import SwiftUI

@main
struct SprintTrackerApp: App {
  @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
  @StateObject private var settings = TrackerSettings()

  var body: some Scene {
    WindowGroup("Sprint Tracker") {
      TrackerView()
        .environmentObject(settings)
        .frame(minWidth: 550)
        .onAppear { appDelegate.makeFloating() }
    }
    Settings {
      SettingsView()
        .environmentObject(settings)
        .frame(width: 510, height: 490)
    }
  }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
  private let frameKey = "sprint-tracker.main-window-frame"
  private weak var mainWindow: NSWindow?

  func applicationDidFinishLaunching(_ notification: Notification) {
    NSApp.setActivationPolicy(.regular)
  }

  func makeFloating() {
    DispatchQueue.main.async {
      guard let window = NSApp.windows.first, self.mainWindow == nil else { return }
      self.mainWindow = window
      window.level = .floating
      window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
      window.isMovableByWindowBackground = true
      window.titleVisibility = .hidden
      window.titlebarAppearsTransparent = true
      window.styleMask.insert(.fullSizeContentView)
      window.styleMask.remove(.titled)
      window.styleMask.insert(.resizable)
      window.minSize = NSSize(width: 400, height: 32)

      NotificationCenter.default.addObserver(self,
                                             selector: #selector(self.saveWindowFrame),
                                             name: NSWindow.didResizeNotification,
                                             object: window)
      NotificationCenter.default.addObserver(self,
                                             selector: #selector(self.saveWindowFrame),
                                             name: NSWindow.didMoveNotification,
                                             object: window)

      // SwiftUI finishes applying its initial content size on the next pass.
      // Restore after that so it cannot overwrite the user's saved frame.
      DispatchQueue.main.async {
        guard let storedFrame = UserDefaults.standard.string(forKey: self.frameKey) else {
          return
        }
        window.setFrame(NSRectFromString(storedFrame), display: true)
      }
    }
  }

  @objc private func saveWindowFrame(_ notification: Notification) {
    guard let window = notification.object as? NSWindow else { return }
    UserDefaults.standard.set(NSStringFromRect(window.frame), forKey: frameKey)
  }
}

final class TrackerSettings: ObservableObject {
  struct Stored: Codable {
    var fiscalYear = 2027
    var quarter = 2
    var currentWeek = 11
    // The 13th position is the offsite, after the twelve sprint weeks.
    var completeEmoji = "✅"
    var currentEmoji = "⬜️"
    var upcomingEmoji = "◻️"
    var offsiteEmoji = "✈️"
    var textSize: Double = 20

    enum CodingKeys: String, CodingKey {
      case fiscalYear, quarter, currentWeek, completeEmoji, currentEmoji
      case upcomingEmoji, offsiteEmoji, textSize
    }

    init() {}

    init(from decoder: Decoder) throws {
      let values = try decoder.container(keyedBy: CodingKeys.self)
      fiscalYear = try values.decodeIfPresent(Int.self, forKey: .fiscalYear) ?? 2027
      quarter = try values.decodeIfPresent(Int.self, forKey: .quarter) ?? 2
      currentWeek = try values.decodeIfPresent(Int.self, forKey: .currentWeek) ?? 11
      completeEmoji = try values.decodeIfPresent(String.self, forKey: .completeEmoji) ?? "✅"
      currentEmoji = try values.decodeIfPresent(String.self, forKey: .currentEmoji) ?? "⬜️"
      upcomingEmoji = try values.decodeIfPresent(String.self, forKey: .upcomingEmoji) ?? "◻️"
      offsiteEmoji = try values.decodeIfPresent(String.self, forKey: .offsiteEmoji) ?? "✈️"
      textSize = try values.decodeIfPresent(Double.self, forKey: .textSize) ?? 20
    }
  }

  @Published var data: Stored { didSet { save() } }
  private let key = "sprint-tracker.settings"

  init() {
    if let raw = UserDefaults.standard.data(forKey: key),
       let decoded = try? JSONDecoder().decode(Stored.self, from: raw) {
      data = decoded
    } else {
      data = Stored()
    }
  }

  func advanceWeek(_ amount: Int) {
    data.currentWeek = min(max(data.currentWeek + amount, 1), 13)
  }

  func advanceQuarter(_ amount: Int) {
    var q = data.quarter + amount
    if q > 4 { q = 1; data.fiscalYear += 1 }
    if q < 1 { q = 4; data.fiscalYear -= 1 }
    data.quarter = q
    data.currentWeek = 1
  }

  private func save() {
    guard let encoded = try? JSONEncoder().encode(data) else { return }
    UserDefaults.standard.set(encoded, forKey: key)
  }
}

struct TrackerView: View {
  @EnvironmentObject private var settings: TrackerSettings
  var body: some View {
    HStack(spacing: 14) {
      reservedLabel("FY3000 Q4", value: "FY\(settings.data.fiscalYear) Q\(settings.data.quarter)",
                    size: settings.data.textSize + 2, weight: .semibold)
      reservedLabel("Week 12 of 12", value: sprintLabel,
                    size: settings.data.textSize, weight: .medium)

      HStack(spacing: 4) {
        ForEach(1...12, id: \.self) { week in
          Text(emoji(for: week))
            .font(.system(size: settings.data.textSize + 7))
            .accessibilityLabel("Week \(week)")
        }
        Text(settings.data.offsiteEmoji)
          .font(.system(size: settings.data.textSize + 7))
          .padding(.leading, 2)
          .help(offsiteHelp)
          .accessibilityLabel(offsiteHelp)
      }

      Spacer(minLength: 0)

      HStack(spacing: 8) {
        TrackerArrowButton(icon: "chevron.left", help: "Previous week",
                           isDisabled: settings.data.currentWeek == 1) {
          settings.advanceWeek(-1)
        }
        TrackerArrowButton(icon: "chevron.right", help: "Next week / offsite",
                           isDisabled: settings.data.currentWeek == 13) {
          settings.advanceWeek(1)
        }
      }
      .font(.system(size: settings.data.textSize - 2, weight: .bold))
    }
    .padding(.horizontal, 22)
    .padding(.vertical, 4)
    .background(Color(nsColor: .controlBackgroundColor))
  }

  private func reservedLabel(_ longest: String, value: String, size: Double,
                             weight: Font.Weight) -> some View {
    Text(longest)
      .font(.system(size: size, weight: weight, design: .rounded))
      .hidden()
      .overlay(alignment: .leading) {
        Text(value)
          .font(.system(size: size, weight: weight, design: .rounded))
      }
  }

  private var sprintLabel: String {
    if settings.data.currentWeek == 13 { return "Offsite" }
    return "Week \(settings.data.currentWeek) of 12"
  }

  private var offsiteHelp: String {
    let remaining = 13 - settings.data.currentWeek
    if remaining == 0 { return "Offsite week" }
    return "Offsite in \(remaining) \(remaining == 1 ? "week" : "weeks")"
  }

  private func emoji(for week: Int) -> String {
    if week < settings.data.currentWeek { return settings.data.completeEmoji }
    if week == settings.data.currentWeek { return settings.data.currentEmoji }
    return settings.data.upcomingEmoji
  }
}

struct TrackerArrowButton: View {
  let icon: String
  let help: String
  let isDisabled: Bool
  let action: () -> Void
  @State private var isHovering = false

  var body: some View {
    Button(action: action) {
      Image(systemName: icon)
        .frame(width: 28, height: 28)
        .contentShape(Rectangle())
        .background {
          RoundedRectangle(cornerRadius: 6)
            .fill(isHovering && !isDisabled ? Color.accentColor.opacity(0.24) : .clear)
        }
    }
    .buttonStyle(.plain)
    .disabled(isDisabled)
    .onHover { isHovering = $0 }
    .help(help)
  }
}

struct SettingsView: View {
  @EnvironmentObject private var settings: TrackerSettings

  private var currentPositionLabel: String {
    settings.data.currentWeek == 13 ? "Current position: Offsite" :
      "Current week: \(settings.data.currentWeek)"
  }

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 16) {
        GroupBox("Quarter") {
          VStack(spacing: 12) {
            HStack {
              Text("Fiscal year: " + String(settings.data.fiscalYear))
              Spacer()
              Button("−") { settings.data.fiscalYear -= 1 }
              Button("+") { settings.data.fiscalYear += 1 }
            }
            HStack {
              Text("Quarter")
              Spacer()
              Picker("Quarter", selection: $settings.data.quarter) {
                ForEach(1...4, id: \.self) { Text("Q\($0)").tag($0) }
              }
              .labelsHidden()
              .frame(width: 110)
            }
            Stepper(currentPositionLabel,
                    value: $settings.data.currentWeek, in: 1...13)
            HStack {
              Text("Main text size: \(Int(settings.data.textSize))")
              Slider(value: $settings.data.textSize, in: 12...32, step: 1)
                .frame(width: 170)
            }
            Text("Twelve sprint weeks, then the offsite.")
              .font(.caption)
              .foregroundStyle(.secondary)
              .frame(maxWidth: .infinity, alignment: .leading)
          }
          .padding(6)
        }

        GroupBox("Indicators") {
          VStack(spacing: 10) {
            emojiField("Completed week", value: $settings.data.completeEmoji)
            emojiField("Current week", value: $settings.data.currentEmoji)
            emojiField("Upcoming week", value: $settings.data.upcomingEmoji)
            emojiField("Offsite", value: $settings.data.offsiteEmoji)
          }
          .padding(6)
        }
      }
      .padding(20)
      .frame(maxWidth: .infinity, alignment: .leading)
    }
  }

  private func emojiField(_ label: String, value: Binding<String>) -> some View {
    HStack {
      Text(label)
      Spacer()
      TextField("Emoji", text: value)
        .multilineTextAlignment(.center)
        .frame(width: 82)
    }
  }
}
