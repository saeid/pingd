import Foundation

enum DateHelper {
    static func makeDate(year: Int, month: Int, day: Int) -> Date {
        var components = DateComponents()
        components.day = day
        components.month = month
        components.year = year
        return Calendar.current.date(from: components)!
    }
}
