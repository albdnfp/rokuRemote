import SwiftUI
import Network
import AppKit

// MARK: - Bulletproof SSDP Discovery
struct RokuDevice: Identifiable, Hashable {
    let id = UUID()
    let name: String
    let ip: String
}

func discoverRokuDevices() -> [RokuDevice] {
    let ssdpAddress = "239.255.255.250"
    let ssdpPort: UInt16 = 1900
    
    let searchMessage = "M-SEARCH * HTTP/1.1\r\n" +
                        "Host: 239.255.255.250:1900\r\n" +
                        "Man: \"ssdp:discover\"\r\n" +
                        "ST: roku:ecp\r\n\r\n"
    
    var discoveredDevices: [RokuDevice] = []
    
    let sock = socket(AF_INET, SOCK_DGRAM, IPPROTO_UDP)
    guard sock >= 0 else { return [] }
    defer { close(sock) }
    
    var reuse: Int32 = 1
    setsockopt(sock, SOL_SOCKET, SO_REUSEADDR, &reuse, socklen_t(MemoryLayout.size(ofValue: reuse)))
    
    var broadcast: Int32 = 1
    setsockopt(sock, SOL_SOCKET, SO_BROADCAST, &broadcast, socklen_t(MemoryLayout.size(ofValue: broadcast)))
    
    var localAddr = sockaddr_in()
    localAddr.sin_family = sa_family_t(AF_INET)
    localAddr.sin_port = 0
    localAddr.sin_addr.s_addr = INADDR_ANY.bigEndian
    
    let bindResult = withUnsafePointer(to: &localAddr) {
        $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
            bind(sock, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
        }
    }
    guard bindResult >= 0 else { return [] }
    
    var destAddr = sockaddr_in()
    destAddr.sin_family = sa_family_t(AF_INET)
    destAddr.sin_port = ssdpPort.bigEndian
    destAddr.sin_addr.s_addr = inet_addr(ssdpAddress)
    
    guard let data = searchMessage.data(using: .utf8) else { return [] }
    
    let sent = data.withUnsafeBytes { ptr in
        withUnsafePointer(to: &destAddr) { targetAddr in
            targetAddr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sa in
                sendto(sock, ptr.baseAddress, data.count, 0, sa, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
    }
    
    guard sent >= 0 else { return [] }
    
    let timeout: TimeInterval = 2.5
    let startTime = Date()
    
    while Date().timeIntervalSince(startTime) < timeout {
        var tv = timeval(tv_sec: 0, tv_usec: 300_000)
        setsockopt(sock, SOL_SOCKET, SO_RCVTIMEO, &tv, socklen_t(MemoryLayout<timeval>.size))
        
        var buffer = [UInt8](repeating: 0, count: 2048)
        var senderAddr = sockaddr_in()
        var senderAddrLen = socklen_t(MemoryLayout<sockaddr_in>.size)
        
        let bytesRead = withUnsafeMutablePointer(to: &senderAddr) { saPtr in
            saPtr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sa in
                recvfrom(sock, &buffer, buffer.count, 0, sa, &senderAddrLen)
            }
        }
        
        if bytesRead > 0, let response = String(bytes: buffer[0..<bytesRead], encoding: .utf8) {
            var deviceIP = ""
            var deviceName = "Roku Device"
            
            for line in response.components(separatedBy: "\r\n") {
                let upper = line.uppercased()
                if upper.hasPrefix("LOCATION:") {
                    let parts = line.components(separatedBy: " ")
                    if let locationURL = parts.dropFirst().joined(separator: " ").addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
                       let url = URL(string: locationURL), let host = url.host {
                        deviceIP = host
                    }
                }
                if upper.hasPrefix("SERVER:") {
                    let comps = line.components(separatedBy: ":")
                    if comps.count > 1 {
                        deviceName = comps.dropFirst().joined(separator: ":").trimmingCharacters(in: .whitespaces)
                    }
                }
            }
            
            if !deviceIP.isEmpty {
                let cleanName = deviceName.components(separatedBy: " ").first ?? "Roku"
                let newDevice = RokuDevice(name: "\(cleanName) (\(deviceIP))", ip: deviceIP)
                if !discoveredDevices.contains(where: { $0.ip == deviceIP }) {
                    discoveredDevices.append(newDevice)
                }
            }
        }
    }
    
    return discoveredDevices
}

// MARK: - Key Binding Model
struct KeyBinding: Identifiable, Codable {
    let id = UUID()
    let name: String
    let command: String
    var keyChar: String
}

// MARK: - Graphical Interface & Keymapper
struct RemoteWindowView: View {
    @State var rokuIP: String = "Scanning..."
    @State var deviceDisplayName: String = "Scanning..."
    @State private var connectionStatus: StatusState = .scanning
    @FocusState private var isFocused: Bool
    @State private var showingKeymapSheet = false
    @State private var showingTextSearchSheet = false
    @State private var showingDevicePicker = false
    @State private var foundDevices: [RokuDevice] = []
    @State private var selectedDevice: RokuDevice? = nil
    @State private var eventMonitor: Any? = nil
    
    @AppStorage("savedKeybindings") private var savedKeybindingsJSON: String = ""
    @AppStorage("manualRokuIP") private var manualRokuIP: String = ""
    @State private var manualInputText: String = ""
    @State private var showingManualIPPrompt = false
    
    @State private var bindings: [KeyBinding] = []
    
    enum StatusState {
        case scanning, online, offline
        var color: Color {
            switch self {
            case .scanning: return .yellow
            case .online: return .green
            case .offline: return .red
            }
        }
    }
    
    init() {
        let defaultBindings = [
            KeyBinding(name: "Power", command: "Power", keyChar: "esc"),
            KeyBinding(name: "Up", command: "Up", keyChar: "w"),
            KeyBinding(name: "Down", command: "Down", keyChar: "s"),
            KeyBinding(name: "Left", command: "Left", keyChar: "a"),
            KeyBinding(name: "Right", command: "Right", keyChar: "d"),
            KeyBinding(name: "Select / OK", command: "Select", keyChar: " "),
            KeyBinding(name: "Home", command: "Home", keyChar: "h"),
            KeyBinding(name: "Back", command: "Back", keyChar: "/"),
            KeyBinding(name: "Play / Resume", command: "Play", keyChar: "shift"),
            KeyBinding(name: "Volume Up", command: "VolumeUp", keyChar: "v"),
            KeyBinding(name: "Volume Down", command: "VolumeDown", keyChar: "b"),
            KeyBinding(name: "Mute", command: "VolumeMute", keyChar: "m")
        ]
        
        if let data = UserDefaults.standard.string(forKey: "savedKeybindings"),
           var decoded = try? JSONDecoder().decode([KeyBinding].self, from: data.data(using: .utf8) ?? Data()) {
            if !decoded.contains(where: { $0.command == "Power" }) {
                decoded.insert(KeyBinding(name: "Power", command: "Power", keyChar: "esc"), at: 0)
            }
            if !decoded.contains(where: { $0.command == "Back" }) {
                decoded.append(KeyBinding(name: "Back", command: "Back", keyChar: "/"))
            }
            if !decoded.contains(where: { $0.command == "Play" }) {
                decoded.append(KeyBinding(name: "Play / Resume", command: "Play", keyChar: "shift"))
            }
            _bindings = State(initialValue: decoded)
        } else {
            _bindings = State(initialValue: defaultBindings)
        }
    }
    
    var body: some View {
        ZStack(alignment: .bottom) {
            VStack(spacing: 10) {
                HStack(spacing: 6) {
                    Button(action: { scanAndShowPicker() }) {
                        Text("Roku: \(rokuIP)")
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(.borderless)
                    .help("Click to rescan network")
                    
                    Spacer()
                    
                    Button(action: { showingTextSearchSheet = true }) {
                        Image(systemName: "keyboard")
                            .font(.system(size: 12))
                    }
                    .buttonStyle(.borderless)
                    .help("Type Text to Roku")
                    
                    Button(action: { showingKeymapSheet = true }) {
                        Image(systemName: "gearshape.fill")
                            .font(.system(size: 12))
                    }
                    .buttonStyle(.borderless)
                    .help("Configure Keybindings")
                }
                .padding(.horizontal, 4)
                
                HStack(spacing: 8) {
                    Button("Power") { sendCommand("Power") }
                    Button("Home") { sendCommand("Home") }
                    Button("Back") { sendCommand("Back") }
                    Button("Play") { sendCommand("Play") }
                }
                
                VStack(spacing: 5) {
                    Button("▲") { sendCommand("Up") }
                    
                    HStack(spacing: 15) {
                        Button("◀") { sendCommand("Left") }
                        Button("OK") { sendCommand("Select") }
                        Button("▶") { sendCommand("Right") }
                    }
                    
                    Button("▼") { sendCommand("Down") }
                }
                .padding(.vertical, 2)
                
                HStack(spacing: 10) {
                    Button("Vol -") { sendCommand("VolumeDown") }
                    Button("Mute") { sendCommand("VolumeMute") }
                    Button("Vol +") { sendCommand("VolumeUp") }
                }
            }
            .padding(.horizontal, 14)
            .padding(.top, 10)
            .padding(.bottom, 32) // Extra bottom padding so buttons stay clear of the bottom bar
            
            // Bottom Bar: Quit Button (Left) & Status LED Indicator (Right)
            HStack {
                Button(action: {
                    NSApplication.shared.terminate(nil)
                }) {
                    Text("Quit")
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.borderless)
                .help("Quit Application")
                
                Spacer()
                
                HStack(spacing: 5) {
                    Circle()
                        .fill(connectionStatus.color)
                        .frame(width: 8, height: 8)
                    Text(deviceDisplayName)
                        .font(.system(size: 9, design: .monospaced))
                        .foregroundColor(.secondary)
                }
            }
            .padding(.horizontal, 14)
            .padding(.bottom, 10)
        }
        .frame(width: 275, height: 290) // Increased height to provide clean separation
        .focusable(false)
        .focusEffectDisabled(true)
        .onAppear {
            NSApp.setActivationPolicy(.accessory)
            
            if !manualRokuIP.isEmpty {
                verifyAndSetRokuIP(manualRokuIP)
            } else {
                scanAndShowPicker()
            }
            
            eventMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .flagsChanged]) { event in
                if let firstResponder = NSApp.keyWindow?.firstResponder,
                   firstResponder is NSText || firstResponder is NSTextView {
                    return event
                }
                
                if event.type == .flagsChanged {
                    if event.modifierFlags.contains(.shift) {
                        if handleKeypress(target: "shift") { return nil }
                    }
                } else if event.type == .keyDown {
                    if event.keyCode == 53 {
                        if handleKeypress(target: "esc") { return nil }
                    } else {
                        let chars = (event.characters ?? "").lowercased()
                        if chars == " " {
                            if handleKeypress(target: "space") { return nil }
                        } else if let firstChar = chars.first {
                            if handleKeypress(target: String(firstChar)) { return nil }
                        }
                    }
                }
                return event
            }
        }
        .onDisappear {
            if let monitor = eventMonitor {
                NSEvent.removeMonitor(monitor)
            }
        }
        .sheet(isPresented: $showingKeymapSheet) {
            KeymapEditorView(bindings: $bindings, onSave: saveBindings)
        }
        .sheet(isPresented: $showingTextSearchSheet) {
            TextSearchPopupView(rokuIP: $rokuIP)
        }
        .sheet(isPresented: $showingDevicePicker) {
            DevicePickerView(devices: foundDevices, selectedDevice: $selectedDevice, onManualClick: {
                showingDevicePicker = false
                showingManualIPPrompt = true
            }) { chosenDevice in
                if let dev = chosenDevice {
                    verifyAndSetRokuIP(dev.ip)
                    self.deviceDisplayName = dev.name
                }
                showingDevicePicker = false
            }
        }
        .sheet(isPresented: $showingManualIPPrompt) {
            ManualIPView(ipInput: $manualInputText) { enteredIP in
                if !enteredIP.isEmpty {
                    let cleaned = enteredIP.trimmingCharacters(in: .whitespacesAndNewlines)
                    verifyAndSetRokuIP(cleaned)
                }
                showingManualIPPrompt = false
            }
        }
    }
    
    @discardableResult
    func handleKeypress(target: String) -> Bool {
        for binding in bindings {
            let targetKey = binding.keyChar.lowercased()
            if targetKey == target && !targetKey.isEmpty {
                sendCommand(binding.command)
                return true
            }
        }
        return false
    }
    
    func scanAndShowPicker() {
        connectionStatus = .scanning
        rokuIP = "Scanning..."
        deviceDisplayName = "Scanning..."
        
        DispatchQueue.global().async {
            let devices = discoverRokuDevices()
            DispatchQueue.main.async {
                self.foundDevices = devices
                if let first = devices.first {
                    self.verifyAndSetRokuIP(first.ip)
                    self.deviceDisplayName = first.name
                } else if !self.manualRokuIP.isEmpty {
                    self.verifyAndSetRokuIP(self.manualRokuIP)
                } else {
                    self.rokuIP = "Not Found"
                    self.deviceDisplayName = "Scan Failed"
                    self.connectionStatus = .offline
                    self.showingDevicePicker = true
                }
                if devices.count > 1 {
                    self.showingDevicePicker = true
                }
            }
        }
    }
    
    func verifyAndSetRokuIP(_ ip: String) {
        guard let url = URL(string: "http://\(ip):8060/query/device-info") else { return }
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = 3.0
        
        URLSession.shared.dataTask(with: request) { _, response, _ in
            DispatchQueue.main.async {
                if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 {
                    self.manualRokuIP = ip
                    self.rokuIP = ip
                    if !self.deviceDisplayName.contains("(") {
                        self.deviceDisplayName = "Roku (\(ip))"
                    }
                    self.connectionStatus = .online
                } else {
                    self.rokuIP = ip
                    self.deviceDisplayName = "Unreachable"
                    self.connectionStatus = .offline
                }
            }
        }.resume()
    }
    
    func saveBindings() {
        if let encoded = try? JSONEncoder().encode(bindings),
           let jsonString = String(data: encoded, encoding: .utf8) {
            savedKeybindingsJSON = jsonString
        }
    }
    
    func sendCommand(_ cmd: String) {
        let activeIP = rokuIP.trimmingCharacters(in: .whitespacesAndNewlines)
        guard activeIP != "Scanning..." && activeIP != "Not Found" && !activeIP.isEmpty else {
            self.connectionStatus = .offline
            return
        }
        
        guard let url = URL(string: "http://\(activeIP):8060/keypress/\(cmd)") else { return }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 3.0
        
        URLSession.shared.dataTask(with: request) { _, response, _ in
            DispatchQueue.main.async {
                if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 {
                    self.connectionStatus = .online
                } else {
                    self.connectionStatus = .offline
                }
            }
        }.resume()
        print("➔ Sent: \(cmd) to \(activeIP)")
    }
}

