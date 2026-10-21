import SwiftUI

@main
struct UnchartedApp: App {
    var body: some Scene {
        WindowGroup {
            RootView()
                .preferredColorScheme(.dark)
        }
    }
}

// MARK: - RootView with sidebar navigation

struct RootView: View {
    var body: some View {
        TabView {
            LibraryScreen()
                .tabItem { Label("Library", systemImage: "square.stack.3d.up.fill") }
            DisplayScreen()
                .tabItem { Label("Display", systemImage: "rectangle.on.rectangle") }
            ControlsScreen()
                .tabItem { Label("Controls", systemImage: "gamecontroller.fill") }
            DataScreen()
                .tabItem { Label("Data", systemImage: "shippingbox.fill") }
            AdvancedScreen()
                .tabItem { Label("Advanced", systemImage: "gearshape.fill") }
            LogScreen()
                .tabItem { Label("Log", systemImage: "text.bubble.fill") }
        }
        .environmentObject(SettingsStore.shared)
    }
}

// MARK: - Library

struct LibraryScreen: View {
    @EnvironmentObject var settings: SettingsStore
    @State private var launching: String?
    @State private var jitOK: Bool = true

    var body: some View {
        NavigationStack {
            VStack(spacing: 18) {
                VStack(spacing: 4) {
                    Text("UNCHARTED").font(.system(size: 34, weight: .black, design: .serif))
                        .tracking(6)
                    Text("The Nathan Drake Collection — iOS port")
                        .font(.footnote).foregroundStyle(.secondary)
                }
                .padding(.top, 14)

                if !jitOK {
                    Label("JIT entitlement missing — enable AltJIT or use TrollStore. Games will refuse to start.",
                          systemImage: "exclamationmark.triangle.fill")
                        .font(.footnote).foregroundStyle(.red).multilineTextAlignment(.center)
                        .padding(.horizontal)
                }

                ForEach(["u1", "u2", "u3"], id: \.self) { key in
                    GameCard(key: key, ready: settings.library[key]?.ready ?? false,
                             busy: launching != nil)
                        .onTapGesture { launch(key) }
                }
                Spacer(minLength: 18)

                if let l = launching {
                    HStack(spacing: 10) {
                        ProgressView()
                        Text(l).font(.subheadline).foregroundStyle(.secondary)
                        Spacer()
                        Button("Stop") { stopGame() }.buttonStyle(.bordered)
                    }.padding(.horizontal)
                }
            }
            .navigationTitle("Library")
            .onAppear { jitOK = EngineBridge.jitSupported() }
        }
    }

    private func launch(_ key: String) {
        guard let slot = settings.library[key], slot.ready, launching == nil,
              EngineBridge.jitSupported() else { return }
        launching = "Starting \(slot.title)"
        EngineBridge.start(key: key,
                           env: settings.engineEnvironment(),
                           onEvent: { kind, payload in
            settings.appendLog("[\(kind)] \(payload)")
            if kind == "exit" { DispatchQueue.main.async { launching = nil } }
        })
    }

    private func stopGame() {
        EngineBridge.stop()
        launching = nil
    }
}

struct GameCard: View {
    @EnvironmentObject var settings: SettingsStore
    let key: String
    let ready: Bool
    let busy: Bool

    var body: some View {
        HStack(spacing: 14) {
            RoundedRectangle(cornerRadius: 12)
                .fill(LinearGradient(colors: [.orange, .brown, .black],
                                     startPoint: .topLeading, endPoint: .bottomTrailing))
                .frame(width: 74, height: 96)
                .overlay {
                    if let ui = settings.coverImage(key) {
                        Image(uiImage: ui).resizable().clipShape(RoundedRectangle(cornerRadius: 12))
                    }
                }
            VStack(alignment: .leading, spacing: 6) {
                Text(title).font(.headline)
                Text(ready ? "Ready — tap to play" : "No dump — import in the Data tab")
                    .font(.caption).foregroundStyle(ready ? .green : .secondary)
            }
            Spacer()
            Image(systemName: ready && !busy ? "play.circle.fill" : "circle.dashed")
                .font(.largeTitle).foregroundStyle(ready ? .green : .gray)
        }
        .padding().background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
        .padding(.horizontal)
    }

    var title: String { settings.library[key]?.title ?? key }
}

// MARK: - Display

struct DisplayScreen: View {
    @EnvironmentObject var settings: SettingsStore
    var body: some View {
        Form {
            Section("Frame rate") {
                Picker("FPS", selection: $settings.fps) {
                    Text("60").tag("60"); Text("90").tag("90")
                    Text("120").tag("uncap"); Text("30").tag("30")
                }.pickerStyle(.segmented)
            }
            Section("Upscaler") {
                Picker("Anti-aliasing", selection: $settings.upscaler) {
                    Text("Native TAA").tag("taa")
                    Text("FSR 3.1").tag("fsr3")
                }.pickerStyle(.segmented)
                Toggle("Reactive mask", isOn: $settings.reactive)
                Toggle("FPS counter", isOn: $settings.fpsCounter)
                VStack(alignment: .leading) {
                    Text("RCAS sharpen: \(settings.sharpen, specifier: "%.2f")")
                    Slider(value: $settings.sharpen, in: 0...1)
                }
            }
            Section("Output") {
                Picker("Resolution", selection: $settings.outputRes) {
                    Text("Auto").tag(""); Text("720p").tag("1280x720")
                    Text("1080p").tag("1920x1080"); Text("1440p").tag("2560x1440")
                }
            }
        }
    }
}

