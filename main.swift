import Foundation
import Cocoa

struct ModelQuota: Codable, Identifiable {
    var id: String { label }
    let label: String
    let remainingPercentage: Double?
    let timeUntilResetMs: Double?
}

struct QuotaData: Codable {
    let email: String
    let method: String
    let timestamp: String
    var models: [ModelQuota]
}

struct CodexRateLimitInfo {
    let primaryRemainingPct: Double
    let primaryResetTimeMs: Double
    let secondaryRemainingPct: Double
    let secondaryResetTimeMs: Double
}

class AppDelegate: NSObject, NSApplicationDelegate {
    var statusBarItem: NSStatusItem!
    var menu: NSMenu!
    var timer: Timer?
    var isFetching = false
    
    func applicationDidFinishLaunching(_ notification: Notification) {
        statusBarItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        
        if let button = statusBarItem.button {
            button.title = "⚡ ..."
        }
        
        menu = NSMenu()
        statusBarItem.menu = menu
        
        setupInitialMenu()
        refreshData()
        
        // Auto refresh every 5 minutes (300 seconds)
        timer = Timer.scheduledTimer(withTimeInterval: 300, repeats: true) { [weak self] _ in
            self?.refreshData()
        }
    }
    
    func setupInitialMenu() {
        menu.removeAllItems()
        let loadingItem = createMenuItem(text: "Loading Antigravity Quota...", color: .secondaryLabelColor)
        loadingItem.isEnabled = false
        menu.addItem(loadingItem)
        menu.addItem(NSMenuItem.separator())
        
        let quitItem = NSMenuItem(title: "Quit", action: #selector(quit), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)
    }
    
    func createMenuItem(text: String, color: NSColor? = nil, isBold: Bool = false) -> NSMenuItem {
        let item = NSMenuItem()
        let font = isBold ? 
            (NSFont(name: "Monaco-Bold", size: 12) ?? NSFont.monospacedSystemFont(ofSize: 12, weight: .bold)) :
            (NSFont(name: "Monaco", size: 12) ?? NSFont.monospacedSystemFont(ofSize: 12, weight: .regular))
        
        var attrs: [NSAttributedString.Key: Any] = [
            .font: font
        ]
        
        if let textColor = color {
            attrs[.foregroundColor] = textColor
        } else {
            attrs[.foregroundColor] = NSColor.labelColor
        }
        
        item.attributedTitle = NSAttributedString(string: text, attributes: attrs)
        return item
    }
    
    func makeUnicodeBar(pct: Double, width: Int = 12) -> String {
        let filledLength = Int(round(pct * Double(width)))
        let emptyLength = width - filledLength
        let filled = String(repeating: "█", count: max(0, filledLength))
        let empty = String(repeating: "░", count: max(0, emptyLength))
        return "\(filled)\(empty)"
    }
    
    func cleanModelLabel(_ label: String) -> String {
        return label
            .replacingOccurrences(of: "Claude ", with: "")
            .replacingOccurrences(of: " 4.6 (Thinking)", with: " 4.6 (Think)")
            .replacingOccurrences(of: " Flash ", with: " ")
            .replacingOccurrences(of: " 3.1 Pro ", with: " 3.1 ")
            .replacingOccurrences(of: " 120B (Medium)", with: " (Med)")
            .replacingOccurrences(of: " (Medium)", with: " (Med)")
            .replacingOccurrences(of: " (Thinking)", with: " (Think)")
    }
    
    func formatResetTime(_ ms: Double) -> String {
        guard ms > 0 else { return "No reset pending" }
        let minutes = Int(ms / 60000)
        let hours = minutes / 60
        let mins = minutes % 60
        if hours >= 24 {
            let days = hours / 24
            let remHours = hours % 24
            return "Resets in \(days)d \(remHours)h"
        }
        return "Resets in \(hours)h \(mins)m"
    }
    
    func colorForPercentage(_ pct: Double) -> NSColor {
        if pct <= 0.20 {
            return NSColor(red: 0.86, green: 0.21, blue: 0.27, alpha: 1.0) // red
        } else if pct <= 0.50 {
            return NSColor(red: 1.0, green: 0.76, blue: 0.03, alpha: 1.0) // orange
        } else {
            return NSColor(red: 0.16, green: 0.65, blue: 0.27, alpha: 1.0) // green
        }
    }
    
    func runCcusage() -> String {
        let task = Process()
        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = pipe
        
        let homeDir = FileManager.default.homeDirectoryForCurrentUser.path
        let appSupportScript = "\(homeDir)/Library/Application Support/AntigravityQuotaBar/fetch-quota.js"
        
        let cmd = """
        if [ -f "\(appSupportScript)" ]; then
            node "\(appSupportScript)" 2>/dev/null || antigravity-usage quota --json 2>/dev/null
        else
            antigravity-usage quota --json 2>/dev/null || npx --no-install antigravity-usage quota --json 2>/dev/null
        fi
        """
        
        task.arguments = ["-lc", cmd]
        task.launchPath = "/bin/zsh"
        
        var env = ProcessInfo.processInfo.environment
        let nvmBinDir = "\(homeDir)/.nvm/versions/node"
        var nodePaths: [String] = []
        if let contents = try? FileManager.default.contentsOfDirectory(atPath: nvmBinDir) {
            for v in contents {
                nodePaths.append("\(nvmBinDir)/\(v)/bin")
            }
        }
        let customPaths = nodePaths.joined(separator: ":")
        env["PATH"] = "\(customPaths):/opt/homebrew/bin:/usr/local/bin:\(homeDir)/.local/bin:/usr/bin:/bin:/usr/sbin:/sbin:" + (env["PATH"] ?? "")
        task.environment = env
        
        do {
            try task.run()
            task.waitUntilExit()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            return String(data: data, encoding: .utf8) ?? ""
        } catch {
            return ""
        }
    }
    
    func extractJSON(from input: String) -> String? {
        guard let firstBrace = input.firstIndex(of: "{"),
              let lastBrace = input.lastIndex(of: "}") else {
            return nil
        }
        return String(input[firstBrace...lastBrace])
    }
    
    func getCodexQuota() -> CodexRateLimitInfo? {
        let fileManager = FileManager.default
        let homeDir = fileManager.homeDirectoryForCurrentUser
        let sessionsDir = homeDir.appendingPathComponent(".codex/sessions")
        
        var jsonlFiles: [(url: URL, date: Date)] = []
        let enumerator = fileManager.enumerator(at: sessionsDir, includingPropertiesForKeys: [.contentModificationDateKey], options: [.skipsHiddenFiles])
        
        while let fileURL = enumerator?.nextObject() as? URL {
            if fileURL.pathExtension == "jsonl" {
                if let attrs = try? fileManager.attributesOfItem(atPath: fileURL.path),
                   let modDate = attrs[.modificationDate] as? Date {
                    jsonlFiles.append((fileURL, modDate))
                }
            }
        }
        
        guard let latestFile = jsonlFiles.sorted(by: { $0.date > $1.date }).first else {
            return nil
        }
        
        guard let content = try? String(contentsOf: latestFile.url, encoding: .utf8) else {
            return nil
        }
        
        let lines = content.components(separatedBy: .newlines)
        
        for line in lines.reversed() {
            if line.contains("rate_limits") {
                if let data = line.data(using: .utf8),
                   let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let payload = json["payload"] as? [String: Any],
                   let rateLimits = payload["rate_limits"] as? [String: Any] {
                    
                    // Filter out lines where primary rate limit is missing or null
                    guard let primary = rateLimits["primary"] as? [String: Any],
                          let usedNum = primary["used_percent"] as? NSNumber else {
                        continue
                    }
                    
                    let primaryPct = max(0.0, 1.0 - (usedNum.doubleValue / 100.0))
                    var primaryResetMs = 0.0
                    var secondaryPct = 1.0
                    var secondaryResetMs = 0.0
                    
                    let now = Date().timeIntervalSince1970
                    
                    if let resetsAtNum = primary["resets_at"] as? NSNumber {
                        primaryResetMs = max(0.0, (resetsAtNum.doubleValue - now) * 1000.0)
                    }
                    
                    if let secondary = rateLimits["secondary"] as? [String: Any] {
                        if let secUsedNum = secondary["used_percent"] as? NSNumber {
                            secondaryPct = max(0.0, 1.0 - (secUsedNum.doubleValue / 100.0))
                        }
                        if let secResetsAtNum = secondary["resets_at"] as? NSNumber {
                            secondaryResetMs = max(0.0, (secResetsAtNum.doubleValue - now) * 1000.0)
                        }
                    }
                    
                    return CodexRateLimitInfo(
                        primaryRemainingPct: primaryPct,
                        primaryResetTimeMs: primaryResetMs,
                        secondaryRemainingPct: secondaryPct,
                        secondaryResetTimeMs: secondaryResetMs
                    )
                }
            }
        }
        
        return nil
    }
    
    @objc func refresh() {
        refreshData()
    }
    
    func refreshData() {
        guard !isFetching else { return }
        isFetching = true
        
        if let button = statusBarItem.button {
            button.title = "⚡ ⌛"
        }
        
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let rawStr = self?.runCcusage() ?? ""
            let jsonStr = self?.extractJSON(from: rawStr) ?? ""
            
            var output: QuotaData? = nil
            if let data = jsonStr.data(using: .utf8) {
                let decoder = JSONDecoder()
                output = try? decoder.decode(QuotaData.self, from: data)
            }
            
            let codexInfo = self?.getCodexQuota()
            
            DispatchQueue.main.async {
                if var validOutput = output {
                    if let codex = codexInfo {
                        validOutput.models.append(ModelQuota(
                            label: "Codex 5h",
                            remainingPercentage: codex.primaryRemainingPct,
                            timeUntilResetMs: codex.primaryResetTimeMs
                        ))
                        validOutput.models.append(ModelQuota(
                            label: "Codex Weekly",
                            remainingPercentage: codex.secondaryRemainingPct,
                            timeUntilResetMs: codex.secondaryResetTimeMs
                        ))
                    }
                    self?.updateUI(with: validOutput)
                } else if let codex = codexInfo {
                    var fallbackModels: [ModelQuota] = []
                    fallbackModels.append(ModelQuota(
                        label: "Codex 5h",
                        remainingPercentage: codex.primaryRemainingPct,
                        timeUntilResetMs: codex.primaryResetTimeMs
                    ))
                    fallbackModels.append(ModelQuota(
                        label: "Codex Weekly",
                        remainingPercentage: codex.secondaryRemainingPct,
                        timeUntilResetMs: codex.secondaryResetTimeMs
                    ))
                    
                    let fallbackOutput = QuotaData(
                        email: "Antigravity CLI Offline",
                        method: "Codex Local Log",
                        timestamp: ISO8601DateFormatter().string(from: Date()),
                        models: fallbackModels
                    )
                    self?.updateUI(with: fallbackOutput)
                } else {
                    var cleanError = rawStr.trimmingCharacters(in: .whitespacesAndNewlines)
                    if cleanError.contains("not running and you are not logged in") {
                        cleanError = "Antigravity not logged in. Open IDE or run: antigravity-usage login"
                    } else if cleanError.isEmpty {
                        cleanError = "No output from CLI tool"
                    }
                    
                    let debugDir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?.appendingPathComponent("AntigravityQuotaBar")
                    if let debugDir = debugDir {
                        try? FileManager.default.createDirectory(at: debugDir, withIntermediateDirectories: true)
                        let debugFile = debugDir.appendingPathComponent("debug.txt")
                        let debugInfo = "--- ERROR ---\n\(cleanError)\n\n--- RAW OUTPUT ---\n\(rawStr)\n"
                        try? debugInfo.write(to: debugFile, atomically: true, encoding: .utf8)
                    }
                    
                    self?.updateUIWithError(cleanError)
                }
            }
        }
    }
    
