import AppKit
import CryptoKit
import Darwin
import Foundation

@MainActor
final class EmulatorModel: ObservableObject {
    struct Device: Identifiable, Hashable {
        let id: String
        let name: String
    }
    struct LibraryItem: Identifiable, Hashable {
        let url: URL
        let device: String?
        let modified: Date
        var id: URL { url }
        var name: String { url.deletingPathExtension().lastPathComponent }
    }

    @Published private(set) var romURL: URL?
    @Published private(set) var detectedDevice: String?
    @Published private(set) var isRunning = false
    @Published var networkEnabled = UserDefaults.standard.object(forKey: "networkEnabled") as? Bool ?? true {
        didSet {
            UserDefaults.standard.set(networkEnabled, forKey: "networkEnabled")
            core?.setNetworkEnabled(networkEnabled)
            if isRunning { message = networkEnabled ? "网络连接已启用。" : "网络连接已关闭。" }
        }
    }
    @Published var message = "选择 Palm OS ROM 文件后即可启动模拟器。"
    @Published private(set) var sessions: [LibraryItem] = []
    @Published private(set) var cards: [LibraryItem] = []
    @Published private(set) var mountedCardURL: URL?
    @Published private(set) var selectedSessionURL: URL?

    let devices: [Device] = [
        .init(id: "PalmPilot", name: "Palm Pilot"),
        .init(id: "PalmIII", name: "Palm III"),
        .init(id: "PalmIIIc", name: "Palm IIIc"),
        .init(id: "PalmV", name: "Palm V"),
        .init(id: "PalmVx", name: "Palm Vx"),
        .init(id: "PalmM100", name: "Palm m100"),
        .init(id: "PalmM105", name: "Palm m105"),
        .init(id: "PalmM500", name: "Palm m500"),
        .init(id: "PalmM505", name: "Palm m505"),
        .init(id: "PalmM515", name: "Palm m515"),
        .init(id: "PalmM125", name: "Palm m125"),
        .init(id: "PalmM130", name: "Palm m130"),
        .init(id: "HandEra330", name: "HandEra 330"),
        .init(id: "PEG-S300", name: "Sony CLIÉ S300"),
        .init(id: "PEG-S500C", name: "Sony CLIÉ S500C")
    ]

    var detectedDeviceName: String {
        guard let detectedDevice else { return "未识别设备" }
        return devices.first(where: { $0.id == detectedDevice })?.name ?? detectedDevice
    }
    var sourceName: String {
        selectedSessionURL == nil ? (romURL?.lastPathComponent ?? "未选择 ROM") : "\(detectedDeviceName) 会话"
    }

    private weak var displayView: NSView?
    private var core: EmbeddedCore?
    private var timer: Timer?
    private var activeSessionURL: URL?
    private var pendingBrowserInstall = false
    private var pendingKeys: [Int] = []
    private var lastSaveAt = Date()

    init() {
        if let bundled = Bundle.main.resourceURL?.appendingPathComponent("Palm-m515-4.1-en.rom"),
           FileManager.default.fileExists(atPath: bundled.path) {
            if let device = try? EmbeddedCore().detectDevice(rom: bundled) {
                romURL = bundled
                detectedDevice = device
                message = "已识别 \(detectedDeviceName)，可直接启动。"
            } else {
                message = "内置 ROM 无法识别。"
            }
        }
        refreshLibrary()
    }

    func attach(_ view: NSView) { displayView = view }

