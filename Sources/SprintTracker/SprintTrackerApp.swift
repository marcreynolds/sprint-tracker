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
        .onAppear { appDelegate.makeFloating() }
    }
    .windowResizability(.contentMinSize)

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

  func applicationWillFinishLaunching(_ notification: Notification) {
    guard let iconURL = Bundle.main.url(forResource: "AppIcon", withExtension: "icns"),
          let icon = NSImage(contentsOf: iconURL) else { return }
    NSApp.applicationIconImage = icon
  }

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
    var wrapIndicators = false
    var autoAdvanceOnMondays = false
    var lastAutoAdvanceMonday: Date?

    enum CodingKeys: String, CodingKey {
      case fiscalYear, quarter, currentWeek, completeEmoji, currentEmoji
      case upcomingEmoji, offsiteEmoji, textSize, wrapIndicators
      case autoAdvanceOnMondays, lastAutoAdvanceMonday
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
      wrapIndicators = try values.decodeIfPresent(Bool.self, forKey: .wrapIndicators) ?? false
      autoAdvanceOnMondays = try values.decodeIfPresent(Bool.self,
                                                        forKey: .autoAdvanceOnMondays) ?? false
      lastAutoAdvanceMonday = try values.decodeIfPresent(Date.self,
                                                         forKey: .lastAutoAdvanceMonday)
    }
  }

  @Published var data: Stored { didSet { save() } }
  @Published var autoAdvanceNotice: String?
  private let key = "sprint-tracker.settings"
  private var autoAdvanceTimer: Timer?
  private let calendar = Calendar.current

  init() {
    if let raw = UserDefaults.standard.data(forKey: key),
       let decoded = try? JSONDecoder().decode(Stored.self, from: raw) {
      data = decoded
    } else {
      data = Stored()
    }
    applyAutomaticAdvances()
    startAutoAdvanceTimer()
  }

  func setAutoAdvance(_ enabled: Bool) {
    data.autoAdvanceOnMondays = enabled
    data.lastAutoAdvanceMonday = enabled ? monday(containing: Date()) : nil
  }

  func applyAutomaticAdvances(now: Date = Date()) {
    guard data.autoAdvanceOnMondays else { return }
    let currentMonday = monday(containing: now)
    guard let lastMonday = data.lastAutoAdvanceMonday else {
      data.lastAutoAdvanceMonday = currentMonday
      return
    }

    let elapsedDays = calendar.dateComponents([.day], from: lastMonday,
                                              to: currentMonday).day ?? 0
    let weeksToAdvance = elapsedDays / 7
    guard weeksToAdvance > 0 else { return }
    let priorWeek = data.currentWeek
    data.currentWeek = min(data.currentWeek + weeksToAdvance, 13)
    data.lastAutoAdvanceMonday = currentMonday
    announceAutoAdvance(data.currentWeek - priorWeek)
  }

  func simulateAutomaticAdvance() {
    guard data.currentWeek < 13 else { return }
    data.currentWeek += 1
    data.lastAutoAdvanceMonday = monday(containing: Date())
    announceAutoAdvance(1)
  }

  func advancePosition(_ amount: Int) {
    guard amount != 0 else { return }
    if amount > 0 && data.currentWeek == 13 {
      advanceQuarter(1)
      return
    }
    if amount < 0 && data.currentWeek == 1 {
      advanceQuarter(-1)
      data.currentWeek = 13
      return
    }
    data.currentWeek = min(max(data.currentWeek + amount, 1), 13)
  }

  func advanceQuarter(_ amount: Int) {
    var q = data.quarter + amount
    if q > 4 { q = 1; data.fiscalYear += 1 }
    if q < 1 { q = 4; data.fiscalYear -= 1 }
    data.quarter = q
    data.currentWeek = 1
    if data.autoAdvanceOnMondays {
      data.lastAutoAdvanceMonday = monday(containing: Date())
    }
  }

  private func announceAutoAdvance(_ advancedBy: Int) {
    guard advancedBy > 0 else { return }
    let destination = data.currentWeek == 13 ? "Offsite" : "Week \(data.currentWeek)"
    let count = advancedBy == 1 ? "one week" : "\(advancedBy) weeks"
    autoAdvanceNotice = "Auto-advanced \(count) to \(destination)"
  }

  private func monday(containing date: Date) -> Date {
    let day = calendar.startOfDay(for: date)
    let weekday = calendar.component(.weekday, from: day)
    let daysSinceMonday = (weekday + 5) % 7
    return calendar.date(byAdding: .day, value: -daysSinceMonday, to: day) ?? day
  }

  private func startAutoAdvanceTimer() {
    autoAdvanceTimer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) {
      [weak self] _ in self?.applyAutomaticAdvances()
    }
  }

  private func save() {
    guard let encoded = try? JSONEncoder().encode(data) else { return }
    UserDefaults.standard.set(encoded, forKey: key)
  }
}

struct TrackerView: View {
  @EnvironmentObject private var settings: TrackerSettings
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @State private var noticeDismissal: DispatchWorkItem?

