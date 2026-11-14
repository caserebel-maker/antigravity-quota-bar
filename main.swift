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

struct ClaudeAppRateLimitInfo {
    let fiveHourRemainingPct: Double
    let fiveHourResetTimeMs: Double
    let weeklyRemainingPct: Double
    let weeklyResetTimeMs: Double
    let opusRemainingPct: Double?
    let opusResetTimeMs: Double?
    let sonnetRemainingPct: Double?
    let sonnetResetTimeMs: Double?
}

struct GrokBotRateLimitInfo {
    let remainingPct: Double
    let resetTimeMs: Double?
    let planLabel: String
}

class QuotaRowView: NSView {
    let attrText: NSAttributedString
    let bgColor: NSColor
    let borderColor: NSColor?
    let isHeader: Bool
    
    init(attrText: NSAttributedString, bgColor: NSColor, borderColor: NSColor? = nil, isHeader: Bool = false, width: CGFloat = 430, height: CGFloat = 20) {
        self.attrText = attrText
        self.bgColor = bgColor
        self.borderColor = borderColor
        self.isHeader = isHeader
        super.init(frame: NSRect(x: 0, y: 0, width: width, height: isHeader ? 23 : 20))
    }
    
    required init?(coder: NSCoder) { fatalError() }
    
    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        let rect = bounds.insetBy(dx: isHeader ? 4 : 7, dy: 1)
        let path = NSBezierPath(roundedRect: rect, xRadius: isHeader ? 5 : 4, yRadius: isHeader ? 5 : 4)
        bgColor.setFill()
        path.fill()
        
        if let border = borderColor {
            border.setStroke()
            path.lineWidth = 1
            path.stroke()
        }
        
        attrText.draw(at: NSPoint(x: isHeader ? 12 : 14, y: isHeader ? 3.5 : 2))
    }
}

class AppDelegate: NSObject, NSApplicationDelegate {
    var statusBarItem: NSStatusItem!
    var menu: NSMenu!
    var timer: Timer?
    var isFetching = false
    