    func pen(x: Int, y: Int, down: Bool) { core?.pen(x: x, y: y, down: down) }
    func key(_ code: Int) {
        if isRunning { pendingKeys.append(code) }
    }
    func hardwareButton(_ id: Int32, down: Bool) { core?.button(id, down: down) }
    func hotSync() {
        guard let core else { return }
        core.button(7, down: true)
        core.button(7, down: false)
        message = "已启动设备端 HotSync；桌面同步服务需另行配置。"
    }
    func reset() {
        guard let core else { return }
        core.reset()
        message = "Palm OS 正在软重置。"
    }
    func screenshot() {
        guard isRunning, let display = displayView as? PalmDisplayView,
              let data = display.screenshotPNG() else {
            message = "当前没有可保存的画面。"
            return
        }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.png]
        panel.canCreateDirectories = true
        let timestamp = ISO8601DateFormatter().string(from: Date()).replacingOccurrences(of: ":", with: "-")
        panel.nameFieldStringValue = "Palm OS \(timestamp).png"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try data.write(to: url, options: .atomic)
            message = "截图已保存：\(url.lastPathComponent)"
        } catch {
            message = "保存截图失败：\(error.localizedDescription)"
        }
    }
    func saveNow() {
        guard let core, let activeSessionURL else { return }
        let sessionSaved = core.save(to: activeSessionURL)
        let cardSaved = mountedCardURL.map { core.saveCard(to: $0) } ?? true
        message = sessionSaved && cardSaved ? "会话已保存。" : "保存会话或存储卡失败。"
        lastSaveAt = Date()
        refreshLibrary()
    }

    func installDatabases() {
        guard let core else { return }
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.data]
        panel.allowsOtherFileTypes = true
        panel.allowsMultipleSelection = true
        panel.message = "选择要安装的 PRC 或 PDB 文件"
        guard panel.runModal() == .OK else { return }
        var success = 0
        var rebootRequired = false
        var failures: [String] = []
        for url in panel.urls {
            guard ["prc", "pdb"].contains(url.pathExtension.lowercased()) else {
                failures.append(url.lastPathComponent)
                continue
            }
            let result = core.installDatabase(url)
            if result == 1 || result == 2 { success += 1; rebootRequired = rebootRequired || result == 2 }
            else { failures.append(url.lastPathComponent) }
        }
        message = failures.isEmpty
            ? (rebootRequired ? "已安装 \(success) 个，需软重置。" : "已安装 \(success) 个 Palm 数据库。")
            : "已安装 \(success) 个；失败：\(failures.joined(separator: "、"))"
    }

    func refreshLibrary() {
        let manager = FileManager.default
        let sessionRoot = supportDirectory.appendingPathComponent("Sessions", isDirectory: true)
        let cardRoot = supportDirectory.appendingPathComponent("Cards", isDirectory: true)
        let core = try? EmbeddedCore()
        sessions = (try? manager.contentsOfDirectory(at: sessionRoot, includingPropertiesForKeys: [.contentModificationDateKey]))?
            .filter { $0.pathExtension.lowercased() == "img" }
            .map { url in
                let date = (try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
                return LibraryItem(url: url, device: core?.detectDevice(rom: url), modified: date)
            }
            .sorted { $0.modified > $1.modified } ?? []
        cards = (try? manager.contentsOfDirectory(at: cardRoot, includingPropertiesForKeys: [.contentModificationDateKey]))?
            .filter { $0.pathExtension.lowercased() == "img" }
            .map { url in
                let date = (try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
                return LibraryItem(url: url, device: nil, modified: date)
            }
            .sorted { $0.modified > $1.modified } ?? []
    }

    func openSession(_ item: LibraryItem) {
        guard let device = item.device else { message = "会话镜像无法识别。"; return }
        if isRunning { stop() }
        selectedSessionURL = item.url
        mountedCardURL = nil
        detectedDevice = device
        launch()
    }

    func importSession() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.data]
        panel.allowsOtherFileTypes = true
        panel.message = "选择 Cloudpilot 会话镜像（.img）"
        guard panel.runModal() == .OK, let source = panel.url else { return }
        guard (try? EmbeddedCore().detectDevice(rom: source)) != nil else {
            message = "无法识别此会话镜像。"
            return
        }
        do {
            let root = supportDirectory.appendingPathComponent("Sessions", isDirectory: true)
            try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
            let destination = root.appendingPathComponent("\(source.deletingPathExtension().lastPathComponent)-\(UUID().uuidString.prefix(6)).img")
            try FileManager.default.copyItem(at: source, to: destination)
            refreshLibrary()
            message = "会话已导入。"
        } catch { message = "导入会话失败：\(error.localizedDescription)" }
    }

    func duplicateSession() {
        guard isRunning, let activeSessionURL else { return }
        saveNow()
        do {
            let destination = supportDirectory.appendingPathComponent("Sessions", isDirectory: true)
                .appendingPathComponent("\(detectedDevice ?? "Palm")-\(UUID().uuidString.prefix(8)).img")
            try FileManager.default.copyItem(at: activeSessionURL, to: destination)
            selectedSessionURL = destination
            self.activeSessionURL = destination
            if let mountedCardURL {
                UserDefaults.standard.set(mountedCardURL.path, forKey: "card:\(destination.path)")
            }
            refreshLibrary()
            message = "已创建会话副本。"
        } catch { message = "复制会话失败：\(error.localizedDescription)" }
    }

    func exportSession(_ item: LibraryItem) {
        if activeSessionURL == item.url { saveNow() }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.data]
        panel.nameFieldStringValue = item.url.lastPathComponent
        guard panel.runModal() == .OK, let destination = panel.url else { return }
        do {
            try Data(contentsOf: item.url).write(to: destination, options: .atomic)
            message = "会话已导出。"
        } catch { message = "导出失败：\(error.localizedDescription)" }
    }

    func deleteSession(_ item: LibraryItem) {
        if activeSessionURL == item.url { stop() }
        if selectedSessionURL == item.url {
            selectedSessionURL = nil
            detectedDevice = romURL.flatMap { try? EmbeddedCore().detectDevice(rom: $0) }
            mountedCardURL = nil
        }
        do {
            try FileManager.default.trashItem(at: item.url, resultingItemURL: nil)
            UserDefaults.standard.removeObject(forKey: "card:\(item.url.path)")
            refreshLibrary()
            message = "会话已移到废纸篓。"
        } catch { message = "删除失败：\(error.localizedDescription)" }
    }

    func importCard() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.data]
        panel.allowsOtherFileTypes = true
        panel.message = "选择存储卡镜像（.img）"
        guard panel.runModal() == .OK, let source = panel.url else { return }
        do {
            let size = (try source.resourceValues(forKeys: [.fileSizeKey])).fileSize ?? 0
            guard size > 0, size % 512 == 0, size <= 128 * 1024 * 1024 else {
                message = "存储卡镜像大小必须是 512 字节的倍数，且不超过 128 MB。"
                return
            }
            let root = supportDirectory.appendingPathComponent("Cards", isDirectory: true)
            try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
            let destination = root.appendingPathComponent("\(source.deletingPathExtension().lastPathComponent)-\(UUID().uuidString.prefix(6)).img")
            try FileManager.default.copyItem(at: source, to: destination)
            refreshLibrary()
            mountCard(destination)
        } catch { message = "导入存储卡失败：\(error.localizedDescription)" }
    }

    func createCard(sizeMB: Int) {
        do {
            let root = supportDirectory.appendingPathComponent("Cards", isDirectory: true)
            try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
            let destination = root.appendingPathComponent("空白卡-\(sizeMB)MB-\(UUID().uuidString.prefix(6)).img")
            try Data(count: sizeMB * 1024 * 1024).write(to: destination, options: .atomic)
            refreshLibrary()
            mountCard(destination)
        } catch { message = "创建存储卡失败：\(error.localizedDescription)" }
    }

    func exportCard(_ item: LibraryItem) {
        if mountedCardURL == item.url, let core { _ = core.saveCard(to: item.url) }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.data]
        panel.nameFieldStringValue = item.url.lastPathComponent
        guard panel.runModal() == .OK, let destination = panel.url else { return }
        do {
            try Data(contentsOf: item.url).write(to: destination, options: .atomic)
            message = "存储卡已导出。"
        } catch { message = "导出存储卡失败：\(error.localizedDescription)" }
    }

    func mountCard(_ url: URL) {
        if mountedCardURL == url { return }
        if mountedCardURL != nil { ejectCard() }
        guard mountedCardURL == nil else { return }
        if let core {
            guard core.mountCard(url) else { message = "设备不支持此存储卡镜像。"; return }
        }
        mountedCardURL = url
        if let activeSessionURL { UserDefaults.standard.set(url.path, forKey: "card:\(activeSessionURL.path)") }
        message = isRunning ? "存储卡已挂载。" : "存储卡已选定，启动后挂载。"
    }

    func ejectCard() {
        guard let url = mountedCardURL else { return }
        if let core {
            guard core.saveCard(to: url), core.unmountCard() else {
                message = "存储卡无法保存或弹出。"
                return
            }
        }
        mountedCardURL = nil
        if let activeSessionURL { UserDefaults.standard.removeObject(forKey: "card:\(activeSessionURL.path)") }
        refreshLibrary()
        message = "存储卡已弹出。"
    }

    func deleteCard(_ item: LibraryItem) {
        if mountedCardURL == item.url { ejectCard() }
        guard mountedCardURL != item.url else { return }
        do {
            try FileManager.default.trashItem(at: item.url, resultingItemURL: nil)
            refreshLibrary()
            message = "存储卡已移到废纸篓。"
        } catch { message = "删除失败：\(error.localizedDescription)" }
    }

    private var supportDirectory: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Palm OS Emulator", isDirectory: true)
    }

    func chooseROM() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.data]
        panel.allowsOtherFileTypes = true
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.message = "选择 Palm OS ROM 文件"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        guard let device = try? EmbeddedCore().detectDevice(rom: url) else {
            message = "无法识别此 ROM 对应的设备。"
            return
        }
        if isRunning { stop() }
        romURL = url
        selectedSessionURL = nil
        mountedCardURL = nil
        detectedDevice = device
        message = "已识别 \(detectedDeviceName)。"
    }

    func launch() {
        guard let romURL = selectedSessionURL ?? romURL else { message = "请先选择 ROM 文件。"; return }
        guard let detectedDevice else { message = "无法识别 ROM 对应的设备。"; return }
        guard let displayView else { message = "屏幕视图尚未就绪。"; return }
        do {
            let core = try EmbeddedCore()
            let sessionURL = try selectedSessionURL ?? sessionFile(for: romURL, device: detectedDevice)
            let existingSession = FileManager.default.fileExists(atPath: sessionURL.path)
            let image = existingSession ? sessionURL : romURL
            if mountedCardURL == nil,
               let storedPath = UserDefaults.standard.string(forKey: "card:\(sessionURL.path)"),
               FileManager.default.fileExists(atPath: storedPath) {
                mountedCardURL = URL(fileURLWithPath: storedPath)
            }
            try core.start(rom: image, device: detectedDevice, view: displayView)
            core.setNetworkEnabled(networkEnabled)
            pendingBrowserInstall = !existingSession && selectedSessionURL == nil
                && romURL.lastPathComponent == "Palm-m515-4.1-en.rom"
            self.core = core
            isRunning = true
            message = "Palm OS 正在运行。"
            if let mountedCardURL, !core.mountCard(mountedCardURL) {
                message = "存储卡未能挂载。"
                self.mountedCardURL = nil
            }
            activeSessionURL = sessionURL
            lastSaveAt = Date()
            displayView.window?.makeFirstResponder(displayView)
            timer = Timer.scheduledTimer(withTimeInterval: 1.0 / 60.0, repeats: true) { [weak self] _ in
                Task { @MainActor in
                    guard let self, let core = self.core else { return }
                    if !self.pendingKeys.isEmpty { core.key(self.pendingKeys.removeFirst()) }
                    if !core.cycle() {
                        self.stop()
                    } else if let display = self.displayView as? PalmDisplayView,
                              let frame = core.frame() {
                        display.show(frame.data, width: frame.width, height: frame.height,
                                     pitch: frame.pitch)
                    }
                    if self.pendingBrowserInstall && core.uiReady {
                        self.pendingBrowserInstall = false
                        self.installBundledBrowser(using: core)
                    }
                    if Date().timeIntervalSince(self.lastSaveAt) > 60 {
                        if let url = self.activeSessionURL { _ = core.save(to: url) }
                        if let url = self.mountedCardURL { _ = core.saveCard(to: url) }
                        self.lastSaveAt = Date()
                    }
                }
            }
        } catch {
            message = "启动失败：\(error.localizedDescription)"
            isRunning = false
        }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        if let core, let activeSessionURL { _ = core.save(to: activeSessionURL) }
        if let core, let mountedCardURL { _ = core.saveCard(to: mountedCardURL); _ = core.unmountCard() }
        core?.stop()
        core = nil
        (displayView as? PalmDisplayView)?.clear()
        activeSessionURL = nil
        pendingBrowserInstall = false
        pendingKeys.removeAll()
        isRunning = false
        message = "模拟器已停止。"
        refreshLibrary()
    }

    private func sessionFile(for rom: URL, device: String) throws -> URL {
        let digest = SHA256.hash(data: try Data(contentsOf: rom))
            .map { String(format: "%02x", $0) }.joined()
        let root = supportDirectory.appendingPathComponent("Sessions", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root.appendingPathComponent("\(device)-\(digest).img")
    }

    private func installBundledBrowser(using core: EmbeddedCore) {
        guard let resources = Bundle.main.resourceURL else { return }
        var installed = 0
        for name in ["sslplus_1.0.7i", "EudoraWeb_2.1"] {
            let file = resources.appendingPathComponent("\(name).prc")
            if FileManager.default.fileExists(atPath: file.path),
               [1, 2].contains(core.installDatabase(file)) { installed += 1 }
        }
        message = installed == 2 ? "已安装 EudoraWeb 浏览器，网络可用。" : "浏览器自动安装未完成，可手动安装 PRC。"
    }
}

