import SwiftUI
import WidgetKit

@main
struct TallyItWidgetBundle: WidgetBundle {
    var body: some Widget {
        LiveMatchWidget()
        StandingsWidget()
    }
}
