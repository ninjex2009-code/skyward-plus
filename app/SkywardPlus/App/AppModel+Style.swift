import SwiftUI

extension AppModel {
    // MARK: Class colors

    /// The color a class shows everywhere: the student's pick, or an automatic one
    /// from its place in Skyward's list so it stays the same across launches.
    func classColorChoice(_ courseID: String) -> ClassColor {
        if let chosen = prefs.classColors[courseID] { return chosen }
        return ClassColor.automatic(index: data.courses.firstIndex { $0.id == courseID }, id: courseID)
    }

    func classColor(_ courseID: String?) -> Color {
        guard let courseID, !courseID.isEmpty else { return theme.color }
        return Color(hex: classColorChoice(courseID).hex)
    }

    func isClassColorChosen(_ courseID: String) -> Bool { prefs.classColors[courseID] != nil }

    /// Nil goes back to the automatic color.
    func setClassColor(_ color: ClassColor?, for courseID: String) {
        updatePrefs { $0.classColors[courseID] = color }
    }

    // MARK: Home layout

    var homeSectionsAll: [HomeSection] { HomeSection.ordered(settings.homeOrder) }
    var homeSectionsVisible: [HomeSection] {
        let hidden = Set(settings.homeHidden ?? [])
        return homeSectionsAll.filter { !hidden.contains($0.rawValue) }
    }

    func setHomeOrder(_ order: [HomeSection]) { updateSettings { $0.homeOrder = order.map(\.rawValue) } }

    func setHomeSection(_ section: HomeSection, visible: Bool) {
        updateSettings { s in
            var hidden = Set(s.homeHidden ?? [])
            if visible { hidden.remove(section.rawValue) } else { hidden.insert(section.rawValue) }
            s.homeHidden = hidden.sorted()
        }
    }
}
