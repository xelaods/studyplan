import Foundation

/// 見本のデータ（スクリーンショットとウィジェットの見本用）
enum Sample {
    static func courses() -> [Course] {
        [
            Course(name: "アカデミック・スキル演習", teacher: "佐藤 健一", room: "A201", day: .mon, period: 3, term: .full, color: .blue),
            Course(name: "情報処理演習", teacher: "鈴木 美咲", room: "情報処理室2", day: .mon, period: 4, length: 2, term: .full, color: .orange),
            Course(name: "メディア論", teacher: "高橋 誠", room: "B301", day: .tue, period: 1, term: .full, color: .green),
            Course(name: "統計学入門", teacher: "田中 浩", room: "A105", day: .tue, period: 2, term: .full, color: .purple, absences: 1),
            Course(name: "社会学概論", teacher: "伊藤 由美", room: "大教室", day: .tue, period: 3, term: .full, color: .red),
            Course(name: "英語コミュニケーションII", teacher: "Smith J.", room: "C204", day: .wed, period: 2, term: .full, color: .teal),
            Course(name: "Webデザイン", teacher: "渡辺 翔", room: "情報処理室1", day: .thu, period: 1, term: .full, color: .pink),
            Course(name: "ネットワーク基礎", teacher: "山本 直樹", room: "A302", day: .thu, period: 2, term: .full, color: .indigo),
            Course(name: "健康・スポーツ科学演習", teacher: "中村 大輔", room: "体育館", day: .thu, period: 3, term: .full, color: .mint),
            Course(name: "プログラミング基礎", teacher: "小林 恵", room: "情報処理室3", day: .thu, period: 4, term: .full, color: .yellow),
            Course(name: "キャリアデザイン", teacher: "加藤 隆", room: "オンデマンド", day: nil, period: nil, term: .full, color: .brown),
        ]
    }

    static func catalog() -> [CatalogCourse] {
        let registered: [CatalogCourse] = courses().map { (c: Course) -> CatalogCourse in
            var slots: [Slot] = []
            if let d = c.day, let p = c.period {
                for q in p...(p + c.length - 1) { slots.append(Slot(day: d, period: q)) }
            }
            return CatalogCourse(name: c.name, teacher: c.teacher, room: c.room, slots: slots, term: c.term, source: "エドポタ")
        }
        return registered + [
            CatalogCourse(name: "心理学概論", teacher: "吉田 彩", room: "A201", slots: [Slot(day: .mon, period: 3)], term: .full, source: "エドポタ"),
            CatalogCourse(name: "観光文化論", teacher: "松本 亮", room: "B204", slots: [Slot(day: .mon, period: 3)], term: .full, source: "エドポタ"),
            CatalogCourse(name: "マーケティング論", teacher: "井上 智子", room: "A303", slots: [Slot(day: .wed, period: 3)], term: .full, source: "エドポタ"),
            CatalogCourse(name: "環境と社会", teacher: "木村 修", room: "C101", slots: [Slot(day: .fri, period: 2)], term: .full, source: "エドポタ"),
        ]
    }

    static func data() -> AppData {
        var d = AppData()
        d.courses = courses()
        d.catalog = catalog()
        d.catalogUpdated = Date()
        for i in d.courses.indices where d.courses[i].day != nil {
            d.courses[i].sourceID = CatalogCourse.key(name: d.courses[i].name, teacher: d.courses[i].teacher, term: d.courses[i].term)
        }
        return d
    }

    static func snapshot() -> WidgetSnapshot { data().snapshot }

    /// ウィジェットの見本は「平日の 10:20」として表示する
    static var previewNow: Date {
        let now = Date()
        var d = JST.startOfDay(now)
        // 平日まで進める（月〜木のどれかが見栄えがよい）
        for _ in 0..<7 {
            if let wd = JST.weekday(d), [.mon, .tue, .thu].contains(wd) { break }
            d = JST.adding(days: 1, to: d)
        }
        return JST.date(d, minutes: 10 * 60 + 20)
    }
}
