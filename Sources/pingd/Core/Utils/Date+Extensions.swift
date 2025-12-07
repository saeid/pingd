import Foundation

extension Date {
    func add(days: Int) -> Self {
        let calendar = Calendar.current
        return calendar.date(byAdding: .day, value: days, to: self)!
    }
}
