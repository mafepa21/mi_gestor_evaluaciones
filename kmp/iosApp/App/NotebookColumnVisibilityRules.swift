import SwiftUI
import MiGestorKit

extension NotebookColumnDefinition {
    var isVisibleInGrid: Bool {
        visibility == .visible
    }

    var isTemporarilyHidden: Bool {
        visibility == .hidden
    }

    var isArchived: Bool {
        visibility == .archived
    }

    var canBeShownWithShowAll: Bool {
        visibility == .hidden
    }

    var canBeArchived: Bool {
        visibility == .visible || visibility == .hidden
    }

    var canBeDeleted: Bool {
        !isLocked
    }
}
