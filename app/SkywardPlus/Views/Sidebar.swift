import SwiftUI

/// The Mac and iPad sidebar: a floating glass panel over the living background,
/// with the student up top, sections whose highlight glides between them,
/// counts for what needs you, and sync status at the foot.
/// It folds down to a slim rail of icons.
struct AppSidebar: View {
    @Environment(AppModel.self) private var model
    @Binding var compact: Bool
    @Namespace private var highlight

    var body: some View {
        VStack(spacing: 0) {
            header
                .padding(.bottom, 14)
            ScrollView {
                VStack(alignment: .leading, spacing: compact ? 10 : 18) {
                    group("Overview", AppSection.tabs)
                    group("School", AppSection.school)
                    group("App", AppSection.app)
                }
                .padding(.vertical, 2)
            }
            .scrollIndicators(.never)
            Spacer(minLength: 10)
            SidebarStatusCard(compact: compact)
        }
        .padding(compact ? 10 : 12)
        .frame(maxHeight: .infinity, alignment: .top)
        .background { SidebarPanel() }
        .animation(.spring(response: 0.38, dampingFraction: 0.86), value: compact)
    }

    // MARK: Header

    @ViewBuilder private var header: some View {
        VStack(alignment: compact ? .center : .leading, spacing: 12) {
            HStack(spacing: 8) {
                if !compact {
                    Text("Skyward Plus")
                        .font(.display(14, weight: .bold, relativeTo: .headline))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                    Spacer(minLength: 4)
                }
                Button {
                    compact.toggle()
                } label: {
                    Image(systemName: compact ? "sidebar.right" : "sidebar.left")
                        .font(.callout.weight(.medium))
                        .foregroundStyle(.secondary)
                        .frame(width: 28, height: 28)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help(compact ? "Show the full sidebar" : "Fold the sidebar")
                .accessibilityLabel(compact ? "Show the full sidebar" : "Fold the sidebar")
            }
            .frame(maxWidth: .infinity, alignment: compact ? .center : .leading)
            SidebarProfileCard(compact: compact)
        }
    }

    // MARK: Sections

    @ViewBuilder private func group(_ title: String, _ sections: [AppSection]) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            if compact {
                Capsule().fill(.primary.opacity(0.1)).frame(width: 22, height: 2)
                    .frame(maxWidth: .infinity)
                    .padding(.bottom, 4)
            } else {
                Text(title.uppercased())
                    .font(.caption2.weight(.semibold))
                    .tracking(1.1)
                    .foregroundStyle(.tertiary)
                    .padding(.leading, 10)
                    .padding(.bottom, 3)
            }
            ForEach(sections) { section in
                SidebarRow(section: section, compact: compact, badge: badge(for: section), highlight: highlight)
            }
        }
    }

    private func badge(for section: AppSection) -> Int {
        switch section {
        case .home: return model.unseenChangeCount
        case .grades: return model.missingAssignments.count
        case .planner:
            let end = Calendar.current.date(byAdding: .day, value: 2, to: Calendar.current.startOfDay(for: model.now())) ?? model.now()
            return model.dueItems.filter { !$0.done && $0.due < end }.count
        default: return 0
        }
    }
}

/// One section in the sidebar.
private struct SidebarRow: View {
    @Environment(AppModel.self) private var model
    let section: AppSection
    let compact: Bool
    let badge: Int
    let highlight: Namespace.ID
    @State private var hovering = false

    private var selected: Bool { model.section == section }

