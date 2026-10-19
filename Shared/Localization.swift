import Foundation

/// 한국어로 저장·비교하는 값(헬스 부위, 단위, 추천 이름 등).
/// 화면에는 localizedValue 로 번역해서 보여 주고, 번역은 StoredValues.xcstrings 에 직접 적는다.
enum StoredValue {
    static let table = "StoredValues"

    /// 헬스 부위. 고른 순서가 다음 추천 순서.
    static let parts = ["가슴", "등", "하체", "어깨", "팔", "복근", "유산소"]
    /// 헬스 루틴을 새로 만들 때 기본으로 고르는 부위
    static let defaultParts = ["가슴", "등", "하체", "어깨"]

    /// 부위별 종목 추천
    static let exercises: [String: [String]] = [
        "가슴": ["벤치프레스", "인클라인 덤벨프레스", "체스트 플라이", "딥스", "푸시업"],
        "등": ["랫풀다운", "바벨 로우", "시티드 로우", "데드리프트", "풀업"],
        "하체": ["스쿼트", "레그프레스", "런지", "레그 컬", "레그 익스텐션"],
        "어깨": ["오버헤드 프레스", "사이드 레터럴 레이즈", "리어 델트 플라이", "업라이트 로우"],
        "팔": ["바벨 컬", "해머 컬", "트라이셉스 푸시다운", "오버헤드 익스텐션"],
        "복근": ["크런치", "플랭크", "레그 레이즈", "행잉 레그 레이즈"],
    ]

    /// 분류 기본 이름·반려견 추천처럼 루틴 이름으로 저장되는 값
    static let routineNames = [
        "헬스", "러닝", "식단", "폰 사용", "약속",
        "샴푸", "발톱 깎기", "귀 청소", "심장사상충 약", "구충제", "미용", "종합 백신",
    ]

    /// 화면에 보이는 이름을 저장할 값으로 되돌린다. 번역된 추천 이름이면 한국어 키로, 아니면 그대로.
    static func key(forDisplayed text: String) -> String {
        routineNames.first { $0.localizedValue == text } ?? text
    }
}

extension String {
    /// 저장값을 지금 화면 언어로 보여 준다.
    /// StoredValues 표에만 있는 값을 번역하므로, 사용자가 직접 적은 값은 다른 문장과 겹쳐도 그대로 남는다.
    var localizedValue: String {
        Bundle.main.localizedString(forKey: self, value: self, table: StoredValue.table)
    }
}

extension Locale {
    /// 앱이 실제로 쓰는 언어(한국어·일본어)의 로케일. 기기 지역과 상관없이 날짜 표기를 화면 언어에 맞춘다.
    /// 앱별 언어를 바꾸면 앱이 다시 시작되므로 한 번만 정한다.
    static let app: Locale =
        Bundle.main.preferredLocalizations.first == "ja" ? Locale(identifier: "ja_JP") : Locale(identifier: "ko_KR")
}
