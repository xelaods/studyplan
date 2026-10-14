import Foundation

/// 見本のデータ（スクリーンショットとウィジェットの見本用）
enum Sample {
    static func courses() -> [Course] {
        [
            Course(name: "アカデミック・スキル演習", teacher: "佐藤 健一", room: "A201", day: .mon, period: 3, term: .full, isRequired: true),
            Course(name: "情報処理演習", teacher: "鈴木 美咲", room: "情報処理室2", day: .mon, period: 4, length: 2, term: .full),
            Course(name: "メディア論", teacher: "高橋 誠", room: "B301", day: .tue, period: 1, term: .full),
            Course(name: "統計学入門", teacher: "田中 浩", room: "A105", day: .tue, period: 2, term: .full, absences: 1),
            Course(name: "社会学概論", teacher: "伊藤 由美", room: "大教室", day: .tue, period: 3, term: .full, isRequired: true),
            Course(name: "英語コミュニケーションII", teacher: "Smith J.", room: "C204", day: .wed, period: 2, term: .full),
            Course(name: "Webデザイン", teacher: "渡辺 翔", room: "情報処理室1", day: .thu, period: 1, term: .full),
            Course(name: "ネットワーク基礎", teacher: "山本 直樹", room: "A302", day: .thu, period: 2, term: .full),
            Course(name: "健康・スポーツ科学演習", teacher: "中村 大輔", room: "体育館", day: .thu, period: 3, term: .full),
            Course(name: "プログラミング基礎", teacher: "小林 恵", room: "情報処理室3", day: .thu, period: 4, term: .full),
            Course(name: "キャリアデザイン", teacher: "加藤 隆", room: "オンデマンド", day: nil, period: nil, term: .full),
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

    /// 通学の見本（舞浜 → 流山おおたかの森 → 大学）
    static func commutePlan() -> CommutePlan {
        let now = previewNow
        let today = JST.startOfDay(now)
        func r(_ dep: Int, _ arr: Int, _ bus: Int, late: Bool = false, lateBy: Int = 0, last: Bool = false) -> CommuteRow {
            CommuteRow(bus: bus, train: TrainRoute(dep: dep, arr: arr, transfers: 2), late: late, lateBy: lateBy, isLast: last)
        }
        let hm: (Int, Int) -> Int = { $0 * 60 + $1 }
        let back = CommuteSection(direction: .back, title: "3限 社会学概論 14:50終了", subtitle: "", date: now, isToday: true, rows: [
            CommuteRow(bus: hm(15, 0), train: TrainRoute(dep: hm(15, 11), arr: hm(16, 2))),
            CommuteRow(bus: hm(15, 15), train: TrainRoute(dep: hm(15, 26), arr: hm(16, 17))),
            CommuteRow(bus: hm(15, 30), train: TrainRoute(dep: hm(15, 41), arr: hm(16, 33))),
        ])
        let tomorrow = JST.adding(days: 1, to: today)
        let go = CommuteSection(direction: .go, title: "明日 2限 10:50 英語コミュニケーションII", subtitle: CommutePlanner.dayText(tomorrow),
                                date: tomorrow, isToday: false, rows: [
            r(hm(9, 2), hm(9, 48), hm(9, 55)),
            r(hm(9, 14), hm(10, 0), hm(10, 5)),
            r(hm(9, 26), hm(10, 12), hm(10, 20), last: true),
            r(hm(9, 38), hm(10, 24), hm(10, 30), late: true, lateBy: 1),
        ])
        return CommutePlan(title: "帰宅", dia: "Aダイヤ", sections: [back, go], message: nil, generated: now,
                           bus: BusDay(date: now, diaKey: "A", dia: "Aダイヤ",
                                       toUniv: stride(from: hm(8, 0), to: hm(18, 0), by: 15).map { $0 },
                                       toStation: stride(from: hm(9, 0), to: hm(19, 30), by: 15).map { $0 }, unknown: false))
    }
}
