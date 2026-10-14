import SwiftUI
import WebKit

/// エドポタ・Webシラバスを開いて、表示中の画面から授業を読み取る
struct ImportView: View {
    let source: ImportSource
    @EnvironmentObject var store: Store
    @Environment(\.dismiss) var dismiss
    @StateObject var web = WebModel()
    @State var results: [CatalogCourse]?
    @State var showResults = false
    @State var failed = false
    @State var reading = false
    @State var current: ImportSource = .portal

    var body: some View {
        NavigationStack {
            ZStack(alignment: .top) {
                if Store.isDemo {
                    demoPage
                } else {
                    WebView(model: web)
                        .ignoresSafeArea(edges: .bottom)
                }
                if web.progress > 0, web.progress < 1 {
                    ProgressView(value: web.progress)
                        .progressViewStyle(.linear)
                        .tint(.blue)
                }
            }
            .safeAreaInset(edge: .bottom) { bottomBar }
            .navigationTitle(current.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("閉じる") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Picker("開くページ", selection: Binding(get: { current }, set: { open($0) })) {
                            ForEach(ImportSource.allCases) { s in Text(s.title).tag(s) }
                        }
                        Divider()
                        Button { web.reload() } label: { Label("再読み込み", systemImage: "arrow.clockwise") }
                        Toggle(isOn: Binding(get: { web.desktop }, set: { web.setDesktop($0) })) {
                            Label("PC版で表示", systemImage: "desktopcomputer")
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                }
            }
            .navigationDestination(isPresented: $showResults) {
                ImportResultsView(results: results ?? [], onDone: { dismiss() })
            }
            .alert("授業を読み取れませんでした", isPresented: $failed) {
                Button("OK", role: .cancel) {}
            } message: {
                Text("時間割表、またはシラバスの検索結果の一覧を表示してから、もう一度お試しください。うまくいかないときは、右上のメニューから「PC版で表示」に切り替えてみてください。")
            }
            .onAppear {
                current = source
                if Store.isDemo {
                    if ProcessInfo.processInfo.arguments.contains("-results") { read() }
                    return
                }
                web.load(source.url)
            }
        }
    }

    private func open(_ s: ImportSource) {
        current = s
        web.load(s.url)
    }

