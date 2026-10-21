import SwiftUI
import UIKit

// SettingsStore — persisted launcher state. Writes the SAME bbport.ini contract the PC
// launcher uses so the engine needs zero iOS-specific ini config changes.
@MainActor
final class SettingsStore: ObservableObject {
    static let shared = SettingsStore()

    struct Slot: Codable {
        var title: String
        var ready: Bool
        var exe: String
    }

    @Published var library: [String: Slot]
    @Published var fps: String
    @Published var upscaler: String
    @Published var sharpen: Double
    @Published var reactive: Bool
    @Published var outputRes: String
    @Published var fpsCounter: Bool
    @Published var touchpadOverlay: Bool
    @Published var stickRadius: Double
    @Published var dmemMB: Int
    @Published var gpuLog: String
    @Published var fexTso: Bool
    @Published var envOverrides: [String: String]
    @Published var logLines: [String]

    private var bindings: [String: String]
    private let defaults = UserDefaults.standard

    private init() {
        library = [
            "u1": Slot(title: "Drake's Fortune", ready: false, exe: "eboot.bin"),
            "u2": Slot(title: "Among Thieves",  ready: false, exe: "big2-ps4_Shipping.elf"),
            "u3": Slot(title: "Drake's Deception", ready: false, exe: "big3-ps4_Shipping.elf"),
        ]
        fps = defaults.string(forKey: "fps") ?? "60"
        upscaler = defaults.string(forKey: "upscaler") ?? "fsr3"
        sharpen = defaults.object(forKey: "sharpen") == nil ? 0.55 : defaults.double(forKey: "sharpen")
        reactive = defaults.object(forKey: "reactive") == nil ? true : defaults.bool(forKey: "reactive")
        outputRes = defaults.string(forKey: "outputRes") ?? ""
        fpsCounter = defaults.bool(forKey: "fpsCounter")
        touchpadOverlay = defaults.object(forKey: "touchpadOverlay") == nil ? true : defaults.bool(forKey: "touchpadOverlay")
        stickRadius = defaults.object(forKey: "stickRadius") == nil ? 70 : defaults.double(forKey: "stickRadius")
        dmemMB = defaults.integer(forKey: "dmemMB"); if dmemMB == 0 { dmemMB = 4096 }
        gpuLog = defaults.string(forKey: "gpuLog") ?? "warning"
        fexTso = defaults.bool(forKey: "fexTso")
        bindings = (defaults.dictionary(forKey: "bindings") as? [String: String]) ?? [:]
        if let pairs = defaults.dictionary(forKey: "envOverrides") as? [String: String] {
            envOverrides = pairs
        }
        logLines = []

        if let raw = defaults.data(forKey: "library"),
           let dec = try? JSONDecoder().decode([String: Slot].self, from: raw) {
            for (key, stored) in dec { self.library[key] = stored }
        }
        refreshDumpReadiness()
    }

    // MARK: persistence

    func persist() {
        defaults.set(fps, forKey: "fps")
        defaults.set(upscaler, forKey: "upscaler")
        defaults.set(sharpen, forKey: "sharpen")
        defaults.set(reactive, forKey: "reactive")
        defaults.set(outputRes, forKey: "outputRes")
        defaults.set(fpsCounter, forKey: "fpsCounter")
        defaults.set(touchpadOverlay, forKey: "touchpadOverlay")
        defaults.set(stickRadius, forKey: "stickRadius")
        defaults.set(dmemMB, forKey: "dmemMB")
        defaults.set(gpuLog, forKey: "gpuLog")
        defaults.set(fexTso, forKey: "fexTso")
        defaults.set(bindings, forKey: "bindings")
        defaults.set(envOverrides, forKey: "envOverrides")
        if let data = try? JSONEncoder().encode(library) { defaults.set(data, forKey: "library") }
    }

    // MARK: paths

