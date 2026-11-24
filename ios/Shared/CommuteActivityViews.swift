import SwiftUI

struct CommuteActivityCard: View {
    let state: CommuteActivity.ContentState
    let stationName: String
    var isStale = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Label(stationName, systemImage: "tram.fill").font(.caption.bold()).lineLimit(1).minimumScaleFactor(0.8)
                Spacer()
                Text(state.scheduled ? "Timetable" : "Prediction").font(.caption2).foregroundStyle(.secondary)
            }
            if isStale {
                Label("Open app to check this train", systemImage: "arrow.clockwise")
                    .font(.headline).foregroundStyle(.orange).lineLimit(1).minimumScaleFactor(0.8)
            } else if state.leaveAt <= Date() {
                Text("Leave now").font(.title2.bold())
            } else {
                HStack(alignment: .firstTextBaseline) {
                    Text(state.scheduled ? "Aim to leave in" : "Leave in").font(.headline)
                    Text(timerInterval: min(Date(), state.leaveAt)...max(Date(), state.leaveAt), countsDown: true)
                        .monospacedDigit().font(.title2.bold()).contentTransition(.numericText())
                }
            }
            Text(state.headsign).font(.caption.weight(.semibold)).lineLimit(1)
            HStack {
                Text("\(state.walkMinutes)m walk + \(state.bufferMinutes)m buffer")
                Spacer()
                Text("Departs \(state.departureAt.formatted(date: .omitted, time: .shortened))")
            }
            .font(.caption2)
            Text("Updated \(state.predictionAt.formatted(date: .omitted, time: .shortened)) · open app to refresh")
                .font(.system(size: 10)).foregroundStyle(.secondary).lineLimit(1).minimumScaleFactor(0.8)
        }
        .padding(.horizontal, 14).padding(.vertical, 10)
    }
}
