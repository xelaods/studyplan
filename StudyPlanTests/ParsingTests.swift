import XCTest
@testable import StudyPlan

final class ParsingTests: XCTestCase {

    func testSlots() {
        XCTAssertEqual(TimetableParser.parseSlots("月3"), [Slot(day: .mon, period: 3)])
        XCTAssertEqual(TimetableParser.parseSlots("月曜3限"), [Slot(day: .mon, period: 3)])
        XCTAssertEqual(TimetableParser.parseSlots("火曜日 ２時限"), [Slot(day: .tue, period: 2)])
        XCTAssertEqual(TimetableParser.parseSlots("月4・5"), [Slot(day: .mon, period: 4), Slot(day: .mon, period: 5)])
        XCTAssertEqual(TimetableParser.parseSlots("月3,木3"), [Slot(day: .mon, period: 3), Slot(day: .thu, period: 3)])
        XCTAssertEqual(TimetableParser.parseSlots("水/2"), [Slot(day: .wed, period: 2)])
        XCTAssertEqual(TimetableParser.parseSlots("金曜三限"), [Slot(day: .fri, period: 3)])
        // 日付の「10月14日」を曜日と読まない
        XCTAssertEqual(TimetableParser.parseSlots("2026年10月14日"), [])
        XCTAssertEqual(TimetableParser.parseSlots("集中"), [])
    }

    func testTerm() {
        XCTAssertEqual(TimetableParser.parseTerm("2026年度 前期"), .first)
        XCTAssertEqual(TimetableParser.parseTerm("後期"), .second)
        XCTAssertEqual(TimetableParser.parseTerm("通年"), .full)
        XCTAssertNil(TimetableParser.parseTerm("複数学期"))
    }

    func testCell() {
        let info = TimetableParser.splitCell("データベースI\n松尾由美 (T-0504)\nE302 AVラック\n10795\n2単位")
        XCTAssertEqual(info?.name, "データベースI")
        XCTAssertEqual(info?.teacher, "松尾由美")
        XCTAssertEqual(info?.room, "E302")
        XCTAssertEqual(info?.code, "10795")

        let info2 = TimetableParser.splitCell("情報文化演習\n廣田 有里(D-1004)\nB603 AVラック\n10823\n4単位\n複数学期")
        XCTAssertEqual(info2?.name, "情報文化演習")
        XCTAssertEqual(info2?.teacher, "廣田 有里")
        XCTAssertEqual(info2?.room, "B603")

        let info3 = TimetableParser.splitCell("コンピュータグラフィックス\nZhan Ping(D-1304)\nB702 PC\n10791\n2単位")
        XCTAssertEqual(info3?.teacher, "Zhan Ping")
        XCTAssertEqual(info3?.room, "B702")
    }

    /// エドポタの「学生時間割表」と同じ形の表
    func testPortalGrid() {
        let rows: [[String]] = [
            ["", "月曜日", "火曜日", "水曜日", "木曜日", "金曜日"],
            ["1", "", "コンピュータグラフィックス\nZhan Ping(D-1304)\nB702 PC\n10791\n2単位", "", "Webアプリ開発\n山口 敏和(T-0603)\nB702 PC\n10790\n2単位", ""],
            ["2", "", "統計学概論\n松尾由美 (T-0504)\nB605 AVラック\n10811\n2単位", "ネットワークと社会\n玉田 和恵 (T-0503)\nD122 ネットワーク\n10788\n2単位", "情報ネットワーク演習\n吉村 準(H-0023)\nB705 PC\n10798\n2単位", ""],
            ["昼休み", "昼休み", "昼休み", "昼休み", "昼休み", "昼休み"],
            ["3", "アカデミック・スキル演習IIB\n市村 由起\nD121 ネットワーク\n10166\n2単位", "民俗学\n林 承緯\nD321 AVラック\n10409\n2単位", "", "健康・スポーツ科学演習\n青木 拓郎(T-0601)\n第二体育館\n10219\n4単位\n複数学期", ""],
            ["4", "情報文化演習\n廣田 有里(D-1004)\nB603 AVラック\n10823\n4単位\n複数学期", "情報社会と文化\n廣田 有里(D-1004)\nB605 AVラック\n10818\n2単位", "", "プログラミングII\n八木 徹 (D-0103)\nE312 ネットワーク\n10794\n2単位", ""],
            ["5", "情報文化実習\n廣田 有里(D-1004)\nB603 AVラック\n10824\n2単位\n複数学期", "", "", "", ""],
        ]
        let found = TimetableParser.parse(tables: [(rows, "2026年度 後期")], text: "", term: nil, source: "test")
        XCTAssertEqual(found.count, 12)
        XCTAssertTrue(found.allSatisfy { $0.term == .second })
        let skill = found.first { $0.name == "アカデミック・スキル演習IIB" }
        XCTAssertEqual(skill?.slots, [Slot(day: .mon, period: 3)])
        XCTAssertEqual(skill?.room, "D121")
        let net = found.first { $0.name == "ネットワークと社会" }
        XCTAssertEqual(net?.slots, [Slot(day: .wed, period: 2)])
        XCTAssertEqual(net?.teacher, "玉田 和恵")
    }

