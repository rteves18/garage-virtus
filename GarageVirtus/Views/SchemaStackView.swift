import GarageVirtusKit
import SwiftUI

/// The group's schemas for the selected year window, stacked in one scroll view. The schema most in view is the current one (the inspector
/// lists its parts). Picking a schema or jumping to a part scrolls to it. Zoom applies to all diagrams: 100% fits the
/// width, and larger zooms scroll sideways.
struct SchemaStackView: View {
    @Bindable var model: GroupDetailViewModel
    let file: SchemaGroupFile

    @State private var zoom: CGFloat = 1
    @GestureState private var pinch: CGFloat = 1

    private let minZoom: CGFloat = 0.5
    private let maxZoom: CGFloat = 6
    private let padding: CGFloat = 16

    var body: some View {
        let scale = clamp(zoom * pinch)
        // Vertical only at 100%: if the content could also scroll sideways, a vertical scroll bar taking width would
        // add a horizontal one, change the layout, and flip back, looping layout until AppKit kills the app.
        ScrollView(scale > 1 ? [.horizontal, .vertical] : .vertical) {
            VStack(alignment: .leading, spacing: 24) {
                ForEach(model.visibleSchemas, id: \.schema.id) { entry in
                    SchemaSection(model: model, schema: entry.schema, index: entry.index, scale: scale, padding: padding)
                        .id(entry.schema.id)
                }
            }
            .scrollTargetLayout()
            .padding(padding)
        }
        .scrollPosition(id: $model.currentSchemaID, anchor: .top)
        .background(Color.secondary.opacity(0.08))
        .gesture(
            MagnifyGesture()
                .updating($pinch) { value, state, _ in state = value.magnification }
                .onEnded { value in zoom = clamp(zoom * value.magnification) }
        )
        .overlay(alignment: .bottomTrailing) {
            ZoomControls(zoom: $zoom, clamp: clamp).padding(12)
        }
    }

    private func clamp(_ value: CGFloat) -> CGFloat { min(max(value, minZoom), maxZoom) }
}

/// One schema: its title and its diagram, as wide as the scroll view's visible width times `scale`.
private struct SchemaSection: View {
    let model: GroupDetailViewModel
    let schema: Schema
    let index: Int
    let scale: CGFloat
    let padding: CGFloat

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
                    .containerRelativeFrame(.horizontal, alignment: .leading) { length, _ in
                        max(length - padding * 2, 100) * scale
                    }
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

    @State private var size: CGSize = .zero
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
        .onGeometryChange(for: CGSize.self) { $0.size } action: { size = $0 }
        .gesture(SpatialTapGesture().onEnded { tap(at: $0.location) })
        .onContinuousHover { phase in
            switch phase {
            case .active(let location): hover(callout(at: location)?.pnc)
            case .ended: hover(nil)
            }
        }
        .help(hovered.flatMap { pnc in schema.callouts.first { $0.pnc == pnc } }.map { "\($0.pnc) – \($0.displayName)" } ?? "")
    }

    private func callout(at location: CGPoint) -> Callout? {
        guard size.width > 0, size.height > 0 else { return nil }
        return schema.callout(at: CGPoint(x: location.x / size.width, y: location.y / size.height),
                              tolerance: pad / size.width)
    }

    private func tap(at location: CGPoint) {
        if let callout = callout(at: location) {
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

private struct ZoomControls: View {
    @Binding var zoom: CGFloat
    let clamp: (CGFloat) -> CGFloat

    var body: some View {
        HStack(spacing: 2) {
            Button(action: zoomOut) { Image(systemName: "minus.magnifyingglass") }
                .keyboardShortcut("-", modifiers: .command)
                .help("Zoom out")
            Button(action: fit) { Text("\(Int((zoom * 100).rounded()))%").monospacedDigit().frame(minWidth: 44) }
                .keyboardShortcut("0", modifiers: .command)
                .help("Fit to width")
            Button(action: zoomIn) { Image(systemName: "plus.magnifyingglass") }
                .keyboardShortcut("=", modifiers: .command)
                .help("Zoom in")
        }
        .buttonStyle(.borderless)
        .padding(6)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
    }

    private func zoomOut() { zoom = clamp(zoom / 1.25) }
    private func zoomIn() { zoom = clamp(zoom * 1.25) }
    private func fit() { zoom = 1 }
}