private final class EmbeddedCore {
    typealias Start = @convention(c) (UnsafePointer<CChar>?, UnsafePointer<CChar>?, UnsafeMutableRawPointer?) -> UnsafePointer<CChar>?
    typealias Cycle = @convention(c) () -> Bool
    typealias Stop = @convention(c) () -> Void
    typealias Size = @convention(c) (UnsafeMutablePointer<Int32>?, UnsafeMutablePointer<Int32>?, UnsafeMutablePointer<Int32>?) -> Void
    typealias CopyFrame = @convention(c) (UnsafeMutableRawPointer?, Int) -> Bool
    typealias Pen = @convention(c) (Int32, Int32, Bool) -> Void
    typealias Key = @convention(c) (Int32) -> Void
    typealias Button = @convention(c) (Int32, Bool) -> Void
    typealias Save = @convention(c) (UnsafePointer<CChar>?) -> Bool
    typealias DetectDevice = @convention(c) (UnsafePointer<CChar>?) -> UnsafePointer<CChar>?
    typealias Reset = @convention(c) () -> Void
    typealias InstallDatabase = @convention(c) (UnsafePointer<CChar>?) -> Int32
    typealias CardPathAction = @convention(c) (UnsafePointer<CChar>?) -> Bool
    typealias CardAction = @convention(c) () -> Bool
    typealias SetNetwork = @convention(c) (Bool) -> Void
    typealias UIReady = @convention(c) () -> Bool

