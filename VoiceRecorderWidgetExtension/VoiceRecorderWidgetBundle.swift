import WidgetKit
import SwiftUI

@main
struct VoiceRecorderWidgetBundle: WidgetBundle {
    var body: some Widget {
        if #available(iOS 16.1, *) {
            VoiceRecorderLiveActivity()
        }
    }
}
