import SwiftUI

/// Saves the district sign-in so background sync can sign back in by itself.
struct RememberSignInSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var username = ""
    @State private var password = ""

    var body: some View {
        let district = model.active?.districtName.isEmpty == false ? Str.titleCase(model.active!.districtName) : "your district"
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Remember your sign-in").font(.title2.bold())
                Text("When Skyward signs you out, Skyward Plus signs you back in on \(district)'s own page using these. They're kept in this Mac's Keychain and sent only to your district.")
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Form {
                TextField("Username", text: $username)
                    .textContentType(.username)
                SecureField("Password", text: $password)
                    .textContentType(.password)
            }
            .formStyle(.grouped)
            .scrollDisabled(true)
            .frame(height: 110)
            HStack {
                if let profile = model.active, model.hasRememberedSignIn(profile) {
                    Button("Forget", role: .destructive) {
                        model.forgetSignIn()
                        dismiss()
                    }
                }
                Spacer()
                Button("Cancel", role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Remember") {
                    model.rememberSignIn(username: username.trimmingCharacters(in: .whitespaces), password: password)
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(username.trimmingCharacters(in: .whitespaces).isEmpty || password.isEmpty)
            }
        }
        .padding(24)
        .frame(width: 440)
        .onAppear {
            if let profile = model.active, let saved = Keychain.loadDistrict(address: profile.address) {
                username = saved.username
            }
        }
    }
}
