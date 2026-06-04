import SwiftUI

struct NotebookSkeletonGridView: View {
    var rowCount: Int = 12
    var columnCount: Int = 6

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(spacing: 2) {
                skeletonRow(isHeader: true)
                ForEach(0..<rowCount, id: \.self) { _ in
                    skeletonRow(isHeader: false)
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
        }
    }

    private func skeletonRow(isHeader: Bool) -> some View {
        HStack(spacing: 8) {
            RoundedRectangle(cornerRadius: 6)
                .fill(Color.primary.opacity(isHeader ? 0.10 : 0.06))
                .frame(width: 160, height: isHeader ? 20 : 40)

            ForEach(0..<columnCount, id: \.self) { _ in
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color.primary.opacity(isHeader ? 0.08 : 0.04))
                    .frame(width: 90, height: isHeader ? 20 : 40)
            }

            Spacer()
        }
        .redacted(reason: .placeholder)
    }
}