    func updateUI(with output: QuotaData) {
        isFetching = false
        
        let filteredModels = output.models.filter { model in
            let lbl = model.label
            if lbl.contains("3.1") || lbl.contains("3.6") { return false }
            if lbl.contains("GPT-OSS") || lbl.lowercased().contains("gptoss") { return false }
            if lbl.contains("3.7") && lbl.contains("Low") { return false }
            return true
        }
        
        let gemWeekly = filteredModels.first(where: { $0.label == "Gemini Weekly" })
        let gem5h = filteredModels.first(where: { $0.label == "Gemini 5h" })
        
        if let g5h = gem5h, let gWk = gemWeekly,
           let p5h = g5h.remainingPercentage, let pWk = gWk.remainingPercentage {
            let val5h = Int(round(p5h * 100))
            let valWk = Int(round(pWk * 100))
            if let button = statusBarItem.button {
                button.title = "⚡ \(val5h)% (5h) · \(valWk)% (Wk)"
            }
        } else {
            let flashHigh = filteredModels.first(where: { 
                $0.label.contains("Gemini 3.8 Flash (High)") ||
                $0.label.contains("Gemini 3.7 Flash (High)") ||
                $0.label.contains("Gemini 3.8 Flash") ||
                $0.label.contains("Gemini 3.7 Flash") ||
                $0.label.contains("Gemini 3.5 Flash") 
            })
            let opus = filteredModels.first(where: { $0.label.contains("Claude Opus 4.6") || $0.label.contains("Opus 4.6") })
            let sonnet = filteredModels.first(where: { $0.label.contains("Claude Sonnet 4.6") || $0.label.contains("Sonnet 4.6") })
            let codex5h = filteredModels.first(where: { $0.label.contains("Codex 5h") })
            
            var displayPct = 100
            var shortName = ""
            
            let importantModels = [flashHigh, sonnet, opus, codex5h].compactMap { $0 }
            if !importantModels.isEmpty {
                let lowest = importantModels.reduce(importantModels[0]) { 
                    let p1 = $0.remainingPercentage ?? 1.0
                    let p2 = $1.remainingPercentage ?? 1.0
                    return p2 < p1 ? $1 : $0 
                }
                displayPct = Int(round((lowest.remainingPercentage ?? 1.0) * 100))
                shortName = lowest.label.contains("Gemini") ? "Gem" : (lowest.label.contains("Sonnet") ? "Son" : (lowest.label.contains("Opus") ? "Opu" : "Cod"))
            } else if !filteredModels.isEmpty {
                let lowest = filteredModels.reduce(filteredModels[0]) { 
                    let p1 = $0.remainingPercentage ?? 1.0
                    let p2 = $1.remainingPercentage ?? 1.0
                    return p2 < p1 ? $1 : $0 
                }
                displayPct = Int(round((lowest.remainingPercentage ?? 1.0) * 100))
                shortName = lowest.label.contains("Gemini") ? "Gem" : "Model"
            }
            
            if let button = statusBarItem.button {
                button.title = "⚡ \(displayPct)% (\(shortName))"
            }
        }
        
        menu.removeAllItems()
        
        let titleItem = createMenuItem(text: "⚡ ANTIGRAVITY QUOTA STATUS", isBold: true)
        titleItem.isEnabled = false
        menu.addItem(titleItem)
        
        let emailItem = createMenuItem(text: "Email:  \(output.email)", color: .secondaryLabelColor)
        emailItem.isEnabled = false
        menu.addItem(emailItem)
        
        let methodItem = createMenuItem(text: "Method: \(output.method)", color: .secondaryLabelColor)
        methodItem.isEnabled = false
        menu.addItem(methodItem)
        
        let dateFormatter = DateFormatter()
        dateFormatter.timeStyle = .medium
        let syncItem = createMenuItem(text: "Sync:   \(dateFormatter.string(from: Date()))", color: .secondaryLabelColor)
        syncItem.isEnabled = false
        menu.addItem(syncItem)
        
        menu.addItem(NSMenuItem.separator())
        
        let poolModels = filteredModels.filter { 
            $0.label == "Gemini Weekly" || $0.label == "Gemini 5h" ||
            $0.label == "Claude/GPT Weekly" || $0.label == "Claude/GPT 5h"
        }
        let codexModels = filteredModels.filter { $0.label.starts(with: "Codex") }
        let individualModels = filteredModels.filter { model in
            !poolModels.contains(where: { $0.label == model.label }) &&
            !codexModels.contains(where: { $0.label == model.label })
        }
        
        func appendModelRow(_ model: ModelQuota) {
            let remainingPct = model.remainingPercentage ?? 1.0
            let pctVal = Int(round(remainingPct * 100))
            let bar = makeUnicodeBar(pct: remainingPct, width: 12)
            let shortLabel = cleanModelLabel(model.label).padding(toLength: 18, withPad: " ", startingAt: 0)
            
            var resetStr = ""
            if let resetMs = model.timeUntilResetMs, resetMs > 0 {
                let minutes = Int(resetMs / 60000)
                let hours = minutes / 60
                let mins = minutes % 60
                if hours >= 24 {
                    let days = hours / 24
                    let remHours = hours % 24
                    resetStr = " (Resets \(days)d \(remHours)h)"
                } else {
                    resetStr = " (Resets \(hours)h \(mins)m)"
                }
            }
            
            let rowText = "\(shortLabel) [\(bar)] \(String(format: "%3d%%", pctVal))\(resetStr)"
            let color = colorForPercentage(remainingPct)
            let modelItem = createMenuItem(text: rowText, color: color)
            modelItem.isEnabled = false
            menu.addItem(modelItem)
        }
        
        if !poolModels.isEmpty {
            let poolHeader = createMenuItem(text: "─── QUOTA POOLS (WEEKLY & 5H) ───", color: .secondaryLabelColor, isBold: true)
            poolHeader.isEnabled = false
            menu.addItem(poolHeader)
            for model in poolModels {
                appendModelRow(model)
            }
            menu.addItem(NSMenuItem.separator())
        }
        
        if !individualModels.isEmpty {
            let indHeader = createMenuItem(text: "─── INDIVIDUAL MODELS ───────────", color: .secondaryLabelColor, isBold: true)
            indHeader.isEnabled = false
            menu.addItem(indHeader)
            for model in individualModels {
                appendModelRow(model)
            }
            menu.addItem(NSMenuItem.separator())
        }
        
        if !codexModels.isEmpty {
            let codexHeader = createMenuItem(text: "─── CODEX LIMITS ────────────────", color: .secondaryLabelColor, isBold: true)
            codexHeader.isEnabled = false
            menu.addItem(codexHeader)
            for model in codexModels {
                appendModelRow(model)
            }
            menu.addItem(NSMenuItem.separator())
        }
        
        let launchItem = NSMenuItem(title: "Launch at Login", action: #selector(toggleLaunchAtLogin), keyEquivalent: "")
        launchItem.target = self
        launchItem.state = isLaunchAtLoginEnabled() ? .on : .off
        menu.addItem(launchItem)
        
        let refreshItem = NSMenuItem(title: "Refresh Now", action: #selector(refresh), keyEquivalent: "r")
        refreshItem.target = self
        menu.addItem(refreshItem)
        
        menu.addItem(NSMenuItem.separator())
        
        let quitItem = NSMenuItem(title: "Quit", action: #selector(quit), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)
    }
    
    func updateUIWithError(_ errorMsg: String) {
        isFetching = false
        if let button = statusBarItem.button {
            button.title = "⚡ Err"
        }
        
        menu.removeAllItems()
        let errTitle = createMenuItem(text: "⚡ QUOTA ERROR", color: .systemRed, isBold: true)
        errTitle.isEnabled = false
        menu.addItem(errTitle)
        
        let errDesc = createMenuItem(text: errorMsg, color: .secondaryLabelColor)
        errDesc.isEnabled = false
        menu.addItem(errDesc)
        
        menu.addItem(NSMenuItem.separator())
        
        let refreshItem = NSMenuItem(title: "Refresh Now", action: #selector(refresh), keyEquivalent: "r")
        refreshItem.target = self
        menu.addItem(refreshItem)
        
        menu.addItem(NSMenuItem.separator())
        
        let quitItem = NSMenuItem(title: "Quit", action: #selector(quit), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)
    }
    
    var plistPath: URL {
        let home = FileManager.default.homeDirectoryForCurrentUser
        return home.appendingPathComponent("Library/LaunchAgents/com.ebci.antigravity-quota-bar.plist")
    }
    
    func isLaunchAtLoginEnabled() -> Bool {
        return FileManager.default.fileExists(atPath: plistPath.path)
    }
    
    @objc func toggleLaunchAtLogin() {
        let enabled = isLaunchAtLoginEnabled()
        if enabled {
            try? FileManager.default.removeItem(at: plistPath)
        } else {
            let selfPath = CommandLine.arguments[0]
            let plistContent = """
            <?xml version="1.0" encoding="UTF-8"?>
            <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
            <plist version="1.0">
            <dict>
                <key>Label</key>
                <string>com.ebci.antigravity-quota-bar</string>
                <key>ProgramArguments</key>
                <array>
                    <string>\(selfPath)</string>
                </array>
                <key>RunAtLoad</key>
                <true/>
                <key>KeepAlive</key>
                <false/>
            </dict>
            </plist>
            """
            
            let launchAgentsDir = plistPath.deletingLastPathComponent()
            try? FileManager.default.createDirectory(at: launchAgentsDir, withIntermediateDirectories: true, attributes: nil)
            try? plistContent.write(to: plistPath, atomically: true, encoding: .utf8)
        }
        
        refreshData()
    }
    
    @objc func quit() {
        NSApplication.shared.terminate(nil)
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
