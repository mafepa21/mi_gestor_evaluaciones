import Foundation

struct ScheduleTimelineBlockLayout: Hashable {
    let matchID: UUID
    let x: Double
    let width: Double
}

struct ScheduleTimelineLayoutModel {
    let hourWidth: Double
    let markerDates: [Date]
    let markerSpacing: Double
    let timelineWidth: Double
    let blocks: [UUID: ScheduleTimelineBlockLayout]

    func block(for slot: ScheduledMatchSlot) -> ScheduleTimelineBlockLayout? {
        blocks[slot.id]
    }

    func xPosition(for date: Date) -> Double {
        guard let firstDate = markerDates.first else { return 0 }
        guard markerDates.count > 1 else { return 0 }

        if date <= firstDate { return 0 }

        for index in 1..<markerDates.count {
            let upperDate = markerDates[index]
            guard date <= upperDate else { continue }

            let lowerDate = markerDates[index - 1]
            let interval = upperDate.timeIntervalSince(lowerDate)
            let fraction = interval > 0
                ? date.timeIntervalSince(lowerDate) / interval
                : 0
            return (Double(index - 1) + min(max(fraction, 0), 1)) * markerSpacing
        }

        let lastIndex = markerDates.count - 1
        let lastInterval = markerDates[lastIndex].timeIntervalSince(markerDates[lastIndex - 1])
        let extra = lastInterval > 0
            ? date.timeIntervalSince(markerDates[lastIndex]) / lastInterval
            : 0
        return (Double(lastIndex) + max(extra, 0)) * markerSpacing
    }
}

enum ScheduleTimelineLayout {
    static let minimumGap = 4.0

    static func make(
        slots: [ScheduledMatchSlot],
        startDate: Date,
        zoomHourWidth: Double,
        markerMinutes: Int,
        readableColumnWidth: Double? = nil
    ) -> ScheduleTimelineLayoutModel {
        let hourWidth = max(1, zoomHourWidth)
        let intervalMinutes = max(markerMinutes, 1)
        let sortedSlots = slots.sorted {
            if $0.startDate != $1.startDate {
                return $0.startDate < $1.startDate
            }
            return $0.venueNumber < $1.venueNumber
        }

        let markerSpacing: Double
        let markerDates: [Date]

        if let readableColumnWidth {
            markerSpacing = max(minimumGap + 1, readableColumnWidth + minimumGap)
            var seenDates = Set<Date>()
            markerDates = sortedSlots.reduce(into: [Date]()) { dates, slot in
                guard seenDates.insert(slot.startDate).inserted else { return }
                dates.append(slot.startDate)
            }
        } else {
            markerSpacing = hourWidth * Double(intervalMinutes) / 60
            let latestEndDate = sortedSlots.map(\.endDate).max()
                ?? startDate.addingTimeInterval(TimeInterval(intervalMinutes * 60))
            let markerCount = max(
                1,
                Int(ceil(latestEndDate.timeIntervalSince(startDate) / TimeInterval(intervalMinutes * 60)))
            )
            markerDates = (0...markerCount).map { index in
                startDate.addingTimeInterval(TimeInterval(index * intervalMinutes * 60))
            }
        }

        var blocks: [UUID: ScheduleTimelineBlockLayout] = [:]
        var nextAvailableXByVenue: [Int: Double] = [:]

        for slot in sortedSlots {
            let naturalX = max(0, slot.startDate.timeIntervalSince(startDate) / 3_600 * hourWidth)
            let naturalWidth = max(
                minimumGap,
                slot.endDate.timeIntervalSince(slot.startDate) / 3_600 * hourWidth
            )
            let isReadableColumnLayout = readableColumnWidth != nil
            let visualWidth = max(naturalWidth, readableColumnWidth ?? 0)
            // In a valid schedule this is exactly naturalX. The guard only protects
            // against malformed data with two matches on one venue at the same time.
            let x: Double

            if isReadableColumnLayout,
               let columnIndex = markerDates.firstIndex(of: slot.startDate) {
                x = Double(columnIndex) * markerSpacing
            } else {
                x = max(naturalX, nextAvailableXByVenue[slot.venueNumber] ?? 0)
            }

            blocks[slot.id] = ScheduleTimelineBlockLayout(
                matchID: slot.id,
                x: x,
                width: visualWidth
            )
            nextAvailableXByVenue[slot.venueNumber] = max(
                nextAvailableXByVenue[slot.venueNumber] ?? 0,
                x + visualWidth + minimumGap
            )
        }

        let lastBlockEdge = blocks.values.map { $0.x + $0.width }.max() ?? 0
        let lastMarkerEdge = Double(max(markerDates.count - 1, 0)) * markerSpacing

        return ScheduleTimelineLayoutModel(
            hourWidth: hourWidth,
            markerDates: markerDates,
            markerSpacing: markerSpacing,
            timelineWidth: max(280, max(lastBlockEdge + markerSpacing * 0.25, lastMarkerEdge)),
            blocks: blocks
        )
    }
}
