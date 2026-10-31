import SwiftUI
import Network
import AppKit

// MARK: - SSDP Auto-Discovery Logic
func discoverRokuIP() -> String {
    let ssdpAddress = "239.255.255.250"
    let ssdpPort: UInt16 = 1900
    
    let searchMessage = """
    M-SEARCH * HTTP/1.1\r
    Host: \(ssdpAddress):\(ssdpPort)\r
    Man: "ssdp:discover"\r
    ST: roku:ecp\r\n\r\n
    """
    
    let sock = socket(AF_INET, SOCK_DGRAM, IPPROTO_UDP)
    guard sock >= 0 else { return "192.168.1.50" }
    
    var reuse: Int32 = 1
    setsockopt(sock, SOL_SOCKET, SO_REUSEADDR, &reuse, socklen_t(MemoryLayout.size(ofValue: reuse)))
    
    var addr = sockaddr_in()
    addr.sin_family = sa_family_t(AF_INET)
    addr.sin_port = ssdpPort.bigEndian
    addr.sin_addr.s_addr = inet_addr(ssdpAddress)
    
    let data = searchMessage.data(using: .utf8)!
    data.withUnsafeBytes { ptr in
        _ = withUnsafePointer(to: &addr) { targetAddr in
            targetAddr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sa in
                sendto(sock, ptr.baseAddress, data.count, 0, sa, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
    }
    
    var tv = timeval(tv_sec: 1, tv_usec: 0)
    setsockopt(sock, SOL_SOCKET, SO_RCVTIMEO, &tv, socklen_t(MemoryLayout<timeval>.size))
    
    var buffer = [UInt8](repeating: 0, count: 2048)
    var senderAddr = sockaddr_in()
    var senderAddrLen = socklen_t(MemoryLayout<sockaddr_in>.size)
    
    let bytesRead = withUnsafeMutablePointer(to: &senderAddr) { saPtr in
        saPtr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sa in
            recvfrom(sock, &buffer, buffer.count, 0, sa, &senderAddrLen)
        }
    }
    
    close(sock)
    
    if bytesRead > 0, let response = String(bytes: buffer[0..<bytesRead], encoding: .utf8) {
        for line in response.components(separatedBy: "\r\n") {
            if line.uppercased().hasPrefix("LOCATION:") {
                let parts = line.components(separatedBy: " ")
                if let locationURL = parts.dropFirst().joined(separator: " ").addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
                   let url = URL(string: locationURL), let host = url.host {
                    return host
                }
            }
        }
    }
    
    return ProcessInfo.processInfo.environment["ROKU_IP"] ?? "192.168.1.50"
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
    @FocusState private var isFocused: Bool
    @State private var showingKeymapSheet = false
    
    @AppStorage("savedKeybindings") private var savedKeybindingsJSON: String = ""
    @State private var bindings: [KeyBinding] = []
    
    init() {
        let defaultBindings = [
            KeyBinding(name: "Up", command: "Up", keyChar: "w"),
            KeyBinding(name: "Down", command: "Down", keyChar: "s"),
            KeyBinding(name: "Left", command: "Left", keyChar: "a"),
            KeyBinding(name: "Right", command: "Right", keyChar: "d"),
            KeyBinding(name: "Select / OK", command: "Select", keyChar: " "),
            KeyBinding(name: "Home", command: "Home", keyChar: "h"),
            KeyBinding(name: "Back", command: "Back", keyChar: "/"),
            KeyBinding(name: "Volume Up", command: "VolumeUp", keyChar: "v"),
            KeyBinding(name: "Volume Down", command: "VolumeDown", keyChar: "b"),
            KeyBinding(name: "Mute", command: "VolumeMute", keyChar: "m")
        ]
        
        if let data = UserDefaults.standard.string(forKey: "savedKeybindings"),
           var decoded = try? JSONDecoder().decode([KeyBinding].self, from: data.data(using: .utf8) ?? Data()) {
            
            // Migration check: if "Back" command is missing from local storage, inject it automatically
            if !decoded.contains(where: { $0.command == "Back" }) {
                decoded.append(KeyBinding(name: "Back", command: "Back", keyChar: "/"))
            }
            _bindings = State(initialValue: decoded)
        } else {
            _bindings = State(initialValue: defaultBindings)
        }
    }
    
    var body: some View {
        VStack(spacing: 12) {
            HStack {
                Text("Roku: \(rokuIP)")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundColor(.secondary)
                Spacer()
                Button(action: { showingKeymapSheet = true }) {
                    Image(systemName: "gearshape.fill")
                        .font(.system(size: 12))
                }
                .buttonStyle(.borderless)
                .help("Configure Keybindings")
            }
            .padding(.horizontal, 4)
            
            // Power, Home, and Back Row
            HStack(spacing: 10) {
                Button("Power") { sendCommand("Power") }
                Button("Home") { sendCommand("Home") }
                Button("Back") { sendCommand("Back") }
            }
            
            // D-Pad Grid
            VStack(spacing: 6) {
                Button("▲") { sendCommand("Up") }
                
                HStack(spacing: 15) {
                    Button("◀") { sendCommand("Left") }
                    Button("OK") { sendCommand("Select") }
                    Button("▶") { sendCommand("Right") }
                }
                
                Button("▼") { sendCommand("Down") }
            }
            .padding(.vertical, 4)
            
            // Volume Controls Row
            HStack(spacing: 10) {
                Button("Vol -") { sendCommand("VolumeDown") }
                Button("Mute") { sendCommand("VolumeMute") }
                Button("Vol +") { sendCommand("VolumeUp") }
            }
        }
        .padding(18)
        .frame(width: 260, height: 260)
        .focusable()
        .focused($isFocused)
        .onAppear {
            isFocused = true
            NSApplication.shared.setActivationPolicy(.regular)
            NSApplication.shared.activate(ignoringOtherApps: true)
            
            DispatchQueue.global().async {
                let ip = discoverRokuIP()
                DispatchQueue.main.async {
                    self.rokuIP = ip
                }
            }
        }
        .onKeyPress { keyPress in
            let typedChar = keyPress.characters.lowercased()
            
            for binding in bindings {
                let targetKey = binding.keyChar.lowercased()
                if (targetKey == "space" && (typedChar == " " || keyPress.key == .space)) ||
                   (typedChar == targetKey && !targetKey.isEmpty) {
                    sendCommand(binding.command)
                    return .handled
                }
            }
            return .ignored
        }
        .sheet(isPresented: $showingKeymapSheet) {
            KeymapEditorView(bindings: $bindings, onSave: saveBindings)
        }
    }
    
    func saveBindings() {
        if let encoded = try? JSONEncoder().encode(bindings),
           let jsonString = String(data: encoded, encoding: .utf8) {
            savedKeybindingsJSON = jsonString
        }
    }
    
    func sendCommand(_ cmd: String) {
        guard rokuIP != "Scanning..." && !rokuIP.isEmpty else { return }
        guard let url = URL(string: "http://\(rokuIP):8060/keypress/\(cmd)") else { return }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        URLSession.shared.dataTask(with: request).resume()
        print("➔ Sent: \(cmd)")
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
                ForEach($bindings) { $binding in
                    HStack {
                        Text(binding.name)
                            .font(.system(size: 13, weight: .medium))
                        Spacer()
                        
                        let displayKey = binding.keyChar == " " ? "Space" : binding.keyChar.uppercased()
                        Text("[\(displayKey)]")
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
                        KeyBinding(name: "Up", command: "Up", keyChar: "w"),
                        KeyBinding(name: "Down", command: "Down", keyChar: "s"),
                        KeyBinding(name: "Left", command: "Left", keyChar: "a"),
                        KeyBinding(name: "Right", command: "Right", keyChar: "d"),
                        KeyBinding(name: "Select / OK", command: "Select", keyChar: " "),
                        KeyBinding(name: "Home", command: "Home", keyChar: "h"),
                        KeyBinding(name: "Back", command: "Back", keyChar: "/"),
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
        .frame(width: 340, height: 380)
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
}

// MARK: - Key Capture Popup Modal
struct KeyCapturePopup: View {
    let bindingName: String
    var onKeyCaptured: (String) -> Void
    @Environment(\.dismiss) var dismiss
    @FocusState private var isFocused: Bool
    
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
        .focusable()
        .focused($isFocused)
        .onAppear {
            isFocused = true
        }
        .onKeyPress { keyPress in
            let char = keyPress.characters
            if char == " " || keyPress.key == .space {
                onKeyCaptured(" ")
            } else if let firstChar = char.lowercased().first {
                onKeyCaptured(String(firstChar))
            }
            dismiss()
            return .handled
        }
    }
}

// MARK: - Safe Application Entry Point
@main
struct RokuRemoteApp: App {
    var body: some Scene {
        WindowGroup {
            RemoteWindowView()
        }
        .windowResizability(.contentSize)
    }
}
