import SwiftUI

struct ContentView: View {
    @ObservedObject var model: EmulatorModel
    @State private var showingLibrary = false

    var body: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 24)
            device
            Spacer(minLength: 24)
            statusBar
        }
        .frame(minWidth: 460, idealWidth: 500, minHeight: 650, idealHeight: 700)
        .background(Color(nsColor: .windowBackgroundColor))
        .sheet(isPresented: $showingLibrary) { LibraryView(model: model) }
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Button(action: model.chooseROM) {
                    Label("打开 ROM", systemImage: "folder")
                }
                .help("打开 Palm OS ROM…")

                Button {
                    model.installDatabases()
                } label: {
                    Label("安装 PRC/PDB", systemImage: "square.and.arrow.down")
                }
                .disabled(!model.isRunning)
                .help("安装 Palm 应用或数据库…")

                Button {
                    showingLibrary = true
                } label: {
                    Label("资源库", systemImage: "square.stack")
                }
                .help("管理会话与存储卡")

                Button(action: model.isRunning ? model.stop : model.launch) {
                    Label(model.isRunning ? "停止" : "启动", systemImage: model.isRunning ? "stop.fill" : "play.fill")
                }
                .buttonStyle(.borderedProminent)
                .help(model.isRunning ? "停止并保存会话" : "启动 Palm OS")

                Menu {
                    Toggle("网络连接", isOn: $model.networkEnabled)
                    Divider()
                    Button("HotSync", systemImage: "arrow.triangle.2.circlepath", action: model.hotSync)
                    Button("软重置", systemImage: "restart", action: model.reset)
                    Divider()
                    Button("保存截图…", systemImage: "camera", action: model.screenshot)
                } label: {
                    Label("更多操作", systemImage: "ellipsis.circle")
                }
                .disabled(!model.isRunning)
                .help("网络连接、HotSync、重置与截图")
            }
        }
    }

    private var device: some View {
        VStack(spacing: 0) {
            HStack {
                Text("palm")
                    .font(.system(size: 18, weight: .semibold, design: .rounded))
                    .tracking(-1.5)
                    .foregroundStyle(.secondary)
                Spacer()
                Text(model.detectedDeviceName)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if model.isRunning && model.networkEnabled {
                    Image(systemName: "network")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .help("原生网络连接已启用")
                }
                Circle()
                    .fill(model.isRunning ? Color.green : Color.gray.opacity(0.45))
                    .frame(width: 7, height: 7)
                    .accessibilityLabel(model.isRunning ? "正在运行" : "已停止")
            }
            .padding(.horizontal, 5)
            .padding(.bottom, 14)

            ZStack {
                EmulatorDisplay(model: model)
                    .frame(width: 320, height: 440)
                    .background(.black)
                if !model.isRunning {
                    VStack(spacing: 10) {
                        Image(systemName: "power")
                            .font(.system(size: 25, weight: .light))
                        Text("点击工具栏中的启动按钮")
                            .font(.callout)
                    }
                    .foregroundStyle(.white.opacity(0.72))
                    .allowsHitTesting(false)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 5))
            .overlay(RoundedRectangle(cornerRadius: 5).strokeBorder(.black.opacity(0.25)))

            HStack(spacing: 11) {
                hardwareButton(0, "日历", "calendar")
                hardwareButton(1, "通讯录", "person.crop.rectangle")
                Spacer(minLength: 0)
                VStack(spacing: 2) {
                    hardwareButton(4, "向上", "chevron.up", compact: true)
                    hardwareButton(5, "向下", "chevron.down", compact: true)
                }
                Spacer(minLength: 0)
                hardwareButton(2, "待办事项", "checklist")
                hardwareButton(3, "备忘录", "note.text")
            }
            .padding(.top, 17)
        }
        .padding(18)
        .frame(width: 356)
        .background(
            RoundedRectangle(cornerRadius: 24)
                .fill(Color(nsColor: .controlBackgroundColor))
                .shadow(color: .black.opacity(0.10), radius: 24, y: 10)
        )
        .overlay(RoundedRectangle(cornerRadius: 24).strokeBorder(.primary.opacity(0.10)))
    }

    private func hardwareButton(_ id: Int32, _ title: String, _ symbol: String, compact: Bool = false) -> some View {
        Button {
            model.hardwareButton(id, down: true)
            model.hardwareButton(id, down: false)
        } label: {
            Image(systemName: symbol)
                .font(.system(size: compact ? 11 : 15, weight: .medium))
                .frame(width: compact ? 38 : 42, height: compact ? 23 : 38)
                .contentShape(RoundedRectangle(cornerRadius: compact ? 8 : 13))
        }
        .buttonStyle(.plain)
        .background(.quaternary.opacity(0.55), in: RoundedRectangle(cornerRadius: compact ? 8 : 13))
        .overlay(RoundedRectangle(cornerRadius: compact ? 8 : 13).strokeBorder(.primary.opacity(0.10)))
        .disabled(!model.isRunning)
        .help(title)
        .accessibilityLabel(title)
    }

    private var statusBar: some View {
        HStack(spacing: 10) {
            Image(systemName: "internaldrive")
                .foregroundStyle(.secondary)
            Text(model.sourceName)
                .lineLimit(1)
                .truncationMode(.middle)
                .help(model.selectedSessionURL?.path ?? model.romURL?.path ?? "")
            Spacer(minLength: 12)
            Circle()
                .fill(model.isRunning ? Color.green : Color.secondary.opacity(0.5))
                .frame(width: 6, height: 6)
            Text(model.message)
                .lineLimit(1)
                .truncationMode(.tail)
                .help(model.message)
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .padding(.horizontal, 18)
        .frame(height: 36)
        .frame(maxWidth: .infinity)
        .background(.bar)
        .overlay(alignment: .top) { Divider() }
    }
}

