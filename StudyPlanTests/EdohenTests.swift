import XCTest
@testable import StudyPlan

/// エドヘン（出席）のページの読み取り
final class EdohenTests: XCTestCase {

    func testClassify() {
        XCTAssertEqual(EdohenClient.classify("<p>エラー：講義ﾊﾟｽﾜｰﾄﾞが違います</p>", course: ""), .wrongCode)
        XCTAssertEqual(EdohenClient.classify("<p>既に出席登録されています</p>", course: "統計学入門"), .already(course: "統計学入門"))
        XCTAssertEqual(EdohenClient.classify("<p>エラー：受付時間外です</p>", course: ""), .failure("受付時間外です"))
        XCTAssertNil(EdohenClient.classify("<p>出席登録</p>", course: ""))
    }

    func testHiddenInputs() {
        let html = #"<input type="hidden" name="jyugyo_name" value="統計学入門"><input type="hidden" name="cd" value="">"#
        let inputs = EdohenClient.hiddenInputs(html)
        XCTAssertEqual(inputs.map(\.name), ["jyugyo_name", "cd"])
        XCTAssertEqual(inputs.first?.value, "統計学入門")
    }

    func testParseCourses() {
        let html = """
        <html><table border="1"><tr><td colspan="4"><font color="black">統計学入門</font></td>\
        <td><font>10/01<br>３限</font></td><td><font>10/08<br>３限</font></td><td><font>10/15<br>３限</font></td></tr>\
        <tr><td>田中 浩</td><td>1</td><td>1</td><td>1</td>\
        <td>13:11</td><td bgcolor="#FF9999">×</td><td bgcolor="#FFFF66">13:25</td></tr></table>\
        <table border="1"><tr><td colspan="4"><font color="black">観光文化論</font></td>\
        <td><font>05/10<br>２限</font></td></tr>\
        <tr><td bgcolor="#CCCCCC">松本 亮</td><td>0</td><td>0</td><td>0</td><td bgcolor="#CC9966">未利用</td></tr></table></html>
        """
        let list = EdohenClient.parseCourses(html)
        XCTAssertEqual(list.count, 2)

        let a = list[0]
        XCTAssertEqual(a.name, "統計学入門")
        XCTAssertEqual(a.teacher, "田中 浩")
        XCTAssertEqual([a.present, a.late, a.absent], [1, 1, 1])
        XCTAssertTrue(a.isLatter)
        XCTAssertFalse(a.isUnregistered)
        XCTAssertEqual(a.sessions.map(\.status), [.present, .absent, .late])
        XCTAssertEqual(a.sessions.first?.date, "10/01")

        let b = list[1]
        XCTAssertTrue(b.isUnregistered)
        XCTAssertFalse(b.isLatter)
        XCTAssertEqual(b.sessions.map(\.status), [.unused])
    }

    func testMatchTimetableCourse() {
        let list = AttendanceStore.sample()
        let stats = Course(name: "統計学入門", day: .tue, period: 2, term: .full)
        XCTAssertEqual(AttendanceStore.match(stats, in: list, currentIsLatter: true)?.teacher, "田中 浩")
        // 全角・空白の違いは同じ授業として扱う
        let web = Course(name: "Ｗｅｂ デザイン", day: .thu, period: 1)
        XCTAssertEqual(AttendanceStore.match(web, in: list, currentIsLatter: true)?.absent, 3)
        // 未履修の科目とは結びつけない
        let tour = Course(name: "観光文化論", day: .mon, period: 3)
        XCTAssertNil(AttendanceStore.match(tour, in: list, currentIsLatter: true))
        XCTAssertNil(AttendanceStore.match(Course(name: "存在しない授業", day: nil, period: nil), in: list, currentIsLatter: true))
    }
}