  var body: some View {
    HStack(spacing: 14 * scale) {
      reservedLabel("FY3000 Q4", value: "FY\(settings.data.fiscalYear) Q\(settings.data.quarter)",
                    size: settings.data.textSize + 2, weight: .semibold)
      reservedLabel("Week 12 of 12", value: sprintLabel,
                    size: settings.data.textSize, weight: .medium)

      indicatorView
        .overlay {
          if let notice = settings.autoAdvanceNotice {
            Text(notice)
              .font(.system(size: max(10, settings.data.textSize * 0.62), weight: .semibold))
              .foregroundStyle(.primary)
              .padding(.horizontal, 8 * scale)
              .padding(.vertical, 4 * scale)
              .background(.regularMaterial, in: Capsule())
              .overlay {
                Capsule().stroke(Color.accentColor.opacity(0.55), lineWidth: 1)
              }
              .shadow(color: .black.opacity(0.25), radius: 3, y: 1)
              .transition(.opacity.combined(with: .scale(scale: 0.9)))
              .accessibilityLabel(notice)
          }
        }

      Spacer(minLength: 0)

      HStack(spacing: 8 * scale) {
        TrackerArrowButton(icon: "chevron.left", help: "Previous week / quarter",
                           size: 28 * scale,
                           isDisabled: false) {
          settings.advancePosition(-1)
        }
        TrackerArrowButton(icon: "chevron.right", help: "Next week / quarter",
                           size: 28 * scale,
                           isDisabled: false) {
          settings.advancePosition(1)
        }
      }
      .font(.system(size: settings.data.textSize - 2, weight: .bold))
    }
    .padding(.horizontal, 22 * scale)
    .padding(.vertical, 4 * scale)
    .background(Color(nsColor: .controlBackgroundColor))
    .animation(.easeInOut(duration: 0.25), value: settings.autoAdvanceNotice)
    .onAppear { dismissAutoAdvanceNotice() }
    .onChange(of: settings.autoAdvanceNotice) { dismissAutoAdvanceNotice() }
  }

  private func dismissAutoAdvanceNotice() {
    noticeDismissal?.cancel()
    guard settings.autoAdvanceNotice != nil else { return }
    let dismissal = DispatchWorkItem { settings.autoAdvanceNotice = nil }
    noticeDismissal = dismissal
    DispatchQueue.main.asyncAfter(deadline: .now() + 7, execute: dismissal)
  }

  @ViewBuilder
  private var indicatorView: some View {
    if settings.data.wrapIndicators {
      VStack(alignment: .leading, spacing: 3 * scale) {
        indicatorRow(1...6, includesOffsite: false)
        indicatorRow(7...12, includesOffsite: true)
      }
    } else {
      indicatorRow(1...12, includesOffsite: true)
    }
  }

  private func indicatorRow(_ weeks: ClosedRange<Int>, includesOffsite: Bool) -> some View {
    HStack(spacing: 4 * scale) {
      ForEach(weeks, id: \.self) { week in
        Text(emoji(for: week))
          .font(.system(size: emojiSize))
          .accessibilityLabel("Week \(week)")
      }
      if includesOffsite {
        offsiteIndicator
          .padding(.leading, 2 * scale)
          .help(offsiteHelp)
          .accessibilityLabel(offsiteHelp)
      }
    }
  }

  private var offsiteIndicator: some View {
    TimelineView(.animation(minimumInterval: 1.0 / 30.0,
                            paused: settings.data.currentWeek != 13 || reduceMotion)) {
      context in
      let phase = sin(context.date.timeIntervalSinceReferenceDate * .pi * 2 / 1.8)
      let animationAmount = settings.data.currentWeek == 13 && !reduceMotion ? phase : 0
      Text(settings.data.offsiteEmoji)
        .font(.system(size: emojiSize))
        .scaleEffect(1 + max(animationAmount, 0) * 0.08)
        .rotationEffect(.degrees(animationAmount * 7))
        .offset(y: -max(animationAmount, 0) * 3 * scale)
    }
  }

  private var scale: CGFloat {
    CGFloat(settings.data.textSize / 20)
  }

  private var emojiSize: CGFloat {
    27 * scale
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
  let size: CGFloat
  let isDisabled: Bool
  let action: () -> Void
  @State private var isHovering = false

  var body: some View {
    Button(action: action) {
      Image(systemName: icon)
        .frame(width: size, height: size)
        .contentShape(Rectangle())
        .background {
          RoundedRectangle(cornerRadius: 6 * size / 28)
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
              Slider(value: $settings.data.textSize, in: 8...32, step: 1)
                .frame(width: 170)
            }
            Toggle("Wrap sprint indicators to two lines", isOn: $settings.data.wrapIndicators)
            Text("Twelve sprint weeks, then the offsite.")
              .font(.caption)
              .foregroundStyle(.secondary)
              .frame(maxWidth: .infinity, alignment: .leading)
          }
          .padding(6)
        }

        GroupBox("Automation") {
          VStack(alignment: .leading, spacing: 8) {
            Toggle("Advance automatically every Monday", isOn: Binding(
              get: { settings.data.autoAdvanceOnMondays },
              set: { settings.setAutoAdvance($0) }
            ))
            Text("Uses your Mac's local time. If the app was closed on Monday, it catches up the next time it opens.")
              .font(.caption)
              .foregroundStyle(.secondary)
            Button("Simulate a Monday advance") {
              settings.simulateAutomaticAdvance()
            }
            .disabled(!settings.data.autoAdvanceOnMondays || settings.data.currentWeek == 13)
            Text("This advances one position and shows the notification. Use the left arrow to undo it.")
              .font(.caption)
              .foregroundStyle(.secondary)
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
