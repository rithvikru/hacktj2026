import SwiftUI

struct QueryHistoryRow: View {
    let entry: QueryHistoryEntry

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "text.magnifyingglass")
                .font(.system(size: 14))
                .foregroundStyle(.dimLabel)
                .frame(width: 28, height: 28)
                .background(.glassWhite, in: Circle())

            VStack(alignment: .leading, spacing: 2) {
                Text(entry.query)
                    .font(SpatialFont.subheadline)
                    .foregroundStyle(.white)
                    .lineLimit(1)

                Text(entry.resultSummary)
                    .font(SpatialFont.caption)
                    .foregroundStyle(.dimLabel)
                    .lineLimit(1)
            }

            Spacer()

            Text(entry.timestamp.formatted(date: .omitted, time: .shortened))
                .font(SpatialFont.caption)
                .foregroundStyle(.dimLabel)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
    }
}
