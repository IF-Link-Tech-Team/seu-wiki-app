import SwiftUI

/// 分区标题 + 右侧「查看全部」。
struct HomeSectionHeader<Destination: View>: View {
    let title: String
    let destination: Destination

    init(title: String, destination: Destination) {
        self.title = title
        self.destination = destination
    }

    var body: some View {
        HStack {
            Text(title)
                .font(.title3.weight(.bold))
            Spacer()
            NavigationLink {
                destination
            } label: {
                Text("查看全部")
                    .font(.subheadline)
            }
        }
        .padding(.horizontal, 4)
    }
}
