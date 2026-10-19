import XCTest
@testable import Momuri

/// 저장값 번역(StoredValues) 테스트. 테스트 언어(ko/ja)와 상관없이 통과해야 한다.
final class LocalizationTests: XCTestCase {
    private var japanese: Bundle {
        Bundle(path: Bundle.main.path(forResource: "ja", ofType: "lproj")!)!
    }

    /// 사용자가 직접 적은 이름이 화면 문장(Localizable)의 키와 같아도 번역되지 않는다
    func testUserTextIsNotTranslatedByScreenStrings() {
        XCTAssertEqual("완료".localizedValue, "완료")
        XCTAssertEqual("오늘".localizedValue, "오늘")
        XCTAssertEqual("내가 만든 운동".localizedValue, "내가 만든 운동")
    }

    /// 이름 칸에 보이는 번역된 추천 이름은 한국어 키로 되돌려 저장한다
    func testDisplayedRoutineNameRoundTrips() {
        for key in StoredValue.routineNames {
            XCTAssertEqual(StoredValue.key(forDisplayed: key.localizedValue), key)
        }
        XCTAssertEqual(StoredValue.key(forDisplayed: "내가 만든 루틴"), "내가 만든 루틴")
    }

    /// 저장값 목록은 모두 일본어 번역이 있다
    func testStoredValuesHaveJapanese() {
        let values = StoredValue.parts + StoredValue.routineNames + StoredValue.exercises.values.flatMap { $0 }
            + RoutineCategory.groupOrder + ["회", "문제", "분", "페이지"]
        for value in values {
            let ja = japanese.localizedString(forKey: value, value: nil, table: StoredValue.table)
            XCTAssertNotEqual(ja, value, "\(value) 의 일본어 번역이 없어요")
        }
    }

    /// 한국어로 저장된 추천 이름은 일본어 화면에서 번역해서 보인다
    func testJapaneseShowsTranslatedPresetName() {
        XCTAssertEqual(japanese.localizedString(forKey: "샴푸", value: nil, table: StoredValue.table), "シャンプー")
        XCTAssertEqual(japanese.localizedString(forKey: "완료", value: nil, table: StoredValue.table), "완료")
    }
}
