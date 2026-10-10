import SwiftUI
import WidgetKit
import AppIntents
import UIKit

private let ink = Color.primary
private let lime = Color(red: 0.086, green: 0.243, blue: 0.176)
private let actionFill = Color(red: 0.722, green: 0.890, blue: 0.420)
private let cream = Color.primary
private let muted = Color.secondary
private let proteinColor = Color(red: 0.941, green: 0.471, blue: 0.580)
private let carbColor = Color(red: 0.945, green: 0.725, blue: 0.388)
private let fatColor = Color(red: 0.604, green: 0.490, blue: 0.867)
private let cardGradient = LinearGradient(
    colors: [Color(red: 0.988, green: 0.980, blue: 0.957), Color.white],
    startPoint: .topLeading,
    endPoint: .bottomTrailing
)

private extension View {
    @ViewBuilder func kayleoBackground() -> some View {
        if #available(iOS 17.0, *) {
            self.containerBackground(Color(uiColor: .systemBackground), for: .widget)
        } else {
            self.background(Color(uiColor: .systemBackground))
        }
    }
}

@ViewBuilder
private func widgetTheme<Content: View>(_ content: Content, appearance: String) -> some View {
    if appearance == "dark" {
        content.environment(\.colorScheme, .dark)
    } else if appearance == "light" {
        content.environment(\.colorScheme, .light)
    } else {
        content
    }
}

private struct KayleoEntry: TimelineEntry {
    let date: Date
    let ready: Bool
    let calories: Int
    let calorieTarget: Int
    let protein: Int
    let proteinTarget: Int
    let carbs: Int
    let carbTarget: Int
    let fat: Int
    let fatTarget: Int
    let streak: Int
    let loggedToday: Bool
    let weekLogged: String
    let appearance: String

    init(date: Date = Date(), preview: Bool = false) {
        self.date = date
        if preview {
            ready = true
            calories = 1480
            calorieTarget = 2200
            protein = 92
            proteinTarget = 130
            carbs = 144
            carbTarget = 250
            fat = 44
            fatTarget = 70
            streak = 12
            loggedToday = true
            weekLogged = "1111100"
            appearance = "system"
            return
        }

        let values = UserDefaults(suiteName: "group.com.rajendrapoudel.kayleo")
        ready = values?.bool(forKey: "ready") ?? false
        let stamp = values?.string(forKey: "date") ?? ""
        let today = Calendar.current.startOfDay(for: date)
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        let savedDay = formatter.date(from: stamp).map { Calendar.current.startOfDay(for: $0) }
        let daysOld = savedDay.map { Calendar.current.dateComponents([.day], from: $0, to: today).day ?? 999 } ?? 999
        let current = ready && daysOld == 0
        let iso = Calendar(identifier: .iso8601)
        let sameWeek = savedDay.map { iso.dateComponents([.yearForWeekOfYear, .weekOfYear], from: $0) == iso.dateComponents([.yearForWeekOfYear, .weekOfYear], from: date) } ?? false
        weekLogged = ready && sameWeek ? values?.string(forKey: "weekLogged") ?? "0000000" : "0000000"
        appearance = values?.string(forKey: "appearance") ?? "system"
        calories = current ? values?.integer(forKey: "calories") ?? 0 : 0
        calorieTarget = ready ? values?.integer(forKey: "calorieTarget") ?? 0 : 0
        protein = current ? values?.integer(forKey: "protein") ?? 0 : 0
        proteinTarget = ready ? values?.integer(forKey: "proteinTarget") ?? 0 : 0
        carbs = current ? values?.integer(forKey: "carbs") ?? 0 : 0
        carbTarget = ready ? values?.integer(forKey: "carbTarget") ?? 0 : 0
        fat = current ? values?.integer(forKey: "fat") ?? 0 : 0
        fatTarget = ready ? values?.integer(forKey: "fatTarget") ?? 0 : 0
        loggedToday = current && (values?.bool(forKey: "loggedToday") ?? false)
        let savedStreak = values?.integer(forKey: "streak") ?? 0
        streak = ready && (daysOld == 0 || (daysOld == 1 && (values?.bool(forKey: "loggedToday") ?? false))) ? savedStreak : 0
    }