// MARK: - Text Search & Input Popup Window
struct TextSearchPopupView: View {
    @Binding var rokuIP: String
    @State private var textInputQuery: String = ""
    @Environment(\.dismiss) var dismiss
    
    var body: some View {
        VStack(spacing: 14) {
            Text("Send Text to Roku")
                .font(.headline)
            
            Text("Type text to send to the active Roku search field or textbox.")
                .font(.caption)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
            
            TextField("Type search query...", text: $textInputQuery)
                .textFieldStyle(.roundedBorder)
                .onSubmit {
                    sendTextToRoku()
                }
            
            HStack(spacing: 10) {
                Button("Clear Roku Field") {
                    clearRokuField()
                }
                .controlSize(.small)
                
                Spacer()
                
                Button("Send Text") {
                    sendTextToRoku()
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
            }
            
            HStack {
                Button("Close") {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)
                Spacer()
            }
        }
        .padding(18)
        .frame(width: 280, height: 200)
    }
    
    func sendTextToRoku() {
        let activeIP = rokuIP.trimmingCharacters(in: .whitespacesAndNewlines)
        guard activeIP != "Scanning..." && activeIP != "Not Found" && !activeIP.isEmpty, !textInputQuery.isEmpty else { return }
        
        for (index, char) in textInputQuery.enumerated() {
            let charString = String(char)
            let encodedChar = charString.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? charString
            
            DispatchQueue.global().asyncAfter(deadline: .now() + Double(index) * 0.08) {
                guard let url = URL(string: "http://\(activeIP):8060/keypress/Lit_\(encodedChar)") else { return }
                var request = URLRequest(url: url)
                request.httpMethod = "POST"
                request.timeoutInterval = 2.0
                URLSession.shared.dataTask(with: request).resume()
            }
        }
        print("⌨️ Sent text query to Roku: \(textInputQuery)")
        DispatchQueue.main.async {
            self.textInputQuery = ""
            dismiss()
        }
    }
    
    func clearRokuField() {
        let activeIP = rokuIP.trimmingCharacters(in: .whitespacesAndNewlines)
        guard activeIP != "Scanning..." && activeIP != "Not Found" && !activeIP.isEmpty else { return }
        
        for i in 0..<20 {
            DispatchQueue.global().asyncAfter(deadline: .now() + Double(i) * 0.05) {
                guard let url = URL(string: "http://\(activeIP):8060/keypress/Backspace") else { return }
                var request = URLRequest(url: url)
                request.httpMethod = "POST"
                request.timeoutInterval = 2.0
                URLSession.shared.dataTask(with: request).resume()
            }
        }
        print("🧹 Cleared active Roku text field.")
    }
}

// MARK: - Roku Device Selection Drop-down Modal
struct DevicePickerView: View {
    let devices: [RokuDevice]
    @Binding var selectedDevice: RokuDevice?
    var onManualClick: () -> Void
    var onComplete: (RokuDevice?) -> Void
    
