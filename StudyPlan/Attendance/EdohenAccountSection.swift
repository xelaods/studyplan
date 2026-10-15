import SwiftUI

/// 設定のいちばん上：エドヘンのアカウント
struct EdohenAccountSection: View {
    @State private var userID = ""
    @State private var password = ""
    @State private var studentNo = ""
    @State private var loaded = false
    @State private var testState: TestState = .idle

    enum TestState: Equatable {
        case idle, testing, ok, failed(String)
    }

    var body: some View {
        Section {
            TextField("edo-net ID", text: $userID)
                .textContentType(.username)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
            SecureField("パスワード", text: $password)
                .textContentType(.password)
            TextField("学籍番号", text: $studentNo)
                .keyboardType(.numberPad)
        } header: {
            Text("エドヘン アカウント")
        } footer: {
            Text("出席登録と出席状況に使います。アカウント情報はこのiPhoneの中にだけ保存され、パスワードはキーチェーンに保存されます。")
        }
        .onAppear(perform: load)
        .onChange(of: userID) { save() }
        .onChange(of: password) { save() }
        .onChange(of: studentNo) { save() }

        Section {
            Button {
                Task { await test() }
            } label: {
                HStack {
                    Text("ログインを確認")
                    Spacer()
                    switch testState {
                    case .idle: EmptyView()
                    case .testing: ProgressView()
                    case .ok:
                        Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                    case .failed:
                        Image(systemName: "xmark.circle.fill").foregroundStyle(.red)
                    }
                }
            }
            .disabled(testState == .testing)
        } footer: {
            if case .failed(let message) = testState {
                Text(message)
            }
        }
    }

    private func load() {
        guard !loaded else { return }
        let c = CredentialStore.load()
        userID = c.userID
        password = c.password
        studentNo = c.studentNo
        loaded = true
    }

    private func save() {
        guard loaded else { return }
        CredentialStore.save(EdohenCredentials(userID: userID, password: password, studentNo: studentNo))
        if testState != .testing { testState = .idle }
    }

    private func test() async {
        testState = .testing
        do {
            try await EdohenClient(credentials: CredentialStore.load()).login()
            testState = .ok
            await AttendanceStore.shared.load()
        } catch {
            testState = .failed(error.localizedDescription)
        }
    }
}

/// 出席登録ウィジェットの使い方
struct AttendWidgetHelpView: View {
    var body: some View {
        Form {
            Section {
                VStack(alignment: .leading, spacing: 10) {
                    step(1, "ホーム画面の何もないところを長押しして、左上の「編集」→「ウィジェットを追加」")
                    step(2, "「出席・時間割」の中の「出席登録」を、中または大のサイズで追加")
                    step(3, "置いたウィジェットを長押し →「ウィジェットを編集」で、設定と同じID・パスワード・学籍番号を入力")
                    step(4, "数字を6桁押すと、自動で出席登録します。結果はウィジェットと通知に出ます")
                }
                .padding(.vertical, 4)
            } footer: {
                Text("ウィジェットとアプリは保存場所が別なので、ウィジェットにもアカウントの入力が必要です。")
            }
        }
        .navigationTitle("出席登録ウィジェット")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func step(_ n: Int, _ text: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text("\(n)")
                .font(.caption.weight(.bold))
                .foregroundStyle(.white)
                .frame(width: 20, height: 20)
                .background(Color.accentColor, in: Circle())
            Text(text)
                .font(.subheadline)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
