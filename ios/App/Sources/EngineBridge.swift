import Foundation
import UIKit

// EngineBridge — Swift -> C bridge to the engine core (libbbios.a + bbi_public.h).
// One background engine thread per launch; C-side events hop to the main thread.
enum EngineBridge {
    static var runningKey: String?

    static func jitSupported() -> Bool { bbi_jit_supported() != 0 }
    static func freeSpace() -> Int64   { bbi_dump_free_space() }

    static func start(key: String, env: [String: String],
                      onEvent: @escaping (String, String) -> Void) {
        if runningKey != nil { return }

        let slot = SettingsStore.shared.library[key]
        runningKey = key
        eventSink = onEvent

        for (k, v) in env { bbi_set_env(k, v) }
        let gameDir  = SettingsStore.shared.dumpURL.path
        let userDir  = SettingsStore.shared.savesURL.path
        let bootFile = "boot-linked.bin"                       // docs/05 flow
        let exe      = slot?.exe ?? "eboot.bin"

        if bbi_dump_looks_valid(gameDir, exe) == 0 {
            SettingsStore.shared.appendLog("STOP: dump for \(key) missing at \(gameDir)")
            runningKey = nil
            return
        }
        if jitSupported() == false {
            SettingsStore.shared.appendLog("STOP: no JIT entitlement; enable AltJIT or use TrollStore (docs/06)")
            runningKey = nil
            return
        }

        let engineEvent: bbi_event_cb = { kind, payload, _ in
            let k = String(cString: kind)
            let p = String(cString: payload)
            DispatchQueue.main.async {
                eventSink?(k, p)
                SettingsStore.shared.appendLog("[\(k)] \(p)")
            }
        }
        engineEventHandler = engineEvent   // keep the block alive across the C callback

        SettingsStore.shared.appendLog("launching \(key) from \(gameDir)")
        let rc = bbi_start_game(key, gameDir, userDir, bootFile, dispatcher, nil)
        if rc != 0 {
            SettingsStore.shared.appendLog("launch failed rc=\(rc)")
            runningKey = nil
        }
    }

    static func stop() {
        bbi_stop_game()
        runningKey = nil
        SettingsStore.shared.appendLog("stop requested")
    }

    static let defaultActions: [String] = [
        "cross", "circle", "square", "triangle", "l1", "r1", "l2", "r2",
        "l3", "r3", "share", "options", "left stick", "right stick"
    ]

    // Keep Swift closure alive across the C callback boundary:
    static var eventSink: ((String, String) -> Void)?
    static var engineEventHandler: bbi_event_cb?
}

// C-visible dispatcher referenced by bbi_start_game's function pointer:
private func dispatcher(_ kind: UnsafePointer<CChar>?, _ payload: UnsafePointer<CChar>?, _ _: UnsafeMutableRawPointer?) {
    guard let kind = kind, let payload = payload else { return }
    // hop through the retained Swift closure so capture happens safely
    EngineBridge.engineEventHandler?(kind, payload, nil)
}
