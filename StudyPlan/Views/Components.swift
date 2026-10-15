import SwiftUI

/// 授業を取り込む先
enum ImportSource: String, Identifiable, CaseIterable {
    case portal, syllabus

    var id: String { rawValue }

    var title: String {
        switch self {
        case .portal: return "エドポタ"
        case .syllabus: return "Webシラバス"
        }
    }

    var url: URL {
        switch self {
        case .portal: return URL(string: "https://portal.edogawa-u.ac.jp/uprx/")!
        case .syllabus: return URL(string: "https://portal.edogawa-u.ac.jp/uprx/up/pk/pky001/Pky00101.xhtml?guestlogin=Pkx003")!
        }
    }

    var hint: String {
        switch self {
        case .portal: return "ログインして、上のメニュー「履修・時間割」→「学生時間割表」を開き、下のボタンを押してください"
        case .syllabus: return "授業を検索して一覧を表示し、下のボタンを押してください"
        }
    }
}

/// 授業の一覧の1行
struct CourseListRow: View {
    let course: Course
    var showSlot: Bool = true
    @ObservedObject var attendance = AttendanceStore.shared

    var body: some View {
        HStack(spacing: 12) {
            CourseBadge(color: course.color, text: course.period.map { "\($0)" } ?? "−")
            VStack(alignment: .leading, spacing: 2) {
                Text(course.name.isEmpty ? "名前なし" : course.name)
                    .lineLimit(2)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
            if course.isRequired {
                Text("必修")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(Soft.red)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Soft.red.opacity(0.14), in: Capsule())
            }
            let absences = attendance.record(for: course)?.absent ?? course.absences
            if absences > 0 {
                Text("欠\(absences)")
                    .font(.caption2.weight(.semibold))
                    .monospacedDigit()
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .foregroundStyle(absences >= 3 ? .white : .red)
                    .background(absences >= 4 ? Color.red : (absences >= 3 ? Color.orange : Color.red.opacity(0.14)), in: Capsule())
            }
        }
    }

    private var subtitle: String {
        var parts: [String] = []
        if showSlot { parts.append(course.slotText) }
        if !course.room.isEmpty { parts.append(course.room) }
        if !course.teacher.isEmpty { parts.append(course.teacher) }
        return parts.joined(separator: "・")
    }
}

/// 設定アプリのアイコンのような角丸の四角
struct CourseBadge: View {
    let color: CourseColor
    let text: String
    var size: CGFloat = 30

    var body: some View {
        Text(text)
            .font(.system(size: size * 0.5, weight: .bold, design: .rounded))
            .foregroundStyle(.white)
            .frame(width: size, height: size)
            .background(color.color.gradient, in: RoundedRectangle(cornerRadius: size * 0.25, style: .continuous))
    }
}

/// 設定の行の文字（出席アプリと同じく、アイコンなしのシンプルな行）
struct SettingsLabel: View {
    let title: String
    var systemName: String = ""
    var color: Color = .accentColor

    var body: some View {
        Text(title)
    }
}

/// 必修（赤）・選択（青）の切り替え
struct RequiredPicker: View {
    @Binding var isRequired: Bool

    var body: some View {
        Picker("区分", selection: $isRequired) {
            Text("必修（赤）").tag(true)
            Text("選択・その他（青）").tag(false)
        }
        .pickerStyle(.segmented)
        .padding(.vertical, 2)
    }
}

/// 取得した授業の1行（選択式の一覧で使う）
struct CatalogRow: View {
    let course: CatalogCourse
    var selected: Bool? = nil
    var registered: Bool = false

    var body: some View {
        HStack(spacing: 12) {
            if let selected {
                Image(systemName: registered ? "checkmark.circle.fill" : (selected ? "checkmark.circle.fill" : "circle"))
                    .font(.title2)
                    .foregroundStyle(registered ? Color.secondary.opacity(0.5) : (selected ? Color.accentColor : Color.secondary.opacity(0.6)))
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(course.name)
                    .foregroundStyle(registered ? Color.secondary : Color.primary)
                    .lineLimit(2)
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
            if registered {
                Text("登録済み")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .contentShape(Rectangle())
    }

    private var detail: String {
        var parts = [course.slotText]
        if let t = course.term { parts.append(t.label) }
        if !course.room.isEmpty { parts.append(course.room) }
        if !course.teacher.isEmpty { parts.append(course.teacher) }
        return parts.joined(separator: "・")
    }
}