    var documentsURL: URL { FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0] }
    var savesURL: URL { documentsURL.appendingPathComponent("user") }
    var dumpURL: URL { documentsURL.appendingPathComponent("dump") }

    func refreshDumpReadiness() {
        let exePaths = library
        for (key, slot) in exePaths {
            let exePath = dumpURL.appendingPathComponent(slot.exe).path
            let dataDir = dumpURL.appendingPathComponent("\(key == "u1" ? "u1" : key)data")
            var ready = FileManager.default.fileExists(atPath: exePath)
            if ready { ready = FileManager.default.fileExists(atPath: dataDir.path) }
            library[key]?.ready = ready
        }
        persist()
    }

    func coverImage(_ key: String) -> UIImage? {
        let icon = dumpURL.appendingPathComponent("sce_sys/icon0.png")
        if FileManager.default.fileExists(atPath: icon.path),
           let ui = UIImage(contentsOfFile: icon.path) { return ui }
        if let bundled = Bundle.main.path(forResource: "cover_\(key)", ofType: "png"),
           let ui = UIImage(contentsOfFile: bundled) { return ui }
        return nil
    }

    // MARK: engine contract (upstream run.py env names, unchanged)

    func engineEnvironment() -> [String: String] {
        var env: [String: String] = [
            "BB_GAME_DIR": dumpURL.path,
            "BB_USER_DIR": savesURL.path,
            "BB_CONFIG": writeBBPortIni(),
            "BB_FPS": fps,
            "BB_UPSCALER": upscaler,
            "BB_FSR_SHARPNESS": String(format: "%.2f", sharpen),
            "BB_REACTIVE": reactive ? "1" : "0",
            "BB_OUTPUT_RES": outputRes,
            "BB_FRAME_STATS": fpsCounter ? "1" : "0",
            "BB_DMEM_MB": "\(dmemMB)",
            "BB_GPU_LOG": gpuLog,
            "BB_FEX_TSO": fexTso ? "1" : "0",
            // Uncharted shader-key hooks (run.py contract from the PC port):
            "BB_VELOCITY_PS": "f4b18264",
            "BB_UPSCALE_BEFORE_CS": "aec539f0",
            "BB_HUDLESS_PS": "484cdbf5",
        ]
        for (k, v) in envOverrides { env[k] = v }
        return env
    }

    func writeBBPortIni() -> String {
        let path = documentsURL.appendingPathComponent("bbport.ini")
        var lines: [String] = ["[bbport]"]
        lines.append("upscaler=\(upscaler)")
        lines.append("sharp=\(String(format: "%.2f", sharpen))")
        lines.append("jitter=1")
        lines.append("reactive=\(reactive ? 1 : 0)")
        if !outputRes.isEmpty { lines.append("output_res=\(outputRes)") }
        try? lines.joined(separator: "\n").write(to: path, atomically: true, encoding: .utf8)
        return path.path
    }

    // MARK: caches

    func clearShaderCache() {
        try? FileManager.default.removeItem(at: savesURL.appendingPathComponent("shader_cache"))
        appendLog("shader cache cleared")
    }
    func clearFexProfile() {
        try? FileManager.default.removeItem(at: savesURL.appendingPathComponent("fex-cache"))
        appendLog("FEX AOT profile cleared")
    }

    // MARK: env overrides UI

    func promptEnvOverride(on vc: UIViewController) {
        let alert = UIAlertController(title: "BB_ override", message: nil, preferredStyle: .alert)
        alert.addTextField { $0.placeholder = "KEY" }
        alert.addTextField { $0.placeholder = "VALUE" }
        alert.addAction(UIAlertAction(title: "Save", style: .default) { [weak self] _ in
            if let k = alert.textFields?[0].text, let v = alert.textFields?[1].text, !k.isEmpty {
                self?.envOverrides[k] = v
                self?.persist()
            }
        })
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel, handler: nil))
        vc.present(alert, animated: true)
    }

    // MARK: log

    func appendLog(_ line: String) {
        let stamp = DateFormatter.localizedString(from: Date(), dateStyle: .none, timeStyle: .short)
        logLines.append("\(stamp)  \(line)")
        if logLines.count > 2000 {
            logLines.removeFirst(logLines.count - 1600)
        }
    }

    // MARK: input.ini (same keys the PC runtime reads)

    static let defaultActions: [String] = [
        "cross", "circle", "square", "triangle", "l1", "r1", "l2", "r2",
        "l3", "r3", "share", "options", "left stick", "right stick"
    ]

    func binding(_ action: String) -> String { bindings[action] ?? "—" }
    func setBinding(_ action: String, _ value: String) {
        bindings[action] = value
        persist()
        writeInputIni()
    }

    var inputIniURL: URL { documentsURL.appendingPathComponent("input.ini") }

    func writeInputIni() {
        var lines: [String] = ["[pad]"]
        for action in Self.defaultActions {
            if let pad = bindings[action] { lines.append("pad.\(action)=\(pad)") }
        }
        try? lines.joined(separator: "\n").write(to: inputIniURL, atomically: true, encoding: .utf8)
    }
}
