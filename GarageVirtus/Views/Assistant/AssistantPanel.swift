import GarageVirtusKit
import SwiftData
import SwiftUI

/// Chat with Claude about the open group. Lists it builds are priced by the app and can be added to My garage → Need.
struct AssistantPanel: View {
    let model: GroupDetailViewModel
    @Query private var garageParts: [GaragePart]
    @Environment(GarageStore.self) private var garage

    var body: some View {
        if let assistant = model.assistant {
            AssistantChat(assistant: assistant, onNewChat: startChat)
        } else if APIKeyStore().read() == nil {
            ContentUnavailableView {
                Label("Add your API key", systemImage: "key")
            } description: {
                Text("The parts assistant uses Claude. Add your Anthropic API key in Settings.")
            } actions: {
                SettingsLink { Text("Open Settings…") }
            }
        } else {
            ProgressView().onAppear(perform: startChat)
        }
    }

    private func startChat() {
        guard let key = APIKeyStore().read() else { return }
        var coverage: [String: Coverage] = [:]
        let carID = garage.activeCar.id
        let carParts = garageParts.filter { $0.car?.id == carID }
        for key in Set(carParts.compactMap(\.oemKey)) {
            coverage[key] = GarageStore.coverage(forOEMKey: key, in: carParts)
        }
        model.startAssistant(apiKey: key, coverage: coverage)
    }
}

private struct AssistantChat: View {
    let assistant: PartsAssistant
    let onNewChat: () -> Void
    @State private var draft = ""

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Ask AI").font(.headline)
                Spacer()
                Button("New chat", action: onNewChat).disabled(assistant.isSending)
            }
            .padding(12)
            Divider()
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 10) {
                        if assistant.entries.isEmpty {
                            Text("Ask about this section, e.g. “What hardware do I need?” or “Which of these parts are discontinued?”")
                                .foregroundStyle(.secondary)
                        }
                        ForEach(Array(assistant.entries.enumerated()), id: \.offset) { _, entry in
                            EntryView(entry: entry)
                        }
                        if assistant.isSending {
                            ProgressView().controlSize(.small)
                        }
                        Color.clear.frame(height: 1).id("end")
                    }
                    .padding(12)
                }
                .onChange(of: assistant.entries.count) { _, _ in proxy.scrollTo("end", anchor: .bottom) }
            }
            Divider()
            HStack {
                TextField("Ask about these parts…", text: $draft, axis: .vertical)
                    .lineLimit(1...4)
                    .onSubmit(send)
                Button(action: send) { Image(systemName: "arrow.up.circle.fill").font(.title2) }
                    .buttonStyle(.plain)
                    .disabled(draft.trimmingCharacters(in: .whitespaces).isEmpty || assistant.isSending)
            }
            .padding(12)
        }
    }

    private func send() {
        let text = draft
        draft = ""
        Task { await assistant.send(text) }
    }
}

private struct EntryView: View {
    let entry: PartsAssistant.Entry

    var body: some View {
        switch entry {
        case .user(let text):
            Text(text)
                .padding(8)
                .frame(maxWidth: .infinity, alignment: .trailing)
                .background(Color.accentColor.opacity(0.15), in: RoundedRectangle(cornerRadius: 8))
        case .assistant(let text):
            Text(LocalizedStringKey(text)).textSelection(.enabled)
        case .partsList(let list):
            PartsListCard(list: list)
        case .notice(let text):
            Label(text, systemImage: "exclamationmark.triangle").font(.callout).foregroundStyle(.orange)
        }
    }
}

/// A priced list from the assistant, with the total and "Add all to Need".
private struct PartsListCard: View {
    @Environment(GarageStore.self) private var garage
    let list: PartsList
    @State private var isAdded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(list.title).font(.headline)
            ForEach(Array(list.lines.enumerated()), id: \.offset) { _, line in
                HStack(alignment: .firstTextBaseline) {
                    Text("\(line.quantity) ×").monospacedDigit().foregroundStyle(.secondary)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(line.oem).font(.system(.callout, design: .monospaced))
                        Text(line.reason ?? line.name.localizedCapitalized).font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    if let total = line.lineTotal {
                        Text(total, format: .currency(code: list.currency)).monospacedDigit()
                    } else {
                        Text(line.isInSection ? (line.status ?? "No price") : "Not in section")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
            Divider()
            HStack {
                Text("Total").fontWeight(.semibold)
                if list.unpricedCount > 0 {
                    Text("(unpriced lines: \(list.unpricedCount))").font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Text(list.total, format: .currency(code: list.currency)).fontWeight(.semibold).monospacedDigit()
            }
            Button(isAdded ? "Added to Need" : "Add all to Need", action: addAll)
                .disabled(isAdded)
        }
        .padding(10)
        .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
    }

    private func addAll() {
        for line in list.lines where line.isInSection {
            garage.markWanted(oemNumber: line.oem, name: line.name, status: .need, quantity: line.quantity)
        }
        isAdded = true
    }
}
