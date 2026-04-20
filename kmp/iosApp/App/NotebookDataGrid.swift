import SwiftUI

struct NotebookDataGrid<FixedTopAccessory: View, ScrollTopAccessory: View, FixedHeader: View, ScrollHeader: View, FixedRows: View, ScrollRows: View>: View {
    let fixedColumnWidth: CGFloat
    let fixedTopAccessory: FixedTopAccessory
    let scrollTopAccessory: ScrollTopAccessory
    let fixedHeader: FixedHeader
    let scrollHeader: ScrollHeader
    let fixedRows: FixedRows
    let scrollRows: ScrollRows

    init(
        fixedColumnWidth: CGFloat,
        @ViewBuilder fixedTopAccessory: () -> FixedTopAccessory,
        @ViewBuilder scrollTopAccessory: () -> ScrollTopAccessory,
        @ViewBuilder fixedHeader: () -> FixedHeader,
        @ViewBuilder scrollHeader: () -> ScrollHeader,
        @ViewBuilder fixedRows: () -> FixedRows,
        @ViewBuilder scrollRows: () -> ScrollRows
    ) {
        self.fixedColumnWidth = fixedColumnWidth
        self.fixedTopAccessory = fixedTopAccessory()
        self.scrollTopAccessory = scrollTopAccessory()
        self.fixedHeader = fixedHeader()
        self.scrollHeader = scrollHeader()
        self.fixedRows = fixedRows()
        self.scrollRows = scrollRows()
    }

    var body: some View {
        ScrollView(.vertical, showsIndicators: true) {
            HStack(alignment: .top, spacing: 0) {
                VStack(alignment: .leading, spacing: 0) {
                    fixedTopAccessory
                    fixedHeader
                    fixedRows
                }
                .frame(width: fixedColumnWidth, alignment: .topLeading)
                .background(appSecondarySystemBackgroundColor().opacity(0.94))
                .shadow(color: Color.black.opacity(0.08), radius: 4, x: 2, y: 0)
                .zIndex(1)

                Divider()

                ScrollView(.horizontal, showsIndicators: true) {
                    VStack(alignment: .leading, spacing: 0) {
                        scrollTopAccessory
                        scrollHeader
                        scrollRows
                    }
                }
            }
        }
    }
}
