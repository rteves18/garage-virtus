import GarageVirtusKit
import SwiftData
import SwiftUI

/// Edits one tracked part: status, what it is, and purchase or wish-list details, plus photos.
struct PartEditorView: View {
    @Environment(GarageStore.self) private var garage
    @Bindable var part: GaragePart
    let coverage: Coverage?
    let onClose: () -> Void

    var body: some View {
        Form {
            Section {
                Picker("Status", selection: statusBinding) {
                    ForEach(PartStatus.allCases, id: \.self) { Text($0.title).tag($0) }
                }
                TextField("Name", text: $part.name)
                TextField("Part number", text: optional(\.oemNumber))
                Stepper("Quantity: \(part.quantity)", value: $part.quantity, in: 1...999)
            }
            if part.status.isOwned {
                Section("Purchase") {
                    TextField("Cost", value: decimal(\.cost), format: .currency(code: part.currency))
                    TextField("Seller", text: optional(\.seller))
                    TextField("Seller link", text: optional(\.sellerURL))
                    DatePicker("Purchased", selection: date(\.purchasedOn), displayedComponents: .date)
                    Picker("Condition", selection: $part.condition) {
                        Text("—").tag(PartCondition?.none)
                        ForEach(PartCondition.allCases, id: \.self) { Text($0.title).tag(PartCondition?.some($0)) }
                    }
                    TextField("Stored at", text: optional(\.storageLocation))
                }
            } else {
                Section("Wish list") {
                    TextField("Target price", value: decimal(\.targetPrice), format: .currency(code: part.currency))
                    TextField("Link", text: optional(\.linkURL))
                    if let coverage {
                        LabeledContent("Have", value: "\(coverage.owned) of \(coverage.needed)")
                    }
                    Button("Mark bought", action: markBought)
                        .help("Adds the parts still short to In storage; this need stays until it's covered")
                }
            }
            Section("Notes") {
                TextEditor(text: $part.notes).frame(minHeight: 60)
            }
            Section("Photos") {
                PhotoStrip(part: part)
            }
            Section {
                Button("Delete part", role: .destructive, action: deletePart)
            }
        }
        .formStyle(.grouped)
        .onSubmit { garage.save(touching: part) }
        .onDisappear { garage.save(touching: part) }
        .toolbar {
            ToolbarItem {
                Button(action: onClose) { Label("Close", systemImage: "xmark") }
            }
        }
    }

    private var statusBinding: Binding<PartStatus> {
        Binding(get: { part.status }, set: { garage.setStatus($0, for: part) })
    }

    private func markBought() {
        garage.markBought(part, quantity: max(coverage?.short ?? part.quantity, 1))
    }

    private func deletePart() {
        onClose()
        garage.delete(part)
    }

    /// Empty text clears the field.
    private func optional(_ keyPath: ReferenceWritableKeyPath<GaragePart, String?>) -> Binding<String> {
        Binding(get: { part[keyPath: keyPath] ?? "" },
                set: { part[keyPath: keyPath] = $0.isEmpty ? nil : $0 })
    }

    /// Zero clears the field.
    private func decimal(_ keyPath: ReferenceWritableKeyPath<GaragePart, Decimal?>) -> Binding<Decimal> {
        Binding(get: { part[keyPath: keyPath] ?? 0 },
                set: { part[keyPath: keyPath] = $0 == 0 ? nil : $0 })
    }

    private func date(_ keyPath: ReferenceWritableKeyPath<GaragePart, Date?>) -> Binding<Date> {
        Binding(get: { part[keyPath: keyPath] ?? .now }, set: { part[keyPath: keyPath] = $0 })
    }
}
