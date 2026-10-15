import WidgetKit
import SwiftUI
import AppIntents

// MARK: - Timeline

struct KeypadEntry: TimelineEntry {
    let date: Date
    let digits: String
    let status: WidgetStatus
    let configured: Bool
}

struct KeypadProvider: AppIntentTimelineProvider {
    func placeholder(in context: Context) -> KeypadEntry {
        KeypadEntry(date: .now, digits: "", status: .idle, configured: true)
    }

    func snapshot(for configuration: AttendConfigIntent, in context: Context) async -> KeypadEntry {
        if context.isPreview {
            return KeypadEntry(date: .now, digits: "415", status: .idle, configured: true)
        }
        return entry(configuration)
    }

    func timeline(for configuration: AttendConfigIntent, in context: Context) async -> Timeline<KeypadEntry> {
        Timeline(entries: [entry(configuration)], policy: .never)
    }

    private func entry(_ configuration: AttendConfigIntent) -> KeypadEntry {
        // ボタンの処理から読めるよう、設定を保存しておく
        WidgetStore.credentials = EdohenCredentials(
            userID: configuration.userID ?? "",
            password: configuration.password ?? "",
            studentNo: configuration.studentNo ?? "")
        return KeypadEntry(date: .now,
                           digits: WidgetStore.digits,
                           status: WidgetStore.status,
                           configured: WidgetStore.credentials.isComplete)
    }
}

// MARK: - Widget

struct AttendWidget: Widget {
    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: "AttendKeypad",
                               intent: AttendConfigIntent.self,
                               provider: KeypadProvider()) { entry in
            KeypadWidgetView(entry: entry)
                .widgetURL(URL(string: "studyplan://status"))
                .containerBackground(for: .widget) {
                    Color(uiColor: .systemBackground)
                }
        }
        .configurationDisplayName("出席登録")
        .description("講義パスワードを6桁押すと出席登録します。")
        .supportedFamilies([.systemMedium, .systemLarge])
    }
}

// MARK: - Views

struct KeypadWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: KeypadEntry

    var body: some View {
        if family == .systemLarge { large } else { medium }
    }

    // 中サイズ：左に入力欄、右にキーパッド
    private var medium: some View {
        HStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 0) {
                header
                Spacer(minLength: 6)
                WidgetCodeBoxes(code: entry.digits, box: 20)
                Spacer(minLength: 6)
                statusLine(compact: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            WidgetKeypad(spacing: 4, fontSize: 15)
                .frame(width: 148)
        }
    }

    // 大サイズ：上に入力欄、下に大きなキーパッド
    private var large: some View {
        VStack(spacing: 12) {
            HStack {
                header
                Spacer()
            }
            WidgetCodeBoxes(code: entry.digits, box: 34)
            statusLine(compact: false)
                .frame(height: 36)
            WidgetKeypad(spacing: 8, fontSize: 24)
        }
    }

    private var header: some View {
        Label("出席登録", systemImage: "checkmark.circle.fill")
            .font(.caption.weight(.semibold))
            .foregroundStyle(.green)
    }

    @ViewBuilder
    private func statusLine(compact: Bool) -> some View {
        if !entry.configured {
            Text("長押し→「ウィジェットを編集」でIDを設定")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(2)
        } else if case .result(let r) = entry.status {
            HStack(alignment: .top, spacing: 5) {
                Image(systemName: r.symbol)
                    .foregroundStyle(r.tint)
                VStack(alignment: .leading, spacing: 0) {
                    Text(r.title)
                        .font(.caption.weight(.semibold))
                    Text(r.message)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(compact ? 2 : 1)
                }
            }
        } else {
            Text(entry.digits.isEmpty ? "6桁で自動送信" : "あと\(6 - entry.digits.count)桁")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }
}

struct WidgetCodeBoxes: View {
    let code: String
    let box: CGFloat

    var body: some View {
        let chars = Array(code)
        HStack(spacing: box * 0.22) {
            ForEach(0..<6, id: \.self) { i in
                RoundedRectangle(cornerRadius: box * 0.26, style: .continuous)
                    .fill(Color(uiColor: .secondarySystemFill))
                    .frame(width: box, height: box * 1.25)
                    .overlay {
                        if i < chars.count {
                            Text(String(chars[i]))
                                .font(.system(size: box * 0.6, weight: .semibold, design: .rounded))
                        }
                    }
                    .overlay {
                        if i == chars.count {
                            RoundedRectangle(cornerRadius: box * 0.26, style: .continuous)
                                .strokeBorder(Color.green, lineWidth: 1.5)
                        }
                    }
            }
        }
    }
}

struct WidgetKeypad: View {
    let spacing: CGFloat
    let fontSize: CGFloat

    var body: some View {
        Grid(horizontalSpacing: spacing, verticalSpacing: spacing) {
            GridRow { digit(1); digit(2); digit(3) }
            GridRow { digit(4); digit(5); digit(6) }
            GridRow { digit(7); digit(8); digit(9) }
            GridRow {
                Button(intent: ClearDigitsIntent()) {
                    keyFace { Text("C").font(.system(size: fontSize * 0.85, weight: .medium)) }
                }
                .buttonStyle(.plain)
                digit(0)
                Button(intent: DeleteDigitIntent()) {
                    keyFace { Image(systemName: "delete.backward").font(.system(size: fontSize * 0.8)) }
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func digit(_ n: Int) -> some View {
        Button(intent: PressDigitIntent(digit: n)) {
            keyFace {
                Text("\(n)").font(.system(size: fontSize, weight: .regular, design: .rounded))
            }
        }
        .buttonStyle(.plain)
    }

    private func keyFace<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        content()
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color(uiColor: .secondarySystemFill),
                        in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .contentShape(Rectangle())
    }
}
