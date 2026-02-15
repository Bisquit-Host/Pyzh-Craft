import SwiftUI

/// Universal Sheet view component
/// Divided into three parts: header, body and bottom, adaptive content size
struct CommonSheetView<Header: View, BodyContent: View, Footer: View>: View {

    // MARK: - Properties
    let header: Header
    let bodyContent: BodyContent
    let footer: Footer

    // MARK: - Initialization
    init(
        @ViewBuilder header: () -> Header,
        @ViewBuilder body: () -> BodyContent,
        @ViewBuilder footer: () -> Footer
    ) {
        self.header = header()
        self.bodyContent = body()
        self.footer = footer()
    }

    // MARK: - Body
    var body: some View {
        VStack(spacing: 0) {
            // head area
            header
                .padding(.horizontal)
                .padding()
            Divider()

            // main area
            bodyContent
                .padding(.horizontal)
                .padding()

            // bottom area
            Divider()
            footer
                .padding(.horizontal)
                .padding()
        }
    }
}

// MARK: - Convenience Initializers
extension CommonSheetView where Header == EmptyView, Footer == EmptyView {
    /// Initialization method with only body content
    init(
        @ViewBuilder body: () -> BodyContent
    ) {
        self.header = EmptyView()
        self.bodyContent = body()
        self.footer = EmptyView()
    }
}

extension CommonSheetView where Footer == EmptyView {
    /// Initialization methods with head and body
    init(
        @ViewBuilder header: () -> Header,
        @ViewBuilder body: () -> BodyContent
    ) {
        self.header = header()
        self.bodyContent = body()
        self.footer = EmptyView()
    }
}

extension CommonSheetView where Header == EmptyView {
    /// There are initialization methods for body and bottom
    init(
        @ViewBuilder body: () -> BodyContent,
        @ViewBuilder footer: () -> Footer
    ) {
        self.header = EmptyView()
        self.bodyContent = body()
        self.footer = footer()
    }
}