    private let handle: UnsafeMutableRawPointer
    private let startFunction: Start
    private let cycleFunction: Cycle
    private let stopFunction: Stop
    private let sizeFunction: Size
    private let copyFrameFunction: CopyFrame
    private let penFunction: Pen
    private let keyFunction: Key
    private let buttonFunction: Button
    private let saveFunction: Save
    private let detectDeviceFunction: DetectDevice
    private let resetFunction: Reset
    private let installDatabaseFunction: InstallDatabase
    private let mountCardFunction: CardPathAction
    private let saveCardFunction: CardPathAction
    private let unmountCardFunction: CardAction
    private let setNetworkFunction: SetNetwork
    private let uiReadyFunction: UIReady
    private var started = false

    init() throws {
        let bundled = Bundle.main.privateFrameworksURL?.appendingPathComponent("libcloudpilot-embed.dylib")
        let workingDirectory = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        let development = workingDirectory.appendingPathComponent("src/cloudpilot/libcloudpilot-embed.dylib")
        let developmentFromMacApp = workingDirectory.appendingPathComponent("../src/cloudpilot/libcloudpilot-embed.dylib")
        let library = [bundled, development, developmentFromMacApp].compactMap { $0 }
            .first { FileManager.default.fileExists(atPath: $0.path) }
        guard let library, let handle = dlopen(library.path, RTLD_NOW | RTLD_LOCAL) else {
            throw CoreError.message(dlerror().map { String(cString: $0) } ?? "找不到内嵌模拟器核心")
        }
        self.handle = handle
        guard let start = dlsym(handle, "cloudpilot_embedded_start"),
              let cycle = dlsym(handle, "cloudpilot_embedded_cycle"),
              let stop = dlsym(handle, "cloudpilot_embedded_stop"),
              let size = dlsym(handle, "cloudpilot_embedded_size"),
              let copy = dlsym(handle, "cloudpilot_embedded_copy_frame"),
              let pen = dlsym(handle, "cloudpilot_embedded_pen"),
              let key = dlsym(handle, "cloudpilot_embedded_key"),
              let button = dlsym(handle, "cloudpilot_embedded_button"),
              let detectDevice = dlsym(handle, "cloudpilot_embedded_detect_device"),
              let reset = dlsym(handle, "cloudpilot_embedded_reset"),
              let installDatabase = dlsym(handle, "cloudpilot_embedded_install_database"),
              let mountCard = dlsym(handle, "cloudpilot_embedded_mount_card"),
              let saveCard = dlsym(handle, "cloudpilot_embedded_save_card"),
              let unmountCard = dlsym(handle, "cloudpilot_embedded_unmount_card"),
              let setNetwork = dlsym(handle, "cloudpilot_embedded_set_network"),
              let uiReady = dlsym(handle, "cloudpilot_embedded_ui_ready"),
              let save = dlsym(handle, "cloudpilot_embedded_save") else {
            dlclose(handle)
            throw CoreError.message("模拟器核心缺少内嵌接口")
        }
        startFunction = unsafeBitCast(start, to: Start.self)
        cycleFunction = unsafeBitCast(cycle, to: Cycle.self)
        stopFunction = unsafeBitCast(stop, to: Stop.self)
        sizeFunction = unsafeBitCast(size, to: Size.self)
        copyFrameFunction = unsafeBitCast(copy, to: CopyFrame.self)
        penFunction = unsafeBitCast(pen, to: Pen.self)
        keyFunction = unsafeBitCast(key, to: Key.self)
        buttonFunction = unsafeBitCast(button, to: Button.self)
        saveFunction = unsafeBitCast(save, to: Save.self)
        detectDeviceFunction = unsafeBitCast(detectDevice, to: DetectDevice.self)
        resetFunction = unsafeBitCast(reset, to: Reset.self)
        installDatabaseFunction = unsafeBitCast(installDatabase, to: InstallDatabase.self)
        mountCardFunction = unsafeBitCast(mountCard, to: CardPathAction.self)
        saveCardFunction = unsafeBitCast(saveCard, to: CardPathAction.self)
        unmountCardFunction = unsafeBitCast(unmountCard, to: CardAction.self)
        setNetworkFunction = unsafeBitCast(setNetwork, to: SetNetwork.self)
        uiReadyFunction = unsafeBitCast(uiReady, to: UIReady.self)
    }