    var body: some View {
        Button {
            withAnimation(.spring(response: 0.34, dampingFraction: 0.82)) { model.section = section }
        } label: {
            HStack(spacing: 11) {
                ZStack {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(selected ? Color.white.opacity(0.22) : model.theme.color.opacity(hovering ? 0.22 : 0.14))
                    Image(systemName: section.symbol)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(selected ? Color.white : model.theme.color)
                        .symbolEffect(.bounce, value: selected)
                }
                .frame(width: 28, height: 28)
                .overlay(alignment: .topTrailing) {
                    if compact && badge > 0 {
                        Circle().fill(Palette.bad).frame(width: 8, height: 8).offset(x: 3, y: -3)
                    }
                }
                if !compact {
                    Text(section.title)
                        .font(.body.weight(selected ? .semibold : .medium))
                        .foregroundStyle(selected ? Color.white : Color.primary)
                        .lineLimit(1)
                    Spacer(minLength: 4)
                    if badge > 0 {
                        Text("\(badge)")
                            .font(.caption.weight(.bold).monospacedDigit())
                            .foregroundStyle(selected ? model.theme.color : .white)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 2)
                            .background(Capsule().fill(selected ? Color.white : model.theme.color))
                            .contentTransition(.numericText())
                    }
                }
            }
            .padding(.horizontal, compact ? 0 : 7)
            .padding(.vertical, 6)
            .frame(maxWidth: .infinity, alignment: compact ? .center : .leading)
            .background {
                if selected {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(LinearGradient(colors: [model.theme.color, model.theme.color.opacity(0.72)], startPoint: .topLeading, endPoint: .bottomTrailing))
                        .shadow(color: model.theme.color.opacity(0.45), radius: 10, y: 4)
                        .matchedGeometryEffect(id: "selection", in: highlight)
                } else if hovering {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(Color.primary.opacity(0.07))
                }
            }
            .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .animation(.easeOut(duration: 0.15), value: hovering)
        .help(compact ? section.title : "")
        .accessibilityLabel(section.title + (badge > 0 ? ", \(badge)" : ""))
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

/// Who's signed in, with the menu to switch or add students.
private struct SidebarProfileCard: View {
    @Environment(AppModel.self) private var model
    let compact: Bool

    var body: some View {
        if let profile = model.active {
            Menu {
                ForEach(model.profiles) { other in
                    Button {
                        withAnimation(Motion.snappy) { model.setActive(other.id) }
                    } label: {
                        if other.id == profile.id { Label(other.name, systemImage: "checkmark") } else { Text(other.name) }
                    }
                }
                Divider()
                Button { model.showOnboarding = true } label: { Label("Customize Profile…", systemImage: "slider.horizontal.3") }
                Button { model.signInRequest = SignInRequest() } label: { Label("Add Student…", systemImage: "person.badge.plus") }
            } label: {
                HStack(spacing: 10) {
                    AvatarView(profile: profile, size: compact ? 40 : 38, scalesWithWindow: false)
                        .overlay(Circle().strokeBorder(model.theme.color.opacity(0.6), lineWidth: 2).padding(-3))
                    if !compact {
                        VStack(alignment: .leading, spacing: 1) {
                            Text(profile.name).font(.headline).lineLimit(1)
                            Text(subtitle(profile)).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                        }
                        Spacer(minLength: 4)
                        Image(systemName: "chevron.up.chevron.down").font(.caption2.weight(.semibold)).foregroundStyle(.tertiary)
                    }
                }
                .padding(compact ? 4 : 10)
                .frame(maxWidth: .infinity, alignment: compact ? .center : .leading)
                .background {
                    if !compact {
                        RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Color.primary.opacity(0.06))
                    }
                }
                .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
            .menuStyle(.button)
            .buttonStyle(.plain)
            .menuIndicator(.hidden)
            .help("Switch or add a student")
        }
    }

    private func subtitle(_ profile: Profile) -> String {
        let school = Str.titleCase(model.data.profile.school)
        if !school.isEmpty { return school }
        return profile.districtName.isEmpty ? profile.username : profile.districtName
    }
}

/// The footer: when grades were last checked, and a way to check now.
private struct SidebarStatusCard: View {
    @Environment(AppModel.self) private var model
    let compact: Bool

    var body: some View {
        HStack(spacing: 8) {
            if !compact {
                if model.syncState.isSyncing {
                    ProgressView().controlSize(.small)
                    Text("Syncing…").font(.caption.weight(.medium)).foregroundStyle(.secondary)
                } else {
                    Circle()
                        .fill(model.data.lastSync != nil ? Palette.good : Color.secondary.opacity(0.4))
                        .frame(width: 7, height: 7)
                    Text("Updated " + Fmt.ago(model.data.lastSync, now: model.now()))
                        .font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
                Spacer(minLength: 2)
            }
            Button {
                Task { await model.refresh() }
            } label: {
                SpinningRefreshIcon(spinning: model.syncState.isSyncing)
                    .font(.callout.weight(.semibold))
                    .frame(width: 30, height: 30)
                    .background(Circle().fill(Color.primary.opacity(0.07)))
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .disabled(model.syncState.isSyncing)
            .help("Refresh grades")
            .accessibilityLabel("Refresh grades")
        }
        .padding(compact ? 6 : 10)
        .frame(maxWidth: .infinity)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Color.primary.opacity(0.06)))
    }
}

/// The sidebar's glass: the theme's card tint over a frosted panel, a hairline
/// edge with a faint top highlight, and a soft shadow so it floats over the scene.
private struct SidebarPanel: View {
    @Environment(\.backgroundTheme) private var theme

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 22, style: .continuous)
        shape
            .fill(.ultraThinMaterial)
            .overlay(shape.fill(theme.cardTint))
            .overlay(
                shape.strokeBorder(
                    LinearGradient(colors: [Color.white.opacity(theme.isDark ? 0.22 : 0.7), Color.white.opacity(theme.isDark ? 0.05 : 0.2)],
                                   startPoint: .top, endPoint: .bottom),
                    lineWidth: 1
                )
            )
            .shadow(color: theme.cardShadow, radius: 24, y: 10)
    }
}
