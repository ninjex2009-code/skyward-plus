import SwiftUI

/// While a focus session runs: a slim pill with the task and the time left.
/// It finishes the session by itself when the time is up.
struct FocusPill: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        if let session = model.focus {
            TimelineView(.periodic(from: .now, by: 1)) { context in
                let left = max(0, session.end.timeIntervalSince(context.date))
                HStack(spacing: 10) {
                    Image(systemName: "timer")
                        .foregroundStyle(model.theme.color)
                    Text(session.title)
                        .font(.subheadline.weight(.medium))
                        .lineLimit(1)
                    Spacer(minLength: 8)
                    Text(Duration.seconds(left).formatted(.time(pattern: .minuteSecond)))
                        .font(.subheadline.monospacedDigit())
                        .foregroundStyle(.secondary)
                        .contentTransition(.numericText())
                    Button("Stop") { withAnimation(.snappy) { model.finishFocus() } }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .frame(maxWidth: 420)
                .surface(cornerRadius: 22, elevated: true)
                .onChange(of: left == 0) { _, done in
                    if done { withAnimation(.snappy) { model.finishFocus() } }
                }
                .accessibilityElement(children: .combine)
                .accessibilityLabel("Focusing on \(session.title), \(Int(left / 60)) minutes left")
            }
            .transition(.move(edge: .bottom).combined(with: .opacity))
        }
    }
}
