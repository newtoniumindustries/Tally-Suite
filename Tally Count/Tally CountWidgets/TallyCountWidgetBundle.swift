import SwiftUI
import WidgetKit

@main
struct TallyCountWidgetBundle: WidgetBundle {
    var body: some Widget {
        SingleTimerWidget()
        TimersOverviewWidget()
    }
}
