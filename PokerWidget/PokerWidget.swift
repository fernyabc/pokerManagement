import WidgetKit
import SwiftUI
import ActivityKit

@main
struct PokerWidgetBundle: WidgetBundle {
    var body: some Widget {
        PokerSuggestionLiveActivity()
    }
}

struct PokerSuggestionLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: PokerSuggestionAttributes.self) { context in
            // Lock screen / banner UI goes here
            HStack {
                VStack(alignment: .leading) {
                    Text("GTO Suggestion")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    HStack(alignment: .firstTextBaseline) {
                        Text(context.state.action.uppercased())
                            .font(.system(.title2, design: .rounded).bold())
                            .foregroundColor(context.state.action == "Raise" ? .red : .blue)
                        
                        if let size = context.state.raiseSize, context.state.action == "Raise" {
                            Text("to $\(String(format: "%.1f", size))")
                                .font(.headline)
                        }
                    }
                }
                Spacer()
                if let ev = context.state.ev {
                    VStack(alignment: .trailing) {
                        Text("EV")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                        Text(String(format: "%.2f", ev))
                            .font(.subheadline.bold())
                            .foregroundColor(ev > 0 ? .green : .red)
                    }
                }
            }
            .padding()
            .activityBackgroundTint(Color.black.opacity(0.8))
            
        } dynamicIsland: { context in
            DynamicIsland {
                // Expanded UI
                DynamicIslandExpandedRegion(.leading) {
                    Text("GTO")
                        .font(.headline)
                        .foregroundColor(.secondary)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    if let ev = context.state.ev {
                        Text(String(format: "EV: %.2f", ev))
                            .font(.subheadline)
                            .foregroundColor(ev > 0 ? .green : .red)
                    }
                }
                DynamicIslandExpandedRegion(.center) {
                    Text(context.state.action.uppercased())
                        .font(.system(.title, design: .rounded).bold())
                        .foregroundColor(context.state.action == "Raise" ? .red : .blue)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    if let size = context.state.raiseSize, context.state.action == "Raise" {
                        Text("Size: $\(String(format: "%.1f", size))")
                            .font(.headline)
                    }
                }
            } compactLeading: {
                Image(systemName: "suit.spade.fill")
                    .foregroundColor(.white)
            } compactTrailing: {
                Text(context.state.action.prefix(1))
                    .foregroundColor(context.state.action == "Raise" ? .red : .blue)
            } minimal: {
                Text(context.state.action.prefix(1))
                    .foregroundColor(context.state.action == "Raise" ? .red : .blue)
            }
            .widgetURL(URL(string: "pokerManagement://live-activity"))
            .keylineTint(Color.red)
        }
    }
}