    var body: some View {
        VStack(spacing: 14) {
            Text("Select Roku Device")
                .font(.headline)
            
            if devices.isEmpty {
                Text("No Roku devices found via network scan.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            } else {
                Picker("Discovered Roku:", selection: $selectedDevice) {
                    ForEach(devices) { device in
                        Text(device.name).tag(Optional(device))
                    }
                }
                .pickerStyle(.menu)
                .frame(width: 240)
            }
            
            Button("Enter IP Manually...") {
                onManualClick()
            }
            .font(.caption)
            
            HStack(spacing: 12) {
                Button("Cancel") {
                    onComplete(nil)
                }
                Spacer()
                Button("OK") {
                    onComplete(selectedDevice)
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 300, height: 210)
    }
}

// MARK: - Manual IP Entry Modal
struct ManualIPView: View {
    @Binding var ipInput: String
    var onComplete: (String) -> Void
    
    var body: some View {
        VStack(spacing: 14) {
            Text("Enter Roku IP Address")
                .font(.headline)
            
            TextField("e.g. 192.168.1.15", text: $ipInput)
                .textFieldStyle(.roundedBorder)
                .frame(width: 200)
            
            HStack(spacing: 12) {
                Button("Cancel") {
                    onComplete("")
                }
                Spacer()
                Button("Save") {
                    onComplete(ipInput)
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 265, height: 160)
    }
}

// MARK: - Interactive Key-Capture Editor Sheet
struct KeymapEditorView: View {
    @Binding var bindings: [KeyBinding]
    var onSave: () -> Void
    @Environment(\.dismiss) var dismiss
    @State private var capturingBindingID: UUID? = nil
    
    var body: some View {
        VStack(spacing: 12) {
            Text("Customize Keyboard Shortcuts")
                .font(.headline)
            
            Text("Click 'Change' next to an action, then press any key.")
                .font(.caption)
                .foregroundColor(.secondary)
            
            List {
                ForEach($bindings, id: \.id) { $binding in
                    HStack {
                        Text(binding.name)
                            .font(.system(size: 13, weight: .medium))
                        Spacer()
                        
                        Text("[\(displayKeyString(for: binding.keyChar))]")
                            .font(.system(size: 12, design: .monospaced))
                            .foregroundColor(.secondary)
                        
                        Button("Change") {
                            capturingBindingID = binding.id
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    }
                }
            }
            .frame(height: 220)
            
            HStack {
                Button("Reset Defaults") {
                    bindings = [
                        KeyBinding(name: "Power", command: "Power", keyChar: "esc"),
                        KeyBinding(name: "Up", command: "Up", keyChar: "w"),
                        KeyBinding(name: "Down", command: "Down", keyChar: "s"),
                        KeyBinding(name: "Left", command: "Left", keyChar: "a"),
                        KeyBinding(name: "Right", command: "Right", keyChar: "d"),
                        KeyBinding(name: "Select / OK", command: "Select", keyChar: " "),
                        KeyBinding(name: "Home", command: "Home", keyChar: "h"),
                        KeyBinding(name: "Back", command: "Back", keyChar: "/"),
                        KeyBinding(name: "Play / Resume", command: "Play", keyChar: "shift"),
                        KeyBinding(name: "Volume Up", command: "VolumeUp", keyChar: "v"),
                        KeyBinding(name: "Volume Down", command: "VolumeDown", keyChar: "b"),
                        KeyBinding(name: "Mute", command: "VolumeMute", keyChar: "m")
                    ]
                    onSave()
                }
                Spacer()
                Button("Done") {
                    onSave()
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(16)
        .frame(width: 340, height: 420)
        .sheet(item: Binding<KeyBinding?>(
            get: { bindings.first { $0.id == capturingBindingID } },
            set: { if $0 == nil { capturingBindingID = nil } }
        )) { bindingItem in
            KeyCapturePopup(bindingName: bindingItem.name) { newKey in
                if let index = bindings.firstIndex(where: { $0.id == bindingItem.id }) {
                    bindings[index].keyChar = newKey
                    onSave()
                }
                capturingBindingID = nil
            }
        }
    }
    
    func displayKeyString(for keyChar: String) -> String {
        let lower = keyChar.lowercased()
        if lower == " " {
            return "Space"
        } else if lower == "shift" {
            return "Shift"
        } else if lower == "esc" {
            return "Esc"
        } else {
            return keyChar.uppercased()
        }
    }
}

// MARK: - Key Capture Popup Modal
struct KeyCapturePopup: View {
    let bindingName: String
    var onKeyCaptured: (String) -> Void
    @Environment(\.dismiss) var dismiss
    @State private var monitor: Any? = nil
    
    var body: some View {
        VStack(spacing: 16) {
            Text("Press a key for:")
                .font(.headline)
            Text(bindingName)
                .font(.title2)
                .bold()
                .foregroundColor(.accentColor)
            
            Text("Listening for keystroke...")
                .font(.caption)
                .foregroundColor(.secondary)
            
            Button("Cancel") {
                dismiss()
            }
            .controlSize(.small)
        }
        .padding(24)
        .frame(width: 240, height: 160)
        .onAppear {
            monitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .flagsChanged]) { event in
                if event.type == .flagsChanged {
                    if event.modifierFlags.contains(.shift) {
                        onKeyCaptured("shift")
                        dismiss()
                        return nil
                    }
                } else if event.type == .keyDown {
                    if event.keyCode == 53 {
                        onKeyCaptured("esc")
                        dismiss()
                        return nil
                    }
                    let chars = event.characters ?? ""
                    if chars == " " {
                        onKeyCaptured(" ")
                    } else if let firstChar = chars.lowercased().first {
                        onKeyCaptured(String(firstChar))
                    }
                    dismiss()
                    return nil
                }
                return event
            }
        }
        .onDisappear {
            if let monitor = monitor {
                NSEvent.removeMonitor(monitor)
            }
        }
    }
}

// MARK: - Persistent Menu Bar Floating Panel Controller
class AppDelegate: NSObject, NSApplicationDelegate {
    var statusItem: NSStatusItem!
    var popover: NSPopover!
    
    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "tv.fill", accessibilityDescription: "Roku Remote")
            button.action = #selector(togglePopover(_:))
        }
        
        popover = NSPopover()
        popover.contentSize = NSSize(width: 275, height: 290)
        popover.behavior = .applicationDefined
        popover.contentViewController = NSHostingController(rootView: RemoteWindowView())
    }
    
    @objc func togglePopover(_ sender: AnyObject?) {
        if let button = statusItem.button {
            if popover.isShown {
                popover.performClose(sender)
            } else {
                popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
                popover.contentViewController?.view.window?.makeKey()
            }
        }
    }
}

// MARK: - Sticky Status Item App Entry Point
@main
struct RokuRemoteApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    
    var body: some Scene {
        Settings {
            EmptyView()
        }
    }
}