    func applicationDidFinishLaunching(_ notification: Notification) {
        statusBarItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        
        if let button = statusBarItem.button {
            button.title = "🧠"
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
            .replacingOccurrences(of: "Claude App (5h)", with: "Claude App 5h")
            .replacingOccurrences(of: "Claude App (Weekly)", with: "Claude App Wk")
            .replacingOccurrences(of: "Claude/GPT Weekly", with: "Claude/GPT Wk")
            .replacingOccurrences(of: "Claude Sonnet 5.5 (High)", with: "Sonnet 5.5 (High)")
            .replacingOccurrences(of: "Claude Opus 5.5 (High)", with: "Opus 5.5 (High)")
            .replacingOccurrences(of: "Claude Sonnet 4.6 (High)", with: "Sonnet 4.6 (High)")
            .replacingOccurrences(of: "Claude Opus 4.6 (High)", with: "Opus 4.6 (High)")
            .replacingOccurrences(of: "Gemini 3.8 Flash (High)", with: "Gemini 3.8 Flash")
            .replacingOccurrences(of: "Gemini 4 Argon (High)", with: "Gemini 4 Argon")
            .replacingOccurrences(of: "Gemini 4 Argon (Medium)", with: "Gemini 4 Argon")
            .replacingOccurrences(of: "Gemini 4 Argon (Med)", with: "Gemini 4 Argon")
            .replacingOccurrences(of: "Gemini 4 Hydrogen (High)", with: "Gemini 4 Hydrogen")
            .replacingOccurrences(of: "Gemini 4 Hydrogen (Medium)", with: "Hydrogen (Med)")
            .replacingOccurrences(of: "Gemini 4 Hydrogen (Med)", with: "Hydrogen (Med)")
            .replacingOccurrences(of: "Gemini 4 Hydrogen (XHigh)", with: "Hydrogen (XHi)")
            .replacingOccurrences(of: "Orchestrator (Argon)", with: "Orchestrator (Argon)")
            .replacingOccurrences(of: "Gemini Weekly", with: "Gemini Weekly")
            .replacingOccurrences(of: "Grok Bot (Weekly)", with: "Grok Bot Wk")
            .replacingOccurrences(of: "Codex Weekly", with: "Codex Weekly")
            .replacingOccurrences(of: " (Thinking)", with: "")
            .replacingOccurrences(of: " (Think)", with: "")
    }
    
    func formatShortResetTime(_ ms: Double) -> String {
        guard ms > 0 else { return "" }
        let minutes = Int(ms / 60000)
        let hours = minutes / 60
        let mins = minutes % 60
        
        if hours >= 24 {
            let days = hours / 24
            let remHours = hours % 24
            return " (⏱ \(days)d \(remHours)h)"
        } else if hours > 0 {
            return " (⏱ \(hours)h \(mins)m)"
        } else {
            return " (⏱ \(mins)m)"
        }
    }
    
    @objc func openWebDashboard() {
        if let url = URL(string: "https://forevier.com/quota/") {
            NSWorkspace.shared.open(url)
        }
    }
    
    func formatResetTime(_ ms: Double) -> String {
        guard ms > 0 else { return "" }
        let minutes = Int(ms / 60000)
        let hours = minutes / 60
        let mins = minutes % 60
        
        let targetDate = Date().addingTimeInterval(ms / 1000.0)
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone.current
        
        if hours >= 24 {
            let days = hours / 24
            let remHours = hours % 24
            formatter.dateFormat = "E HH:mm"
            let dateStr = formatter.string(from: targetDate)
            return " (Resets \(days)d \(remHours)h @ \(dateStr))"
        } else if hours > 0 {
            formatter.dateFormat = "HH:mm"
            let dateStr = formatter.string(from: targetDate)
            return " (Resets \(hours)h \(mins)m @ \(dateStr))"
        } else {
            formatter.dateFormat = "HH:mm"
            let dateStr = formatter.string(from: targetDate)
            return " (Resets \(mins)m @ \(dateStr))"
        }
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
        
        let sortedFiles = jsonlFiles.sorted(by: { $0.date > $1.date })
        
        for file in sortedFiles.prefix(20) {
            guard let content = try? String(contentsOf: file.url, encoding: .utf8) else {
                continue
            }
            
            let lines = content.components(separatedBy: .newlines)
            
            for line in lines.reversed() {
                if line.contains("rate_limits") {
                    if let data = line.data(using: .utf8),
                       let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                       let payload = json["payload"] as? [String: Any],
                       let rateLimits = payload["rate_limits"] as? [String: Any] {
                        
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
        }
        
        return nil
    }
    
    func runFetchClaudeQuota() -> String? {
        let task = Process()
        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = Pipe()
        
        let homeDir = FileManager.default.homeDirectoryForCurrentUser.path
        let appSupportScript = "\(homeDir)/Library/Application Support/AntigravityQuotaBar/fetch-claude-quota.js"
        let currentDirScript = "\(FileManager.default.currentDirectoryPath)/fetch-claude-quota.js"
        
        let cmd = """
        if [ -f "\(appSupportScript)" ]; then
            node "\(appSupportScript)" 2>/dev/null
        elif [ -f "\(currentDirScript)" ]; then
            node "\(currentDirScript)" 2>/dev/null
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
        let extraPaths = [
            "/opt/homebrew/bin",
            "/usr/local/bin",
            "/usr/bin",
            "/bin",
            "\(homeDir)/.local/bin"
        ] + nodePaths
        
        let currentPath = env["PATH"] ?? ""
        env["PATH"] = (extraPaths + [currentPath]).joined(separator: ":")
        task.environment = env
        
        do {
            try task.run()
            task.waitUntilExit()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            let output = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
            return (output?.isEmpty ?? true) ? nil : output
        } catch {
            return nil
        }
    }
    
    func getClaudeAppQuota() -> ClaudeAppRateLimitInfo? {
        if let rawOutput = runFetchClaudeQuota(),
           let data = rawOutput.data(using: .utf8),
           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let limits = json["limits"] as? [[String: Any]],
           !limits.isEmpty {
            
            var fiveHourPct = 1.0
            var fiveHourResetMs = 0.0
            var weeklyPct = 1.0
            var weeklyResetMs = 0.0
            
            let isoFormatter = ISO8601DateFormatter()
            isoFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            let fallbackIso = ISO8601DateFormatter()
            fallbackIso.formatOptions = [.withInternetDateTime]
            let now = Date().timeIntervalSince1970
            
            for limit in limits {
                let kind = limit["kind"] as? String ?? ""
                let percentUsed = (limit["percent"] as? NSNumber)?.doubleValue ?? 0.0
                let remainingPct = max(0.0, 1.0 - (percentUsed / 100.0))
                
                var resetTimeMs = 0.0
                if let resetsAtStr = limit["resets_at"] as? String {
                    if let targetDate = isoFormatter.date(from: resetsAtStr) ?? fallbackIso.date(from: resetsAtStr) {
                        resetTimeMs = max(0.0, (targetDate.timeIntervalSince1970 - now) * 1000.0)
                    }
                }
                
                if kind == "session" {
                    fiveHourPct = remainingPct
                    fiveHourResetMs = resetTimeMs
                } else if kind == "weekly_all" {
                    weeklyPct = remainingPct
                    weeklyResetMs = resetTimeMs
                }
            }
            
            return ClaudeAppRateLimitInfo(
                fiveHourRemainingPct: fiveHourPct,
                fiveHourResetTimeMs: fiveHourResetMs,
                weeklyRemainingPct: weeklyPct,
                weeklyResetTimeMs: weeklyResetMs,
                opusRemainingPct: nil,
                opusResetTimeMs: nil,
                sonnetRemainingPct: nil,
                sonnetResetTimeMs: nil
            )
        }

        let fileManager = FileManager.default
        let homeDir = fileManager.homeDirectoryForCurrentUser
        let historyFile = homeDir.appendingPathComponent("Library/Application Support/Claude/plan-usage-history.json")
        
        guard fileManager.fileExists(atPath: historyFile.path),
              let data = try? Data(contentsOf: historyFile),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let samples = json["samples"] as? [[String: Any]],
              !samples.isEmpty else {
            return nil
        }
        
        guard let latest = samples.max(by: {
            let t1 = ($0["t"] as? NSNumber)?.int64Value ?? 0
            let t2 = ($1["t"] as? NSNumber)?.int64Value ?? 0
            return t1 < t2
        }) else {
            return nil
        }
        
        let sampleTimeMs = (latest["t"] as? NSNumber)?.doubleValue ?? 0.0
        let nowMs = Date().timeIntervalSince1970 * 1000.0
        
        let u = latest["u"] as? [String: Any] ?? [:]
        
        let fhUsed = (u["fh"] as? NSNumber)?.doubleValue ?? 0.0
        let fhNormalized = fhUsed > 1.0 ? (fhUsed / 100.0) : fhUsed
        let fiveHourRemaining = max(0.0, 1.0 - fhNormalized)
        var fiveHourResetMs = 0.0
        if fhUsed > 0 && sampleTimeMs > 0 {
            let expireMs = sampleTimeMs + (5.0 * 3600.0 * 1000.0)
            fiveHourResetMs = max(0.0, expireMs - nowMs)
        }
        
        let sdUsed = (u["sd"] as? NSNumber)?.doubleValue ?? 0.0
        let sdNormalized = sdUsed > 1.0 ? (sdUsed / 100.0) : sdUsed
        let weeklyRemaining = max(0.0, 1.0 - sdNormalized)
        var weeklyResetMs = 0.0
        if sdUsed > 0 && sampleTimeMs > 0 {
            let expireMs = sampleTimeMs + (7.0 * 24.0 * 3600.0 * 1000.0)
            weeklyResetMs = max(0.0, expireMs - nowMs)
        }
        
        var opusRemaining: Double? = nil
        var opusResetMs: Double? = nil
        if let soUsedNum = u["so"] as? NSNumber {
            let soUsed = soUsedNum.doubleValue
            opusRemaining = max(0.0, 1.0 - soUsed)
            if soUsed > 0 && sampleTimeMs > 0 {
                let expireMs = sampleTimeMs + (7.0 * 24.0 * 3600.0 * 1000.0)
                opusResetMs = max(0.0, expireMs - nowMs)
            } else {
                opusResetMs = 0.0
            }
        }
        
        var sonnetRemaining: Double? = nil
        var sonnetResetMs: Double? = nil
        if let snUsedNum = u["sn"] as? NSNumber {
            let snUsed = snUsedNum.doubleValue
            sonnetRemaining = max(0.0, 1.0 - snUsed)
            if snUsed > 0 && sampleTimeMs > 0 {
                let expireMs = sampleTimeMs + (7.0 * 24.0 * 3600.0 * 1000.0)
                sonnetResetMs = max(0.0, expireMs - nowMs)
            } else {
                sonnetResetMs = 0.0
            }
        }
        
        return ClaudeAppRateLimitInfo(
            fiveHourRemainingPct: fiveHourRemaining,
            fiveHourResetTimeMs: fiveHourResetMs,
            weeklyRemainingPct: weeklyRemaining,
            weeklyResetTimeMs: weeklyResetMs,
            opusRemainingPct: opusRemaining,
            opusResetTimeMs: opusResetMs,
            sonnetRemainingPct: sonnetRemaining,
            sonnetResetTimeMs: sonnetResetMs
        )
    }
    
    func getGrokBotQuota() -> GrokBotRateLimitInfo? {
        let fileManager = FileManager.default
        let homeDir = fileManager.homeDirectoryForCurrentUser
        let persistenceDir = homeDir.appendingPathComponent("Library/Application Support/Grok Bot/sand-client-persistence")
        
        guard let files = try? fileManager.contentsOfDirectory(at: persistenceDir, includingPropertiesForKeys: nil) else {
            return nil
        }
        
        for fileURL in files {
            guard fileURL.pathExtension == "blob" else { continue }
            guard let data = try? Data(contentsOf: fileURL),
                  let str = String(data: data, encoding: .utf8),
                  str.contains("percentUsed") && str.contains("nextResetMs") else {
                continue
            }
            
            guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let val = json["value"] as? [String: Any],
                  let reading = val["reading"] as? [String: Any],
                  let usage = reading["usage"] as? [String: Any] else {
                continue
            }
            
            let percentUsed = (usage["percentUsed"] as? NSNumber)?.doubleValue ?? 0.0
            let remainingPct = max(0.0, min(1.0, (100.0 - percentUsed) / 100.0))
            
            var resetMs: Double? = nil
            if let nextResetNum = usage["nextResetMs"] as? NSNumber {
                let nextResetEpochMs = nextResetNum.doubleValue
                let nowMs = Date().timeIntervalSince1970 * 1000.0
                resetMs = max(0.0, nextResetEpochMs - nowMs)
            }
            
            let plan = (usage["grokPlanLabel"] as? String) ?? (usage["unifiedPlanName"] as? String) ?? "Grok Bot"
            
            return GrokBotRateLimitInfo(
                remainingPct: remainingPct,
                resetTimeMs: resetMs,
                planLabel: plan
            )
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
            button.title = "🧠"
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
            let claudeAppInfo = self?.getClaudeAppQuota()
            let grokBotInfo = self?.getGrokBotQuota()
            
            DispatchQueue.main.async {
                if var validOutput = output {
                    if let claudeApp = claudeAppInfo {
                        validOutput.models.append(ModelQuota(
                            label: "Claude App (5h)",
                            remainingPercentage: claudeApp.fiveHourRemainingPct,
                            timeUntilResetMs: claudeApp.fiveHourResetTimeMs > 0 ? claudeApp.fiveHourResetTimeMs : nil
                        ))
                        validOutput.models.append(ModelQuota(
                            label: "Claude App (Weekly)",
                            remainingPercentage: claudeApp.weeklyRemainingPct,
                            timeUntilResetMs: claudeApp.weeklyResetTimeMs > 0 ? claudeApp.weeklyResetTimeMs : nil
                        ))
                        if let opusPct = claudeApp.opusRemainingPct {
                            validOutput.models.append(ModelQuota(
                                label: "Claude App (Opus)",
                                remainingPercentage: opusPct,
                                timeUntilResetMs: claudeApp.opusResetTimeMs
                            ))
                        }
                        if let sonnetPct = claudeApp.sonnetRemainingPct {
                            validOutput.models.append(ModelQuota(
                                label: "Claude App (Sonnet)",
                                remainingPercentage: sonnetPct,
                                timeUntilResetMs: claudeApp.sonnetResetTimeMs
                            ))
                        }
                    }
                    if let grok = grokBotInfo {
                        validOutput.models.append(ModelQuota(
                            label: "Grok Bot (Weekly)",
                            remainingPercentage: grok.remainingPct,
                            timeUntilResetMs: grok.resetTimeMs
                        ))
                    }
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
                } else if codexInfo != nil || claudeAppInfo != nil || grokBotInfo != nil {
                    var fallbackModels: [ModelQuota] = []
                    if let claudeApp = claudeAppInfo {
                        fallbackModels.append(ModelQuota(
                            label: "Claude App (5h)",
                            remainingPercentage: claudeApp.fiveHourRemainingPct,
                            timeUntilResetMs: claudeApp.fiveHourResetTimeMs > 0 ? claudeApp.fiveHourResetTimeMs : nil
                        ))
                        fallbackModels.append(ModelQuota(
                            label: "Claude App (Weekly)",
                            remainingPercentage: claudeApp.weeklyRemainingPct,
                            timeUntilResetMs: claudeApp.weeklyResetTimeMs > 0 ? claudeApp.weeklyResetTimeMs : nil
                        ))
                    }
                    if let grok = grokBotInfo {
                        fallbackModels.append(ModelQuota(
                            label: "Grok Bot (Weekly)",
                            remainingPercentage: grok.remainingPct,
                            timeUntilResetMs: grok.resetTimeMs
                        ))
                    }
                    if let codex = codexInfo {
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
                    }
                    
                    let fallbackOutput = QuotaData(
                        email: "Antigravity CLI Offline",
                        method: "Local Cache",
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
    
    func syncToCloud(output: QuotaData) {
        DispatchQueue.global(qos: .background).async {
            let appSupportDir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?.appendingPathComponent("AntigravityQuotaBar")
            guard let dir = appSupportDir else { return }
            let jsonPath = dir.appendingPathComponent("quota.json")
            let scriptPath = dir.appendingPathComponent("sync-cloud.sh")
            
            let encoder = JSONEncoder()
            encoder.outputFormatting = .prettyPrinted
            if let data = try? encoder.encode(output) {
                try? data.write(to: jsonPath)
            }
            
            if FileManager.default.fileExists(atPath: scriptPath.path) {
                let task = Process()
                task.launchPath = "/bin/bash"
                task.arguments = [scriptPath.path]
                try? task.run()
            }
        }
    }
    
    func updateUI(with output: QuotaData) {
        isFetching = false
        syncToCloud(output: output)
        
        let filteredModels = output.models.filter { model in
            let lbl = model.label
            if lbl.contains("3.1") || lbl.contains("3.6") { return false }
            if lbl.contains("GPT-OSS") || lbl.lowercased().contains("gptoss") { return false }
            if lbl.contains("3.7") && lbl.contains("Low") { return false }
            
            // Claude Sonnet & Opus: keep only High, remove Medium and Low
            if (lbl.contains("Sonnet") || lbl.contains("Opus") || lbl.contains("Claude")) && !lbl.starts(with: "Claude App") {
                if !lbl.contains("Claude/GPT") { // keep pool summary models (Claude/GPT 5h, Claude/GPT Weekly)
                    if !lbl.contains("(High)") && !lbl.contains("(Hi") {
                        return false
                    }
                }
            }
            
            // Gemini 3.8: keep only High, remove Medium and Low
            if lbl.contains("3.8") {
                if !lbl.contains("(High)") && !lbl.contains("(Hi") {
                    return false
                }
            }
            
            // Argon & Hydrogen: remove Low tier
            if (lbl.contains("Argon") || lbl.contains("Hydrogen")) && (lbl.contains("Low") || lbl.contains("(Lo")) {
                return false
            }
            return true
        }
        
        let gemWeekly = filteredModels.first(where: { $0.label == "Gemini Weekly" })
        let gem5h = filteredModels.first(where: { $0.label == "Gemini 5h" })
        
        if let g5h = gem5h, let gWk = gemWeekly,
           let p5h = g5h.remainingPercentage, let pWk = gWk.remainingPercentage {
            let val5h = Int(round(p5h * 100))
            let valWk = Int(round(pWk * 100))
            if let button = statusBarItem.button {
                button.title = "🧠"
                var tips: [String] = []
                if let r5h = g5h.timeUntilResetMs, r5h > 0 {
                    tips.append("Gemini 5h: \(val5h)%\(self.formatResetTime(r5h))")
                }
                if let rWk = gWk.timeUntilResetMs, rWk > 0 {
                    tips.append("Gemini Weekly: \(valWk)%\(self.formatResetTime(rWk))")
                }
                tips.append("Click to view full quota status")
                button.toolTip = tips.joined(separator: "\n")
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
                button.title = "🧠"
                button.toolTip = "Lowest: \(displayPct)% (\(shortName))\nClick to view full quota status"
            }
        }
        
        menu.removeAllItems()
        
        let titleItem = createMenuItem(text: "🧠 ANTIGRAVITY QUOTA STATUS", isBold: true)
        titleItem.isEnabled = false
        menu.addItem(titleItem)
        
        let dateFormatter = DateFormatter()
        dateFormatter.timeStyle = .medium
        let infoItem = createMenuItem(text: "\(output.email) · Sync: \(dateFormatter.string(from: Date()))", color: .secondaryLabelColor)
        infoItem.isEnabled = false
        menu.addItem(infoItem)
        
        menu.addItem(NSMenuItem.separator())
        
        // 1. 🔵 GEMINI (GOOGLE) - Faint Blue
        var geminiSectionModels: [ModelQuota] = []
        if let g5h = filteredModels.first(where: { $0.label == "Gemini 5h" }) { geminiSectionModels.append(g5h) }
        if let gw = filteredModels.first(where: { $0.label == "Gemini Weekly" }) { geminiSectionModels.append(gw) }
        if let argWk = filteredModels.first(where: { $0.label == "Argon Weekly" }) { geminiSectionModels.append(argWk) }
        if let gFlash = filteredModels.first(where: { $0.label.contains("Gemini 3.8") && $0.label.contains("High") }) { geminiSectionModels.append(gFlash) }
        if let gArgon = filteredModels.first(where: { $0.label.contains("Argon") && ($0.label.contains("High") || $0.label.contains("Med")) }) {
            if !geminiSectionModels.contains(where: { $0.label == gArgon.label }) { geminiSectionModels.append(gArgon) }
        }
        if let gHydro = filteredModels.first(where: { $0.label.contains("Hydrogen") && $0.label.contains("High") }) ?? filteredModels.first(where: { $0.label.contains("Hydrogen") }) {
            if !geminiSectionModels.contains(where: { $0.label == gHydro.label }) { geminiSectionModels.append(gHydro) }
        }
        if let orch = filteredModels.first(where: { $0.label.contains("Orchestrator") }) {
            if !geminiSectionModels.contains(where: { $0.label == orch.label }) { geminiSectionModels.append(orch) }
        }
        
        // 2. 🟠 CLAUDE (ANTHROPIC) - Faint Orange
        var claudeSectionModels: [ModelQuota] = []
        let cApp = filteredModels.filter { $0.label.starts(with: "Claude App") }
            .sorted { ($0.label.contains("5h") ? 1 : 2) < ($1.label.contains("5h") ? 1 : 2) }
        claudeSectionModels.append(contentsOf: cApp)
        if let c5h = filteredModels.first(where: { $0.label == "Claude/GPT 5h" }) { claudeSectionModels.append(c5h) }
        if let cw = filteredModels.first(where: { $0.label == "Claude/GPT Weekly" }) { claudeSectionModels.append(cw) }
        if let sonnet = filteredModels.first(where: { $0.label.contains("Sonnet") && $0.label.contains("High") }) { claudeSectionModels.append(sonnet) }
        if let opus = filteredModels.first(where: { $0.label.contains("Opus") && $0.label.contains("High") }) { claudeSectionModels.append(opus) }

        // 3. ⚡ GROK (XAI) - Faint Black
        let grokSectionModels = filteredModels.filter { $0.label.starts(with: "Grok Bot") }

        // 4. ⚪ OPENAI / CODEX - Faint White
        let codexSectionModels = filteredModels.filter { $0.label.starts(with: "Codex") }
            .sorted { ($0.label.contains("5h") ? 1 : 2) < ($1.label.contains("5h") ? 1 : 2) }
            
        func appendModelRow(_ model: ModelQuota, rowBg: NSColor, rowBorder: NSColor?, barColor: NSColor) {
            let remainingPct = model.remainingPercentage ?? 1.0
            let pctVal = Int(round(remainingPct * 100))
            let width = 10
            let filledLen = Int(round(remainingPct * Double(width)))
            let emptyLen = width - filledLen
            let filled = String(repeating: "█", count: max(0, filledLen))
            let empty = String(repeating: "░", count: max(0, emptyLen))
            
            let shortLabel = cleanModelLabel(model.label).padding(toLength: 20, withPad: " ", startingAt: 0)
            
            var resetStr = ""
            if pctVal < 100, let resetMs = model.timeUntilResetMs, resetMs > 0 {
                resetStr = formatShortResetTime(resetMs)
            }
            
            let font = NSFont(name: "Monaco", size: 12) ?? NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)
            
            let attrStr = NSMutableAttributedString()
            attrStr.append(NSAttributedString(string: "\(shortLabel) [", attributes: [
                .font: font,
                .foregroundColor: NSColor.white
            ]))
            attrStr.append(NSAttributedString(string: filled, attributes: [
                .font: font,
                .foregroundColor: barColor
            ]))
            attrStr.append(NSAttributedString(string: empty, attributes: [
                .font: font,
                .foregroundColor: NSColor.white.withAlphaComponent(0.22)
            ]))
            attrStr.append(NSAttributedString(string: "] \(String(format: "%3d%%", pctVal))", attributes: [
                .font: font,
                .foregroundColor: barColor
            ]))
            if !resetStr.isEmpty {
                attrStr.append(NSAttributedString(string: resetStr, attributes: [
                    .font: font,
                    .foregroundColor: NSColor.secondaryLabelColor
                ]))
            }
            
            let modelItem = NSMenuItem()
            modelItem.view = QuotaRowView(attrText: attrStr, bgColor: rowBg, borderColor: rowBorder, isHeader: false)
            menu.addItem(modelItem)
        }
        
        func addSection(
            header: String,
            models: [ModelQuota],
            headerColor: NSColor,
            headerBg: NSColor,
            headerBorder: NSColor,
            rowBg: NSColor,
            rowBorder: NSColor,
            barColor: NSColor
        ) {
            guard !models.isEmpty else { return }
            
            let font = NSFont(name: "Monaco-Bold", size: 12) ?? NSFont.monospacedSystemFont(ofSize: 12, weight: .bold)
            let headerAttr = NSAttributedString(string: header, attributes: [
                .font: font,
                .foregroundColor: headerColor
            ])
            
            let headerItem = NSMenuItem()
            headerItem.view = QuotaRowView(attrText: headerAttr, bgColor: headerBg, borderColor: headerBorder, isHeader: true)
            menu.addItem(headerItem)
            
            for model in models {
                appendModelRow(model, rowBg: rowBg, rowBorder: rowBorder, barColor: barColor)
            }
            
            menu.addItem(NSMenuItem.separator())
        }
        
        // 1. 🔵 GEMINI (GOOGLE) - สีฟ้า
        addSection(
            header: "─── 🔵 GEMINI (GOOGLE) ────────────────────",
            models: geminiSectionModels,
            headerColor: NSColor(red: 0.35, green: 0.75, blue: 1.0, alpha: 1.0),
            headerBg: NSColor(red: 0.15, green: 0.55, blue: 0.95, alpha: 0.22),
            headerBorder: NSColor(red: 0.15, green: 0.55, blue: 0.95, alpha: 0.45),
            rowBg: NSColor(red: 0.15, green: 0.55, blue: 0.95, alpha: 0.10),
            rowBorder: NSColor(red: 0.15, green: 0.55, blue: 0.95, alpha: 0.20),
            barColor: NSColor(red: 0.35, green: 0.75, blue: 1.0, alpha: 1.0)
        )
        
        // 2. 🟠 CLAUDE (ANTHROPIC) - สีส้ม
        addSection(
            header: "─── 🟠 CLAUDE (ANTHROPIC) ─────────────────",
            models: claudeSectionModels,
            headerColor: NSColor(red: 1.0, green: 0.65, blue: 0.25, alpha: 1.0),
            headerBg: NSColor(red: 0.96, green: 0.45, blue: 0.10, alpha: 0.22),
            headerBorder: NSColor(red: 0.96, green: 0.45, blue: 0.10, alpha: 0.45),
            rowBg: NSColor(red: 0.96, green: 0.45, blue: 0.10, alpha: 0.10),
            rowBorder: NSColor(red: 0.96, green: 0.45, blue: 0.10, alpha: 0.20),
            barColor: NSColor(red: 1.0, green: 0.60, blue: 0.20, alpha: 1.0)
        )
        
        // 3. ⚡ GROK (XAI) - สีดำ
        addSection(
            header: "─── ⚡ GROK (XAI) ─────────────────────────",
            models: grokSectionModels,
            headerColor: NSColor(red: 0.98, green: 0.45, blue: 0.55, alpha: 1.0),
            headerBg: NSColor(white: 0.08, alpha: 0.60),
            headerBorder: NSColor(white: 1.0, alpha: 0.25),
            rowBg: NSColor(white: 0.08, alpha: 0.38),
            rowBorder: NSColor(white: 1.0, alpha: 0.14),
            barColor: NSColor(red: 0.98, green: 0.45, blue: 0.55, alpha: 1.0)
        )
        
        // 4. ⚪ OPENAI / CODEX - สีขาว
        addSection(
            header: "─── ⚪ OPENAI / CODEX ─────────────────────",
            models: codexSectionModels,
            headerColor: NSColor(white: 0.95, alpha: 1.0),
            headerBg: NSColor(white: 1.0, alpha: 0.18),
            headerBorder: NSColor(white: 1.0, alpha: 0.40),
            rowBg: NSColor(white: 1.0, alpha: 0.09),
            rowBorder: NSColor(white: 1.0, alpha: 0.18),
            barColor: NSColor.white
        )
        
        let webItem = NSMenuItem(title: "🌐 Open Web Dashboard", action: #selector(openWebDashboard), keyEquivalent: "w")
        webItem.target = self
        menu.addItem(webItem)
        
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
            button.title = "🧠"
            button.toolTip = "Error fetching quota: \(errorMsg)"
        }
        
        menu.removeAllItems()
        let errTitle = createMenuItem(text: "🧠 QUOTA ERROR", color: .systemRed, isBold: true)
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
