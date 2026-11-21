import GarageVirtusKit
import SwiftUI

/// Settings (⌘,): the Anthropic API key the parts assistant uses, kept in the Keychain.
struct AssistantSettingsView: View {
    @State private var key = ""
    @State private var hasKey = APIKeyStore().read() != nil
    @State private var message: String?

    var body: some View {
        Form {
            Section {
                SecureField("Anthropic API key", text: $key, prompt: Text(hasKey ? "Saved – enter a new key to replace it" : "sk-ant-…"))
                HStack {
                    Button("Save", action: save).disabled(key.isEmpty)
                    if hasKey { Button("Remove key", role: .destructive, action: remove) }
                }
                if let message { Text(message).font(.callout).foregroundStyle(.secondary) }
            } header: {
                Text("AI parts assistant")
            } footer: {
                Text("Used for “Ask AI” in a schema group. Requests go to Anthropic’s API with model \(ClaudeClient.model). The key is stored in your Keychain.")
                    .font(.caption)
            }
        }
        .formStyle(.grouped)
        .frame(width: 460)
        .padding()
    }

    private func save() {
        do {
            try APIKeyStore().save(key.trimmingCharacters(in: .whitespacesAndNewlines))
            key = ""
            hasKey = true
            message = "Saved."
        } catch {
            message = "Couldn't save the key: \(error)"
        }
    }

    private func remove() {
        APIKeyStore().delete()
        hasKey = false
        message = "Removed."
    }
}
