import GarageVirtusKit
import SwiftUI

/// The group's schemas for the selected year window, stacked in one vertical scroll view, each diagram filling the
/// column's width. The schema most in view is the current one (the parts panel lists its parts); picking a schema or
/// jumping to a part scrolls to it.
struct SchemaStackView: View {
    @Bindable var model: GroupDetailViewModel
    let file: SchemaGroupFile

    var body: some View {
        ScrollView(.vertical) {
            VStack(alignment: .leading, spacing: 24) {
                ForEach(model.visibleSchemas, id: \.schema.id) { entry in
                    SchemaSection(model: model, schema: entry.schema, index: entry.index)
                        .id(entry.schema.id)
                }
            }
            .scrollTargetLayout()
            .padding(16)
        }
        .scrollPosition(id: $model.currentSchemaID, anchor: .top)
        // Always reserve the scroll bar's width, so the space for diagrams doesn't change when the bar appears.
        .scrollIndicators(.visible)
        .background(Color.secondary.opacity(0.08))
    }
}

/// One schema: its title and its diagram, filling the available width at the diagram's aspect ratio.
private struct SchemaSection: View {
    let model: GroupDetailViewModel
    let schema: Schema
    let index: Int

    var body: some View {
        let isCurrent = index == model.schemaIndex
        VStack(alignment: .leading, spacing: 8) {
            Text(model.label(for: schema))
                .font(.headline)
                .foregroundStyle(isCurrent ? .primary : .secondary)
            if let image = model.image(for: schema) {
                let size = model.imageSize(for: schema)
                DiagramCanvas(model: model, image: image, schema: schema, schemaIndex: index)
                    .aspectRatio(size.width / size.height, contentMode: .fit)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                    .overlay(RoundedRectangle(cornerRadius: 6)
                        .stroke(isCurrent ? Color.accentColor.opacity(0.6) : Color.secondary.opacity(0.2),
                                lineWidth: isCurrent ? 2 : 1))
            } else {
                ContentUnavailableView("Diagram missing", systemImage: "photo",
                                       description: Text("Expected _images/\(schema.image)"))
                    .frame(maxWidth: .infinity, minHeight: 200)
            }
        }
    }
}

/// A diagram and its callout hotspots, drawn in one Canvas: a group with hundreds of hotspots stays one view per
/// diagram. Taps and hover are hit-tested against the hotspots' 0...1 rects. Highlights apply only on the current
/// schema, because callout labels repeat across schemas.
struct DiagramCanvas: View {
    let model: GroupDetailViewModel
    let image: CGImage
    let schema: Schema
    let schemaIndex: Int

    @State private var localHover: String?

    private let pad: CGFloat = 3

    var body: some View {
        let isCurrent = schemaIndex == model.schemaIndex
        let selected = isCurrent ? model.selectedPNC : nil
        let hovered = (isCurrent ? model.hoveredPNC : nil) ?? localHover
        let showsHotspots = model.showHotspots
        Canvas { context, size in
            context.draw(Image(decorative: image, scale: 1), in: CGRect(origin: .zero, size: size))
            for callout in schema.callouts {
                let isSelected = callout.pnc == selected
                let isHovered = callout.pnc == hovered
                guard isSelected || isHovered || showsHotspots else { continue }
                for hotspot in callout.hotspots {
                    let norm = hotspot.norm.rect
                    let rect = CGRect(x: norm.minX * size.width, y: norm.minY * size.height,
                                      width: norm.width * size.width, height: norm.height * size.height)
                        .insetBy(dx: -pad, dy: -pad)
                    let path = Path(roundedRect: rect, cornerRadius: 3)
                    if isSelected || isHovered {
                        context.fill(path, with: .color(.accentColor.opacity(isSelected ? 0.28 : 0.12)))
                    }
                    let stroke: Color = isSelected ? .accentColor : isHovered ? .accentColor.opacity(0.8) : .blue.opacity(0.35)
                    context.stroke(path, with: .color(stroke), lineWidth: isSelected ? 2 : 1)
                }
            }
        }
        .background(Color.white)
        .overlay {
            // Reads the drawn size for hit-testing without storing it, so nothing feeds back into layout.
            GeometryReader { geo in
                Color.clear
                    .contentShape(Rectangle())
                    .gesture(SpatialTapGesture().onEnded { tap(at: $0.location, in: geo.size) })
                    .onContinuousHover { phase in
                        switch phase {
                        case .active(let location): hover(callout(at: location, in: geo.size)?.pnc)
                        case .ended: hover(nil)
                        }
                    }
            }
        }
        .help(hovered.flatMap { pnc in schema.callouts.first { $0.pnc == pnc } }.map { "\($0.pnc) – \($0.displayName)" } ?? "")
    }

    private func callout(at location: CGPoint, in size: CGSize) -> Callout? {
        guard size.width > 0, size.height > 0 else { return nil }
        return schema.callout(at: CGPoint(x: location.x / size.width, y: location.y / size.height),
                              tolerance: pad / size.width)
    }

    private func tap(at location: CGPoint, in size: CGSize) {
        if let callout = callout(at: location, in: size) {
            model.selectCallout(callout.pnc, inSchemaAt: schemaIndex)
        } else {
            model.selectedPNC = nil
        }
    }

    /// Hovering the current schema drives the inspector's hover link. Other schemas only highlight locally.
    private func hover(_ pnc: String?) {
        if localHover != pnc { localHover = pnc }
        guard schemaIndex == model.schemaIndex, model.hoveredPNC != pnc else { return }
        model.hoveredPNC = pnc
    }
}