    /// 前期と後期の表が1つの画面にあるとき
    func testTwoTerms() {
        let front: [[String]] = [
            ["", "月曜日", "火曜日", "水曜日", "木曜日", "金曜日"],
            ["1", "", "データベースI\n松尾由美 (T-0504)\nE302 AVラック\n10795\n2単位", "", "", ""],
        ]
        let back: [[String]] = [
            ["", "月曜日", "火曜日", "水曜日", "木曜日", "金曜日"],
            ["1", "", "コンピュータグラフィックス\nZhan Ping(D-1304)\nB702 PC\n10791\n2単位", "", "", ""],
        ]
        let found = TimetableParser.parse(tables: [(front, "2026年度 前期"), (back, "2026年度 後期")], text: "", term: nil, source: "test")
        XCTAssertEqual(found.first { $0.name == "データベースI" }?.term, .first)
        XCTAssertEqual(found.first { $0.name == "コンピュータグラフィックス" }?.term, .second)
    }

    /// シラバスの検索結果のような一覧
    func testList() {
        let rows: [[String]] = [
            ["No", "時間割コード", "科目名", "担当教員", "曜日・時限", "開講学期", "単位"],
            ["1", "10811", "統計学概論", "松尾 由美", "火2", "後期", "2"],
            ["2", "10823", "情報文化演習", "廣田 有里", "月4・5", "通年", "4"],
            ["3", "10900", "インターンシップ", "加藤 隆", "集中", "前期", "2"],
        ]
        let found = TimetableParser.parseList(rows, term: nil, source: "test")
        XCTAssertEqual(found.count, 3)
        let stats = found.first { $0.name == "統計学概論" }
        XCTAssertEqual(stats?.slots, [Slot(day: .tue, period: 2)])
        XCTAssertEqual(stats?.term, .second)
        XCTAssertEqual(stats?.code, "10811")
        let ex = found.first { $0.name == "情報文化演習" }
        XCTAssertEqual(ex?.slots, [Slot(day: .mon, period: 4), Slot(day: .mon, period: 5)])
        XCTAssertEqual(found.first { $0.name == "インターンシップ" }?.slots, [])
    }

    func testMakeCourses() {
        let c = CatalogCourse(name: "情報文化演習", slots: [Slot(day: .mon, period: 4), Slot(day: .mon, period: 5), Slot(day: .thu, period: 2)], term: .second)
        let courses = c.makeCourses(term: .first, color: .blue)
        XCTAssertEqual(courses.count, 2)
        XCTAssertEqual(courses[0].day, .mon)
        XCTAssertEqual(courses[0].period, 4)
        XCTAssertEqual(courses[0].length, 2)
        XCTAssertEqual(courses[1].day, .thu)
        XCTAssertEqual(courses[0].term, .second)
    }

    func testSchedule() {
        var d = AppData()
        d.termMode = .second
        d.courses = [
            Course(name: "A", day: .wed, period: 2, term: .second),
            Course(name: "B", day: .wed, period: 3, length: 2, term: .second),
            Course(name: "C", day: .wed, period: 1, term: .first),
        ]
        let s = Schedule(d)
        var comps = DateComponents()
        comps.year = 2026; comps.month = 10; comps.day = 14; comps.hour = 11; comps.minute = 0
        let now = JST.calendar.date(from: comps)!
        XCTAssertEqual(s.items(on: now).map(\.course.name), ["A", "B"])
        XCTAssertEqual(s.current(at: now)?.course.name, "A")
        XCTAssertEqual(s.next(after: now)?.course.name, "B")
        let b = s.items(on: now)[1]
        XCTAssertEqual(JST.hm(b.start), "13:10")
        XCTAssertEqual(JST.hm(b.end), "16:40")
    }
}
