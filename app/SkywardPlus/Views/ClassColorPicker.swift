import SwiftUI

/// A dot in the class's color; tapping it opens a palette to pick another.
struct ClassColorButton: View {
    @Environment(AppModel.self) private var model
    let courseID: String
    @State private var picking = false

    var body: some View {
        Button {
            picking = true
        } label: {
            Label {
                Text("Class Color")
            } icon: {
                Circle()
                    .fill(model.classColor(courseID))
                    .frame(width: 16, height: 16)
                    .overlay(Circle().strokeBorder(.white.opacity(0.35), lineWidth: 1))
            }
            .labelStyle(.iconOnly)
        }
        .help("Class color")
        .accessibilityLabel("Class color, \(model.classColorChoice(courseID).title)")
        .popover(isPresented: $picking, arrowEdge: .bottom) {
            ClassColorPalette(courseID: courseID) { picking = false }
                .padding(16)
                .presentationCompactAdaptation(.popover)
        }
    }
}

/// Twelve swatches and "Automatic".
struct ClassColorPalette: View {
    @Environment(AppModel.self) private var model
    let courseID: String
    var done: () -> Void = {}

    var body: some View {
        let current = model.classColorChoice(courseID)
        VStack(alignment: .leading, spacing: 12) {
            Text("Class color").font(.headline)
            LazyVGrid(columns: Array(repeating: GridItem(.fixed(34), spacing: 10), count: 6), spacing: 10) {
                ForEach(ClassColor.allCases) { color in
                    Button {
                        withAnimation(.snappy) { model.setClassColor(color, for: courseID) }
                        done()
                    } label: {
                        Circle()
                            .fill(Color(hex: color.hex))
                            .frame(width: 30, height: 30)
                            .overlay {
                                if color == current {
                                    Image(systemName: "checkmark").font(.caption.weight(.bold)).foregroundStyle(.white)
                                }
                            }
                            .overlay(Circle().strokeBorder(.primary.opacity(color == current ? 0.6 : 0), lineWidth: 2).padding(-3))
                            .contentShape(Circle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(color.title)
                    .accessibilityAddTraits(color == current ? .isSelected : [])
                }
            }
            if model.isClassColorChosen(courseID) {
                Button("Back to Automatic") {
                    withAnimation(.snappy) { model.setClassColor(nil, for: courseID) }
                    done()
                }
                .buttonStyle(.borderless)
            }
        }
        .frame(width: 6 * 34 + 5 * 10)
    }
}

/// The thin color bar that leads a class row or tile.
/// A class's badge: a little tile in the class's color with an icon for its subject.
struct ClassBadge: View {
    @Environment(AppModel.self) private var model
    let courseID: String
    var size: CGFloat = 30

    var body: some View {
        let color = model.classColor(courseID)
        let name = model.course(courseID)?.name ?? ""
        RoundedRectangle(cornerRadius: size * 0.3, style: .continuous)
            .fill(color.opacity(0.18))
            .overlay {
                Image(systemName: ClassSubject.symbol(for: name))
                    .font(.system(size: size * 0.46, weight: .semibold))
                    .foregroundStyle(color)
            }
            .frame(width: size, height: size)
            .accessibilityHidden(true)
    }
}


