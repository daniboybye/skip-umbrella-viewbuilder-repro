import Inner
import SwiftUI

public struct DemoView: View {
    public init() {
    }

    public var body: some View {
        VStack {
            Text("Header")
            Badge()
            Card {
                Text("a")
                Text("b")
            }
        }
    }
}
