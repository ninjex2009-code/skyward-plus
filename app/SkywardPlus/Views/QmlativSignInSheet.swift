import SwiftUI
import WebKit

struct QmlativSignInSession: Identifiable {
    let id = UUID()
    let engine: QmlativEngine
    let address: String
    let districtName: String
}

struct QmlativSignInSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    let session: QmlativSignInSession

    @State private var duplicateSession = false
    @State private var finishing = false

    private var titleText: String {
        let name = session.districtName.trimmingCharacters(in: .whitespacesAndNewlines)
        return name.isEmpty ? "Sign In" : "Sign in to \(name)"
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(titleText)
                    .font(.headline)
                Spacer()
                Button("Cancel") {
                    session.engine.attachToHiddenHost()
                    model.cancelQmlativSignIn()
                    dismiss()
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(.bar)

            Divider()

            if duplicateSession {
                HStack(spacing: 8) {
                    Image(systemName: "info.circle")
                        .foregroundStyle(.secondary)
                    Text("Skyward signs you out everywhere else when you sign in here.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    Spacer()
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(Palette.inset)
                Divider()
            }

            HostedQmlativWebView(engine: session.engine)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .onDisappear {
            session.engine.attachToHiddenHost()
        }
        .task {
            while !Task.isCancelled && !finishing {
                if let st = await session.engine.state() {
                    if st.duplicateSession {
                        duplicateSession = true
                    }
                    if st.signedIn {
                        finishing = true
                        session.engine.attachToHiddenHost()
                        await model.finishQmlativSignIn()
                        dismiss()
                        break
                    }
                }
                try? await Task.sleep(nanoseconds: 700_000_000)
            }
        }
    }
}

#if os(macOS)
struct HostedQmlativWebView: NSViewRepresentable {
    let engine: QmlativEngine

    func makeNSView(context: Context) -> NSView {
        let container = NSView(frame: CGRect(x: 0, y: 0, width: 960, height: 680))
        let wv = engine.webView
        wv.removeFromSuperview()
        wv.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(wv)
        NSLayoutConstraint.activate([
            wv.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            wv.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            wv.topAnchor.constraint(equalTo: container.topAnchor),
            wv.bottomAnchor.constraint(equalTo: container.bottomAnchor),
        ])
        return container
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        let wv = engine.webView
        if wv.superview !== nsView {
            wv.removeFromSuperview()
            wv.translatesAutoresizingMaskIntoConstraints = false
            nsView.addSubview(wv)
            NSLayoutConstraint.activate([
                wv.leadingAnchor.constraint(equalTo: nsView.leadingAnchor),
                wv.trailingAnchor.constraint(equalTo: nsView.trailingAnchor),
                wv.topAnchor.constraint(equalTo: nsView.topAnchor),
                wv.bottomAnchor.constraint(equalTo: nsView.bottomAnchor),
            ])
        }
    }

    static func dismantleNSView(_ nsView: NSView, coordinator: ()) {
        for sub in nsView.subviews {
            sub.translatesAutoresizingMaskIntoConstraints = true
        }
    }
}
#else
struct HostedQmlativWebView: UIViewRepresentable {
    let engine: QmlativEngine

    func makeUIView(context: Context) -> UIView {
        let container = UIView(frame: CGRect(x: 0, y: 0, width: 390, height: 680))
        let wv = engine.webView
        wv.removeFromSuperview()
        wv.alpha = 1.0
        wv.isUserInteractionEnabled = true
        wv.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(wv)
        NSLayoutConstraint.activate([
            wv.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            wv.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            wv.topAnchor.constraint(equalTo: container.topAnchor),
            wv.bottomAnchor.constraint(equalTo: container.bottomAnchor),
        ])
        return container
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        let wv = engine.webView
        if wv.superview !== uiView {
            wv.removeFromSuperview()
            wv.alpha = 1.0
            wv.isUserInteractionEnabled = true
            wv.translatesAutoresizingMaskIntoConstraints = false
            uiView.addSubview(wv)
            NSLayoutConstraint.activate([
                wv.leadingAnchor.constraint(equalTo: uiView.leadingAnchor),
                wv.trailingAnchor.constraint(equalTo: uiView.trailingAnchor),
                wv.topAnchor.constraint(equalTo: uiView.topAnchor),
                wv.bottomAnchor.constraint(equalTo: uiView.bottomAnchor),
            ])
        }
    }

    static func dismantleUIView(_ uiView: UIView, coordinator: ()) {
        for sub in uiView.subviews {
            sub.translatesAutoresizingMaskIntoConstraints = true
        }
    }
}
#endif
