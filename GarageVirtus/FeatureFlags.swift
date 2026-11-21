/// Switches for features that are built but turned off.
enum FeatureFlags {
    /// The in-app "Ask AI" chat (Claude API, needs a paid API key). Hidden for now in favour of the MCP server, which
    /// lets Claude Desktop / Claude Code use the catalogue on Ryan's subscription. To turn it back on, set this to
    /// true and add `com.apple.security.network.client` back to GarageVirtus.entitlements.
    static let isAskAIEnabled = false
}
