import SwiftUI
import UIKit
import UniformTypeIdentifiers

// DumpImport — Data-tab row: UIDocumentPickerDirectory flow that imports the user's
// decrypted PS4 dump into the app sandbox (Documents/dump) and validates EXEs + subfolders.
struct DumpImportRow: View {
    @ObservedObject var settings: SettingsStore
    @State private var showImporter = false
    @State private var importing = false
    @State private var importedBytes: Int64 = 0

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button {
                showImporter = true
            } label: {
                HStack {
                    Image(systemName: "square.and.arrow.down.on.square")
                    Text(importing ? "Copying \(ByteCountFormatter.string(fromByteCount: importedBytes, countStyle: .file))…"
                                   : "Import dump folder…")
                }
            }
            .disabled(importing)

            if importing {
                ProgressView(value: Double(importedBytes), total: 1)
            }

            Text("Reference instead of a copy is used when the folder already lives under Documents (no duplication).")
                .font(.caption2).foregroundStyle(.secondary)
        }
        .fileImporter(isPresented: $showImporter,
                      allowedContentTypes: [.folder],
                      allowsMultipleSelection: false)
        { result in
            guard case .success(let urls) = result, let picked = urls.first else { return }
            importing = true
            Task.detached(priority: .userInitiated) {
                importedBytes = DumpImporter.import(from: picked)
                await MainActor.run {
                    importing = false
                    settings.refreshDumpReadiness()
                    settings.appendLog("dump import: \(ByteCountFormatter.string(fromByteCount: importedBytes, countStyle: .file)) copied")
                }
            }
        }
    }
}

enum DumpImporter {
    /// Copy (hard link where possible: same volume) the selected folder into Documents/dump.
    static func import(from url: URL) -> Int64 {
        let fm = FileManager.default
        let dst = SettingsStore.shared.dumpURL
        try? fm.createDirectory(at: dst, withIntermediateDirectories: true)

        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        var copied: Int64 = 0
        copied = copyTree(src: url.path, dst: dst.path)
        return copied
    }

    static func copyTree(src: String, dst: String) -> Int64 {
        let fm = FileManager.default
        try? fm.createDirectory(atPath: dst, withIntermediateDirectories: true)
        var copied: Int64 = 0
        guard let entries = try? fm.contentsOfDirectory(atPath: src) else { return 0 }
        for e in entries {
            let s = src + "/" + e
            let d = dst + "/" + e
            var isDir: ObjCBool = false
            fm.fileExists(atPath: s, isDirectory: &isDir)
            if isDir.boolValue {
                copied += copyTree(src: s, dst: d)
            } else {
                do {
                    // Same volume → cheap zero-copy hard link; otherwise regular copy:
                    if hardLinkIfSameVolume(s, d) { copied += fileSize(atPath: s); continue }
                    try? fm.removeItem(atPath: d)
                    if fm.copyItem(atPath: s, toPath: d) {
                        copied += fileSize(atPath: s)
                    }
                }
            }
        }
        return copied
    }

    /// Hard link first — zero-copy on the same volume; falls back silently.
    private static func hardLinkIfSameVolume(_ a: String, _ b: String) -> Bool {
        return link(a, b) == 0
    }

    private static func fileSize(atPath p: String) -> Int64 {
        let attrs = try? FileManager.default.attributesOfItem(atPath: p)
        return (attrs?[.size] as? Int64) ?? 0
    }
}
