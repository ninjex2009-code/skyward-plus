import SwiftUI
import UserNotifications

/// Whether alerts are allowed, with a way to fix it and a test button.
struct NotificationStatusGroup: View {
    @Environment(AppModel.self) private var model
    @Environment(\.openURL) private var openURL
    @State private var status: UNAuthorizationStatus?
    @State private var testResult: String?

    var body: some View {
        SettingsGroup(footer: testResult) {
            SettingRow(title: "Notifications", subtitle: subtitle) {
                if status == .denied {
                    Button("Open Settings") { openSystemSettings() }
                        .buttonStyle(.bordered)
                } else {
                    Text(statusText).foregroundStyle(status == .authorized || status == .provisional ? Palette.good : .secondary)
                }
            }
            ActionRow(title: "Send a Test Notification") {
                Task {
                    let allowed = await model.sendTestAlert()
                    status = await Notifier.authorizationStatus()
                    if allowed {
                        testResult = model.phoneRelayConfig != nil
                            ? "Sent here and to your phone. Nothing on the phone? Check the topic in the ntfy app."
                            : "Sent. If nothing appeared, check Focus and notification settings."
                    } else {
                        testResult = "Notifications are turned off for Skyward Plus."
                    }
                }
            }
        }
        .task { status = await Notifier.authorizationStatus() }
    }

    private var statusText: String {
        switch status {
        case .authorized, .provisional, .ephemeral: return "On"
        case .denied: return "Off"
        case .notDetermined: return "Not asked yet"
        default: return ""
        }
    }

    private var subtitle: String? {
        status == .denied ? "Turned off in System Settings. Nothing below can reach you." : nil
    }

    private func openSystemSettings() {
        #if os(macOS)
        let id = Bundle.main.bundleIdentifier ?? "com.skywardplus.app"
        if let url = URL(string: "x-apple.systempreferences:com.apple.Notifications-Settings.extension?id=" + id) { openURL(url) }
        #else
        if let url = URL(string: UIApplication.openNotificationSettingsURLString) { openURL(url) }
        #endif
    }
}

#if os(macOS)
/// Copies every alert from this Mac to the free ntfy app on a phone.
struct PhoneRelayGroup: View {
    @Environment(AppModel.self) private var model
    @State private var copied = false

    private var isOn: Bool { !model.settings.phoneRelayTopic.isEmpty }

    var body: some View {
        SettingsGroup(title: "Send to my phone", footer: footer) {
            ToggleRow(title: "Send alerts to my phone", isOn: Binding(
                get: { isOn },
                set: { on in
                    model.updateSettings { $0.phoneRelayTopic = on ? PhoneRelay.newTopic() : "" }
                    Notifier.relay = model.phoneRelayConfig
                }
            ))
            if isOn {
                SettingRow(title: "Topic", subtitle: model.settings.phoneRelayTopic) {
                    Button(copied ? "Copied" : "Copy") {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(model.settings.phoneRelayTopic, forType: .string)
                        copied = true
                    }
                    .buttonStyle(.bordered)
                }
                ToggleRow(title: "Include scores and averages", isOn: Binding(
                    get: { model.settings.phoneRelayScores },
                    set: { on in
                        model.updateSettings { $0.phoneRelayScores = on }
                        Notifier.relay = model.phoneRelayConfig
                    }
                ))
            }
        }
    }

    private var footer: String {
        if isOn {
            return "On your phone, install the free ntfy app, tap +, and subscribe to the topic above (server ntfy.sh). Then send a test notification. Alerts pass through ntfy.sh, and anyone who knows the topic could read them, so keep it to yourself."
        }
        return "This Mac checks Skyward every few minutes, so it can pass each alert on to your phone through the free ntfy app. Nothing is sent until you turn this on."
    }
}
#endif
