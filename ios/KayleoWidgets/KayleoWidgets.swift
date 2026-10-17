import SwiftUI
import WidgetKit
import AppIntents
import UIKit

private func rgb(_ hex: UInt32) -> UIColor {
    UIColor(red: CGFloat((hex >> 16) & 255) / 255,
            green: CGFloat((hex >> 8) & 255) / 255,
            blue: CGFloat(hex & 255) / 255, alpha: 1)
}

// Resolve concrete colors from the app preference, not UIKit's host traits.
// WidgetKit can render the background separately from the content.
private struct WidgetPalette {
    var dark = false
    func color(_ light: UInt32, _ darkValue: UInt32) -> Color {
        Color(uiColor: rgb(dark ? darkValue : light))
    }
    var text: Color { color(0x163E2D, 0xF5F7F1) }
    var muted: Color { color(0x626E64, 0xB5C1B7) }
    var background: Color { color(0xFCFAF4, 0x1D1B24) }
    var border: Color { color(0xE2E6DC, 0x302D38) }
    var tile: Color { color(0xE4EBDD, 0x292630) }
    var track: Color { color(0xE4EBDD, 0x403C49) }
    var accent: Color { color(0x163E2D, 0xB8E36B) }
    var protein: Color { color(0xB23858, 0xF07894) }
    var carbs: Color { color(0x8A5B12, 0xF1B963) }
    var fat: Color { color(0x7250AD, 0x9A7DDD) }
}

private struct WidgetPaletteKey: EnvironmentKey {
    static let defaultValue = WidgetPalette()
}
private extension EnvironmentValues {
    var widgetPalette: WidgetPalette {
        get { self[WidgetPaletteKey.self] }
        set { self[WidgetPaletteKey.self] = newValue }
    }
}

private let ink = Color(uiColor: rgb(0x163E2D))
private let actionFill = Color(uiColor: rgb(0xB8E36B))
private let carbColor = Color(uiColor: rgb(0xF1B963))

private struct ThemedWidget<Content: View>: View {
    let content: Content
    let appearance: String
    @Environment(\.colorScheme) private var systemScheme

    var body: some View {
        let dark = appearance == "dark" || (appearance == "system" && systemScheme == .dark)
        let palette = WidgetPalette(dark: dark)
        content
            .environment(\.widgetPalette, palette)
            .environment(\.colorScheme, dark ? .dark : .light)
            .containerBackground(for: .widget) {
                ContainerRelativeShape().fill(palette.background)
                    .overlay {
                        ContainerRelativeShape().strokeBorder(palette.border, lineWidth: 1)
                    }
            }
    }
}