    private var bottomBar: some View {
        VStack(spacing: 8) {
            Text(current.hint)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
            HStack(spacing: 12) {
                Button { web.goBack() } label: {
                    Image(systemName: "chevron.backward").frame(width: 36, height: 36)
                }
                .disabled(!web.canGoBack)
                Button { web.goForward() } label: {
                    Image(systemName: "chevron.forward").frame(width: 36, height: 36)
                }
                .disabled(!web.canGoForward)
                Button {
                    read()
                } label: {
                    HStack {
                        if reading { ProgressView().tint(.white) }
                        Text("この画面から授業を読み取る")
                            .fontWeight(.semibold)
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(reading)
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 10)
        .padding(.bottom, 6)
        .background(.bar)
    }

    private func read() {
        if Store.isDemo {
            results = Sample.catalog()
            showResults = true
            return
        }
        reading = true
        web.extract { page in
            reading = false
            guard let page else { failed = true; return }
            let found = TimetableParser.parse(tables: page.tables.map { ($0.rows, $0.label) }, text: page.text, term: nil, source: current.title)
            if found.isEmpty {
                failed = true
            } else {
                store.mergeCatalog(found)
                results = found
                showResults = true
                UINotificationFeedbackGenerator().notificationOccurred(.success)
            }
        }
    }

    /// スクリーンショット用の見本（エドポタの代わり）
    private var demoPage: some View {
        List {
            Section("学生時間割表") {
                ForEach(Sample.catalog().prefix(6)) { c in
                    VStack(alignment: .leading) {
                        Text(c.name)
                        Text(c.slotText + "・" + c.teacher).font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
        }
    }
}

// MARK: - 読み取った授業から選ぶ

struct ImportResultsView: View {
    let results: [CatalogCourse]
    let onDone: () -> Void
    @EnvironmentObject var store: Store
    @State var selected: Set<String> = []
    @State var term: Term = .second
    @State var didInit = false

    var body: some View {
        let groups = grouped
        List {
            Section {
                VStack(alignment: .leading, spacing: 4) {
                    Text("\(results.count)件の授業が見つかりました")
                        .font(.headline)
                    Text("時間割に入れる授業を選んでください。選ばなかった授業も、あとで空きコマをタップしたときの候補に出てきます。")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 2)
                if results.contains(where: { $0.term == nil }) {
                    Picker("学期", selection: $term) {
                        ForEach(Term.allCases) { t in Text(t.label).tag(t) }
                    }
                }
            } footer: {
                if results.contains(where: { $0.term == nil }) {
                    Text("学期がわからない授業は、ここで選んだ学期として登録します。")
                }
            }

            ForEach(groups) { group in
                Section(group.title) {
                    ForEach(group.items) { c in
                        let registered = store.isRegistered(c)
                        Button {
                            guard !registered else { return }
                            if selected.contains(c.id) { selected.remove(c.id) } else { selected.insert(c.id) }
                        } label: {
                            CatalogRow(course: c, selected: selected.contains(c.id), registered: registered)
                        }
                        .foregroundStyle(.primary)
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("授業を選ぶ")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button(allSelected ? "選択解除" : "すべて選択") {
                    if allSelected { selected.removeAll() } else { selected = Set(selectable.map(\.id)) }
                }
            }
        }
        .safeAreaInset(edge: .bottom) {
            Button {
                store.add(results.filter { selected.contains($0.id) }, term: term)
                UINotificationFeedbackGenerator().notificationOccurred(.success)
                onDone()
            } label: {
                Text(selected.isEmpty ? "授業を選んでください" : "時間割に追加（\(selected.count)件）")
                    .fontWeight(.semibold)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(selected.isEmpty)
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(.bar)
        }
        .onAppear {
            guard !didInit else { return }
            didInit = true
            term = store.term
            // 時間割表から読んだときは自分の授業なので、最初から全部選んでおく（シラバスの検索結果のように多いときは選ばない）
            if results.count <= 40 {
                selected = Set(selectable.map(\.id))
            }
        }
    }

    private var selectable: [CatalogCourse] { results.filter { !store.isRegistered($0) } }
    private var allSelected: Bool { !selectable.isEmpty && selectable.allSatisfy { selected.contains($0.id) } }

    struct Group: Identifiable {
        let title: String
        let items: [CatalogCourse]
        var id: String { title }
    }

    private var grouped: [Group] {
        // 学期ごと（今の学期を先に）、その中は曜日・時限の順
        let current = store.term
        let base: [Term?] = [current, .first, .second, .full, nil]
        var order: [Term?] = []
        for t in base where !order.contains(where: { $0 == t }) { order.append(t) }
        var out: [Group] = []
        for t in order {
            let items = results.filter { $0.term == t }
            guard !items.isEmpty else { continue }
            let title: String
            if let t {
                title = t == current ? "\(t.label)（今の学期）" : t.label
            } else {
                title = "学期の記載なし"
            }
            out.append(Group(title: title, items: items))
        }
        return out
    }
}

// MARK: - WebView

struct ExtractedTable: Decodable {
    let rows: [[String]]
    let label: String
}

struct ExtractedPage: Decodable {
    let tables: [ExtractedTable]
    let text: String
    let title: String
    let url: String
}

final class WebModel: NSObject, ObservableObject, WKNavigationDelegate, WKUIDelegate {
    @Published var progress: Double = 0
    @Published var canGoBack = false
    @Published var canGoForward = false
    @Published var desktop = UserDefaults.standard.bool(forKey: "importDesktop")

    let webView: WKWebView
    private var observations: [NSKeyValueObservation] = []

    static let desktopAgent = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Safari/605.1.15"

    override init() {
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .default()
        config.defaultWebpagePreferences.preferredContentMode = .recommended
        webView = WKWebView(frame: .zero, configuration: config)
        super.init()
        webView.navigationDelegate = self
        webView.uiDelegate = self
        webView.allowsBackForwardNavigationGestures = true
        applyAgent()
        observations = [
            webView.observe(\.estimatedProgress, options: [.new]) { [weak self] wv, _ in
                DispatchQueue.main.async { self?.progress = wv.estimatedProgress }
            },
            webView.observe(\.canGoBack, options: [.new]) { [weak self] wv, _ in
                DispatchQueue.main.async { self?.canGoBack = wv.canGoBack }
            },
            webView.observe(\.canGoForward, options: [.new]) { [weak self] wv, _ in
                DispatchQueue.main.async { self?.canGoForward = wv.canGoForward }
            },
        ]
    }

    private func applyAgent() {
        webView.customUserAgent = desktop ? WebModel.desktopAgent : nil
    }

    func setDesktop(_ on: Bool) {
        desktop = on
        UserDefaults.standard.set(on, forKey: "importDesktop")
        applyAgent()
        webView.reload()
    }

    func load(_ url: URL) { webView.load(URLRequest(url: url)) }
    func reload() { webView.reload() }
    func goBack() { webView.goBack() }
    func goForward() { webView.goForward() }

    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction,
                 preferences: WKWebpagePreferences,
                 decisionHandler: @escaping (WKNavigationActionPolicy, WKWebpagePreferences) -> Void) {
        preferences.preferredContentMode = desktop ? .desktop : .recommended
        decisionHandler(.allow, preferences)
    }

    /// 新しいウインドウで開くリンク（target=_blank）も同じ画面で開く
    func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration,
                 for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
        if navigationAction.targetFrame == nil { webView.load(navigationAction.request) }
        return nil
    }

    func webView(_ webView: WKWebView, runJavaScriptAlertPanelWithMessage message: String,
                 initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping () -> Void) {
        completionHandler()
    }

    func webView(_ webView: WKWebView, runJavaScriptConfirmPanelWithMessage message: String,
                 initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping (Bool) -> Void) {
        completionHandler(true)
    }

    func extract(completion: @escaping (ExtractedPage?) -> Void) {
        webView.evaluateJavaScript(WebModel.extractScript) { result, _ in
            DispatchQueue.main.async {
                guard let json = result as? String, let data = json.data(using: .utf8),
                      let page = try? JSONDecoder().decode(ExtractedPage.self, from: data) else {
                    completion(nil)
                    return
                }
                completion(page)
            }
        }
    }

    /// 画面の表を、結合セル（rowspan・colspan）を展開した2次元の文字列にして返す
    static let extractScript = """
    (function(){
      function txt(el){ return ((el && (el.innerText || el.textContent)) || '').replace(/\\u00a0/g,' ').replace(/[ \\t]+\\n/g,'\\n').trim(); }
      function grid(table){
        var rows = table.rows, m = [];
        for (var r = 0; r < rows.length; r++) {
          m[r] = m[r] || [];
          var c = 0, cells = rows[r].cells;
          for (var i = 0; i < cells.length; i++) {
            while (m[r][c] !== undefined) c++;
            var cell = cells[i], t = txt(cell);
            var rs = Math.max(1, Math.min(10, cell.rowSpan || 1)), cs = Math.max(1, Math.min(10, cell.colSpan || 1));
            for (var a = 0; a < rs; a++) { m[r+a] = m[r+a] || []; for (var b = 0; b < cs; b++) { m[r+a][c+b] = t; } }
            c += cs;
          }
        }
        var out = [];
        for (var r2 = 0; r2 < m.length; r2++) {
          var row = m[r2] || [], o = [];
          for (var k = 0; k < row.length; k++) o.push(row[k] === undefined ? '' : row[k]);
          out.push(o);
        }
        return out;
      }
      var docs = [document];
      var frames = document.querySelectorAll('iframe,frame');
      for (var f = 0; f < frames.length; f++) { try { if (frames[f].contentDocument) docs.push(frames[f].contentDocument); } catch (e) {} }
      var termRe = /(\d{4})\s*年度\s*(前期|後期|通年|前学期|後学期|春学期|秋学期)/;
      var tables = [], text = '';
      for (var d = 0; d < docs.length; d++) {
        var doc = docs[d];
        // 表の前にある「2026年度 前期」のような見出しを、文書の順にたどって表に結びつける
        var all = doc.body ? doc.body.getElementsByTagName('*') : [];
        var last = '';
        for (var i = 0; i < all.length && tables.length < 80; i++) {
          var el = all[i];
          if (el.tagName === 'TABLE') {
            var g = grid(el);
            if (g.length > 1) tables.push({ rows: g, label: last });
            continue;
          }
          if (el.childElementCount <= 2) {
            var t = (el.textContent || '').trim();
            if (t.length > 0 && t.length <= 40) { var m = t.match(termRe); if (m) last = m[0]; }
          }
        }
        var rows = doc.querySelectorAll('[role=row]');
        if (rows.length > 1 && doc.querySelectorAll('table [role=row]').length === 0) {
          var g2 = [];
          for (var j = 0; j < rows.length; j++) {
            var cells = rows[j].querySelectorAll('[role=gridcell],[role=columnheader],[role=cell],[role=rowheader]');
            if (cells.length) { var o2 = []; for (var k2 = 0; k2 < cells.length; k2++) o2.push(txt(cells[k2])); g2.push(o2); }
          }
          if (g2.length > 1) tables.push({ rows: g2, label: '' });
        }
        text += '\\n' + txt(doc.body || doc.documentElement);
      }
      return JSON.stringify({ tables: tables, text: text.slice(0, 200000), title: document.title || '', url: location.href });
    })();
    """
}

struct WebView: UIViewRepresentable {
    let model: WebModel

    func makeUIView(context: Context) -> WKWebView { model.webView }
    func updateUIView(_ uiView: WKWebView, context: Context) {}
}