// MARK: - Controls

struct ControlsScreen: View {
    @EnvironmentObject var settings: SettingsStore
    var body: some View {
        Form {
            Section("On-screen controls") {
                Toggle("Virtual sticks + buttons", isOn: $settings.touchpadOverlay)
                VStack(alignment: .leading) {
                    Text("Stick radius: \(Int(settings.stickRadius))")
                    Slider(value: $settings.stickRadius, in: 40...140)
                }
            }
            Section("Controller (MFi)") {
                ForEach(EngineBridge.defaultActions, id: \.self) { action in
                    HStack {
                        Text(action)
                        Spacer()
                        Text(settings.binding(action))
                            .foregroundStyle(.secondary)
                            .font(.caption)
                    }
                }
                Text("Rebinding writes input.ini exactly like the PC launcher's Controls page.")
                    .font(.caption2).foregroundStyle(.secondary)
            }
        }
    }
}

// MARK: - Data (import / saves)

struct DataScreen: View {
    @EnvironmentObject var settings: SettingsStore
    @State private var freeSpace: Int64 = 0

    var body: some View {
        NavigationStack {
            List {
                Section("Import dump") {
                    DumpImportRow(settings: settings)
                    Text("Needs: eboot.bin (U1), big2-ps4_Shipping.elf (U2), big3-ps4_Shipping.elf (U3), plus sce_sys and u1data/u2data/u3data — the same folder the PC port uses. ~30–70 GB.")
                        .font(.caption).foregroundStyle(.secondary)
                    Text("Free: \(ByteCountFormatter.string(fromByteCount: freeSpace, countStyle: .file))")
                        .font(.caption2)
                }
                Section("Saves & caches") {
                    Button("Clear shader cache (first-run compile)") { settings.clearShaderCache() }
                    Button("Clear FEX AOT profile") { settings.clearFexProfile() }
                }
            }
            .navigationTitle("Data")
            .task { freeSpace = EngineBridge.freeSpace() }
        }
    }
}

// MARK: - Advanced

struct AdvancedScreen: View {
    @EnvironmentObject var settings: SettingsStore
    var body: some View {
        Form {
            Section("Runtime") {
                Stepper("Guest memory MB: \(settings.dmemMB)", value: $settings.dmemMB, in: 2048...8192, step: 1024)
                Picker("GPU log level", selection: $settings.gpuLog) {
                    Text("warning").tag("warning"); Text("info").tag("info"); Text("trace").tag("trace")
                }
                Toggle("FEX TSO (helps unstable, costs speed)", isOn: $settings.fexTso)
            }
            Section("Env overrides") {
                ForEach(Array(settings.envOverrides.keys).sorted(), id: \.self) { k in
                    Text("\(k) = \(settings.envOverrides[k] ?? "")").font(.footnote.monospaced())
                }
                Button("Add / edit override") {
                    settings.promptEnvOverride(on: topViewController())
                }
            }
            Section {
                Text("Docs: see docs/06-LIMITATIONS_FAQ.md about JIT. Statistically you want a ≥6 GB RAM iPhone and 256 GB storage.")
                    .font(.caption).foregroundStyle(.secondary)
            } footer: {
                Text("GPL-2.0+ port of SuperMedo's Windows project; not affiliated with Sony or Naughty Dog.")
            }
        }
    }
}

// MARK: - Log

/// Finds the presented view controller (used by the env-override alert).
func topViewController() -> UIViewController {
    let scene = UIApplication.shared.connectedScenes
        .compactMap { $0 as? UIWindowScene }
        .first { $0.activationState == .foregroundActive }
    var vc = scene?.keyWindow?.rootViewController
    while vc?.presentedViewController != nil { vc = vc?.presentedViewController }
    return vc ?? UIViewController()
}

struct LogScreen: View {
    @EnvironmentObject var settings: SettingsStore
    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 2) {
                    ForEach(Array(settings.logLines.enumerated()), id: \.offset) { i, line in
                        Text(line).font(.caption2.monospaced())
                            .foregroundStyle(line.contains("STOP") ? Color.red : .primary)
                            .id(i)
                    }
                }.padding(8)
            }
            .onChange(of: settings.logLines.count) { _ in
                withAnimation { proxy.scrollTo(settings.logLines.count - 1, anchor: .bottom) }
            }
            .navigationTitle("Log")
        }
    }
}