private struct LibraryView: View {
    @ObservedObject var model: EmulatorModel
    @Environment(\.dismiss) private var dismiss
    @State private var tab = 0
    @State private var selectedSession: EmulatorModel.LibraryItem?
    @State private var selectedCard: EmulatorModel.LibraryItem?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("资源库").font(.title2.weight(.semibold))
                Spacer()
                Button("完成") { dismiss() }
            }
            Picker("资源", selection: $tab) {
                Text("会话").tag(0)
                Text("存储卡").tag(1)
            }
            .pickerStyle(.segmented)
            .labelsHidden()

            if tab == 0 {
                List {
                    ForEach(model.sessions) { item in
                        Button { selectedSession = item } label: {
                            HStack {
                                Image(systemName: "macwindow")
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(item.name.count > 48 ? "\(item.device ?? "Palm") 会话" : item.name).lineLimit(1)
                                    Text("\(item.device ?? "未知设备") · \(item.modified.formatted(date: .abbreviated, time: .shortened))")
                                        .font(.caption).foregroundStyle(.secondary)
                                }
                                Spacer()
                                if model.selectedSessionURL == item.url { Image(systemName: "checkmark.circle.fill").foregroundStyle(.tint) }
                            }
                            .padding(6)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(selectedSession == item ? Color.accentColor.opacity(0.15) : .clear, in: RoundedRectangle(cornerRadius: 7))
                        }
                        .buttonStyle(.plain)
                    }
                }
                .overlay { if model.sessions.isEmpty { emptyState("暂无已保存会话", "macwindow", "停止模拟器后，会话会自动保存在这里。") } }

                HStack {
                    Button("导入…") { model.importSession() }
                    Button("打开") {
                        if let selectedSession { model.openSession(selectedSession); dismiss() }
                    }
                    .disabled(selectedSession == nil)
                    Button("复制当前会话") { model.duplicateSession() }
                        .disabled(!model.isRunning)
                    Spacer()
                    Button("导出…") { if let selectedSession { model.exportSession(selectedSession) } }
                        .disabled(selectedSession == nil)
                    Button("移到废纸篓") {
                        if let selectedSession { model.deleteSession(selectedSession); self.selectedSession = nil }
                    }
                    .disabled(selectedSession == nil)
                }
            } else {
                List {
                    ForEach(model.cards) { item in
                        Button { selectedCard = item } label: {
                            HStack {
                                Image(systemName: "sdcard")
                                Text(item.name).lineLimit(1)
                                Spacer()
                                if model.mountedCardURL == item.url {
                                    Text(model.isRunning ? "已挂载" : "待挂载")
                                        .font(.caption).foregroundStyle(.secondary)
                                }
                            }
                            .padding(6)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(selectedCard == item ? Color.accentColor.opacity(0.15) : .clear, in: RoundedRectangle(cornerRadius: 7))
                        }
                        .buttonStyle(.plain)
                    }
                }
                .overlay { if model.cards.isEmpty { emptyState("暂无存储卡", "sdcard", "导入 .img 存储卡镜像后可挂载到设备。") } }

                HStack {
                    Button("导入镜像…") { model.importCard() }
                    Menu("新建空白卡") {
                        ForEach([4, 8, 16, 32], id: \.self) { size in
                            Button("\(size) MB") { model.createCard(sizeMB: size) }
                        }
                    }
                    Button(model.mountedCardURL == selectedCard?.url ? "弹出" : "挂载") {
                        if model.mountedCardURL == selectedCard?.url { model.ejectCard() }
                        else if let selectedCard { model.mountCard(selectedCard.url) }
                    }
                    .disabled(selectedCard == nil)
                    Spacer()
                    Button("导出…") { if let selectedCard { model.exportCard(selectedCard) } }
                        .disabled(selectedCard == nil)
                    Button("移到废纸篓") {
                        if let selectedCard { model.deleteCard(selectedCard); self.selectedCard = nil }
                    }
                    .disabled(selectedCard == nil)
                }
            }
        }
        .padding(20)
        .frame(width: 580, height: 430)
        .onAppear { model.refreshLibrary() }
    }

    private func emptyState(_ title: String, _ symbol: String, _ detail: String) -> some View {
        VStack(spacing: 8) {
            Image(systemName: symbol).font(.title).foregroundStyle(.secondary)
            Text(title).font(.headline)
            Text(detail).font(.caption).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .allowsHitTesting(false)
    }
}