private func widgetTheme<Content: View>(_ content: Content, appearance: String) -> some View {
    ThemedWidget(content: content, appearance: appearance)
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
    @Environment(\.widgetPalette) private var palette
    let title: String
    var body: some View {
        HStack(spacing: 4) {
            Text("Kayleo").foregroundColor(palette.text)
            Spacer(minLength: 1)
            Text(title).font(.system(size: 8, weight: .bold)).foregroundColor(palette.muted)
        }
        .font(.system(size: 10, weight: .bold))
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
    @Environment(\.widgetPalette) private var palette
    let value: Int
    let target: Int
    let color: Color
    var lineWidth: CGFloat = 8
    var segmented = false
    private var ratio: CGFloat { CGFloat(value) / CGFloat(max(1, target)) }
    var body: some View {
        ZStack {
            ZStack {
                Circle().stroke(palette.track, lineWidth: lineWidth)
                if segmented {
                    segment(0, 0.3, palette.accent)
                    segment(0.3, 0.7, Color(red: 0.420, green: 0.624, blue: 0.322))
                    segment(0.7, 1, actionFill)
                } else {
                    Circle().trim(from: 0, to: min(1, ratio))
                        .stroke(color, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                }
            }.padding(segmented && ratio > 1 ? lineWidth + 3 : 0)
            if segmented && ratio > 1 {
                Circle().stroke(palette.track, lineWidth: lineWidth)
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
    @Environment(\.widgetPalette) private var palette
    let entry: KayleoEntry
    var body: some View {
      GeometryReader { geometry in
        let ringSize = max(40, min(geometry.size.width - 20, geometry.size.height - 70))
        VStack(spacing: 3) {
            BrandHeader(title: "Calories")
            Spacer(minLength: 0)
            Button(intent: ToggleWidgetCalories()) {
              ZStack {
                Ring(value: entry.calories, target: entry.calorieTarget, color: palette.text, segmented: true)
                VStack(spacing: 0) {
                    Text(entry.calorieLabel)
                        .font(.system(size: 24, weight: .bold))
                        .minimumScaleFactor(0.6).lineLimit(1)
                    Text(entry.targetLabel)
                        .font(.system(size: 8, weight: .medium))
                        .foregroundColor(palette.muted).minimumScaleFactor(0.5).lineLimit(1)
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
        .padding(10).frame(maxWidth: .infinity, maxHeight: .infinity)
        .foregroundColor(palette.text)
        .widgetURL(url("today"))
      }
    }
}

private struct BarcodeView: View {
    @Environment(\.widgetPalette) private var palette
    var body: some View {
        VStack(spacing: 3) {
            BrandHeader(title: "Barcode")
            Spacer(minLength: 0)
            Image(systemName: "barcode.viewfinder")
                .resizable().scaledToFit().padding(10)
                .foregroundColor(palette.text)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(palette.tile, in: RoundedRectangle(cornerRadius: 17))
            Text("Food labels, faster")
                .font(.system(size: 9, weight: .medium))
                .foregroundColor(palette.muted).lineLimit(1)
            Spacer(minLength: 0)
            Text("Scan barcode")
                .font(.system(size: 10, weight: .bold))
                .frame(maxWidth: .infinity, minHeight: 28)
                .background(actionFill, in: RoundedRectangle(cornerRadius: 12))
                .foregroundColor(ink)
        }
        .padding(10).frame(maxWidth: .infinity, maxHeight: .infinity)
        .foregroundColor(palette.text)
        .widgetURL(url("barcode"))
    }
}

private struct StreakView: View {
    @Environment(\.widgetPalette) private var palette
    let entry: KayleoEntry

    var body: some View {
        Image(uiImage: streakArtwork(entry.streak, dark: palette.dark))
            .resizable().scaledToFit()
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            .accessibilityLabel("Kayleo: \(entry.streak) day meal logging streak. Tap to view progress.")
            .widgetURL(url("streak"))
    }
}

// Uses the same 600 × 600 drawing coordinates and colors as Android.
private func streakArtwork(_ streak: Int, dark: Bool) -> UIImage {
    let format = UIGraphicsImageRendererFormat()
    format.scale = 1
    return UIGraphicsImageRenderer(size: CGSize(width: 600, height: 600), format: format).image { renderer in
        let context = renderer.cgContext
        let background = rgb(dark ? 0x1D1B24 : 0xFCFAF4)
        func fillFlame(_ path: UIBezierPath, top: UInt32, bottom: UInt32) {
            context.saveGState()
            path.addClip()
            let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                                      colors: [rgb(top).cgColor, rgb(bottom).cgColor] as CFArray,
                                      locations: [0, 1])!
            context.drawLinearGradient(gradient, start: CGPoint(x: 0, y: 80),
                                       end: CGPoint(x: 0, y: 440), options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
            context.restoreGState()
        }
        let flame0 = UIBezierPath()
        flame0.move(to: CGPoint(x: 284, y: 84))
        flame0.addCurve(to: CGPoint(x: 370, y: 215), controlPoint1: CGPoint(x: 350, y: 108), controlPoint2: CGPoint(x: 380, y: 166))
        flame0.addCurve(to: CGPoint(x: 400, y: 156), controlPoint1: CGPoint(x: 398, y: 198), controlPoint2: CGPoint(x: 403, y: 173))
        flame0.addCurve(to: CGPoint(x: 429, y: 361), controlPoint1: CGPoint(x: 461, y: 219), controlPoint2: CGPoint(x: 469, y: 302))
        flame0.addCurve(to: CGPoint(x: 293, y: 422), controlPoint1: CGPoint(x: 401, y: 407), controlPoint2: CGPoint(x: 347, y: 432))
        flame0.addCurve(to: CGPoint(x: 174, y: 296), controlPoint1: CGPoint(x: 217, y: 418), controlPoint2: CGPoint(x: 168, y: 363))
        flame0.addCurve(to: CGPoint(x: 224, y: 190), controlPoint1: CGPoint(x: 178, y: 250), controlPoint2: CGPoint(x: 201, y: 218))
        flame0.addCurve(to: CGPoint(x: 246, y: 244), controlPoint1: CGPoint(x: 217, y: 229), controlPoint2: CGPoint(x: 235, y: 237))
        flame0.addCurve(to: CGPoint(x: 284, y: 84), controlPoint1: CGPoint(x: 276, y: 193), controlPoint2: CGPoint(x: 301, y: 143))
        flame0.close()
        fillFlame(flame0, top: 0xFFB530, bottom: 0xEF8044)
        let flame1 = UIBezierPath()
        flame1.move(to: CGPoint(x: 305, y: 225))
        flame1.addCurve(to: CGPoint(x: 331, y: 292), controlPoint1: CGPoint(x: 332, y: 253), controlPoint2: CGPoint(x: 337, y: 273))
        flame1.addCurve(to: CGPoint(x: 359, y: 258), controlPoint1: CGPoint(x: 350, y: 282), controlPoint2: CGPoint(x: 359, y: 270))
        flame1.addCurve(to: CGPoint(x: 354, y: 377), controlPoint1: CGPoint(x: 392, y: 301), controlPoint2: CGPoint(x: 385, y: 355))
        flame1.addCurve(to: CGPoint(x: 253, y: 363), controlPoint1: CGPoint(x: 322, y: 398), controlPoint2: CGPoint(x: 276, y: 394))
        flame1.addCurve(to: CGPoint(x: 274, y: 272), controlPoint1: CGPoint(x: 225, y: 326), controlPoint2: CGPoint(x: 252, y: 290))
        flame1.addCurve(to: CGPoint(x: 287, y: 310), controlPoint1: CGPoint(x: 271, y: 294), controlPoint2: CGPoint(x: 278, y: 305))
        flame1.addCurve(to: CGPoint(x: 305, y: 225), controlPoint1: CGPoint(x: 303, y: 281), controlPoint2: CGPoint(x: 312, y: 257))
        flame1.close()
        fillFlame(flame1, top: 0xFFEEA4, bottom: 0xFFCC6F)
        rgb(0xFFD696).setFill()
        let stars: [(CGFloat, CGFloat, CGFloat)] = [(124, 161, 26), (466, 117, 32), (119, 289, 12)]
        for (x, y, radius) in stars {
            let star = UIBezierPath()
            let points: [(CGFloat, CGFloat)] = [(0, -1), (0.3, -0.3), (1, 0), (0.3, 0.3), (0, 1), (-0.3, 0.3), (-1, 0), (-0.3, -0.3)]
            for (index, point) in points.enumerated() {
                let position = CGPoint(x: x + point.0 * radius, y: y + point.1 * radius)
                if index == 0 { star.move(to: position) } else { star.addLine(to: position) }
            }
            star.close()
            star.fill()
        }
        let size: CGFloat = streak < 100 ? 204 : 156
        let baseFont = UIFont.systemFont(ofSize: size, weight: .bold)
        let font = UIFont(descriptor: baseFont.fontDescriptor.withSymbolicTraits([.traitBold, .traitCondensed]) ?? baseFont.fontDescriptor, size: size)
        let number = String(streak) as NSString
        let width = number.size(withAttributes: [.font: font]).width
        let origin = CGPoint(x: (600 - width) / 2, y: 493 - font.ascender)
        // Background halo, peach outline, then hollow fill, matching Android.
        number.draw(at: origin, withAttributes: [.font: font, .strokeColor: background, .strokeWidth: 22 / size * 100])
        number.draw(at: origin, withAttributes: [.font: font, .strokeColor: rgb(0xEFAB77), .strokeWidth: 10 / size * 100])
        number.draw(at: origin, withAttributes: [.font: font, .foregroundColor: background])
        let brand = "Kayleo" as NSString
        let brandFont = UIFont.systemFont(ofSize: 23, weight: .bold)
        let brandWidth = brand.size(withAttributes: [.font: brandFont]).width
        brand.draw(at: CGPoint(x: (600 - brandWidth) / 2, y: 558 - brandFont.ascender),
                   withAttributes: [.font: brandFont, .foregroundColor: rgb(dark ? 0xDED1C2 : 0x5B4F42)])
    }
}

private struct MacroRow: View {
    @Environment(\.widgetPalette) private var palette
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
                    .font(.system(size: 17, weight: .bold))
                    .tracking(0).foregroundColor(palette.text)
                Text("\(title) \(value > target ? "over" : "left")")
                    .font(.system(size: 9, weight: .medium))
                    .foregroundColor(color).lineLimit(1)
            }
            Spacer(minLength: 0)
        }
    }
}

private struct RingsView: View {
    @Environment(\.widgetPalette) private var palette
    let entry: KayleoEntry
    var body: some View {
      GeometryReader { geometry in
        VStack(spacing: 4) {
            BrandHeader(title: "TODAY")
            Spacer(minLength: 0)
            HStack(spacing: 7) {
                Button(intent: ToggleWidgetCalories()) {
                  ZStack {
                    Ring(value: entry.calories, target: entry.calorieTarget, color: palette.text, segmented: true)
                    VStack(spacing: 0) {
                        Text(entry.calorieLabel)
                            .font(.system(size: geometry.size.width < 310 ? 22 : 28, weight: .bold))
                            .minimumScaleFactor(0.7).lineLimit(1)
                        Text(entry.targetLabel)
                            .font(.system(size: 8, weight: .medium))
                            .foregroundColor(palette.muted).lineLimit(1)
                    }
                    .frame(width: max(60, (geometry.size.width - 34) * 0.44 - 24))
                }
                }.buttonStyle(.plain)
                .frame(width: (geometry.size.width - 34) * 0.44, height: min(geometry.size.height - 42, (geometry.size.width - 34) * 0.44))

                VStack(alignment: .leading, spacing: 0) {
                    MacroRow(title: "Protein", value: entry.protein, target: entry.proteinTarget, ready: entry.ready, color: palette.protein).frame(maxHeight: .infinity)
                    MacroRow(title: "Carbs", value: entry.carbs, target: entry.carbTarget, ready: entry.ready, color: palette.carbs).frame(maxHeight: .infinity)
                    MacroRow(title: "Fat", value: entry.fat, target: entry.fatTarget, ready: entry.ready, color: palette.fat).frame(maxHeight: .infinity)
                }
                .frame(width: (geometry.size.width - 34) * 0.35)

                VStack(spacing: 3) {
                    action("Scan food", icon: "camera.fill", route: "photo")
                    action("Barcode", icon: "barcode.viewfinder", route: "barcode")
                    action("Voice", icon: "mic.fill", route: "voice")
                }
                .frame(width: (geometry.size.width - 34) * 0.21)
            }
            Spacer(minLength: 0)
        }
        .padding(10).frame(maxWidth: .infinity, maxHeight: .infinity)
        .foregroundColor(palette.text)
        .widgetURL(url("today"))
      }
    }

    private func action(_ title: String, icon: String, route: String) -> some View {
        Link(destination: url(route)) {
            Image(systemName: icon)
                .font(.system(size: 25, weight: .medium))
                .foregroundColor(palette.text)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(palette.tile, in: RoundedRectangle(cornerRadius: 12))
                .accessibilityLabel(title)
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