    var consumed: Bool { UserDefaults(suiteName: "group.com.rajendrapoudel.kayleo")?.bool(forKey: "widgetConsumed") ?? false }
    var calorieLabel: String { ready ? (consumed ? calories : abs(calorieTarget - calories)).formatted() : "—" }
    var targetLabel: String { ready ? (consumed ? "Calories consumed" : calories > calorieTarget ? "Calories over" : "Calories left") : "Open Kayleo" }
}

private struct KayleoProvider: TimelineProvider {
    func placeholder(in context: Context) -> KayleoEntry { KayleoEntry(preview: true) }
    func getSnapshot(in context: Context, completion: @escaping (KayleoEntry) -> Void) {
        completion(KayleoEntry(preview: context.isPreview))
    }
    func getTimeline(in context: Context, completion: @escaping (Timeline<KayleoEntry>) -> Void) {
        let now = Date()
        let tomorrow = Calendar.current.startOfDay(for: Calendar.current.date(byAdding: .day, value: 1, to: now) ?? now.addingTimeInterval(86400))
        completion(Timeline(entries: [KayleoEntry(date: now)], policy: .after(tomorrow)))
    }
}

private func url(_ action: String) -> URL { URL(string: "kayleo://widget/\(action)")! }

private struct BrandHeader: View {
    let title: String
    var body: some View {
        HStack(spacing: 4) {
            Text("Kayleo").foregroundColor(lime)
            Spacer(minLength: 1)
            Text(title).foregroundColor(muted)
        }
        .font(.system(size: 9, weight: .heavy, design: .rounded))
        .tracking(0)
        .lineLimit(1)
    }
}

struct ToggleWidgetCalories: AppIntent {
    static var title: LocalizedStringResource = "Switch calorie display"
    static var openAppWhenRun = false
    func perform() async throws -> some IntentResult {
        let values = UserDefaults(suiteName: "group.com.rajendrapoudel.kayleo")
        values?.set(!(values?.bool(forKey: "widgetConsumed") ?? false), forKey: "widgetConsumed")
        WidgetCenter.shared.reloadAllTimelines()
        return .result()
    }
}

