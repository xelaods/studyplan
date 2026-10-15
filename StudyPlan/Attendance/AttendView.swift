import SwiftUI
import UIKit

enum AttendMode: String, Hashable {
    case register, status
}

/// 出席タブ：上の切り替えで「登録」（キーパッド）と「状況」（出席状況）
struct AttendView: View {
    @EnvironmentObject var router: AppRouter

    var body: some View {
        NavigationStack {
            Group {
                switch router.attendMode {
                case .register: RegisterPane()
                case .status: StatusPane()
                }
            }
            .navigationTitle(router.attendMode == .register ? "出席登録" : "出席状況")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Picker("表示", selection: $router.attendMode) {
                        Text("登録").tag(AttendMode.register)
                        Text("状況").tag(AttendMode.status)
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 200)
                }
            }
            .navigationDestination(for: AttendanceCourse.self) { AttendanceDetailView(course: $0) }
        }
    }
}

// MARK: - 登録

struct RegisterPane: View {
    @State private var code = ""
    @State private var isSending = false
    @State private var result: RegisterResult?

    var body: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 12)

            Text("講義パスワード")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .padding(.bottom, 14)

            CodeBoxes(code: code, boxSize: 44)

            ZStack {
                if isSending {
                    ProgressView("登録中…")
                        .font(.subheadline)
                } else if let result {
                    ResultBanner(result: result)
                        .transition(.opacity.combined(with: .scale(scale: 0.96)))
                } else if let item = currentClass {
                    // 今の授業（どの授業の出席かの目安）
                    Label("\(item.periodText)  \(item.course.name)", systemImage: "book.closed")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            .frame(height: 76)
            .padding(.horizontal, 20)
            .padding(.top, 12)

            Spacer(minLength: 12)

            PhoneKeypad(
                onDigit: press,
                onDelete: { if !code.isEmpty { code.removeLast() } },
                disabled: isSending)
                .padding(.bottom, 24)
        }
        .frame(maxWidth: .infinity)
        .animation(.snappy, value: result)
        .animation(.snappy, value: isSending)
    }

    /// 授業中、または15分以内に始まる授業
    private var currentClass: ClassItem? {
        let now = Clock.now
        let schedule = Store.shared.schedule
        if let cur = schedule.current(at: now) { return cur }
        let focus = ClassFocus(schedule: schedule, now: now)
        if let item = focus.item, JST.isSameDay(item.start, now),
           item.start.timeIntervalSince(now) <= 15 * 60 { return item }
        return nil
    }

    private func press(_ digit: Int) {
        guard !isSending, code.count < 6 else { return }
        if result != nil { result = nil }
        code.append(String(digit))
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        if code.count == 6 {
            Task { await submit() }
        }
    }

    private func submit() async {
        let credentials = CredentialStore.load()
        guard credentials.isComplete, !Store.isDemo else {
            result = Store.isDemo ? .success(course: "アカデミック・スキル演習") : .failure("「設定」でエドヘンのアカウントを登録してください")
            code = ""
            return
        }
        isSending = true
        let outcome: RegisterResult
        do {
            outcome = try await EdohenClient(credentials: credentials).register(code: code)
        } catch {
            outcome = .failure(error.localizedDescription)
        }
        isSending = false
        result = outcome
        code = ""
        let haptic = UINotificationFeedbackGenerator()
        switch outcome {
        case .success, .already:
            haptic.notificationOccurred(.success)
            // 出席状況も新しくしておく
            Task { await AttendanceStore.shared.load() }
        case .wrongCode: haptic.notificationOccurred(.warning)
        case .failure: haptic.notificationOccurred(.error)
        }
    }
}

struct CodeBoxes: View {
    let code: String
    var boxSize: CGFloat

    var body: some View {
        HStack(spacing: boxSize * 0.2) {
            ForEach(0..<6, id: \.self) { i in
                let chars = Array(code)
                RoundedRectangle(cornerRadius: boxSize * 0.24, style: .continuous)
                    .fill(Color(.secondarySystemFill))
                    .frame(width: boxSize, height: boxSize * 1.2)
                    .overlay {
                        if i < chars.count {
                            Text(String(chars[i]))
                                .font(.system(size: boxSize * 0.55, weight: .medium, design: .rounded))
                                .monospacedDigit()
                        }
                    }
                    .overlay {
                        if i == chars.count {
                            RoundedRectangle(cornerRadius: boxSize * 0.24, style: .continuous)
                                .strokeBorder(Color.accentColor, lineWidth: 2)
                        }
                    }
            }
        }
    }
}

struct ResultBanner: View {
    let result: RegisterResult

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: result.symbol)
                .font(.title2)
                .foregroundStyle(result.tint)
            VStack(alignment: .leading, spacing: 2) {
                Text(result.title).font(.headline)
                Text(result.message)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            Spacer(minLength: 0)
        }
        .padding(14)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}

/// 電話アプリ風のキーパッド
struct PhoneKeypad: View {
    let onDigit: (Int) -> Void
    let onDelete: () -> Void
    var disabled = false

    private let rows: [[Int?]] = [[1, 2, 3], [4, 5, 6], [7, 8, 9], [nil, 0, -1]]

