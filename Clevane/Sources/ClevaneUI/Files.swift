import AppKit
import SwiftUI
import UniformTypeIdentifiers
import VaultCore

extension Attachment {
    var type: UTType { UTType(contentType) ?? .data }
    var isPhoto: Bool { type.conforms(to: .image) }
    var symbol: String { isPhoto ? "photo" : type.conforms(to: .pdf) ? "doc.richtext" : "doc" }
    var sizeLabel: String { ByteCountFormatter.string(fromByteCount: Int64(byteCount), countStyle: .file) }
}

/// A File column in the row detail: a photo preview decrypted in memory, the name and size, and Export.
struct FileField: View {
    let model: AppModel
    let column: Column
    let attachment: Attachment?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Caps(column.name)
                Text("· FILE").font(.system(size: 10)).tracking(1.2).foregroundStyle(Palette.quiet)
            }
            if let attachment {
                if attachment.isPhoto { PhotoPreview(model: model, attachment: attachment) }
                HStack(spacing: 8) {
                    Image(systemName: attachment.symbol).foregroundStyle(Palette.text2).accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(attachment.name).font(.system(size: 13, weight: .medium)).lineLimit(1).truncationMode(.middle)
                        Text(attachment.sizeLabel).font(.system(size: 11.5)).foregroundStyle(Palette.muted)
                    }
                    Spacer()
                    Button {
                        if let destination = FilePanels.chooseExportDestination(for: attachment.name) { model.export(attachment, to: destination) }
                    } label: { Image(systemName: "square.and.arrow.up") }
                        .buttonStyle(IconButtonStyle())
                        .help("Export a decrypted copy")
                        .accessibilityLabel("Export \(attachment.name)")
                }
            } else {
                Text("Empty").font(.serifItalic(14)).foregroundStyle(Palette.quiet)
            }
        }
        .padding(.vertical, 12)
        .overlay(alignment: .top) { Rectangle().fill(Palette.line).frame(height: 1) }
    }
}

/// Decrypts the photo when it appears and keeps it only in memory; nothing is written to disk.
struct PhotoPreview: View {
    let model: AppModel
    let attachment: Attachment
    @State private var image: NSImage?

    var body: some View {
        Group {
            if let image {
                Image(nsImage: image).resizable().scaledToFit()
            } else {
                Rectangle().fill(Palette.select)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: 180)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(Palette.line2, lineWidth: 0.5))
        .accessibilityLabel("Photo \(attachment.name)")
        .task(id: attachment.id) {
            image = model.attachmentData(attachment).flatMap(NSImage.init(data:))
        }
    }
}

/// A File column in Add Row: choose or drop a file, replace it or remove it. Picking encrypts it at once;
/// a file left behind by a cancelled sheet is removed at the next save.
struct FilePicker: View {
    let model: AppModel
    let column: Column
    @Binding var attachment: Attachment?
    @State private var isDropTargeted = false

    var body: some View {
        HStack(spacing: 10) {
            if let attachment {
                Image(systemName: attachment.symbol).foregroundStyle(Palette.text2).accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 1) {
                    Text(attachment.name).font(.system(size: 13, weight: .medium)).lineLimit(1).truncationMode(.middle)
                    Text(attachment.sizeLabel).font(.system(size: 11.5)).foregroundStyle(Palette.muted)
                }
                Spacer()
                Button("Replace…", action: choose).buttonStyle(CapsuleButtonStyle())
                Button { self.attachment = nil } label: { Image(systemName: "xmark") }
                    .buttonStyle(IconButtonStyle())
                    .accessibilityLabel("Remove \(attachment.name)")
            } else {
                Image(systemName: "tray.and.arrow.down").foregroundStyle(Palette.muted).accessibilityHidden(true)
                Text("Drop a photo or a file here, up to 50 MB").font(.system(size: 12.5)).foregroundStyle(Palette.muted)
                Spacer()
                Button("Choose File…", action: choose).buttonStyle(CapsuleButtonStyle())
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(isDropTargeted ? Palette.select : Palette.field))
        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(Palette.controlLine, style: StrokeStyle(lineWidth: 1, dash: attachment == nil ? [4, 3] : [])))
        .accessibilityElement(children: .contain)
        .accessibilityLabel(column.name)
        .onDrop(of: [.fileURL], isTargeted: $isDropTargeted) { providers in
            guard let provider = providers.first else { return false }
            _ = provider.loadObject(ofClass: URL.self) { url, _ in
                guard let url else { return }
                Task { @MainActor in attach(url) }
            }
            return true
        }
    }

    private func choose() {
        if let url = FilePanels.chooseAttachment() { attach(url) }
    }

    private func attach(_ url: URL) {
        if let sealed = model.attachFile(at: url) { attachment = sealed }
    }
}
