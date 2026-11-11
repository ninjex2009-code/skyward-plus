import SwiftUI

/// Finding the district, signing in, and the security-code step.
/// Used on first launch, to add another student, and to sign an existing one in again.
struct SignInView: View {
    private enum Step { case district, credentials, code }

    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    var reauth: Profile?
    var isFirstRun = false

    @State private var step: Step = .district
    @State private var finder = DistrictSearch()
    @State private var states: [DistrictState] = []
    @State private var stateID = UserDefaults.standard.string(forKey: "signin.stateID") ?? ""
    @State private var query = ""
    @State private var results: [DistrictResult] = []
    @State private var searched = false
    @State private var searching = false
    @State private var searchError: String?
    @State private var typingAddress = false
    @State private var typedAddress = ""

    @State private var address = ""
    @State private var districtName = ""
    @State private var username = ""
    @State private var password = ""
    @State private var code = ""
    @State private var trustDevice = true
    @State private var hideTrust = false
    @State private var busy = false
    @State private var error: String?
    @State private var showingWebSSO = false

    private var tint: Color { reauth?.theme.color ?? model.theme.color }

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                header
                Group {
                    switch step {
                    case .district: districtStep
                    case .credentials: credentialsStep
                    case .code: codeStep
                    }
                }
                .frame(maxWidth: 460)
                if reauth == nil, step != .code {
                    demoButton
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 20)
            .padding(.vertical, 28)
        }
        .background(Palette.page)
        .navigationTitle(reauth == nil ? (isFirstRun ? "" : "Add Student") : "Sign In Again")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .toolbar {
            if !isFirstRun {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
        .sheet(isPresented: $showingWebSSO) {
            NavigationStack {
                WebSignInSheet(address: address, districtName: districtName)
            }
            #if os(macOS)
            .frame(minWidth: 640, minHeight: 560)
            #endif
        }
        .task { await prepare() }
    }

    // MARK: Pieces

    private var header: some View {
        VStack(spacing: 10) {
            Image(systemName: "graduationcap.fill")
                .font(.system(size: 34))
                .foregroundStyle(.white)
                .frame(width: 76, height: 76)
                .background(ThemeColor.sky.gradient, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            Text("Skyward Plus").font(.largeTitle.weight(.bold))
            Text(reauth == nil ? "Your Skyward grades, made clear." : "Sign in again to keep \(reauth?.firstName ?? "this student")'s grades up to date.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(.top, isFirstRun ? 24 : 0)
    }

    private var districtStep: some View {
        Card {
            Text("Find your district").font(.headline)
            if typingAddress {
                Text("Paste the address of your district's Skyward Family Access login page.")
                    .font(.footnote).foregroundStyle(.secondary)
                TextField("https://skyward.iscorp.com/…/seplog01.w", text: $typedAddress)
                    .textFieldStyle(.roundedBorder)
                    .autocorrectionDisabled()
                    #if os(iOS)
                    .textInputAutocapitalization(.never)
                    .keyboardType(.URL)
                    #endif
                    .onSubmit { useTypedAddress() }
                if let error { errorText(error) }
                HStack {
                    Button("Search by name instead") { typingAddress = false; error = nil }
                        .buttonStyle(.borderless)
                    Spacer()
                    Button("Continue") { useTypedAddress() }
                        .buttonStyle(.borderedProminent)
                        .disabled(typedAddress.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            } else {
                Picker("State", selection: $stateID) {
                    Text(states.isEmpty ? "Loading states…" : "Choose a state").tag("")
                    ForEach(states) { state in Text(state.name).tag(state.id) }
                }
                .disabled(states.isEmpty)
                HStack {
                    TextField("District name", text: $query)
                        .textFieldStyle(.roundedBorder)
                        .autocorrectionDisabled()
                        .onSubmit { Task { await search() } }
                    Button {
                        Task { await search() }
                    } label: {
                        if searching { ProgressView().controlSize(.small) } else { Text("Search") }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(stateID.isEmpty || query.trimmingCharacters(in: .whitespaces).count < 3 || searching)
                }
                if let searchError { errorText(searchError) }
                if searched, results.isEmpty, searchError == nil, !searching {
                    Text("No districts matched. Try fewer letters, or paste your login address instead.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
                if !results.isEmpty {
                    VStack(spacing: 0) {
                        ForEach(Array(results.enumerated()), id: \.element.id) { index, result in
                            districtRow(result).rowDivider(index < results.count - 1)
                        }
                    }
                    .background(Palette.inset, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
                Button("Enter the address myself") { typingAddress = true; error = nil }
                    .buttonStyle(.borderless)
                    .font(.footnote)
            }
        }
    }

    private func districtRow(_ result: DistrictResult) -> some View {
        Button {
            choose(address: result.url, name: Str.titleCase(result.name))
        } label: {
            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(Str.titleCase(result.name)).font(.body.weight(.medium)).foregroundStyle(.primary)
                    Text(result.label)
                        .font(.caption).foregroundStyle(.secondary)
                }
                Spacer(minLength: 8)
                Image(systemName: "chevron.right").font(.caption).foregroundStyle(.secondary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var credentialsStep: some View {
        let isQml = SkywardEndpoint.looksLikeQmlativ(address)
        let displayDistrict = districtName.isEmpty ? "your district" : districtName
        return Card {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(districtName.isEmpty ? "Your district" : districtName).font(.headline)
                    Text(host(of: address)).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
                Spacer()
                if reauth == nil {
                    Button("Change") { step = .district; error = nil }.buttonStyle(.borderless)
                }
            }
            if isQml {
                if let error { errorText(error) }
                Button {
                    model.beginQmlativSignIn(address: address, districtName: districtName)
                } label: {
                    Text("Sign in with \(displayDistrict)")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                Text("You sign in on your district's own page. Skyward Plus never sees your password.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                TextField("Skyward username", text: $username)
                    .textFieldStyle(.roundedBorder)
                    .textContentType(.username)
                    .autocorrectionDisabled()
                    #if os(iOS)
                    .textInputAutocapitalization(.never)
                    #endif
                    .disabled(reauth != nil)
                SecureField("Password", text: $password)
                    .textFieldStyle(.roundedBorder)
                    .textContentType(.password)
                    .onSubmit { Task { await signIn() } }
                if let error { errorText(error) }
                Button {
                    Task { await signIn() }
                } label: {
                    HStack {
                        if busy { ProgressView().controlSize(.small) }
                        Text(busy ? "Signing in…" : "Sign In")
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(busy || username.trimmingCharacters(in: .whitespaces).isEmpty || password.isEmpty)
                Button {
                    showingWebSSO = true
                } label: {
                    Label("Sign in with Browser (Google / Microsoft SSO)", systemImage: "globe")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .disabled(busy || address.isEmpty)
                Label("Your password is kept in this device's Keychain and sent only to your district's Skyward server.", systemImage: "lock.shield")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var codeStep: some View {
        Card {
            Text("Enter your security code").font(.headline)
            Text("Skyward sent a code to the e-mail address or phone on your account.")
                .font(.footnote).foregroundStyle(.secondary)
            TextField("Security code", text: $code)
                .textFieldStyle(.roundedBorder)
                .textContentType(.oneTimeCode)
                .autocorrectionDisabled()
                #if os(iOS)
                .keyboardType(.numberPad)
                #endif
                .onSubmit { Task { await signIn() } }
            if !hideTrust {
                Toggle("Trust this device", isOn: $trustDevice)
                Text("Skyward will not ask for a code here again.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            if let error { errorText(error) }
            HStack {
                Button("Back") { step = .credentials; code = ""; error = nil }.buttonStyle(.bordered)
                Spacer()
                Button {
                    Task { await signIn() }
                } label: {
                    HStack {
                        if busy { ProgressView().controlSize(.small) }
                        Text(busy ? "Checking…" : "Verify")
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(busy || code.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
    }

    private var demoButton: some View {
        VStack(spacing: 6) {
            Button {
                Task {
                    busy = true
                    await model.addDemo()
                    busy = false
                    if !isFirstRun { dismiss() }
                }
            } label: {
                Text("Try it with a sample student")
            }
            .buttonStyle(.bordered)
            .disabled(busy)
            Text("The sample runs entirely on this device.")
                .font(.caption).foregroundStyle(.secondary)
        }
        .padding(.top, 4)
    }

    private func errorText(_ message: String) -> some View {
        Label(message, systemImage: "exclamationmark.circle.fill")
            .font(.footnote)
            .foregroundStyle(Palette.bad)
            .fixedSize(horizontal: false, vertical: true)
    }

    private func host(of address: String) -> String {
        URLComponents(string: address)?.host ?? address
    }

    // MARK: Actions

    private func prepare() async {
        if let reauth {
            address = reauth.address
            districtName = reauth.districtName
            username = reauth.username
            step = .credentials
            return
        }
        guard states.isEmpty else { return }
        do {
            states = try await finder.states()
            if !states.contains(where: { $0.id == stateID }) { stateID = "" }
        } catch {
            searchError = "The district finder could not be reached. You can paste your login address instead."
            typingAddress = true
        }
    }

    private func search() async {
        let text = query.trimmingCharacters(in: .whitespaces)
        guard !stateID.isEmpty, text.count >= 3, !searching else { return }
        searching = true
        searchError = nil
        defer { searching = false }
        UserDefaults.standard.set(stateID, forKey: "signin.stateID")
        do {
            results = try await finder.search(stateID: stateID, query: text)
            searched = true
        } catch {
            results = []
            searchError = error.localizedDescription
        }
    }

    private func useTypedAddress() {
        let text = typedAddress.trimmingCharacters(in: .whitespaces)
        guard SkywardEndpoint.parse(text) != nil else {
            error = "That does not look like a web address."
            return
        }
        choose(address: text, name: "")
    }

    private func choose(address: String, name: String) {
        self.address = address
        districtName = name
        error = nil
        step = .credentials
    }

    private func signIn() async {
        guard !busy else { return }
        busy = true
        error = nil
        defer { busy = false }
        do {
            try await model.signIn(
                address: address, districtName: districtName, username: username, password: password,
                securityCode: step == .code ? code : nil, trustDevice: trustDevice && !hideTrust
            )
            password = ""
            code = ""
            if !isFirstRun { dismiss() }
        } catch let failure as SkywardError {
            switch failure {
            case .mfaRequired(let hide):
                hideTrust = hide
                step = .code
            case .mfaInvalid:
                error = failure.localizedDescription
                code = ""
            default:
                error = failure.localizedDescription
                if step == .code { step = .credentials }
            }
        } catch {
            self.error = error.localizedDescription
        }
    }
}
