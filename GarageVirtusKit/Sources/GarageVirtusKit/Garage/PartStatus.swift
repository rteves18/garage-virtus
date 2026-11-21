/// Where a tracked part stands. Need and want are parts Ryan doesn't have yet; the rest are parts he owns.
public enum PartStatus: String, Codable, CaseIterable, Sendable {
    case need, want, inStorage, waitingToInstall, installed

    /// True for parts Ryan has: in storage, waiting to install, or installed.
    public var isOwned: Bool {
        switch self {
        case .need, .want: false
        case .inStorage, .waitingToInstall, .installed: true
        }
    }

    public var title: String {
        switch self {
        case .need: "Need"
        case .want: "Want"
        case .inStorage: "In storage"
        case .waitingToInstall: "Waiting to install"
        case .installed: "Installed"
        }
    }
}

/// The state an owned part is in.
public enum PartCondition: String, Codable, CaseIterable, Sendable {
    case new, usedGood, usedFair, needsRebuild, core

    public var title: String {
        switch self {
        case .new: "New"
        case .usedGood: "Used – good"
        case .usedFair: "Used – fair"
        case .needsRebuild: "Needs rebuild"
        case .core: "Core"
        }
    }
}
