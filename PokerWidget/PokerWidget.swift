import WidgetKit
import SwiftUI
import ActivityKit

struct PokerSuggestionLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: PokerSuggestionAttributes.self) { context in
            // Lock Screen Live Activity
            lockScreenView(context: context)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Text(context.state.action)
                        .font(.headline)
                        .bold()
                }
                DynamicIslandExpandedRegion(.trailing) {
                    if let ev = context.state.ev {
                        Text("EV \(ev, specifier: "%.1f")")
                            .font(.caption)
                    }
                }
                DynamicIslandExpandedRegion(.bottom) {
                    if context.state.isSolving {
                        ProgressView()
                            .progressViewStyle(.circular)
                    } else {
                        weightsBar(state: context.state)
                    }
                }
            } compactLeading: {
                if context.state.isSolving {
                    ProgressView()
                } else {
                    Text(context.state.action)
                        .font(.caption)
                        .bold()
                }
            } compactTrailing: {
                if let r = context.state.raiseSize {
                    Text("$\(r, specifier: "%.0f")")
                        .font(.caption)
                } else if let ev = context.state.ev {
                    Text("\(ev, specifier: "%.1f")")
                        .font(.caption)
                }
            } minimal: {
                Text(String(context.state.action.prefix(1)))
                    .font(.caption)
                    .bold()
            }
        }
    }

    @ViewBuilder
    private func lockScreenView(context: ActivityViewContext<PokerSuggestionAttributes>) -> some View {
        VStack(spacing: 8) {
            HStack {
                Text(context.state.action)
                    .font(.headline)
                    .bold()
                if let raise = context.state.raiseSize {
                    Text("$\(raise, specifier: "%.0f")")
                        .font(.subheadline)
                }
                Spacer()
                if context.state.isSolving {
                    ProgressView()
                }
            }

            if !context.state.isSolving {
                weightsBar(state: context.state)
            }

            Text(context.state.reasoning)
                .font(.caption)
                .lineLimit(2)
        }
        .padding()
    }

    @ViewBuilder
    private func weightsBar(state: PokerSuggestionAttributes.ContentState) -> some View {
        if let f = state.foldWeight, let c = state.callWeight, let r = state.raiseWeight {
            GeometryReader { geo in
                HStack(spacing: 2) {
                    Rectangle().fill(.red.opacity(0.8))
                        .frame(width: geo.size.width * f)
                        .overlay(Text("F \(Int(f*100))%").font(.system(size: 9)).foregroundColor(.white))
                    Rectangle().fill(.blue.opacity(0.8))
                        .frame(width: geo.size.width * c)
                        .overlay(Text("C \(Int(c*100))%").font(.system(size: 9)).foregroundColor(.white))
                    Rectangle().fill(.green.opacity(0.8))
                        .frame(width: geo.size.width * r)
                        .overlay(Text("R \(Int(r*100))%").font(.system(size: 9)).foregroundColor(.white))
                }
                .clipShape(RoundedRectangle(cornerRadius: 4))
            }
            .frame(height: 20)
        }
    }
}
