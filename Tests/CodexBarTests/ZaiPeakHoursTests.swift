import CodexBarCore
import Foundation
import Testing

struct ZaiPeakHoursTests {
    private static let eastern = TimeZone(identifier: "America/New_York")!

    private func date(
        year: Int = 2026,
        month: Int = 3,
        day: Int,
        hour: Int,
        minute: Int = 0,
        second: Int = 0) -> Date
    {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = Self.eastern
        return cal.date(from: DateComponents(
            year: year,
            month: month,
            day: day,
            hour: hour,
            minute: minute,
            second: second))!
    }

    @Test
    func `before peak on weekday`() {
        let status = ZaiPeakHours.status(at: self.date(day: 25, hour: 1))
        #expect(!status.isPeak)
        #expect(status.label == "Off-peak · peak in 1h")
    }

    @Test
    func `just before peak`() {
        let status = ZaiPeakHours.status(at: self.date(day: 25, hour: 1, minute: 45))
        #expect(!status.isPeak)
        #expect(status.label == "Off-peak · peak in 15m")
    }

    @Test
    func `peak start`() {
        let status = ZaiPeakHours.status(at: self.date(day: 25, hour: 2))
        #expect(status.isPeak)
        #expect(status.label == "Peak · ends in 4h")
    }

    @Test
    func `mid peak`() {
        let status = ZaiPeakHours.status(at: self.date(day: 25, hour: 4, minute: 30))
        #expect(status.isPeak)
        #expect(status.label == "Peak · ends in 1h 30m")
    }

    @Test
    func `peak end boundary`() {
        let status = ZaiPeakHours.status(at: self.date(day: 25, hour: 5, minute: 59))
        #expect(status.isPeak)
        #expect(status.label == "Peak · ends in 1m")
    }

    @Test
    func `after peak`() {
        let status = ZaiPeakHours.status(at: self.date(day: 25, hour: 6))
        #expect(!status.isPeak)
        #expect(status.label == "Off-peak · peak in 20h")
    }

    @Test
    func `late evening`() {
        let status = ZaiPeakHours.status(at: self.date(day: 25, hour: 23))
        #expect(!status.isPeak)
        #expect(status.label == "Off-peak · peak in 3h")
    }

    @Test
    func `saturday during peak`() {
        let status = ZaiPeakHours.status(at: self.date(day: 28, hour: 3))
        #expect(status.isPeak)
        #expect(status.label == "Peak · ends in 3h")
    }

    @Test
    func `sunday off-peak`() {
        let status = ZaiPeakHours.status(at: self.date(day: 29, hour: 12))
        #expect(!status.isPeak)
        #expect(status.label == "Off-peak · peak in 14h")
    }

    @Test
    func `midnight`() {
        let status = ZaiPeakHours.status(at: self.date(day: 25, hour: 0))
        #expect(!status.isPeak)
        #expect(status.label == "Off-peak · peak in 2h")
    }

    @Test
    func `peak with minute granularity`() {
        let status = ZaiPeakHours.status(at: self.date(day: 25, hour: 3, minute: 15))
        #expect(status.isPeak)
        #expect(status.label == "Peak · ends in 2h 45m")
    }

    @Test
    func `saturday midnight before peak`() {
        let status = ZaiPeakHours.status(at: self.date(day: 28, hour: 0))
        #expect(!status.isPeak)
        #expect(status.label == "Off-peak · peak in 2h")
    }

    @Test
    func `sunday early morning peak`() {
        let status = ZaiPeakHours.status(at: self.date(day: 29, hour: 5))
        #expect(status.isPeak)
        #expect(status.label == "Peak · ends in 1h")
    }
}