private struct Ring: View {
    let value: Int
    let target: Int
    let color: Color
    var lineWidth: CGFloat = 8
    var segmented = false
    private var ratio: CGFloat { CGFloat(value) / CGFloat(max(1, target)) }
    private let track = Color(red: 0.894, green: 0.922, blue: 0.867)
    var body: some View {
        ZStack {
            ZStack {
                Circle().stroke(track, lineWidth: lineWidth)
                if segmented {
                    segment(0, 0.3, ink)
                    segment(0.3, 0.7, Color(red: 0.420, green: 0.624, blue: 0.322))
                    segment(0.7, 1, actionFill)
                } else {
                    Circle().trim(from: 0, to: min(1, ratio))
                        .stroke(color, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                }
            }.padding(segmented && ratio > 1 ? lineWidth + 3 : 0)
            if segmented && ratio > 1 {
                Circle().stroke(track, lineWidth: lineWidth)
                Circle().trim(from: 0, to: min(1, ratio - 1))
                    .stroke(carbColor, lineWidth: lineWidth).rotationEffect(.degrees(-90))
            }
        }.padding(lineWidth / 2)
    }
    @ViewBuilder private func segment(_ start: CGFloat, _ end: CGFloat, _ color: Color) -> some View {
        if ratio > start {
            Circle().trim(from: start, to: min(end, ratio))
                .stroke(color, lineWidth: lineWidth).rotationEffect(.degrees(-90))
        }
    }
}

private struct CaloriesView: View {
    let entry: KayleoEntry
    var body: some View {
      GeometryReader { geometry in
        let ringSize = max(68, min(100, geometry.size.height - 72))
        VStack(spacing: 3) {
            BrandHeader(title: "Calories")
            Spacer(minLength: 0)
            Button(intent: ToggleWidgetCalories()) {
              ZStack {
                Ring(value: entry.calories, target: entry.calorieTarget, color: lime, segmented: true)
                VStack(spacing: 0) {
                    Text(entry.calorieLabel)
                        .font(.system(size: 24, weight: .bold, design: .rounded))
                        .minimumScaleFactor(0.6).lineLimit(1)
                    Text(entry.targetLabel)
                        .font(.system(size: 8, weight: .medium))
                        .foregroundColor(muted).minimumScaleFactor(0.5).lineLimit(1)
                }
                .frame(width: min(78, ringSize - (entry.calories > entry.calorieTarget ? 32 : 16)))
            }
            }.buttonStyle(.plain)
            .frame(width: ringSize, height: ringSize)
            Spacer(minLength: 0)
            Link(destination: url("photo")) {
                Label("Log your food", systemImage: "camera.fill")
                    .font(.system(size: 10, weight: .bold))
                    .frame(maxWidth: .infinity, minHeight: 28)
                    .background(actionFill, in: RoundedRectangle(cornerRadius: 12))
                    .foregroundColor(ink)
            }
        }
        .padding(11).frame(maxWidth: .infinity, maxHeight: .infinity)
        .kayleoBackground().foregroundColor(cream)
        .widgetURL(url("photo"))
      }
    }
}

private struct BarcodeView: View {
    var body: some View {
        VStack(spacing: 3) {
            BrandHeader(title: "Barcode")
            Spacer(minLength: 0)
            Image(systemName: "barcode.viewfinder")
                .font(.system(size: 34, weight: .light))
                .foregroundColor(lime)
                .frame(width: 65, height: 65)
                .background(Color(red: 0.894, green: 0.922, blue: 0.867), in: RoundedRectangle(cornerRadius: 17))
            Text("Food labels, faster")
                .font(.system(size: 9, weight: .medium))
                .foregroundColor(muted).lineLimit(1)
            Spacer(minLength: 0)
            Text("Scan barcode")
                .font(.system(size: 10, weight: .bold))
                .frame(maxWidth: .infinity, minHeight: 28)
                .background(actionFill, in: RoundedRectangle(cornerRadius: 12))
                .foregroundColor(ink)
        }
        .padding(11).frame(maxWidth: .infinity, maxHeight: .infinity)
        .kayleoBackground().foregroundColor(cream)
        .widgetURL(url("barcode"))
    }
}

private struct StreakView: View {
    let entry: KayleoEntry
    var body: some View {
        VStack(spacing: 1) {
            BrandHeader(title: "Streak")
            Spacer(minLength: 0)
            ZStack {
                Image(systemName: "flame.fill")
                    .font(.system(size: 57, weight: .regular))
                    .foregroundStyle(LinearGradient(colors: [.orange, Color(red: 1, green: 0.72, blue: 0.42)], startPoint: .top, endPoint: .bottom))
                Text("\(entry.streak)")
                    .font(.system(size: 23, weight: .heavy, design: .rounded))
                    .foregroundColor(Color(red: 0.20, green: 0.15, blue: 0.10))
                    .offset(y: 10)
            }
            .frame(height: 65)
            Spacer(minLength: 0)
            Text("day streak")
                .font(.system(size: 11, weight: .heavy, design: .rounded))
                .tracking(0.6)
            Text(entry.ready ? (entry.loggedToday ? "Logged today · well done" : (entry.streak == 0 ? "Log a meal to start" : "Log today to continue")) : "Open Kayleo to begin")
                .font(.system(size: 8, weight: .medium))
                .foregroundColor(muted).lineLimit(1)
            HStack(spacing: 0) {
                ForEach(0..<7, id: \.self) { index in
                    let done = Array(entry.weekLogged).indices.contains(index) && Array(entry.weekLogged)[index] == "1"
                    Text(["M", "T", "W", "T", "F", "S", "S"][index])
                        .font(.system(size: 7, weight: .bold))
                        .foregroundColor(done ? .white : muted)
                        .frame(width: 15, height: 15)
                        .background(done ? Color.orange.opacity(0.75) : Color(red: 0.894, green: 0.922, blue: 0.867), in: Circle())
                        .frame(maxWidth: .infinity)
                }
            }
            .padding(.top, 5)
        }
        .padding(11).frame(maxWidth: .infinity, maxHeight: .infinity)
        .kayleoBackground().foregroundColor(cream)
        .widgetURL(url("streak"))
    }
}

private struct MacroRow: View {
    let title: String
    let value: Int
    let target: Int
    let ready: Bool
    let color: Color

