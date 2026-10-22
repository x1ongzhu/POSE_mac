import AppKit
import SwiftUI

@main
struct CloudpilotMacApp: App {
    @StateObject private var model = EmulatorModel()

    var body: some Scene {
        Window("Palm OS", id: "main") {
            ContentView(model: model)
                .onDisappear { model.stop() }
        }
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("新建窗口", action: openNewWindow)
                    .keyboardShortcut("n")
                Button("打开 ROM…", action: model.chooseROM)
                    .keyboardShortcut("o")
            }
            CommandMenu("模拟器") {
                Button(model.isRunning ? "停止" : "启动", action: model.isRunning ? model.stop : model.launch)
                    .keyboardShortcut("r")
                Button("保存会话", action: model.saveNow)
                    .keyboardShortcut("s")
                    .disabled(!model.isRunning)
                Divider()
                Button("HotSync", action: model.hotSync)
                    .disabled(!model.isRunning)
                Button("软重置", action: model.reset)
                    .disabled(!model.isRunning)
                Button("保存截图…", action: model.screenshot)
                    .keyboardShortcut("s", modifiers: [.command, .shift])
                    .disabled(!model.isRunning)
                Divider()
                Button("安装 PRC/PDB…", action: model.installDatabases)
                    .keyboardShortcut("i")
                    .disabled(!model.isRunning)
            }
        }
    }

    private func openNewWindow() {
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.createsNewApplicationInstance = true
        configuration.activates = true
        configuration.arguments = ["--new-window"]
        NSWorkspace.shared.openApplication(at: Bundle.main.bundleURL, configuration: configuration) { _, error in
            if let error {
                DispatchQueue.main.async {
                    model.message = "无法新建窗口：\(error.localizedDescription)"
                }
            }
        }
    }
}