    var body: some View {
        VStack(spacing: 16) {
            ForEach(rows.indices, id: \.self) { r in
                HStack(spacing: 26) {
                    ForEach(rows[r].indices, id: \.self) { c in
                        key(rows[r][c])
                    }
                }
            }
        }
        .disabled(disabled)
    }

    @ViewBuilder
    private func key(_ value: Int?) -> some View {
        switch value {
        case .some(-1):
            Button(action: onDelete) {
                Image(systemName: "delete.backward")
                    .font(.title2)
                    .frame(width: 78, height: 78)
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .foregroundStyle(.primary)
        case .some(let n):
            Button { onDigit(n) } label: {
                Text("\(n)")
                    .font(.system(size: 34, weight: .regular))
                    .frame(width: 78, height: 78)
                    .background(Color(.secondarySystemFill), in: Circle())
            }
            .buttonStyle(KeyButtonStyle())
        case .none:
            Color.clear.frame(width: 78, height: 78)
        }
    }
}

struct KeyButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(.primary)
            .opacity(configuration.isPressed ? 0.45 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

// MARK: - 状況

struct StatusPane: View {
    @ObservedObject var attendance = AttendanceStore.shared

    var body: some View {
        List {
            if let errorText = attendance.errorText {
                Section {
                    Label(errorText, systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.red)
                }
            }
            section("後期", attendance.latter)
            section("前期", attendance.former)
            section("未履修", attendance.unregistered)
            if let updatedAt = attendance.updatedAt, !attendance.courses.isEmpty {
                Section {
                } footer: {
                    Text("\(updatedAt.formatted(date: .abbreviated, time: .shortened)) に更新")
                        .frame(maxWidth: .infinity)
                }
            }
        }
        .listStyle(.insetGrouped)
        .refreshable { await attendance.load() }
        .overlay {
            if attendance.courses.isEmpty {
                if attendance.isLoading {
                    ProgressView()
                } else if attendance.errorText == nil {
                    ContentUnavailableView("出席データがありません",
                                           systemImage: "list.bullet.rectangle",
                                           description: Text("下に引っ張って更新します"))
                }
            }
        }
        .task { await attendance.refreshIfStale() }
    }

    @ViewBuilder
    private func section(_ title: String, _ items: [AttendanceCourse]) -> some View {
        if !items.isEmpty {
            Section(title) {
                ForEach(items) { course in
                    NavigationLink(value: course) {
                        AttendanceRow(course: course)
                    }
                }
            }
        }
    }
}

struct AttendanceRow: View {
    let course: AttendanceCourse

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text(course.name)
                    .font(.body.weight(.semibold))
                    .lineLimit(1)
                Spacer(minLength: 8)
                Text(course.teacher)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            AttendanceCounts(course: course)
            SessionStrip(sessions: course.sessions)
        }
        .padding(.vertical, 4)
        .opacity(course.isUnregistered ? 0.5 : 1)
    }
}

/// 出・遅・欠の3つのバッジ
struct AttendanceCounts: View {
    let course: AttendanceCourse

    var body: some View {
        HStack(spacing: 6) {
            CountBadge(label: "出", value: course.present, color: .green)
            CountBadge(label: "遅", value: course.late, color: .orange)
            CountBadge(label: "欠", value: course.absent, color: .red,
                       filled: course.absent >= 3 && !course.isUnregistered,
                       fillColor: course.absent >= 4 ? .red : .orange)
        }
    }
}

struct CountBadge: View {
    let label: String
    let value: Int
    let color: Color
    var filled = false
    var fillColor: Color = .red

    var body: some View {
        Text("\(label) \(value)")
            .font(.caption.weight(.semibold))
            .monospacedDigit()
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .foregroundStyle(filled ? .white : color)
            .background(filled ? fillColor : color.opacity(0.14), in: Capsule())
    }
}

struct SessionStrip: View {
    let sessions: [AttendanceSession]

    var body: some View {
        HStack(spacing: 3) {
            ForEach(sessions) { s in
                RoundedRectangle(cornerRadius: 3, style: .continuous)
                    .fill(s.status.color)
                    .frame(width: 11, height: 11)
            }
        }
    }
}

// MARK: - 詳細

/// 各回の記録の行（出席の詳細と時間割の授業の詳細で共通）
struct SessionRow: View {
    let session: AttendanceSession

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(session.date).monospacedDigit()
                Text(session.period)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Label {
                Text(detailText)
                    .monospacedDigit()
            } icon: {
                Image(systemName: session.status.symbol)
                    .foregroundStyle(session.status.color)
            }
            .foregroundStyle(.secondary)
        }
    }

    private var detailText: String {
        switch session.status {
        case .present, .late:
            return session.detail.contains(":") ? "\(session.status.label) \(session.detail)" : session.status.label
        case .absent, .unused:
            return session.status.label
        }
    }
}

struct AttendanceDetailView: View {
    let course: AttendanceCourse

    var body: some View {
        List {
            Section {
                LabeledContent("担当", value: course.teacher)
                LabeledContent("出席", value: "\(course.present) 回")
                LabeledContent("遅刻", value: "\(course.late) 回")
                LabeledContent("欠席", value: "\(course.absent) 回")
            }
            Section("各回の記録") {
                ForEach(course.sessions) { SessionRow(session: $0) }
            }
        }
        .navigationTitle(course.name)
        .navigationBarTitleDisplayMode(.inline)
    }
}