    var body: some View {
        HStack(spacing: 7) {
            Ring(value: value, target: target, color: color, lineWidth: 3)
                .frame(width: 26, height: 26)
            VStack(alignment: .leading, spacing: 1) {
                Text(ready ? "\(abs(target - value))g" : "—")
                    .font(.system(size: 17, weight: .bold, design: .rounded))
                    .tracking(0).foregroundColor(cream)
                Text("\(title) \(value > target ? "over" : "left")")
                    .font(.system(size: 9, weight: .medium))
                    .foregroundColor(color).lineLimit(1)
            }
            Spacer(minLength: 0)
        }
    }
}

private struct RingsView: View {
    let entry: KayleoEntry
    var body: some View {
      GeometryReader { geometry in
        VStack(spacing: 5) {
            BrandHeader(title: "Calories")
            Spacer(minLength: 0)
            HStack(spacing: 8) {
                Button(intent: ToggleWidgetCalories()) {
                  ZStack {
                    Ring(value: entry.calories, target: entry.calorieTarget, color: lime, segmented: true)
                    VStack(spacing: 0) {
                        Text(entry.calorieLabel)
                            .font(.system(size: 27, weight: .bold, design: .rounded))
                            .minimumScaleFactor(0.7).lineLimit(1)
                        Text(entry.targetLabel)
                            .font(.system(size: 8, weight: .medium))
                            .foregroundColor(muted).lineLimit(1)
                    }
                    .frame(width: 86)
                }
                }.buttonStyle(.plain)
                .frame(width: min(124, geometry.size.width * 0.36), height: min(124, geometry.size.width * 0.36))

                VStack(alignment: .leading, spacing: 13) {
                    MacroRow(title: "Protein", value: entry.protein, target: entry.proteinTarget, ready: entry.ready, color: proteinColor)
                    MacroRow(title: "Carbs", value: entry.carbs, target: entry.carbTarget, ready: entry.ready, color: carbColor)
                    MacroRow(title: "Fat", value: entry.fat, target: entry.fatTarget, ready: entry.ready, color: fatColor)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                VStack(spacing: 5) {
                    action("Scan food", icon: "camera.fill", route: "photo")
                    action("Barcode", icon: "barcode.viewfinder", route: "barcode")
                    action("Voice", icon: "mic.fill", route: "voice")
                }
                .frame(width: 65)
            }
            Spacer(minLength: 0)
        }
        .padding(11).frame(maxWidth: .infinity, maxHeight: .infinity)
        .kayleoBackground().foregroundColor(cream)
        .widgetURL(url("today"))
      }
    }

    private func action(_ title: String, icon: String, route: String) -> some View {
        Link(destination: url(route)) {
            HStack(spacing: 3) {
                Image(systemName: icon).font(.system(size: 15, weight: .medium)).foregroundColor(lime)
                Text(title).font(.system(size: 9, weight: .medium)).foregroundColor(cream)
            }
            .frame(maxWidth: .infinity, minHeight: 36)
            .background(Color(red: 0.894, green: 0.922, blue: 0.867), in: RoundedRectangle(cornerRadius: 12))
        }
    }
}

private struct CaloriesWidget: Widget {
    let kind = "KayleoCalories"
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: KayleoProvider()) { entry in
            widgetTheme(CaloriesView(entry: entry), appearance: entry.appearance)
        }
            .configurationDisplayName("Kayleo Calories")
            .description("Your calorie ring and a one-tap food camera.")
            .supportedFamilies([.systemSmall])
            .contentMarginsDisabled()
    }
}

private struct BarcodeWidget: Widget {
    let kind = "KayleoBarcode"
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: KayleoProvider()) { entry in
            widgetTheme(BarcodeView(), appearance: entry.appearance)
        }
            .configurationDisplayName("Kayleo Barcode")
            .description("Scan a product barcode from your home screen.")
            .supportedFamilies([.systemSmall])
            .contentMarginsDisabled()
    }
}

private struct StreakWidget: Widget {
    let kind = "KayleoStreak"
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: KayleoProvider()) { entry in
            widgetTheme(StreakView(entry: entry), appearance: entry.appearance)
        }
            .configurationDisplayName("Kayleo Streak")
            .description("See your meal logging streak at a glance.")
            .supportedFamilies([.systemSmall])
            .contentMarginsDisabled()
    }
}

private struct RingsWidget: Widget {
    let kind = "KayleoRings"
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: KayleoProvider()) { entry in
            widgetTheme(RingsView(entry: entry), appearance: entry.appearance)
        }
            .configurationDisplayName("Kayleo Nutrition")
            .description("Calorie and macro rings with scan and voice shortcuts.")
            .supportedFamilies([.systemMedium])
            .contentMarginsDisabled()
    }
}

@main
struct KayleoWidgetBundle: WidgetBundle {
    var body: some Widget {
        CaloriesWidget()
        BarcodeWidget()
        StreakWidget()
        RingsWidget()
    }
}
