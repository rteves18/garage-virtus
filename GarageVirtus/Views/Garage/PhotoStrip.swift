import GarageVirtusKit
import ImageIO
import PhotosUI
import SwiftUI

/// A part's photos as thumbnails. Add from Photos or by dropping image files; remove from each thumbnail.
struct PhotoStrip: View {
    @Environment(GarageStore.self) private var garage
    let part: GaragePart
    @State private var pickerItem: PhotosPickerItem?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ScrollView(.horizontal) {
                HStack(spacing: 8) {
                    ForEach(part.photos.sorted { $0.createdAt < $1.createdAt }) { photo in
                        PhotoThumbnail(photo: photo) { garage.removePhoto(photo) }
                    }
                }
            }
            .frame(height: 96)
            PhotosPicker("Add from Photos…", selection: $pickerItem, matching: .images)
        }
        .dropDestination(for: URL.self) { urls, _ in
            let images = urls.compactMap { try? Data(contentsOf: $0) }
            images.forEach { garage.addPhoto($0, to: part) }
            return !images.isEmpty
        }
        .task(id: pickerItem) { await addPickedPhoto() }
    }

    private func addPickedPhoto() async {
        guard let item = pickerItem, let data = try? await item.loadTransferable(type: Data.self) else { return }
        garage.addPhoto(data, to: part)
        pickerItem = nil
    }
}

private struct PhotoThumbnail: View {
    let photo: PartPhoto
    let onRemove: () -> Void

    var body: some View {
        Group {
            if let image = Self.thumbnail(photo.imageData) {
                Image(decorative: image, scale: 1).resizable().scaledToFill()
            } else {
                Image(systemName: "photo").foregroundStyle(.secondary)
            }
        }
        .frame(width: 96, height: 96)
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .overlay(alignment: .topTrailing) {
            Button(action: onRemove) { Image(systemName: "xmark.circle.fill") }
                .buttonStyle(.plain)
                .padding(4)
                .help("Remove photo")
        }
    }

    /// Decodes a small thumbnail with ImageIO (never the full-size image).
    private static func thumbnail(_ data: Data) -> CGImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        let options = [kCGImageSourceCreateThumbnailFromImageAlways: true,
                       kCGImageSourceThumbnailMaxPixelSize: 192,
                       kCGImageSourceCreateThumbnailWithTransform: true] as CFDictionary
        return CGImageSourceCreateThumbnailAtIndex(source, 0, options)
    }
}
