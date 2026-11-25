import SwiftUI
import SwiftData
import TallyCore

@main
struct Tally_CanastaApp: App {
    private let containerResult: TallyContainerResult

    init() {
        self.containerResult = TallyDataConfig.makeContainer(for: [
            CanastaGame.self,
            Round.self,
            RuleSet.self,
            TallyPlayer.self
        ])
    }

    var body: some Scene {
        WindowGroup {
            if let container = containerResult.container {
                VStack(spacing: 0) {
                    if containerResult.isUsingFallbackStore,
                       let warning = containerResult.startupErrorDescription {
                        HStack(spacing: 8) {
                            Image(systemName: "exclamationmark.triangle.fill")
                            Text(warning)
                                .font(.caption.bold())
                        }
                        .foregroundStyle(Color.white)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.orange)
                    }

                    ContentView()
                }
                .modelContainer(container)
            } else {
                ContentUnavailableView(
                    "Storage Unavailable",
                    systemImage: "externaldrive.badge.exclamationmark",
                    description: Text(
                        containerResult.startupErrorDescription
                            ?? "Please restart Tally: Canasta to try again."
                    )
                )
            }
        }
    }
}