private struct EmulatorDisplay: NSViewRepresentable {
    @ObservedObject var model: EmulatorModel

    func makeNSView(context: Context) -> NSView {
        let view = PalmDisplayView()
        view.model = model
        model.attach(view)
        return view
    }

    func updateNSView(_ view: NSView, context: Context) {
        (view as? PalmDisplayView)?.model = model
        model.attach(view)
    }
}

final class PalmDisplayView: NSView {
    weak var model: EmulatorModel?
    private var imageWidth = 320
    private var imageHeight = 440
    private var currentImage: CGImage?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.contentsGravity = .resizeAspect
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override var acceptsFirstResponder: Bool { true }

    func show(_ data: Data, width: Int, height: Int, pitch: Int) {
        guard let provider = CGDataProvider(data: data as CFData),
              let image = CGImage(width: width, height: height, bitsPerComponent: 8,
                                  bitsPerPixel: 32, bytesPerRow: pitch,
                                  space: CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: CGBitmapInfo.byteOrder32Little.union(
                                    CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedFirst.rawValue)),
                                  provider: provider, decode: nil,
                                  shouldInterpolate: false, intent: .defaultIntent) else { return }
        imageWidth = width
        imageHeight = height
        currentImage = image
        layer?.contents = image
    }

    func screenshotPNG() -> Data? {
        guard let image = currentImage else { return nil }
        return NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:])
    }

    func clear() {
        currentImage = nil
        layer?.contents = nil
    }

    private func sendPen(_ event: NSEvent, down: Bool) {
        let point = convert(event.locationInWindow, from: nil)
        let scale = min(bounds.width / CGFloat(imageWidth), bounds.height / CGFloat(imageHeight))
        let originX = (bounds.width - CGFloat(imageWidth) * scale) / 2
        let originY = (bounds.height - CGFloat(imageHeight) * scale) / 2
        let x = Int((point.x - originX) / scale)
        let y = Int((bounds.height - point.y - originY) / scale)
        model?.pen(x: max(0, min(imageWidth - 1, x)),
                   y: max(0, min(imageHeight - 1, y)), down: down)
    }

    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        sendPen(event, down: true)
    }

    override func mouseDragged(with event: NSEvent) { sendPen(event, down: true) }
    override func mouseUp(with event: NSEvent) { sendPen(event, down: false) }
    override func keyDown(with event: NSEvent) {
        if event.modifierFlags.contains(.command) {
            if event.charactersIgnoringModifiers?.lowercased() == "v" { paste(nil) }
            else { super.keyDown(with: event) }
            return
        }
        let input = [event.characters, event.charactersIgnoringModifiers]
            .compactMap { $0 }
            .first { !$0.isEmpty && $0.unicodeScalars.allSatisfy { $0.value < 256 } }
        if let input { sendText(input) }
    }

    @objc func paste(_ sender: Any?) {
        guard let text = NSPasteboard.general.string(forType: .string) else { return }
        sendText(text)
    }

    private func sendText(_ text: String) {
        for scalar in text.unicodeScalars where scalar.value < 256 {
            model?.key(Int(scalar.value))
        }
    }
}
