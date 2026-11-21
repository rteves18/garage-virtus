import GarageVirtusKit
import SwiftUI
import AppKit

/// An OEM number you can click to copy. Hover shows a subtle chip + copy icon; after copying
/// the icon turns into a checkmark for a moment. Right-click offers the dash-less form too.
struct CopyableOEM: View {
    let oem: String
    var font: Font = .system(.body, design: .monospaced).weight(.medium)

    @State private var isHovering = false
    @State private var didCopy = false

    var body: some View {
        Button { copy(oem) } label: {
            HStack(spacing: 5) {
                Text(oem).font(font)
                Image(systemName: didCopy ? "checkmark" : "doc.on.doc")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(didCopy ? AnyShapeStyle(Color.green) : AnyShapeStyle(.secondary))
                    .opacity(isHovering || didCopy ? 1 : 0)
                    .contentTransition(.symbolEffect(.replace))
            }
            .padding(.horizontal, 5)
            .padding(.vertical, 2)
            .background(
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .fill(Color.primary.opacity(isHovering ? 0.08 : 0))
            )
            .contentShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
        }
        .buttonStyle(.plain)
        .padding(.horizontal, -5)            // keep the text aligned with the rows around it
        .onHover { isHovering = $0 }
        .animation(.easeOut(duration: 0.12), value: isHovering)
        .help(didCopy ? "Copied" : "Click to copy \(oem)")
        .contextMenu {
            Button("Copy \(oem)") { copy(oem) }
            let plain = CatalogueStore.normalize(oem)
            if plain != oem {
                Button("Copy \(plain)") { copy(plain) }
            }
        }
        .accessibilityLabel("Part number \(oem)")
        .accessibilityHint("Copies to the clipboard")
    }

    private func copy(_ value: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(value, forType: .string)
        didCopy = true
        Task {
            try? await Task.sleep(for: .seconds(1.2))
            didCopy = false
        }
    }
}
