import SwiftUI

/// A plain view with no content closure.
public struct Badge: View {
    public init() {
    }

    public var body: some View {
        Text("Badge")
            .padding(8)
            .background(Color.yellow)
    }
}

/// A container view taking @ViewBuilder content.
public struct Card<Content: View>: View {
    let content: Content

    public init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    public var body: some View {
        VStack(alignment: .leading) {
            content
        }
        .padding()
        .border(Color.gray)
    }
}
