import GarageVirtusKit
import SwiftUI

/// Every schema in the group, stacked in one scroll view. The schema most in view is the current one (the inspector
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
        GeometryReader { geo in
            let width = max(geo.size.width - padding * 2, 100) * clamp(zoom * pinch)
            ScrollView([.horizontal, .vertical]) {
                VStack(alignment: .leading, spacing: 24) {
                    ForEach(Array(file.schemas.enumerated()), id: \.element.id) { index, schema in
                        SchemaSection(model: model, schema: schema, index: index, width: width)
                            .id(schema.id)
                    }
                }
                .scrollTargetLayout()
                .padding(padding)
                .frame(minWidth: geo.size.width, alignment: .leading)
            }
            .scrollPosition(id: $model.currentSchemaID, anchor: .top)
            .background(Color(nsColor: .underPageBackgroundColor))
            .gesture(
                MagnifyGesture()
                    .updating($pinch) { value, state, _ in state = value.magnification }
                    .onEnded { value in zoom = clamp(zoom * value.magnification) }
            )
        }
        .overlay(alignment: .bottomTrailing) {
            ZoomControls(zoom: $zoom, clamp: clamp).padding(12)
        }
    }

    private func clamp(_ value: CGFloat) -> CGFloat { min(max(value, minZoom), maxZoom) }
}

/// One schema: its title and its diagram at `width`.
private struct SchemaSection: View {
    let model: GroupDetailViewModel
    let schema: Schema
    let index: Int
    let width: CGFloat

    var body: some View {
        let isCurrent = index == model.schemaIndex
        VStack(alignment: .leading, spacing: 8) {
            Text(model.label(for: schema))
                .font(.headline)
                .foregroundStyle(isCurrent ? .primary : .secondary)
            if let image = model.image(for: schema) {
                let size = model.imageSize(for: schema)
                DiagramCanvas(model: model, image: image, callouts: schema.callouts, schemaIndex: index,
                              size: CGSize(width: width, height: width * size.height / size.width))
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                    .overlay(RoundedRectangle(cornerRadius: 6)
                        .stroke(isCurrent ? Color.accentColor.opacity(0.6) : Color.secondary.opacity(0.2),
                                lineWidth: isCurrent ? 2 : 1))
            } else {
                ContentUnavailableView("Diagram missing", systemImage: "photo",
                                       description: Text("Expected _images/\(schema.image)"))
                    .frame(width: width, height: 200)
            }
        }
    }
}

/// A diagram drawn at `size`, with clickable callout hotspots. Hotspots use normalized (0...1) rects, so they line up
/// at any size. Highlights apply only on the current schema, because callout labels repeat across schemas.
struct DiagramCanvas: View {
    let model: GroupDetailViewModel
    let image: NSImage
    let callouts: [Callout]
    let schemaIndex: Int
    let size: CGSize

    @State private var localHover: String?

    var body: some View {
        ZStack(alignment: .topLeading) {
            Image(nsImage: image)
                .resizable()
                .interpolation(.high)
                .frame(width: size.width, height: size.height)
                .background(Color.white)
                .onTapGesture { model.selectedPNC = nil }

            ForEach(callouts) { callout in
                ForEach(Array(callout.hotspots.enumerated()), id: \.offset) { _, hotspot in
                    hotspotView(callout, hotspot)
                }
            }
        }
        .frame(width: size.width, height: size.height)
    }

    @ViewBuilder
    private func hotspotView(_ callout: Callout, _ hotspot: Hotspot) -> some View {
        let isSelected = model.isSelected(callout.pnc, inSchemaAt: schemaIndex)
        let isHovered = model.isHovered(callout.pnc, inSchemaAt: schemaIndex) || localHover == callout.pnc
        let pad: CGFloat = 3
        let rect = CGRect(
            x: hotspot.norm.x1 * size.width - pad,
            y: hotspot.norm.y1 * size.height - pad,
            width: (hotspot.norm.x2 - hotspot.norm.x1) * size.width + pad * 2,
            height: (hotspot.norm.y2 - hotspot.norm.y1) * size.height + pad * 2)
        let stroke: Color = isSelected ? .accentColor
            : isHovered ? .accentColor.opacity(0.8)
            : model.showHotspots ? .blue.opacity(0.35) : .clear

        RoundedRectangle(cornerRadius: 3)
            .fill(isSelected ? Color.accentColor.opacity(0.28)
                  : isHovered ? Color.accentColor.opacity(0.12) : Color.clear)
            .overlay(RoundedRectangle(cornerRadius: 3).stroke(stroke, lineWidth: isSelected ? 2 : 1))
            .frame(width: rect.width, height: rect.height)
            .contentShape(Rectangle())
            .onTapGesture { model.selectCallout(callout.pnc, inSchemaAt: schemaIndex) }
            .onHover { inside in hover(callout.pnc, inside: inside) }
            .help("\(callout.pnc) – \(callout.displayName)")
            .position(x: rect.midX, y: rect.midY)
            .animation(.easeOut(duration: 0.12), value: isSelected)
    }

    /// Hovering the current schema drives the inspector's hover link. Other schemas only highlight locally.
    private func hover(_ pnc: String, inside: Bool) {
        if inside { localHover = pnc } else if localHover == pnc { localHover = nil }
        guard schemaIndex == model.schemaIndex else { return }
        if inside { model.hoveredPNC = pnc } else if model.hoveredPNC == pnc { model.hoveredPNC = nil }
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