    func start(rom: URL, device: String, view: NSView) throws {
        let error = rom.path.withCString { romPath in
            device.withCString { deviceId in
                startFunction(romPath, deviceId, Unmanaged.passUnretained(view).toOpaque())
            }
        }
        if let error { throw CoreError.message(String(cString: error)) }
        started = true
    }

    func cycle() -> Bool { cycleFunction() }

    func frame() -> (data: Data, width: Int, height: Int, pitch: Int)? {
        var width: Int32 = 0, height: Int32 = 0, pitch: Int32 = 0
        sizeFunction(&width, &height, &pitch)
        guard width > 0, height > 0, pitch >= width * 4 else { return nil }
        var data = Data(count: Int(pitch * height))
        let copied = data.withUnsafeMutableBytes { buffer in
            copyFrameFunction(buffer.baseAddress, buffer.count)
        }
        return copied ? (data, Int(width), Int(height), Int(pitch)) : nil
    }

    func pen(x: Int, y: Int, down: Bool) { penFunction(Int32(x), Int32(y), down) }
    func key(_ code: Int) { keyFunction(Int32(code)) }
    func button(_ id: Int32, down: Bool) { buttonFunction(id, down) }
    func reset() { resetFunction() }
    func setNetworkEnabled(_ enabled: Bool) { setNetworkFunction(enabled) }
    var uiReady: Bool { uiReadyFunction() }
    func installDatabase(_ url: URL) -> Int32 { url.path.withCString { installDatabaseFunction($0) } }
    func mountCard(_ url: URL) -> Bool { url.path.withCString { mountCardFunction($0) } }
    func saveCard(to url: URL) -> Bool { url.path.withCString { saveCardFunction($0) } }
    func unmountCard() -> Bool { unmountCardFunction() }
    func detectDevice(rom: URL) -> String? {
        rom.path.withCString { path in
            detectDeviceFunction(path).map { String(cString: $0) }
        }
    }
    func save(to url: URL) -> Bool { url.path.withCString { saveFunction($0) } }

    func stop() {
        if started { stopFunction(); started = false }
    }

    deinit {
        stop()
        dlclose(handle)
    }

    private enum CoreError: LocalizedError {
        case message(String)
        var errorDescription: String? {
            if case let .message(value) = self { return value }
            return nil
        }
    }
}
