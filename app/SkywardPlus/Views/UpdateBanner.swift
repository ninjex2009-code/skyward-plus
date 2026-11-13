#if os(iOS)
import SwiftUI

/// Where the iPhone app's updates come from: an AltStore / SideStore source.
enum PhoneUpdates {
    static let sourceURL = "https://raw.githubusercontent.com/ninjex2009-code/skyward-plus/main/altstore/source.json"

    /// Opens AltStore (or SideStore) at the Skyward Plus source, falling back to the release page.
    @MainActor
    static func open(_ update: UpdateInfo?, with openURL: OpenURLAction) {
        let encoded = sourceURL.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? sourceURL
        let candidates = [
            URL(string: "altstore://source?url=\(encoded)"),
            URL(string: "sidestore://source?url=\(encoded)"),
            update?.pageURL ?? URL(string: "https://github.com/ninjex2009-code/skyward-plus/releases/latest"),
        ].compactMap { $0 }
        func attempt(_ index: Int) {
            guard index < candidates.count else { return }
            openURL(candidates[index]) { accepted in if !accepted { attempt(index + 1) } }
        }
        attempt(0)
    }
}

/// A small banner at the top of Home when a newer version is out.
struct UpdateBanner: View {
    @Environment(AppModel.self) private var model
    @Environment(\.openURL) private var openURL
    @AppStorage("update.dismissedVersion") private var dismissed = ""

    var body: some View {
        if let update = model.availableUpdate, update.version != dismissed {
            HStack(spacing: 12) {
                Image(systemName: "arrow.down.app.fill")
                    .font(.title2)
                    .foregroundStyle(model.theme.color)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Version \(update.version) is out").font(.headline).lineLimit(1)
                    Text("Opens AltStore or SideStore").font(.subheadline).foregroundStyle(.secondary)
                        .lineLimit(1).minimumScaleFactor(0.8)
                }
                Spacer(minLength: 8)
                Button("Update") { PhoneUpdates.open(update, with: openURL) }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                Button {
                    withAnimation(.snappy) { dismissed = update.version }
                } label: {
                    Image(systemName: "xmark").font(.caption.weight(.bold)).foregroundStyle(.secondary)
                        .frame(width: 28, height: 28).contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Hide until the next version")
            }
            .padding(14)
            .surface(cornerRadius: 16)
            .transition(.opacity.combined(with: .move(edge: .top)))
        }
    }
}

/// Settings → About on iPhone: check for updates and add the AltStore source.
struct PhoneUpdateRows: View {
    @Environment(AppModel.self) private var model
    @Environment(\.openURL) private var openURL

    var body: some View {
        SettingRow(title: model.availableUpdate.map { "Version \($0.version) is available" } ?? "Updates") {
            if let update = model.availableUpdate {
                Button("Update") { PhoneUpdates.open(update, with: openURL) }.buttonStyle(.borderedProminent).controlSize(.small)
            } else {
                Button("Check Now") { Task { await model.checkForUpdates(manual: true) } }
            }
        }
        if let message = model.updateMessage, model.availableUpdate == nil {
            Text(message).font(.footnote).foregroundStyle(.secondary).padding(.horizontal, 4)
        }
        ActionRow(title: "Add the AltStore Source") { PhoneUpdates.open(nil, with: openURL) }
    }
}
#endif
