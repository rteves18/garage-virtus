import SwiftUI
import AppKit

/// The exploded-view diagram with clickable callout hotspots.
/// Hotspots use the normalized (0...1) rects, so they line up at any zoom.
struct DiagramView: View {
    let image: NSImage
    let imageSize: CGSize
    let callouts: [Callout]
    let showHotspots: Bool
    @Binding var selectedPNC: String?
    @Binding var hoveredPNC: String?

    @State private var zoom: CGFloat = 1
    @GestureState private var pinch: CGFloat = 1

    private let minZoom: CGFloat = 0.5
    private let maxZoom: CGFloat = 6

    var body: some View {
        GeometryReader { geo in
            let fit = min(geo.size.width / imageSize.width, geo.size.height / imageSize.height)
            let scale = fit * clamp(zoom * pinch)
            let size = CGSize(width: imageSize.width * scale, height: imageSize.height * scale)

            ScrollView([.horizontal, .vertical]) {
                ZStack(alignment: .topLeading) {
                    Image(nsImage: image)
                        .resizable()
                        .interpolation(.high)
                        .frame(width: size.width, height: size.height)
                        .background(Color.white)
                        .onTapGesture { selectedPNC = nil }

                    ForEach(callouts) { callout in
                        ForEach(Array(callout.hotspots.enumerated()), id: \.offset) { _, hotspot in
                            hotspotView(callout, hotspot, in: size)
                        }
                    }
                }
                .frame(width: size.width, height: size.height)
                .frame(minWidth: geo.size.width, minHeight: geo.size.height)
            }
            .background(Color(nsColor: .underPageBackgroundColor))
            .gesture(
                MagnifyGesture()
                    .updating($pinch) { value, state, _ in state = value.magnification }
                    .onEnded { value in zoom = clamp(zoom * value.magnification) }
            )
        }
        .overlay(alignment: .bottomTrailing) { zoomControls.padding(12) }
    }

    @ViewBuilder
    private func hotspotView(_ callout: Callout, _ hotspot: Hotspot, in size: CGSize) -> some View {
        let isSelected = callout.pnc == selectedPNC
        let isHovered = callout.pnc == hoveredPNC
        let pad: CGFloat = 3
        let rect = CGRect(
            x: hotspot.norm.x1 * size.width - pad,
            y: hotspot.norm.y1 * size.height - pad,
            width: (hotspot.norm.x2 - hotspot.norm.x1) * size.width + pad * 2,
            height: (hotspot.norm.y2 - hotspot.norm.y1) * size.height + pad * 2)
        let stroke: Color = isSelected ? .accentColor
            : isHovered ? .accentColor.opacity(0.8)
            : showHotspots ? .blue.opacity(0.35) : .clear

        RoundedRectangle(cornerRadius: 3)
            .fill(isSelected ? Color.accentColor.opacity(0.28)
                  : isHovered ? Color.accentColor.opacity(0.12) : Color.clear)
            .overlay(RoundedRectangle(cornerRadius: 3).stroke(stroke, lineWidth: isSelected ? 2 : 1))
            .frame(width: rect.width, height: rect.height)
            .contentShape(Rectangle())
            .onTapGesture { selectedPNC = callout.pnc }
            .onHover { inside in
                if inside { hoveredPNC = callout.pnc }
                else if hoveredPNC == callout.pnc { hoveredPNC = nil }
            }
            .help("\(callout.pnc) – \(callout.displayName)")
            .position(x: rect.midX, y: rect.midY)
            .animation(.easeOut(duration: 0.12), value: isSelected)
    }

    private var zoomControls: some View {
        HStack(spacing: 2) {
            Button { zoom = clamp(zoom / 1.25) } label: { Image(systemName: "minus.magnifyingglass") }
                .keyboardShortcut("-", modifiers: .command)
            Button { zoom = 1 } label: { Text("\(Int((zoom * 100).rounded()))%").monospacedDigit().frame(minWidth: 44) }
                .keyboardShortcut("0", modifiers: .command)
                .help("Fit to window")
            Button { zoom = clamp(zoom * 1.25) } label: { Image(systemName: "plus.magnifyingglass") }
                .keyboardShortcut("=", modifiers: .command)
        }
        .buttonStyle(.borderless)
        .padding(6)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
    }

    private func clamp(_ value: CGFloat) -> CGFloat { min(max(value, minZoom), maxZoom) }
}
