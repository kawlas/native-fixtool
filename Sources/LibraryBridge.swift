import AppKit
// SPDX-License-Identifier: LicenseRef-NI-Fix-Tool-Private-Use-1.0
import Combine
import CoreText
import Darwin
import UniformTypeIdentifiers

struct LibraryRow: Codable, Identifiable, Hashable {
    let id: String
    let folder: String
    let title: String
    let state: String
    let reason: String
    let version: String
    let targetVersion: String
    let upid: String
    let identitySource: String
    let registeredPath: String?
    var recoverable: Bool { state == "canLocate" || state == "receiptAvailable" }
    var registered: Bool { state == "registered" }
}
struct ScanSummary: Codable {
    let total: Int
    let registered: Int
    let recoverable: Int
    let review: Int
}
struct Connection: Codable {
    let connected: Bool
    let version: String
    let message: String
    let supportsRepair: Bool
}
struct DownloadInfo: Codable, Identifiable {
    let title: String
    let state: String
    let progress: Double
    let verifiedFilesObserved: Int
    let httpGetRequestsObserved: Int
    var id: String { title }
}
struct UpdateAudit: Codable {
    let date: String
    let totalFiles: Int
    let matchingFiles: Int
    let totalBytes: Int64
    let matchingFileBytes: Int64
    let matchingPieceBytes: Int64
    let changedFileBytes: Int64
    let estimatedTransferBytes: Int64
}
struct UpdateRow: Codable, Identifiable, Hashable {
    let id: String
    let upid: String
    let title: String
    let folder: String
    let installedVersion: String
    let targetVersion: String
    let state: String
    let reason: String
    let artifactID: String
    let contentBytes: Int64?
    let audit: UpdateAudit?
    static func == (a: Self, b: Self) -> Bool {
        a.id == b.id && a.state == b.state && a.installedVersion == b.installedVersion
            && a.targetVersion == b.targetVersion && a.audit?.estimatedTransferBytes == b.audit?.estimatedTransferBytes
    }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
}
struct UpdateStatus: Codable {
    let upid: String
    let title: String
    let targetVersion: String
    let installedVersion: String
    let state: String
    let progress: Double
}
struct OperationError: Codable {
    let title: String?
    let message: String
}
struct ResultEvent: Codable {
    let command: String
    let root: String?
    let connection: Connection?
    let rows: [LibraryRow]?
    let summary: ScanSummary?
    let planFile: String?
    let planID: String?
    let downloads: [DownloadInfo]?
    let reportPath: String?
    let backupPath: String?
    let vault: String?
    let saved: Int?
    let errors: [OperationError]?
    let cancelled: Bool?
    let verified: Int?
    let total: Int?
    let changedFileBytes: Int64?
    let updates: [UpdateRow]?
    let updatePlanFile: String?
    let updateSessionFile: String?
    let updateStatuses: [UpdateStatus]?
    let suggestedLibraryPath: String?
    let started: Int?
}
struct ActivityItem: Identifiable {
    let id = UUID()
    let date = Date()
    let text: String
}
enum Section: String, CaseIterable { case home, libraries, updates, migration, help, activity }

@MainActor final class BridgeModel: ObservableObject {
    @Published var root = ""
    @Published var rows: [LibraryRow] = []
    @Published var selected = Set<String>()
    @Published var summary: ScanSummary?
    @Published var connection: Connection?
    @Published var downloads: [DownloadInfo] = []
    @Published var updates: [UpdateRow] = []
    @Published var updatesLoaded = false
    @Published var suggestedRoot = ""
    @Published var selectedUpdates = Set<String>()
    @Published var updateStatuses: [UpdateStatus] = []
    var updatePolling = true
    var updatePlanFile: String?
    var updateSessionFile: String? = UserDefaults.standard.string(forKey: "updateSessionFile")
    @Published var previewMode = false
    @Published var busy = false
    @Published var stage = ""
    @Published var progressTitle = ""
    @Published var current = 0
    @Published var total = 0
    @Published var cancelled = false
    @Published var activity: [ActivityItem] = []
    @Published var error: String?
    @Published var notice: String?
    @Published var lastReport: String?
    @Published var section: Section = .home
    @Published var query = ""
    @Published var filter = "all"
    @Published var showRepairReview = false
    @Published var setContent = true
    @Published var cancelRedundant = true
    @Published var language = UserDefaults.standard.string(forKey: "language") ?? "pl" {
        didSet { UserDefaults.standard.set(language, forKey: "language") }
    }
    var planFile: String?
    var process: Process?
    var activeCommand = ""
    private var buffer = Data()
    private var hadResult = false
    private var stderrText = ""
    var isPolish: Bool { language == "pl" }
    func t(_ pl: String, _ en: String) -> String { isPolish ? pl : en }
    var updateSelection: [UpdateRow] { updates.filter { selectedUpdates.contains($0.id) && $0.state == "ready" } }
    func bytes(_ n: Int64?) -> String {
        n.map { ByteCountFormatter.string(fromByteCount: $0, countStyle: .file) } ?? t("nieustalone", "unknown")
    }
    func loadUpdates() {
        if !updateStatuses.isEmpty && updateStatuses.allSatisfy({ $0.state == "confirmed" }) {
            updateSessionFile = nil
            updateStatuses = []
            UserDefaults.standard.removeObject(forKey: "updateSessionFile")
        }
        start("updates", extra: [])
    }
    func auditUpdates() {
        guard let updatePlanFile, !updateSelection.isEmpty else { return }
        let ids = String(data: try! JSONEncoder().encode(updateSelection.map(\.id)), encoding: .utf8)!
        start("update-audit", extra: ["--plan", updatePlanFile, "--selected", ids])
    }
    func startUpdates() {
        guard let updatePlanFile, !updateSelection.isEmpty else { return }
        let ids = String(data: try! JSONEncoder().encode(updateSelection.map(\.id)), encoding: .utf8)!
        start("update-start", extra: ["--plan", updatePlanFile, "--selected", ids])
    }
    func updateSession(_ command: String = "update-status") {
        if let updateSessionFile { start(command, extra: ["--session", updateSessionFile]) }
    }
    var recoverableSelection: [LibraryRow] { rows.filter { selected.contains($0.id) && $0.recoverable } }
    var visibleRows: [LibraryRow] {
        rows.filter { row in
            let statusMatches =
                filter == "all" || (filter == "ready" && row.recoverable) || (filter == "registered" && row.registered)
                || (filter == "review" && !row.registered && !row.recoverable)
            return statusMatches
                && (query.isEmpty || row.title.localizedCaseInsensitiveContains(query)
                    || row.folder.localizedCaseInsensitiveContains(query))
        }
    }
    var vaultURL: URL? { root.isEmpty ? nil : URL(fileURLWithPath: root).appendingPathComponent(".library-bridge") }
    func status(_ row: LibraryRow) -> String {
        switch row.state {
        case "registered": return t("Gotowa w Native Access", "Ready in Native Access")
        case "canLocate": return t("Można przywrócić", "Ready to recover")
        case "receiptAvailable": return t("Można sprawdzić kopię", "Backup can be checked")
        case "registeredElsewhere": return t("Działa w innym folderze", "Works in another folder")
        case "notOwned": return t("Brak na Twoim koncie NI", "Not on your NI account")
        case "offline": return t("Otwórz Native Access", "Open Native Access")
        default: return t("Do sprawdzenia", "Needs review")
        }
    }
    func statusIcon(_ row: LibraryRow) -> String {
        if row.registered { return "checkmark.circle.fill" }
        if row.recoverable { return "arrow.triangle.branch" }
        return "info.circle"
    }
    func statusColor(_ row: LibraryRow) -> NSColor {
        row.registered ? .systemGreen : row.recoverable ? .controlAccentColor : .secondaryLabelColor
    }
    var stageLabel: String {
        switch stage {
        case "updateCatalog": return t("Odczytuję aktualizacje z konta NI…", "Reading updates from your NI account…")
        case "updateManifest":
            return t("Pobieram opis plików, bez dźwięków…", "Fetching file metadata, without samples…")
        case "auditUpdates":
            return t("Sprawdzam pliki na SSD — bez pobierania…", "Checking SSD files — no content download…")
        case "startUpdate": return t("Uruchamiam aktualizację NI…", "Starting the NI update…")
        case "connect": return t("Łączę z Native Access…", "Connecting to Native Access…")
        case "scan":
            return t(
                "Sprawdzam, które biblioteki widzi Native Access…", "Checking which libraries Native Access recognises…"
            )
        case "repair": return t("Podłączam istniejącą bibliotekę…", "Reconnecting an existing library…")
        case "verify": return t("Porównuję pliki na dysku…", "Comparing files on the drive…")
        case "snapshot":
            return t("Zapisuję informacje potrzebne na nowym Macu…", "Saving information needed on your new Mac…")
        case "snapshotFiles":
            return t(
                "Sprawdzam pliki i przygotowuję dane do przeniesienia…",
                "Checking files and preparing migration information…")
        case "refresh": return t("Czekam na skan i aktywację NI…", "Waiting for NI to scan and activate…")
        case "cancelling": return t("Kończę bieżącą operację…", "Finishing the current operation…")
        default: return t("Pracuję…", "Working…")
        }
    }
    func log(_ text: String) {
        activity.append(ActivityItem(text: text))
        if activity.count > 600 { activity.removeFirst(activity.count - 600) }
    }
    func chooseFolder() {
        guard !busy else { return }
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.message = t(
            "Wybierz wspólny folder z bibliotekami, np. NI na zewnętrznym dysku. W środku powinny być foldery poszczególnych instrumentów. Nie wybieraj pojedynczego pliku z dźwiękiem.",
            "Choose the folder containing your libraries, for example NI on an external drive. It should contain the individual instrument folders. Do not select a single sample file."
        )
        panel.prompt = t("Użyj tego folderu", "Use this folder")
        if !root.isEmpty {
            panel.directoryURL = URL(fileURLWithPath: root)
        } else if !suggestedRoot.isEmpty {
            panel.directoryURL = URL(fileURLWithPath: suggestedRoot)
        }
        if panel.runModal() == .OK, let url = panel.url {
            setRoot(url.path)
            loadCurrentTask()
        }
    }
    func setRoot(_ path: String) {
        if !root.isEmpty && root != path {
            updateStatuses = []
            updateSessionFile = nil
            UserDefaults.standard.removeObject(forKey: "updateSessionFile")
        }
        previewMode = false
        root = path
        UserDefaults.standard.set(path, forKey: "libraryPath")
        rows = []
        summary = nil
        planFile = nil
        selected = []
        downloads = []
        updates = []
        updatesLoaded = false
        selectedUpdates = []
        updatePlanFile = nil
        error = nil
        notice = nil
    }
    func loadCurrentTask() {
        if section == .updates { loadUpdates() } else if section == .libraries || section == .migration { scan() }
    }
    func go(_ section: Section) {
        self.section = section
        guard !previewMode, !busy, !root.isEmpty else { return }
        if section == .updates && !updatesLoaded {
            loadUpdates()
        } else if (section == .libraries || section == .migration) && summary == nil {
            scan()
        }
    }
    func initialLoad() {
        BridgeAppDelegate.model = self
        let args = CommandLine.arguments
        if let i = args.firstIndex(of: "--language"), args.count > i + 1 { language = args[i + 1] }
        if let i = args.firstIndex(of: "--section"), args.count > i + 1, let section = Section(rawValue: args[i + 1]) {
            self.section = section
        }
        if let i = args.firstIndex(of: "--scan-result"), args.count > i + 1 {
            let file = URL(fileURLWithPath: args[i + 1])
            do {
                let data = try Data(contentsOf: file)
                let lines = String(decoding: data, as: UTF8.self).split(separator: "\n")
                if let line = lines.last,
                    let object = try JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any],
                    let root = object["root"] as? String
                {
                    self.root = root
                }
                previewMode = true
                consume(data)
                planFile = nil
                updatePlanFile = nil
                updateSessionFile = nil
                selected = []
                selectedUpdates = []
                notice = t(
                    "Podgląd zapisanego skanu — odczyt. Aktualny stan wymaga ponownego skanowania dysku.",
                    "Saved scan preview — read-only. Scan the drive again to check its current state.")
                captureOwnWindowIfRequested()
                return
            } catch {
                self.error = error.localizedDescription
                return
            }
        }

        if let i = args.firstIndex(of: "--library"), args.count > i + 1 {
            setRoot(args[i + 1])
            loadCurrentTask()
        } else if let saved = UserDefaults.standard.string(forKey: "libraryPath"), !saved.isEmpty {
            setRoot(saved)
            loadCurrentTask()
        }
        if root.isEmpty && !CommandLine.arguments.contains("--no-discovery") { start("discover", extra: []) }
        captureOwnWindowIfRequested()
    }
    func scan() {
        guard !root.isEmpty, !busy else { return }
        start("scan", extra: [])
    }
    func repair() {
        guard let planFile, !recoverableSelection.isEmpty else { return }
        let ids = recoverableSelection.map(\.id)
        let json = String(data: try! JSONEncoder().encode(ids), encoding: .utf8)!
        start(
            "repair",
            extra: [
                "--plan", planFile, "--selected", json, "--set-content", String(setContent), "--cancel-redundant",
                String(cancelRedundant),
            ])
    }
    func snapshot() { start("snapshot", extra: []) }
    func verify(_ row: LibraryRow) {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [
            UTType(filenameExtension: "metalink") ?? .xml, UTType(filenameExtension: "meta4") ?? .xml,
        ]
        panel.message = t(
            "Wybierz oficjalny manifest Metalink dla tej biblioteki, zapisany przez Native Access. To audyt plików, bez pobierania.",
            "Select the official Metalink manifest saved by Native Access for this library. This checks files without downloading."
        )
        panel.directoryURL = URL(fileURLWithPath: "/private/tmp")
        if panel.runModal() == .OK, let url = panel.url {
            start("verify", extra: ["--manifest", url.path], libraryOverride: row.folder)
        }
    }
    func cancel() {
        guard busy, !cancelled else { return }
        cancelled = true
        stage = "cancelling"
        process?.interrupt()
        if ["scan", "verify", "updates", "update-audit", "update-status"].contains(activeCommand), let task = process {
            DispatchQueue.main.asyncAfter(deadline: .now() + 5) { [weak self] in
                guard let self, self.busy, self.cancelled, self.process === task, task.isRunning else { return }
                // These two commands never write NI registration or library content.
                Darwin.kill(task.processIdentifier, SIGKILL)
            }
        }
        log(t("Poproszono o bezpieczne przerwanie.", "Cancellation requested; current write will finish safely."))
    }
    func openNative() { NSWorkspace.shared.open(URL(fileURLWithPath: "/Applications/Native Access.app")) }
    func reveal(_ path: String) { NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: path)]) }
    func exportReport() {
        guard let lastReport else { return }
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "Library-Bridge-report.json"
        panel.allowedContentTypes = [.json]
        if panel.runModal() == .OK, let url = panel.url {
            do {
                let data = try Data(contentsOf: URL(fileURLWithPath: lastReport))
                try data.write(to: url, options: .atomic)
            } catch { self.error = error.localizedDescription }
        }
    }
    func start(_ command: String, extra: [String], libraryOverride: String? = nil) {
        guard !busy, command == "discover" || !root.isEmpty else { return }
        if previewMode && command != "scan" {
            error = t(
                "Otwórz działającą instalację przed wykonaniem zmian.",
                "Open a live installation before making changes.")
            return
        }
        previewMode = false
        guard let resources = Bundle.main.resourceURL else {
            error = "Application resources are missing."
            return
        }
        #if arch(arm64)
            let node = resources.appendingPathComponent("bin/node-arm64")
        #else
            let node = resources.appendingPathComponent("bin/node-x64")
        #endif
        let script = resources.appendingPathComponent("backend/cli.mjs")
        guard FileManager.default.isExecutableFile(atPath: node.path),
            FileManager.default.fileExists(atPath: script.path)
        else {
            error = t(
                "Brakuje plików aplikacji. Zainstaluj ponownie cały pakiet .app.",
                "Application files are missing. Reinstall the complete .app bundle.")
            return
        }
        activeCommand = command
        busy = true
        cancelled = false
        if command != "update-status" {
            error = nil
            notice = nil
        }
        current = 0
        total = 0
        progressTitle = ""
        stage = "connect"
        buffer = Data()
        hadResult = false
        stderrText = ""
        if command != "update-status" { log(t("Rozpoczęto: ", "Started: ") + command) }
        let task = Process()
        task.executableURL = node
        task.arguments = [script.path, command, "--library", libraryOverride ?? root] + extra
        let output = Pipe()
        let errors = Pipe()
        task.standardOutput = output
        task.standardError = errors
        errors.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            if data.isEmpty {
                handle.readabilityHandler = nil
                return
            }
            Task { @MainActor in self?.stderrText += String(data: data, encoding: .utf8) ?? "" }
        }
        do {
            try task.run()
            process = task
            Task.detached(priority: .userInitiated) { [weak self] in
                while true {
                    let data = output.fileHandleForReading.availableData
                    if data.isEmpty { break }
                    await self?.consume(data)
                }
                task.waitUntilExit()
                await self?.finished(task.terminationStatus)
            }
        } catch {
            busy = false
            self.error = error.localizedDescription
            log(error.localizedDescription)
        }
    }
    func consume(_ data: Data) {
        buffer.append(data)
        while let range = buffer.range(of: Data([10])) {
            let line = buffer.subdata(in: 0..<range.lowerBound)
            buffer.removeSubrange(0..<range.upperBound)
            guard !line.isEmpty, let object = try? JSONSerialization.jsonObject(with: line) as? [String: Any],
                let type = object["type"] as? String
            else { continue }
            if type == "progress" {
                stage = object["stage"] as? String ?? stage
                progressTitle = object["title"] as? String ?? ""
                current = object["current"] as? Int ?? 0
                total = object["total"] as? Int ?? 0
            } else if type == "error" {
                hadResult = true
                lastReport = object["reportPath"] as? String
                let message = object["message"] as? String ?? "Unknown error"
                if object["cancelled"] as? Bool == true {
                    notice = t(
                        "Przerwano. Ukończone zmiany i kopie są zapisane w raporcie.",
                        "Cancelled. Completed changes and backups are recorded in the report.")
                } else {
                    error = message
                }
                if activeCommand == "update-status" { updatePolling = false }
                log(message)
            } else if type == "result", let result = try? JSONDecoder().decode(ResultEvent.self, from: line) {
                hadResult = true
                if let rows = result.rows {
                    self.rows = rows
                    selected = selected.intersection(Set(rows.filter(\.recoverable).map(\.id)))
                }
                if let summary = result.summary { self.summary = summary }
                if let connection = result.connection { self.connection = connection }
                if let downloads = result.downloads { self.downloads = downloads }
                if let suggested = result.suggestedLibraryPath { suggestedRoot = suggested }
                if let updates = result.updates {
                    self.updates = updates
                    updatesLoaded = true
                    selectedUpdates =
                        result.command == "updates"
                        ? [] : selectedUpdates.intersection(Set(updates.filter { $0.state == "ready" }.map(\.id)))
                }
                if let plan = result.updatePlanFile { updatePlanFile = plan }
                if let session = result.updateSessionFile {
                    updateSessionFile = session
                    if result.command == "update-start" {
                        updatePolling = true
                        updateStatuses = []
                    }
                    if !previewMode { UserDefaults.standard.set(session, forKey: "updateSessionFile") }
                }
                if let statuses = result.updateStatuses {
                    updateStatuses = statuses
                    if !statuses.isEmpty && statuses.allSatisfy({ $0.state == "confirmed" }) {
                        notice = t(
                            "NI potwierdziło zakończenie wszystkich aktualizacji tej sesji.",
                            "NI confirmed completion of every update in this session.")
                    }
                }
                if result.command == "updates" {
                    notice = t("Dostępne aktualizacje: ", "Available updates: ") + String(result.updates?.count ?? 0)
                    log(notice!)
                }
                if result.command == "update-audit" {
                    notice = t(
                        "Porównanie zakończone. Transfer fragmentów jest szacunkiem z manifestu NI; ponowienia mogą go zwiększyć.",
                        "Comparison complete. Piece transfer is estimated from the NI manifest; retries can increase it."
                    )
                    log(notice!)
                }
                if result.command == "update-start" {
                    notice =
                        (result.cancelled == true
                            ? t("Przerwano. Do NI przekazano aktualizacje: ", "Cancelled. Updates handed to NI: ")
                            : t("Przekazano aktualizacje do NI: ", "Updates handed to NI: "))
                        + String(result.started ?? 0)
                    log(notice!)
                }
                if result.command == "update-pause" {
                    notice = t(
                        "Wstrzymano aktywną aktualizację tej sesji. Wznowienie może powtórzyć sprawdzanie SSD.",
                        "Paused this session’s active update. Resuming may repeat the SSD integrity check.")
                }
                if result.command == "update-resume" {
                    notice = t("Wznowiono aktualizację w NI.", "Resumed the NI update.")
                }
                if let plan = result.planFile { planFile = plan }
                if let report = result.reportPath { lastReport = report }
                if result.command == "scan" {
                    log(
                        t("Skan zakończony. Biblioteki: ", "Scan complete. Libraries: ")
                            + String(result.summary?.total ?? 0))
                }
                if result.command == "repair" {
                    planFile = nil
                    notice =
                        result.cancelled == true
                        ? t("Przerwano. Szczegóły w raporcie.", "Cancelled. See report for completed operations.")
                        : !(result.errors ?? []).isEmpty
                            ? t(
                                "Plan wykonano częściowo. Sprawdź szczegóły w raporcie.",
                                "The plan completed partially. Review the report for details.")
                            : t(
                                "Naprawa zakończona. Stan poniżej pochodzi z Native Access.",
                                "Repair finished. The status below was read back from Native Access.")
                    log(notice!)
                }
                if result.command == "snapshot" {
                    notice =
                        t("Zabezpieczono wpisy instalacji: ", "Installation receipts protected: ")
                        + String(result.saved ?? 0)
                    log(notice!)
                }
                if result.command == "verify" {
                    let bytes = ByteCountFormatter.string(
                        fromByteCount: result.changedFileBytes ?? 0, countStyle: .file)
                    notice =
                        t("SHA-256: zgodne pliki ", "SHA-256: matching files ")
                        + "\(result.verified ?? 0)/\(result.total ?? 0). "
                        + t("Brakujące lub zmienione pliki: ", "Missing or changed files: ") + bytes
                    log(notice!)
                }
                if let issues = result.errors, !issues.isEmpty {
                    error = issues.map { ($0.title.map { $0 + ": " } ?? "") + $0.message }.joined(separator: "\n")
                }
            }
        }
    }
    func captureOwnWindowIfRequested() {
        let args = CommandLine.arguments
        guard let i = args.firstIndex(of: "--capture"), args.count > i + 1 else { return }
        let destination = args[i + 1]
        captureOwnWindow(to: destination)
    }
    func captureOwnWindow(to destination: String) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
            guard let window = NSApp.windows.first(where: { $0.isVisible && $0.contentView != nil }),
                let view = window.contentView
            else { return }
            view.layoutSubtreeIfNeeded()
            window.displayIfNeeded()
            // All production views are native AppKit. Capture their actual rendered
            // content directly; window-server snapshots can contain occlusion artifacts.
            if let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds) {
                view.cacheDisplay(in: view.bounds, to: bitmap)
                if let png = bitmap.representation(using: .png, properties: [:]) {
                    try? png.write(to: URL(fileURLWithPath: destination))
                    return
                }
            }
            // Developer capture is restricted to a window owned by this process.
            // CacheDisplay alone omits SwiftUI compositing layers on newer macOS.
            typealias WindowCapture = @convention(c) (CGRect, UInt32, UInt32, UInt32) -> Unmanaged<CGImage>?
            if let library = dlopen("/System/Library/Frameworks/CoreGraphics.framework/CoreGraphics", RTLD_LAZY),
                let symbol = dlsym(library, "CGWindowListCreateImage")
            {
                let capture = unsafeBitCast(symbol, to: WindowCapture.self)
                if let ownedImage = capture(
                    .null, CGWindowListOption.optionIncludingWindow.rawValue, UInt32(window.windowNumber),
                    CGWindowImageOption.boundsIgnoreFraming.rawValue)?.takeRetainedValue(),
                    let png = NSBitmapImageRep(cgImage: ownedImage).representation(using: .png, properties: [:])
                {
                    try? png.write(to: URL(fileURLWithPath: destination))
                    return
                }
            }
            guard let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return }
            view.cacheDisplay(in: view.bounds, to: bitmap)
            if let png = bitmap.representation(using: .png, properties: [:]) {
                try? png.write(to: URL(fileURLWithPath: destination))
            }
        }
    }
    func finished(_ status: Int32) {
        busy = false
        captureOwnWindowIfRequested()
        process = nil
        if !hadResult && cancelled {
            notice = t(
                "Przerwano odczyt. Biblioteki nie zostały zmienione.",
                "Read operation cancelled. Libraries were not changed.")
        }
        if !hadResult && !cancelled {
            error =
                stderrText.isEmpty
                ? t(
                    "Proces zakończył się bez wyniku. Sprawdź, czy Native Access jest uruchomiony.",
                    "The process ended without a result. Make sure Native Access is running.")
                : String(stderrText.suffix(3000))
            log(error!)
        }
        if status != 0 && error == nil && !cancelled {
            error = t(
                "Operacja nie została ukończona. Szczegóły w raporcie.",
                "The operation did not finish. See the report for details.")
        }
    }
}

// Shared visual roles: the light Native Access reference uses Roboto and neutral surfaces.
// Fonts are independently sourced from Google Fonts under the bundled SIL OFL licence.
enum AccessStyle {
    static let canvas = NSColor(srgbRed: 0.985, green: 0.985, blue: 0.985, alpha: 1)
    static let ink = NSColor(srgbRed: 0.09, green: 0.09, blue: 0.09, alpha: 1)
    static let muted = NSColor(srgbRed: 0.43, green: 0.43, blue: 0.43, alpha: 1)
    static let rule = NSColor(srgbRed: 0.88, green: 0.88, blue: 0.88, alpha: 1)
    static let surface = NSColor(srgbRed: 0.94, green: 0.94, blue: 0.94, alpha: 1)
    static let accent = NSColor(srgbRed: 0.20, green: 0.43, blue: 0.90, alpha: 1)
    static func registerFonts() {
        if let url = Bundle.main.url(forResource: "Roboto", withExtension: "ttf", subdirectory: "Fonts") {
            CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
        }
    }
    static func font(ofSize size: CGFloat, weight: NSFont.Weight = .regular) -> NSFont {
        let face =
            weight >= .bold ? "Bold" : weight >= .semibold ? "SemiBold" : weight >= .medium ? "Medium" : "Regular"
        return NSFont(name: "Roboto-" + face, size: size) ?? .systemFont(ofSize: size, weight: weight)
    }
}

final class AccessButtonCell: NSButtonCell {
    override func drawBezel(withFrame frame: NSRect, in controlView: NSView) {
        let rect = frame.insetBy(dx: 1, dy: 1)
        let fill = (controlView as? NSButton)?.bezelColor ?? AccessStyle.rule
        (isHighlighted ? fill.blended(withFraction: 0.12, of: .black)! : fill).setFill()
        NSBezierPath(roundedRect: rect, xRadius: 2, yRadius: 2).fill()
    }
}

final class AccessTabsCell: NSSegmentedCell {
    override func draw(withFrame cellFrame: NSRect, in controlView: NSView) {
        var x = cellFrame.minX
        for i in 0..<segmentCount {
            let w = width(forSegment: i)
            let selected = isSelected(forSegment: i)
            let label = label(forSegment: i) ?? ""
            let attributes: [NSAttributedString.Key: Any] = [
                .font: AccessStyle.font(ofSize: 16, weight: selected ? .medium : .regular),
                .foregroundColor: selected ? AccessStyle.ink : AccessStyle.muted,
            ]
            let size = (label as NSString).size(withAttributes: attributes)
            (label as NSString).draw(
                at: NSPoint(x: x + 8, y: cellFrame.midY - size.height / 2), withAttributes: attributes)
            if selected {
                AccessStyle.ink.setFill()
                NSRect(x: x + 8, y: cellFrame.maxY - 2, width: size.width, height: 1.5).fill()
            }
            x += w
        }
        if controlView.window?.firstResponder === controlView && showsFirstResponder {
            NSGraphicsContext.saveGraphicsState()
            NSFocusRingPlacement.only.set()
            NSBezierPath(rect: cellFrame.insetBy(dx: 1, dy: 1)).fill()
            NSGraphicsContext.restoreGraphicsState()
        }
    }
}

final class CanvasView: NSView {
    override func draw(_ dirtyRect: NSRect) {
        AccessStyle.canvas.setFill()
        dirtyRect.fill()
    }
}
final class FlippedDocumentStack: NSStackView { override var isFlipped: Bool { true } }

@MainActor
final class BridgeAppDelegate: NSObject, NSApplicationDelegate, NSTableViewDataSource, NSTableViewDelegate,
    NSSearchFieldDelegate, NSMenuDelegate, NSWindowDelegate
{
    static var model: BridgeModel?
    let model = BridgeModel()
    var window: NSWindow!
    var observer: AnyCancellable?
    var refreshQueued = false
    var renderKey = ""
    var navButtons: [NSButton] = []
    var guidanceTitle: NSTextField?
    var guidanceBody: NSTextField?
    var filterExplanation: NSTextField?
    var selectionLabel: NSTextField?
    var updateSummary: NSTextField?
    var sessionLabel: NSTextField?
    var reportText: NSTextView?
    let detail = NSStackView()
    let bodyHost = NSView()
    let actionHost = NSView()
    let sidebar = NSStackView()
    let sourceTitle = NSTextField(labelWithString: "")
    let sourcePath = NSTextField(labelWithString: "")
    let connectionLabel = NSTextField(wrappingLabelWithString: "")
    let noticeLabel = NSTextField(wrappingLabelWithString: "")
    let noticeHost = NSStackView()
    let progressHost = NSStackView()
    let progressLabel = NSTextField(labelWithString: "")
    let progressDetail = NSTextField(labelWithString: "")
    let progressBar = NSProgressIndicator()
    let languagePopup = NSPopUpButton()
    let chooseButton = NSButton()
    let nativeButton = NSButton()
    let scanButton = NSButton()
    let selectButton = NSButton()
    let repairButton = NSButton()
    let backupButton = NSButton()
    let backupOpenButton = NSButton()
    let exportButton = NSButton()
    let updateListButton = NSButton()
    let updateSelectButton = NSButton()
    let updateAuditButton = NSButton()
    let updateStartButton = NSButton()
    let updateStatusButton = NSButton()
    let updatePauseButton = NSButton()
    let updateResumeButton = NSButton()
    let cancelButton = NSButton()
    let table = NSTableView()
    let updateTable = NSTableView()
    let search = NSSearchField()
    let filters = NSSegmentedControl()
    var displayRows: [LibraryRow] = []
    var updateTimer: Timer?
    let blue = AccessStyle.accent

    func t(_ pl: String, _ en: String) -> String { model.t(pl, en) }
    func text(_ value: String, size: CGFloat = 13, weight: NSFont.Weight = .regular, secondary: Bool = false)
        -> NSTextField
    {
        let v = NSTextField(wrappingLabelWithString: value)
        v.font = AccessStyle.font(ofSize: size, weight: weight)
        v.textColor = secondary ? AccessStyle.muted : AccessStyle.ink
        v.setContentCompressionResistancePriority(.required, for: .vertical)
        return v
    }
    func vstack(_ views: [NSView], gap: CGFloat = 10, inset: CGFloat = 0) -> NSStackView {
        let s = NSStackView(views: views)
        s.orientation = .vertical
        s.alignment = .leading
        s.spacing = gap
        s.edgeInsets = NSEdgeInsets(top: inset, left: inset, bottom: inset, right: inset)
        return s
    }
    func hstack(_ views: [NSView], gap: CGFloat = 10) -> NSStackView {
        let s = NSStackView(views: views)
        s.orientation = .horizontal
        s.alignment = .centerY
        s.spacing = gap
        return s
    }
    func spacer() -> NSView {
        let v = NSView()
        v.setContentHuggingPriority(.defaultLow, for: .horizontal)
        v.setContentHuggingPriority(.defaultLow, for: .vertical)
        return v
    }
    func width(_ v: NSView, in parent: NSView, minus: CGFloat = 0) {
        v.translatesAutoresizingMaskIntoConstraints = false
        v.widthAnchor.constraint(equalTo: parent.widthAnchor, constant: -minus).isActive = true
    }
    func pin(_ v: NSView, to p: NSView) {
        v.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            v.leadingAnchor.constraint(equalTo: p.leadingAnchor),
            v.trailingAnchor.constraint(equalTo: p.trailingAnchor), v.topAnchor.constraint(equalTo: p.topAnchor),
            v.bottomAnchor.constraint(equalTo: p.bottomAnchor),
        ])
    }
    func separator() -> NSView {
        let v = NSBox()
        v.boxType = .separator
        return v
    }
    func button(_ title: String, action: Selector, help: String, prominent: Bool = false) -> NSButton {
        let b = NSButton()
        configure(b, action: action)
        style(b, title: title, help: help, prominent: prominent)
        return b
    }
    func configure(_ b: NSButton, action: Selector) {
        b.cell = AccessButtonCell(textCell: "")
        b.target = self
        b.action = action
        b.bezelStyle = .regularSquare
        b.controlSize = .large
        b.font = AccessStyle.font(ofSize: 13, weight: .medium)
    }
    func style(_ b: NSButton, title: String, help: String, prominent: Bool = false) {
        b.title = title
        b.toolTip = help
        b.setAccessibilityLabel(title)
        b.setAccessibilityHelp(help)
        b.bezelColor = prominent && b.isEnabled ? AccessStyle.ink : AccessStyle.rule
        b.attributedTitle = NSAttributedString(
            string: title,
            attributes: [
                .font: AccessStyle.font(ofSize: 13, weight: prominent ? .semibold : .medium),
                .foregroundColor: !b.isEnabled
                    ? AccessStyle.muted : prominent ? NSColor.white : AccessStyle.ink,
            ])
    }
    func actionBlock(_ b: NSButton, _ help: String) -> NSStackView {
        let caption = text(help, size: 12, secondary: true)
        let s = vstack([b, caption], gap: 6)
        width(caption, in: s)
        return s
    }
    func pageHeader(_ title: String, _ description: String) -> NSStackView {
        let a = text(title, size: 26, weight: .medium)
        let b = text(description, size: 14, secondary: true)
        let s = vstack([a, b], gap: 8)
        width(a, in: s)
        width(b, in: s)
        return s
    }
    func document(_ views: [NSView], inset: CGFloat = 28, gap: CGFloat = 20) -> NSView {
        let s = FlippedDocumentStack(views: views)
        s.orientation = .vertical
        s.alignment = .leading
        s.spacing = gap
        s.edgeInsets = NSEdgeInsets(top: inset, left: inset, bottom: inset, right: inset)
        let scroll = NSScrollView()
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        scroll.drawsBackground = false
        scroll.documentView = s
        s.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            s.leadingAnchor.constraint(equalTo: scroll.contentView.leadingAnchor),
            s.trailingAnchor.constraint(equalTo: scroll.contentView.trailingAnchor),
            s.topAnchor.constraint(equalTo: scroll.contentView.topAnchor),
        ])
        for v in views { width(v, in: s, minus: inset * 2) }
        return scroll
    }
    func guide(_ title: String, _ body: String) -> NSStackView {
        let a = text(title, size: 14, weight: .semibold)
        let b = text(body, size: 13, secondary: true)
        guidanceTitle = a
        guidanceBody = b
        let s = vstack([a, b], gap: 4, inset: 10)
        s.wantsLayer = true
        s.layer?.backgroundColor = AccessStyle.surface.cgColor
        s.layer?.cornerRadius = 2
        width(a, in: s, minus: 20)
        width(b, in: s, minus: 20)
        return s
    }
    func stepper(_ labels: [String], active: Int) -> NSView {
        var parts: [NSView] = []
        for (i, label) in labels.enumerated() {
            let v = text(
                "\(i+1). " + label, size: 12, weight: i == active ? .semibold : .regular, secondary: i != active)
            if i == active { v.textColor = blue }
            parts.append(v)
            if i < labels.count - 1 { parts.append(text("›", size: 14, secondary: true)) }
        }
        parts.append(spacer())
        return hstack(parts, gap: 10)
    }
    func applicationDidFinishLaunching(_ notification: Notification) {
        AccessStyle.registerFonts()
        Self.model = model
        let compact = CommandLine.arguments.contains("--compact")
        window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: compact ? 980 : 1180, height: compact ? 700 : 800),
            styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
        window.delegate = self
        window.title = "Native FixTool"
        window.minSize = NSSize(width: 920, height: 660)
        window.center()
        window.isReleasedWhenClosed = false
        window.appearance = NSAppearance(named: .aqua)
        window.backgroundColor = AccessStyle.canvas
        window.contentView = CanvasView()
        let content = window.contentView!
        let root = NSStackView()
        root.orientation = .horizontal
        root.alignment = .top
        root.spacing = 0
        content.addSubview(root)
        pin(root, to: content)
        sidebar.orientation = .vertical
        sidebar.alignment = .leading
        sidebar.spacing = 12
        sidebar.edgeInsets = NSEdgeInsets(top: 26, left: 16, bottom: 18, right: 16)
        sidebar.widthAnchor.constraint(equalToConstant: 202).isActive = true
        sidebar.wantsLayer = true
        sidebar.layer?.backgroundColor = AccessStyle.canvas.cgColor
        let brandIcon = NSImageView(
            image: NSImage(systemSymbolName: "externaldrive.badge.checkmark", accessibilityDescription: nil)!)
        brandIcon.contentTintColor = AccessStyle.ink
        brandIcon.symbolConfiguration = .init(pointSize: 26, weight: .regular)
        sidebar.addArrangedSubview(hstack([brandIcon, text("Native FixTool", size: 17, weight: .bold)], gap: 8))
        sidebar.addArrangedSubview(
            text(
                t("Biblioteki bez zaczynania od zera", "Keep the libraries you already have"), size: 11, secondary: true
            ))
        sidebar.addArrangedSubview(separator())
        let symbols = [
            "house", "wrench.and.screwdriver", "arrow.down.circle", "externaldrive.badge.timemachine",
            "questionmark.circle", "doc.text.magnifyingglass",
        ]
        for (i, section) in Section.allCases.enumerated() {
            let b = NSButton()
            configure(b, action: #selector(navigate(_:)))
            b.tag = i
            b.isBordered = false
            b.alignment = .left
            b.imagePosition = .imageLeading
            b.image = NSImage(systemSymbolName: symbols[i], accessibilityDescription: nil)
            b.wantsLayer = true
            b.layer?.cornerRadius = 0
            b.heightAnchor.constraint(equalToConstant: 36).isActive = true
            b.identifier = .init(section.rawValue)
            sidebar.addArrangedSubview(b)
            width(b, in: sidebar, minus: 32)
            navButtons.append(b)
            if section == .migration { sidebar.addArrangedSubview(spacer()) }
        }
        connectionLabel.font = AccessStyle.font(ofSize: 11)
        connectionLabel.textColor = .secondaryLabelColor
        sidebar.addArrangedSubview(connectionLabel)
        width(connectionLabel, in: sidebar, minus: 32)
        languagePopup.font = AccessStyle.font(ofSize: 13)
        languagePopup.addItems(withTitles: ["Polski", "English"])
        languagePopup.target = self
        languagePopup.action = #selector(changeLanguage(_:))
        sidebar.addArrangedSubview(languagePopup)
        let divider = separator()
        divider.widthAnchor.constraint(equalToConstant: 1).isActive = true
        detail.orientation = .vertical
        detail.alignment = .leading
        detail.spacing = 0
        root.addArrangedSubview(sidebar)
        root.addArrangedSubview(divider)
        root.addArrangedSubview(detail)
        sidebar.heightAnchor.constraint(equalTo: root.heightAnchor).isActive = true
        divider.heightAnchor.constraint(equalTo: root.heightAnchor).isActive = true
        detail.heightAnchor.constraint(equalTo: root.heightAnchor).isActive = true
        detail.widthAnchor.constraint(equalTo: root.widthAnchor, constant: -203).isActive = true
        sourceTitle.font = AccessStyle.font(ofSize: 12, weight: .semibold)
        sourcePath.font = AccessStyle.font(ofSize: 11)
        sourcePath.textColor = .secondaryLabelColor
        sourcePath.lineBreakMode = .byTruncatingMiddle
        sourcePath.isSelectable = true
        let sourceCopy = vstack([sourceTitle, sourcePath], gap: 4)
        sourceCopy.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        configure(chooseButton, action: #selector(choose))
        let bar = hstack([sourceCopy, spacer(), chooseButton])
        bar.edgeInsets = NSEdgeInsets(top: 16, left: 28, bottom: 16, right: 28)
        detail.addArrangedSubview(bar)
        width(bar, in: detail)
        let line = separator()
        detail.addArrangedSubview(line)
        width(line, in: detail)
        bodyHost.setContentHuggingPriority(.defaultLow, for: .vertical)
        bodyHost.heightAnchor.constraint(greaterThanOrEqualToConstant: 100).isActive = true
        detail.addArrangedSubview(bodyHost)
        width(bodyHost, in: detail)
        noticeHost.orientation = .vertical
        noticeHost.alignment = .leading
        noticeHost.edgeInsets = NSEdgeInsets(top: 8, left: 28, bottom: 8, right: 28)
        noticeLabel.font = AccessStyle.font(ofSize: 12)
        noticeLabel.maximumNumberOfLines = 3
        noticeHost.addArrangedSubview(noticeLabel)
        width(noticeLabel, in: noticeHost, minus: 56)
        detail.addArrangedSubview(noticeHost)
        width(noticeHost, in: detail)
        configureProgress()
        detail.addArrangedSubview(progressHost)
        width(progressHost, in: detail)
        detail.addArrangedSubview(actionHost)
        width(actionHost, in: detail)
        configure(nativeButton, action: #selector(openNative))
        let appVersion = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? ""
        let footer = hstack([text("Native FixTool " + appVersion, size: 11, secondary: true), spacer(), nativeButton])
        footer.edgeInsets = NSEdgeInsets(top: 9, left: 28, bottom: 12, right: 28)
        detail.addArrangedSubview(footer)
        width(footer, in: detail)
        configureControls()
        configureTables()
        configureMenus()
        observer = model.objectWillChange.sink { [weak self] in self?.queueRefresh() }
        refresh()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        model.initialLoad()
        refresh()
        updateTimer = Timer.scheduledTimer(withTimeInterval: 6, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self, self.model.section == .updates, !self.model.busy, !self.model.previewMode,
                    !self.model.root.isEmpty, self.model.updateSessionFile != nil, self.model.updatePolling
                else { return }
                if !self.model.updateStatuses.isEmpty
                    && self.model.updateStatuses.allSatisfy({ $0.state == "confirmed" })
                {
                    return
                }
                self.model.updateSession()
            }
        }
        if let i = CommandLine.arguments.firstIndex(of: "--ui-smoke-output"), CommandLine.arguments.count > i + 1 {
            let output = CommandLine.arguments[i + 1]
            Task {
                try? await Task.sleep(nanoseconds: 300_000_000)
                await self.runUISmoke(output: output)
            }
        }
    }
    func configureControls() {
        for (b, action) in [
            (scanButton, #selector(scan)), (selectButton, #selector(selectRecoverable)),
            (repairButton, #selector(reviewRepair)), (backupButton, #selector(snapshot)),
            (backupOpenButton, #selector(openBackup)), (exportButton, #selector(export)),
            (updateListButton, #selector(loadUpdates)), (updateSelectButton, #selector(selectUpdates)),
            (updateAuditButton, #selector(auditUpdates)), (updateStartButton, #selector(reviewUpdates)),
            (updateStatusButton, #selector(updateStatus)), (updatePauseButton, #selector(pauseUpdates)),
            (updateResumeButton, #selector(resumeUpdates)), (cancelButton, #selector(cancel)),
        ] { configure(b, action: action) }
    }
    func configureTables() {
        for (id, w) in [("pick", 34.0), ("library", 270.0), ("status", 180.0), ("version", 105.0)] {
            let c = NSTableColumn(identifier: .init(id))
            c.width = w
            c.headerCell.font = AccessStyle.font(ofSize: 12)
            c.headerCell.textColor = AccessStyle.muted
            c.minWidth = id == "pick" ? 34 : 90
            if id == "pick" { c.maxWidth = 34 }
            table.addTableColumn(c)
        }
        for (id, w) in [("pick", 34.0), ("product", 290.0), ("versions", 155.0), ("transfer", 190.0)] {
            let c = NSTableColumn(identifier: .init(id))
            c.width = w
            c.headerCell.font = AccessStyle.font(ofSize: 12)
            c.headerCell.textColor = AccessStyle.muted
            c.minWidth = id == "pick" ? 34 : 100
            if id == "pick" { c.maxWidth = 34 }
            updateTable.addTableColumn(c)
        }
        for list in [table, updateTable] {
            list.delegate = self
            list.dataSource = self
            list.rowHeight = 58
            list.intercellSpacing = NSSize(width: 12, height: 1)
            list.usesAlternatingRowBackgroundColors = false
            list.backgroundColor = AccessStyle.canvas
            list.gridStyleMask = .solidHorizontalGridLineMask
            list.gridColor = AccessStyle.rule
            list.columnAutoresizingStyle = .lastColumnOnlyAutoresizingStyle
            list.allowsMultipleSelection = false
        }
        let menu = NSMenu()
        menu.autoenablesItems = false
        menu.delegate = self
        table.menu = menu
        table.setAccessibilityRole(.table)
        chooseButton.setAccessibilityRole(.button)
        table.setAccessibilityLabel(t("Biblioteki na wybranym dysku", "Libraries on the selected drive"))
        updateTable.setAccessibilityLabel(t("Dostępne aktualizacje bibliotek", "Available library updates"))
        filters.cell = AccessTabsCell()
        filters.segmentCount = 4
        filters.heightAnchor.constraint(equalToConstant: 38).isActive = true
        filters.trackingMode = .selectOne
        filters.target = self
        filters.action = #selector(changeFilter(_:))
        filters.selectedSegment = 0
        filters.font = AccessStyle.font(ofSize: 12)
        search.font = AccessStyle.font(ofSize: 13)
        search.delegate = self
        search.placeholderString = t("Szukaj biblioteki", "Search libraries")
        search.setAccessibilityLabel(t("Szukaj biblioteki po nazwie", "Search libraries by name"))
        search.widthAnchor.constraint(greaterThanOrEqualToConstant: 150).isActive = true
    }
    func configureProgress() {
        progressHost.orientation = .vertical
        progressHost.alignment = .leading
        progressHost.spacing = 5
        progressHost.edgeInsets = NSEdgeInsets(top: 8, left: 28, bottom: 8, right: 28)
        progressLabel.font = AccessStyle.font(ofSize: 12, weight: .semibold)
        progressDetail.font = AccessStyle.font(ofSize: 11)
        progressDetail.textColor = .secondaryLabelColor
        progressDetail.lineBreakMode = .byTruncatingMiddle
        let row = hstack([progressLabel, spacer(), cancelButton])
        progressHost.addArrangedSubview(row)
        width(row, in: progressHost, minus: 56)
        progressBar.style = .bar
        progressBar.minValue = 0
        progressBar.maxValue = 1
        progressHost.addArrangedSubview(progressBar)
        width(progressBar, in: progressHost, minus: 56)
        progressHost.addArrangedSubview(progressDetail)
        width(progressDetail, in: progressHost, minus: 56)
    }
    func configureMenus() {
        let menu = NSMenu()
        let a = NSMenuItem()
        menu.addItem(a)
        let app = NSMenu()
        let about = app.addItem(
            withTitle: t("O Native FixTool", "About Native FixTool"), action: #selector(showAbout), keyEquivalent: "")
        about.target = self
        app.addItem(.separator())
        app.addItem(
            withTitle: t("Zamknij Native FixTool", "Quit Native FixTool"),
            action: #selector(NSApplication.terminate(_:)),
            keyEquivalent: "q")
        a.submenu = app
        let e = NSMenuItem()
        menu.addItem(e)
        let edit = NSMenu(title: t("Edycja", "Edit"))
        for (title, action, key) in [
            (t("Kopiuj", "Copy"), #selector(NSText.copy(_:)), "c"),
            (t("Wklej", "Paste"), #selector(NSText.paste(_:)), "v"),
            (t("Zaznacz wszystko", "Select All"), #selector(NSText.selectAll(_:)), "a"),
        ] { edit.addItem(withTitle: title, action: action, keyEquivalent: key) }
        e.submenu = edit
        let h = NSMenuItem()
        menu.addItem(h)
        let help = NSMenu(title: t("Pomoc", "Help"))
        let item = NSMenuItem(
            title: t("Pomoc Native FixTool", "Native FixTool Help"), action: #selector(openHelp), keyEquivalent: "?")
        item.target = self
        help.addItem(item)
        h.submenu = help
        NSApp.mainMenu = menu
    }
    func queueRefresh() {
        guard !refreshQueued else { return }
        refreshQueued = true
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.refreshQueued = false
            self.refresh()
        }
    }
    func replace(_ host: NSView, with body: NSView) {
        for view in host.subviews { view.removeFromSuperview() }
        host.addSubview(body)
        pin(body, to: host)
    }
    func homeBody() -> NSView {
        let intro = pageHeader(
            t("Co chcesz zrobić?", "What would you like to do?"),
            t(
                "Wybierz jedno zadanie. Poprowadzimy Cię krok po kroku.",
                "Choose one task. We will guide you through it."))
        let tasks: [(Section, String, String, String)] = [
            (
                .libraries, t("Naprawa", "Repair"),
                t(
                    "Native Access nie widzi bibliotek na dysku? Napraw to bez pobierania ich od nowa.",
                    "Native Access cannot find libraries on your drive? Restore recognition without downloading them again."
                ), "wrench.and.screwdriver"
            ),
            (
                .updates, t("Aktualizacje", "Updates"),
                t(
                    "Zainstaluj nowe wersje bez zbędnego pobierania całych bibliotek.",
                    "Install new versions without unnecessarily downloading whole libraries again."),
                "arrow.down.circle"
            ),
            (
                .migration, t("Przeniesienie", "Migration"),
                t(
                    "Zmieniasz komputer lub system? Użyj bibliotek ze swojego dysku bez ponownego pobierania.",
                    "Changing computers or reinstalling macOS? Reuse the libraries on your drive without downloading them again."
                ), "externaldrive.badge.timemachine"
            ),
        ]
        var views: [NSView] = [intro]
        for (section, title, copy, symbol) in tasks {
            let b = button(title, action: #selector(openTask(_:)), help: copy)
            b.tag = Section.allCases.firstIndex(of: section)!
            b.image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)
            b.imagePosition = .imageLeading
            b.heightAnchor.constraint(equalToConstant: 38).isActive = true
            let label = text(copy, size: 14, secondary: true)
            let row = vstack([b, label], gap: 8, inset: 16)
            width(label, in: row, minus: 32)
            row.wantsLayer = true
            row.layer?.borderWidth = 1
            row.layer?.borderColor = AccessStyle.rule.cgColor
            row.layer?.cornerRadius = 2
            views.append(row)
        }
        views.append(
            text(
                t(
                    "Zacznij od otwarcia Native Access i zalogowania się na konto z Twoimi licencjami. W tej aplikacji nie zakładasz nowego konta.",
                    "First open Native Access and sign into the account holding your licences. You do not create another account in this app."
                ), size: 12, secondary: true))
        views.append(text(projectLicenseSummary(), size: 12, secondary: true))
        return document(views, gap: 16)
    }
    func folderBody() -> NSView {
        let title =
            model.section == .updates
            ? t("Aktualizacje", "Updates")
            : model.section == .migration ? t("Przeniesienie", "Migration") : t("Naprawa", "Repair")
        let header = pageHeader(
            title, t("Krok 1: wskaż, gdzie są Twoje biblioteki.", "Step 1: show us where your libraries are."))
        let choose = button(
            t("Wybierz folder z bibliotekami…", "Choose your library folder…"), action: #selector(choose),
            help: t(
                "Otwiera wybór folderu. Po wybraniu folderu wczytamy listę — bez pobierania dźwięków.",
                "Opens the folder picker. Selecting a folder loads its list without downloading samples."),
            prominent: true)
        let examples = vstack(
            [
                text(t("Który folder wybrać?", "Which folder should I choose?"), size: 16, weight: .semibold),
                text(
                    t(
                        "Wybierz wspólny folder, w którym są katalogi poszczególnych bibliotek. Nie wybieraj folderu jednego instrumentu ani pojedynczego pliku z dźwiękiem.",
                        "Choose the parent folder containing your individual libraries. Do not choose one instrument folder or a single sample file."
                    ), size: 14),
                text(
                    t(
                        "Dysk z bibliotekami\n    NI  ← wybierz ten folder\n        Fables Library\n        Kontakt Factory Library",
                        "Library drive\n    NI  ← choose this folder\n        Fables Library\n        Kontakt Factory Library"
                    ), size: 14),
            ], gap: 12, inset: 18)
        examples.wantsLayer = true
        examples.layer?.backgroundColor = AccessStyle.surface.cgColor
        examples.layer?.cornerRadius = 2
        for v in examples.arrangedSubviews { width(v, in: examples, minus: 36) }
        let hint =
            model.suggestedRoot.isEmpty
            ? t(
                "Folder z presetami w Dokumentach to coś innego. Szukamy dużych bibliotek z dźwiękami, np. na zewnętrznym SSD.",
                "The preset folder in Documents is different. We need your large sample libraries, for example on an external SSD."
            )
            : t("Native Access wskazuje folder: ", "Native Access points to: ") + model.suggestedRoot
                + t(
                    ". Otworzymy wybór folderu w tym miejscu — sprawdź go i zatwierdź.",
                    ". The folder picker will open there so you can check and confirm it.")
        return document([
            header, examples,
            actionBlock(
                choose,
                t(
                    "To tylko wybór miejsca. Niczego nie przenosimy ani nie instalujemy.",
                    "This only selects a location. It moves or installs nothing.")),
            text(hint, size: 13, secondary: true),
        ])
    }
    func listScroll(_ list: NSTableView) -> NSScrollView {
        let s = NSScrollView()
        s.documentView = list
        s.hasVerticalScroller = true
        s.hasHorizontalScroller = true
        s.autohidesScrollers = true
        s.borderType = .noBorder
        s.heightAnchor.constraint(greaterThanOrEqualToConstant: 100).isActive = true
        s.setContentHuggingPriority(.defaultLow, for: .vertical)
        return s
    }
    func libraryBody() -> NSView {
        let header = pageHeader(
            t("Naprawa", "Repair"),
            t(
                "Sprawdzamy biblioteki na dysku i pomagamy Native Access je rozpoznać.",
                "We inspect the libraries on your drive and help Native Access recognise them."))
        let steps = stepper(
            [
                t("Wybierz folder", "Choose folder"), t("Wybierz biblioteki", "Choose libraries"),
                t("Zatwierdź naprawę", "Confirm repair"),
            ], active: model.recoverableSelection.isEmpty ? 1 : 2)
        let g = guide("", "")
        let top = vstack([header, steps, g], gap: 9, inset: 24)
        top.edgeInsets.top = 18
        top.edgeInsets.bottom = 14
        for v in top.arrangedSubviews { width(v, in: top, minus: 48) }
        let filterRow = hstack([text(t("Pokaż:", "Show:"), size: 12, weight: .semibold), filters, spacer()], gap: 8)
        filterExplanation = text("", size: 12, secondary: true)
        let selection = hstack([selectButton, spacer(), search])
        let controls = vstack([filterRow, filterExplanation!, selection], gap: 8, inset: 0)
        let pad = vstack([controls], gap: 0, inset: 24)
        width(controls, in: pad, minus: 48)
        pad.edgeInsets.top = 0
        pad.edgeInsets.bottom = 10
        let s = vstack([top, pad, listScroll(table)], gap: 0)
        for v in s.arrangedSubviews { width(v, in: s) }
        return s
    }
    func updateBody() -> NSView {
        let header = pageHeader(
            t("Aktualizacje", "Updates"),
            t(
                "Nowe wersje bibliotek. Wykorzystaj pliki, które już masz na dysku.",
                "New library versions. Reuse the files you already have on your drive."))
        let steps = stepper(
            [
                t("Wybierz folder", "Choose folder"), t("Wybierz aktualizacje", "Choose updates"),
                t("Zatwierdź", "Confirm"),
            ], active: model.updateSelection.isEmpty ? 1 : 2)
        let g = guide("", "")
        let top = vstack([header, steps, g], gap: 9, inset: 24)
        top.edgeInsets.top = 18
        top.edgeInsets.bottom = 14
        for v in top.arrangedSubviews { width(v, in: top, minus: 48) }
        selectionLabel = text("", size: 12, weight: .medium)
        let row = hstack([updateSelectButton, selectionLabel!, spacer(), updateListButton])
        let controls = vstack(
            [
                row,
                text(
                    t(
                        "Do pobrania to szacunek po porównaniu. Rozmiar całej biblioteki nie oznacza rozmiaru pobierania.",
                        "Download size is estimated after comparison. Full library size is not download size."),
                    size: 12, secondary: true),
            ], gap: 7, inset: 24)
        controls.edgeInsets.top = 0
        controls.edgeInsets.bottom = 10
        for v in controls.arrangedSubviews { width(v, in: controls, minus: 48) }
        let s = vstack([top, controls, listScroll(updateTable)], gap: 0)
        for v in s.arrangedSubviews { width(v, in: s) }
        return s
    }
    func migrationBody() -> NSView {
        let header = pageHeader(
            t("Przeniesienie", "Migration"),
            t(
                "Zmieniasz komputer lub system? Zachowaj biblioteki na swoim dysku.",
                "Changing computers or reinstalling macOS? Keep the libraries on your drive."))
        let old = guide(
            t("Na starym Macu — zrób to przed zmianą systemu", "On your old Mac — before changing systems"),
            t(
                "Kliknij „Zapisz dane bibliotek”. Zapiszemy na tym samym dysku informacje, dzięki którym nowy Mac odnajdzie biblioteki. Same dźwięki zostają na swoim miejscu.",
                "Click Save library information. We save the information your new Mac needs on this same drive. The samples stay where they are."
            ))
        let new = button(
            t("Jestem już na nowym Macu", "I am already on the new Mac"), action: #selector(openRecovery),
            help: t(
                "Przechodzi do Naprawy, aby odszukać istniejące biblioteki na podłączonym dysku.",
                "Opens Repair to reconnect existing libraries on the attached drive."))
        return document([
            header, old,
            actionBlock(
                backupButton,
                t(
                    "Zapisuje dane instalacji na wybranym dysku. To nie jest dodatkowa kopia wszystkich dźwięków.",
                    "Saves installation information on the selected drive. It does not create another copy of all samples."
                )), separator(),
            text(
                t("Na nowym Macu lub po instalacji systemu", "On your new Mac or after reinstalling macOS"), size: 17,
                weight: .semibold),
            text(
                t(
                    "1. Podłącz ten sam dysk.\n2. Zainstaluj Native Access i zaloguj się na to samo konto NI.\n3. Otwórz tę aplikację i wybierz „Naprawa”.",
                    "1. Connect the same drive.\n2. Install Native Access and sign into the same NI account.\n3. Open this app and choose Repair."
                ), size: 14),
            actionBlock(
                new,
                t(
                    "Nowy użytkownik macOS jest w porządku. Licencje muszą nadal być na Twoim koncie NI.",
                    "A new macOS user is fine. Your licences must still belong to your NI account.")),
            actionBlock(
                backupOpenButton,
                t(
                    "Otwiera w Finderze zapisane informacje o bibliotekach.",
                    "Shows the saved library information in Finder.")),
        ])
    }
    func helpBody() -> NSView {
        var views: [NSView] = [
            pageHeader(
                t("Jak to działa?", "How does it work?"),
                t(
                    "Najpierw wybierasz zadanie. Zmiany zawsze zatwierdzasz osobno.",
                    "Choose a task first. Changes always need a separate confirmation."))
        ]
        views.append(
            text(
                projectLicenseSummary() + "\n"
                    + t(
                        "Pełny tekst licencji znajdziesz w menu „O Native FixTool”. Własne licencje na produkty NI pozostają wymagane.",
                        "Read the full licence in About Native FixTool. Your own NI product licences are still required."
                    ),
                size: 13, secondary: true))
        let qa: [(String, String)] = [
            (
                t("Naprawa — kiedy jej użyć?", "Repair — when should I use it?"),
                t(
                    "Gdy biblioteki są na dysku, a Native Access pokazuje Install lub Repair. Wybierz folder, zaznacz dostępne biblioteki i sprawdź podsumowanie naprawy.",
                    "When samples are on your drive but Native Access shows Install or Repair. Choose their folder, select available libraries and review the repair summary."
                )
            ),
            (
                t("Co oznaczają zakładki na liście?", "What do the library filters mean?"),
                t(
                    "Zainstalowane: Native Access już je widzi.\nDostępne: pliki są na dysku, ale trzeba przywrócić ich rozpoznawanie.\nProblemy: aplikacja nie może naprawić ich automatycznie; przy bibliotece wyświetla powód.\nWszystkie: pokazuje całą listę. Filtry niczego nie instalują.",
                    "Installed: Native Access already recognises them.\nAvailable: the files are on your drive but recognition needs restoring.\nProblems: automatic repair is not possible; the reason is shown beside each library.\nAll: displays the whole list. Filters install nothing."
                )
            ),
            (
                t("Zaznaczanie to jeszcze nie naprawa", "Selecting does not start a repair"),
                t(
                    "Kwadrat przy nazwie wybiera bibliotekę. „Zaznacz do naprawy” wybiera wszystkie dostępne biblioteki z widocznej listy. „Sprawdź plan naprawy” pokazuje podsumowanie. Dopiero „Rozpocznij naprawę” zapisuje zmiany.",
                    "The checkbox selects a library. Select for repair selects all available libraries in the current list. Review repair plan shows a summary. Only Start repair writes changes."
                )
            ),
            (
                t("Co porównuje przycisk „Sprawdź rozmiar pobierania”?", "What does Check download size compare?"),
                t(
                    "Porównuje zaznaczone biblioteki na Twoim dysku z plikami najnowszej wersji NI. Nie porównuje bibliotek między sobą. Czyta dysk, ale nie pobiera dźwięków. Może to potrwać — ten krok jest opcjonalny.",
                    "It compares the selected libraries on your drive with NI's latest files, not with each other. It reads the drive without downloading samples. This may take time and is optional."
                )
            ),
            (
                t("Czy aktualizacja zawsze będzie mała?", "Will every update be small?"),
                t(
                    "Nie. Zachowane mogą być pliki i fragmenty zgodne z wersją NI. Jeśli producent zmieni duży plik w całości, potrzebne może być duże pobranie. Native Access nadal sprawdza i instaluje aktualizację.",
                    "No. Files and pieces matching NI's version can be retained. If a whole large file changes, a large download may be needed. Native Access still verifies and installs the update."
                )
            ),
            (
                t("Dlaczego mam Native Instruments w Dokumentach?", "Why is Native Instruments in Documents?"),
                t(
                    "Tam instrumenty zapisują Twoje presety i ustawienia. To inny folder niż duże biblioteki z samplami na SSD. Aplikacje i wtyczki też mają swoje miejsce na Macu i mogą wymagać instalacji po zmianie systemu.",
                    "Instruments keep your user presets and settings there. That is different from large sample libraries on your SSD. Applications and plug-ins also have their own locations and may need installation after changing systems."
                )
            ),
            (
                t("Co robi Wstrzymaj lub Wznów?", "What do Pause and Resume do?"),
                t(
                    "Sterują tylko aktualizacjami uruchomionymi w tej aplikacji. Wstrzymanie podczas sprawdzania dysku może spowodować powtórzenie sprawdzania. Zamknięcie tej aplikacji nie kończy zadań już przyjętych przez Native Access.",
                    "They control only updates started in this app. Pausing during integrity checks may repeat the checks. Closing this app does not stop jobs already accepted by Native Access."
                )
            ),
        ]
        for (q, a) in qa {
            views.append(vstack([text(q, size: 16, weight: .semibold), text(a, size: 14, secondary: true)], gap: 7))
        }
        return document(views)
    }
    func activityBody() -> NSView {
        let log = NSTextView()
        log.isEditable = false
        log.isSelectable = true
        log.font = .monospacedSystemFont(ofSize: 12, weight: .regular)
        log.textContainerInset = NSSize(width: 12, height: 12)
        reportText = log
        let s = NSScrollView()
        s.documentView = log
        s.hasVerticalScroller = true
        s.heightAnchor.constraint(greaterThanOrEqualToConstant: 120).isActive = true
        let top = pageHeader(
            t("Historia i szczegóły", "History and details"),
            t(
                "Tutaj znajdziesz wyniki operacji. Te informacje nie są potrzebne do zwykłego korzystania z aplikacji.",
                "Operation results live here. You do not need these details for everyday use."))
        let head = vstack(
            [
                top,
                actionBlock(
                    exportButton,
                    t(
                        "Zapisuje ostatni raport w wybranym miejscu. Raport może zawierać nazwy bibliotek i ścieżki do Twoich folderów.",
                        "Saves the latest report wherever you choose. Reports may contain library names and local folder paths."
                    )),
            ], gap: 18, inset: 28)
        for v in head.arrangedSubviews { width(v, in: head, minus: 56) }
        let body = vstack([head, s], gap: 0)
        width(head, in: body)
        width(s, in: body)
        return body
    }
    func libraryActions() -> NSView {
        let a = actionBlock(
            scanButton,
            t(
                "Ponownie sprawdza listę. Niczego nie pobiera ani nie naprawia.",
                "Checks the list again. It downloads or repairs nothing."))
        let b = actionBlock(
            repairButton,
            t(
                "Najpierw pokaże, co zostanie naprawione. Zmiany zatwierdzisz osobno.",
                "Shows what will be repaired first. You confirm changes separately."))
        let row = hstack([a, spacer(), b], gap: 20)
        row.alignment = .top
        a.widthAnchor.constraint(equalTo: row.widthAnchor, multiplier: 0.40).isActive = true
        b.widthAnchor.constraint(equalTo: row.widthAnchor, multiplier: 0.49).isActive = true
        let s = vstack([row], gap: 0, inset: 24)
        width(row, in: s, minus: 48)
        return s
    }
    func updateActions() -> NSView {
        if model.updateSessionFile != nil && !model.updateStatuses.isEmpty
            && model.updateStatuses.allSatisfy({ $0.state == "confirmed" })
        {
            let next = button(
                t("Sprawdź pozostałe aktualizacje", "Check remaining updates"), action: #selector(loadUpdates),
                help: t(
                    "Odczytuje ponownie listę nowych wersji. Nie rozpoczyna instalacji.",
                    "Refreshes available versions. It does not start an installation."), prominent: true)
            let s = vstack(
                [
                    actionBlock(
                        next,
                        t(
                            "Te aktualizacje są zakończone. Możesz teraz sprawdzić i wybrać następne.",
                            "These updates are complete. You can now check and select the next ones."))
                ], gap: 0, inset: 20)
            for v in s.arrangedSubviews { width(v, in: s, minus: 40) }
            return s
        }
        if model.updateSessionFile != nil {
            sessionLabel = text("", size: 13, weight: .medium)
            let caption = text(
                t(
                    "Postęp odświeża się sam. Wstrzymanie może spowodować ponowne sprawdzanie SSD.",
                    "Progress refreshes automatically. Pausing may repeat SSD verification."), size: 12, secondary: true
            )
            let row = hstack([updateStatusButton, updatePauseButton, updateResumeButton, spacer()])
            let s = vstack([sessionLabel!, row, caption], gap: 8, inset: 20)
            for v in s.arrangedSubviews { width(v, in: s, minus: 40) }
            return s
        }
        updateSummary = text("", size: 12, secondary: true)
        let a = actionBlock(
            updateAuditButton,
            t(
                "Opcjonalnie: porówna pliki na SSD z nową wersją NI. Nie pobiera dźwięków.",
                "Optional: compares SSD files with NI's new version. It downloads no samples."))
        let b = actionBlock(
            updateStartButton,
            t(
                "Pokaże podsumowanie. Pobieranie ruszy dopiero po Twoim zatwierdzeniu.",
                "Shows a summary. Downloading starts only after you confirm."))
        let row = hstack([a, spacer(), b], gap: 18)
        row.alignment = .top
        a.widthAnchor.constraint(equalTo: row.widthAnchor, multiplier: 0.47).isActive = true
        b.widthAnchor.constraint(equalTo: row.widthAnchor, multiplier: 0.47).isActive = true
        let s = vstack([updateSummary!, row], gap: 7, inset: 20)
        width(row, in: s, minus: 40)
        width(updateSummary!, in: s, minus: 40)
        return s
    }
    func refresh() {
        let hasFolder = !model.root.isEmpty
        let key =
            model.section.rawValue + "|" + String(hasFolder) + "|" + model.language + "|"
            + String(model.updateSessionFile != nil) + "|"
            + String(!model.updateStatuses.isEmpty && model.updateStatuses.allSatisfy { $0.state == "confirmed" })
        if key != renderKey {
            renderKey = key
            guidanceTitle = nil
            guidanceBody = nil
            filterExplanation = nil
            selectionLabel = nil
            updateSummary = nil
            sessionLabel = nil
            reportText = nil
            let needsFolder = [Section.libraries, .updates, .migration].contains(model.section)
            let body: NSView
            if needsFolder && !hasFolder {
                body = folderBody()
            } else {
                switch model.section {
                case .home: body = homeBody()
                case .libraries: body = libraryBody()
                case .updates: body = updateBody()
                case .migration: body = migrationBody()
                case .help: body = helpBody()
                case .activity: body = activityBody()
                }
            }
            replace(bodyHost, with: body)
            if hasFolder && model.section == .libraries {
                replace(actionHost, with: libraryActions())
                actionHost.isHidden = false
            } else if hasFolder && model.section == .updates {
                replace(actionHost, with: updateActions())
                actionHost.isHidden = false
            } else {
                for view in actionHost.subviews { view.removeFromSuperview() }
                actionHost.isHidden = true
            }
        }
        let names = [
            t("Start", "Start"), t("Naprawa", "Repair"), t("Aktualizacje", "Updates"), t("Przeniesienie", "Migration"),
            t("Jak to działa?", "How it works"), t("Historia", "History"),
        ]
        for (i, b) in navButtons.enumerated() {
            let selected = Section.allCases[i] == model.section
            b.title = names[i]
            b.attributedTitle = NSAttributedString(
                string: names[i],
                attributes: [
                    .font: AccessStyle.font(ofSize: 13, weight: selected ? .semibold : .regular),
                    .foregroundColor: selected ? AccessStyle.ink : AccessStyle.muted,
                ])
            b.layer?.backgroundColor =
                NSColor.clear.cgColor
            b.contentTintColor = selected ? AccessStyle.ink : AccessStyle.muted
            b.setAccessibilityLabel(names[i])
            b.setAccessibilityHelp(t("Otwiera: ", "Opens: ") + names[i])
        }
        sourceTitle.stringValue =
            hasFolder
            ? t("Twój folder z bibliotekami", "Your library folder")
            : t("Nie wybrano jeszcze folderu z bibliotekami", "No library folder selected yet")
        sourcePath.stringValue =
            hasFolder ? model.root : t("Wybierzesz go po wybraniu zadania.", "Choose a task to select its folder.")
        chooseButton.isEnabled = !model.busy
        style(
            chooseButton,
            title: hasFolder ? t("Zmień folder…", "Change folder…") : t("Wybierz folder…", "Choose folder…"),
            help: t(
                "Otwiera wybór wspólnego folderu z bibliotekami. Nie przenosi plików.",
                "Choose the parent folder containing your libraries. It does not move files."))
        nativeButton.isEnabled = true
        style(
            nativeButton, title: t("Otwórz Native Access", "Open Native Access"),
            help: t(
                "Przełącza do Native Access, gdzie możesz się zalogować i zobaczyć postęp instalacji.",
                "Opens Native Access to sign in or see installation progress."))
        languagePopup.selectItem(at: model.isPolish ? 0 : 1)
        connectionLabel.stringValue =
            model.previewMode
            ? t("Podgląd zapisanego wyniku\nZmiany są wyłączone", "Saved result preview\nChanges are disabled")
            : model.connection.map {
                $0.connected
                    ? "Native Access \($0.version)"
                    : t("Otwórz Native Access\ni zaloguj się", "Open Native Access\nand sign in")
            } ?? t("Wymaga konta Native Instruments", "Requires your Native Instruments account")
        refreshLibraries()
        refreshUpdates()
        backupButton.isEnabled =
            !model.previewMode && !model.busy && model.connection?.connected == true && model.summary != nil
        style(
            backupButton, title: t("Zapisz dane bibliotek na dysku", "Save library information to the drive"),
            help: t(
                "Zapisuje informacje potrzebne do odnalezienia bibliotek na nowym Macu. Nie kopiuje wszystkich sampli.",
                "Saves the information needed to recognise libraries on your new Mac, without duplicating samples."),
            prominent: true)
        backupOpenButton.isEnabled = hasFolder && !model.previewMode
        style(
            backupOpenButton, title: t("Zobacz zapisane dane", "Show saved information"),
            help: t(
                "Otwiera w Finderze folder z informacjami do przeniesienia bibliotek.",
                "Shows saved library migration information in Finder."))
        exportButton.isEnabled = model.lastReport != nil
        style(
            exportButton, title: t("Zapisz ostatni raport…", "Save latest report…"),
            help: t(
                "Wybierz miejsce, w którym zapiszesz szczegóły ostatniej operacji.",
                "Choose where to save details of the latest operation."))
        let connectionProblem = model.connection.flatMap { $0.connected ? nil : friendlyError($0.message) }
        let message =
            model.error.map { friendlyError($0) } ?? connectionProblem
            ?? (model.previewMode
                ? t(
                    "Podgląd zapisanego wyniku. Wybierz folder ponownie, aby sprawdzić aktualny stan i wykonać zmiany.",
                    "Saved result preview. Select the folder again to check current state and make changes.")
                : model.notice ?? "")
        noticeHost.isHidden = message.isEmpty
        noticeLabel.stringValue = message
        noticeLabel.textColor = model.error == nil ? .secondaryLabelColor : .systemOrange
        noticeLabel.toolTip = model.error
        progressHost.isHidden =
            !model.busy || model.activeCommand == "discover" || model.activeCommand == "update-status"
        progressLabel.stringValue = model.stageLabel
        progressDetail.stringValue = model.progressTitle + (model.total > 0 ? "  \(model.current)/\(model.total)" : "")
        progressBar.isIndeterminate = model.total == 0
        if model.busy && model.total == 0 {
            progressBar.startAnimation(nil)
        } else {
            progressBar.stopAnimation(nil)
            progressBar.doubleValue = Double(model.current) / Double(max(1, model.total))
        }
        cancelButton.isEnabled = !model.cancelled
        style(
            cancelButton, title: t("Przerwij tę operację", "Cancel this operation"),
            help: t(
                "Kończy bieżącą operację tej aplikacji. Już wykonane zmiany pozostają zapisane w raporcie.",
                "Stops this app's current operation. Completed changes remain recorded in its report."))
        if let log = reportText {
            let f = DateFormatter()
            f.timeStyle = .medium
            log.string = model.activity.reversed().map { f.string(from: $0.date) + "  " + $0.text }.joined(
                separator: "\n")
        }
    }
    func refreshLibraries() {
        let labels = [
            t("Wszystkie", "All"), t("Zainstalowane", "Installed"), t("Dostępne", "Available"),
            t("Problemy", "Problems"),
        ]
        let filterValues = ["all", "registered", "ready", "review"]
        for i in 0..<4 {
            filters.setLabel(labels[i], forSegment: i)
            let w = (labels[i] as NSString).size(withAttributes: [.font: AccessStyle.font(ofSize: 16)]).width + 26
            filters.setWidth(w, forSegment: i)
        }
        filters.selectedSegment = filterValues.firstIndex(of: model.filter) ?? 0
        let explanation: String
        switch model.filter {
        case "registered":
            explanation = t(
                "Native Access już widzi te biblioteki. Nie wymagają naprawy.",
                "Native Access already recognises these libraries. They do not need repair.")
        case "ready":
            explanation = t(
                "Te biblioteki są na dysku, ale Native Access jeszcze ich nie widzi. Możesz je zaznaczyć do naprawy.",
                "These libraries are on the drive, but Native Access does not recognise them yet. Select them for repair."
            )
        case "review":
            explanation = t(
                "Nie można ich naprawić automatycznie. Powód jest opisany przy każdej bibliotece.",
                "Automatic repair is not possible. Each library shows the reason.")
        default:
            explanation = t(
                "Wszystkie biblioteki znalezione w wybranym folderze. Te zakładki tylko filtrują listę — niczego nie instalują.",
                "All libraries found in the selected folder. These tabs only filter the list; they install nothing.")
        }
        filterExplanation?.stringValue = explanation
        filters.setAccessibilityLabel(t("Pokaż biblioteki według stanu", "Filter libraries by status"))
        filters.setAccessibilityHelp(explanation)
        search.placeholderString = t("Szukaj nazwy", "Search names")
        if search.stringValue != model.query { search.stringValue = model.query }
        let current = model.visibleRows
        displayRows = current
        table.reloadData()
        let headers = [
            "", t("Biblioteka", "Library"), t("Stan w Native Access", "Native Access status"), t("Wersja", "Version"),
        ]
        for (i, c) in table.tableColumns.enumerated() { c.title = headers[i] }
        selectButton.isEnabled = !model.previewMode && !model.busy && current.contains(where: { $0.recoverable })
        style(
            selectButton, title: t("Zaznacz do naprawy", "Select for repair"),
            help: t(
                "Zaznacza wszystkie dostępne biblioteki z widocznej listy. Nie rozpoczyna naprawy.",
                "Selects all available libraries in the visible list. It does not start repair."))
        repairButton.isEnabled =
            !model.previewMode && !model.busy && !model.recoverableSelection.isEmpty && model.planFile != nil
            && model.connection?.supportsRepair == true
        style(
            repairButton,
            title: t("Sprawdź plan naprawy", "Review repair plan")
                + (model.recoverableSelection.isEmpty ? "" : " (\(model.recoverableSelection.count))"),
            help: t(
                "Pokazuje wybrane biblioteki i proponowane zmiany. Naprawa ruszy dopiero po zatwierdzeniu.",
                "Shows selected libraries and proposed changes. Repair starts only after confirmation."),
            prominent: true)
        scanButton.isEnabled = !model.busy && !model.root.isEmpty
        style(
            scanButton, title: t("Odśwież listę bibliotek", "Refresh library list"),
            help: t(
                "Sprawdza ponownie, które biblioteki Native Access rozpoznaje. Niczego nie pobiera.",
                "Checks which libraries Native Access recognises again, without downloading samples."))
        guard model.section == .libraries else { return }
        if model.busy {
            guidanceTitle?.stringValue = t("Czekaj — sprawdzamy biblioteki", "Please wait — checking your libraries")
            guidanceBody?.stringValue = t(
                "Lista pojawi się po zakończeniu odczytu. Biblioteki nie są teraz pobierane.",
                "The list will appear after reading finishes. Libraries are not being downloaded.")
        } else if let s = model.summary, s.recoverable == 0 && s.review == 0 && s.total > 0 {
            guidanceTitle?.stringValue = t(
                "Wszystko gotowe — nie trzeba nic naprawiać", "Everything is ready — no repair needed")
            guidanceBody?.stringValue =
                t("Native Access widzi wszystkie biblioteki: ", "Native Access recognises every library: ")
                + "\(s.registered)/\(s.total). " + t("Możesz przejść do Aktualizacji.", "You can go to Updates.")
        } else if !model.recoverableSelection.isEmpty {
            guidanceTitle?.stringValue =
                t("Wybrano do naprawy: ", "Selected for repair: ") + String(model.recoverableSelection.count)
            guidanceBody?.stringValue = t(
                "To na razie tylko wybór. Kliknij „Sprawdź plan naprawy”, a potem zatwierdź pokazane zmiany.",
                "This is only a selection so far. Click Review repair plan, then confirm the changes shown.")
        } else {
            guidanceTitle?.stringValue = t("Teraz wybierz biblioteki do naprawy", "Now choose libraries to repair")
            guidanceBody?.stringValue = t(
                "Otwórz „Dostępne” i zaznacz kwadraty przy nazwach albo kliknij „Zaznacz do naprawy”. Zainstalowane biblioteki zostawiamy w spokoju.",
                "Open Available and tick the checkboxes, or click Select for repair. Installed libraries are left alone."
            )
        }
    }
    func refreshUpdates() {
        let selectable = model.updates.filter { $0.state == "ready" }
        let allSelected = !selectable.isEmpty && model.updateSelection.count == selectable.count
        updateSelectButton.isEnabled = !model.previewMode && !model.busy && !selectable.isEmpty
        style(
            updateSelectButton,
            title: allSelected ? t("Odznacz wszystkie", "Deselect all") : t("Zaznacz wszystkie", "Select all"),
            help: t(
                "Wybiera biblioteki z listy. Nie rozpoczyna pobierania ani instalacji.",
                "Selects libraries from the list. It does not start downloading or installing."))
        updateListButton.isEnabled = !model.busy && !model.root.isEmpty
        style(
            updateListButton, title: t("Odśwież listę", "Refresh list"),
            help: t(
                "Sprawdza w NI, czy pojawiły się nowe wersje. Nie pobiera bibliotek.",
                "Checks NI for new versions. It does not download libraries."))
        let canAct = !model.previewMode && !model.busy && model.updatePlanFile != nil && !model.updateSelection.isEmpty
        updateAuditButton.isEnabled = canAct
        style(
            updateAuditButton, title: t("Sprawdź rozmiar pobierania", "Check download size"),
            help: t(
                "Porównuje wybrane biblioteki na SSD z najnowszymi plikami NI i szacuje, ile danych brakuje. To opcjonalny odczyt, bez pobierania dźwięków.",
                "Compares selected SSD libraries with NI's latest files and estimates missing data. Optional; it downloads no samples."
            ))
        updateStartButton.isEnabled = canAct
        style(
            updateStartButton, title: t("Sprawdź plan aktualizacji", "Review update plan"),
            help: t(
                "Pokazuje podsumowanie wybranych aktualizacji. Pobieranie nie ruszy bez kolejnego zatwierdzenia.",
                "Shows the selected updates. Downloading needs a separate confirmation."), prominent: true)
        selectionLabel?.stringValue =
            t("Zaznaczone: ", "Selected: ") + "\(model.updateSelection.count)/\(selectable.count)"
        let audited = model.updateSelection.compactMap(\.audit)
        let unknown = model.updateSelection.count - audited.count
        updateSummary?.stringValue =
            audited.isEmpty
            ? t(
                "Rozmiar pobierania możesz sprawdzić przed zatwierdzeniem. Ten krok jest opcjonalny.",
                "You can check download size before confirming. This step is optional.")
            : t("Dla sprawdzonych bibliotek szacujemy: ", "For compared libraries we estimate: ")
                + model.bytes(audited.reduce(0) { $0 + $1.estimatedTransferBytes })
                + (unknown > 0
                    ? t(". Jeszcze niesprawdzone: ", ". Not compared yet: ") + String(unknown)
                    : t(". To szacunek, nie pomiar transferu.", ". This is an estimate, not measured transfer."))
        for (i, c) in updateTable.tableColumns.enumerated() {
            c.title =
                [
                    "", t("Biblioteka", "Library"), t("Twoja wersja → nowa", "Your version → new"),
                    t("Do pobrania — szacunek", "Estimated download"),
                ][i]
        }
        updateTable.reloadData()
        let hasSession = model.updateSessionFile != nil
        for b in [updateStatusButton, updatePauseButton, updateResumeButton] {
            b.isEnabled = !model.previewMode && !model.busy && hasSession
        }
        updatePauseButton.isEnabled =
            updatePauseButton.isEnabled && model.updateStatuses.contains { $0.state == "STATE_DOWNLOADING" }
        updateResumeButton.isEnabled =
            updateResumeButton.isEnabled && model.updateStatuses.contains { $0.state == "STATE_DOWNLOAD_PAUSED" }
        style(
            updateStatusButton, title: t("Odśwież postęp", "Refresh progress"),
            help: t(
                "Odczytuje z Native Access aktualny stan tych aktualizacji.",
                "Reads current progress for this update session from Native Access."))
        style(
            updatePauseButton, title: t("Wstrzymaj aktualizacje", "Pause updates"),
            help: t(
                "Wstrzymuje tylko aktualizacje uruchomione przez tę aplikację. Może być konieczne ponowne sprawdzenie SSD.",
                "Pauses only this app's update jobs. SSD verification may need to repeat."))
        style(
            updateResumeButton, title: t("Wznów aktualizacje", "Resume updates"),
            help: t(
                "Pozwala Native Access kontynuować wstrzymane aktualizacje z tej sesji.",
                "Lets Native Access continue paused updates from this session."))
        sessionLabel?.stringValue =
            model.updateStatuses.isEmpty
            ? t("Odczytujemy postęp z Native Access…", "Reading progress from Native Access…")
            : model.updateStatuses.map { $0.title + ": " + sessionState($0.state) }.joined(separator: "\n")
        guard model.section == .updates else { return }
        if model.busy && model.activeCommand != "update-status" {
            guidanceTitle?.stringValue = model.stageLabel
            guidanceBody?.stringValue =
                model.activeCommand == "update-audit"
                ? t(
                    "Czytamy pliki na Twoim dysku i porównujemy je z nową wersją NI. Dźwięki nie są pobierane.",
                    "Reading your drive and comparing files with NI's new version. No samples are being downloaded.")
                : t(
                    "Poczekaj na wynik. Nie uruchamiaj drugi raz tej samej operacji.",
                    "Please wait for the result. Do not start the same operation twice.")
        } else if !model.updateStatuses.isEmpty && model.updateStatuses.allSatisfy({ $0.state == "confirmed" }) {
            guidanceTitle?.stringValue = t(
                "Gotowe — Native Access potwierdziło nowe wersje", "Done — Native Access confirmed the new versions")
            guidanceBody?.stringValue = t(
                "Kliknij „Odśwież listę”, aby zobaczyć, czy zostały inne aktualizacje.",
                "Refresh the list to see whether other updates remain.")
        } else if hasSession {
            guidanceTitle?.stringValue = t(
                "Aktualizacje trwają w Native Access", "Updates are running in Native Access")
            guidanceBody?.stringValue = t(
                "Możesz tu sprawdzać postęp lub otworzyć Native Access. Nie uruchamiaj ponownie aktualizacji tych samych bibliotek.",
                "Follow progress here or open Native Access. Do not start the same library updates again.")
        } else if model.updatesLoaded && model.updates.isEmpty {
            guidanceTitle?.stringValue = t("Nie ma nowych aktualizacji", "No new updates available")
            guidanceBody?.stringValue = t(
                "Native Access nie zgłasza nowszych wersji. Niczego nie trzeba pobierać.",
                "Native Access reports no newer versions. Nothing needs downloading.")
        } else if model.updateSelection.isEmpty {
            guidanceTitle?.stringValue = t(
                "Zaznacz biblioteki, które chcesz zaktualizować", "Select the libraries you want to update")
            guidanceBody?.stringValue = t(
                "Zaznacz kwadraty przy nazwach lub kliknij „Zaznacz wszystkie”. To jeszcze nie uruchamia pobierania.",
                "Tick the checkboxes or choose Select all. This does not start downloading.")
        } else {
            guidanceTitle?.stringValue =
                t("Wybrano aktualizacje: ", "Updates selected: ") + String(model.updateSelection.count)
            guidanceBody?.stringValue = t(
                "Możesz opcjonalnie sprawdzić rozmiar pobierania albo kliknąć „Sprawdź plan aktualizacji”, aby zobaczyć podsumowanie.",
                "Optionally check download size, or choose Review update plan to see the summary.")
        }
    }
    func friendlyError(_ message: String) -> String {
        let s = message.lowercased()
        if s.contains("permission") || s.contains("operation not permitted") || s.contains("eacces") {
            return t(
                "Brak dostępu do folderu. Kliknij „Zmień folder”, wybierz go ponownie i zezwól macOS na dostęp do dysku.",
                "Folder access is denied. Choose Change folder, select it again and allow macOS access to the drive.")
        }
        if s.contains("enoent") {
            return t(
                "Nie można znaleźć folderu lub pliku. Sprawdź, czy dysk jest podłączony, i wybierz folder ponownie.",
                "A folder or file could not be found. Connect the drive and select the folder again.")
        }
        if s.contains("unsupported") || s.contains("not supported") || s.contains("adapter") {
            return t(
                "Ta wersja narzędzia obsługuje Native Access 3.26.0. Dla innej wersji potrzebna jest aktualizacja Native FixTool. Nie wykonaliśmy zmian.",
                "This tool supports Native Access 3.26.0. Other versions need an updated Native FixTool. No changes were made."
            )
        }
        if s.contains("native access") || s.contains("network") || s.contains("session") || s.contains("timed out") {
            return t(
                "Nie udało się odczytać danych NI. Otwórz Native Access, zaloguj się i odśwież listę. Szczegóły są w Historii.",
                "NI data could not be read. Open Native Access, sign in and refresh the list. Details are in History.")
        }
        return t(
            "Nie udało się ukończyć operacji. Szczegóły błędu są w Historii; zachowaliśmy raport.",
            "The operation could not finish. Error details are in History and a report was saved.")
    }
    func sessionState(_ state: String) -> String {
        switch state {
        case "confirmed": return t("Gotowe — nowa wersja potwierdzona", "Done — new version confirmed")
        case "STATE_DOWNLOAD_PAUSED": return t("Wstrzymano", "Paused")
        case "STATE_DOWNLOAD_ENQUEUED": return t("Czeka w kolejce Native Access", "Waiting in Native Access queue")
        case "STATE_DOWNLOADING":
            return t("Native Access sprawdza lub pobiera pliki", "Native Access is verifying or downloading files")
        case "STATE_INSTALLING":
            return t("Native Access instaluje aktualizację", "Native Access is installing the update")
        default:
            return t(
                "Native Access nie potwierdziło jeszcze zakończenia", "Native Access has not confirmed completion yet")
        }
    }
    func libraryReason(_ r: LibraryRow) -> String {
        switch r.state {
        case "registered": return t("NI zna folder tej biblioteki.", "NI knows this library's folder.")
        case "canLocate":
            return t(
                "Pliki są na dysku. Można przywrócić ich rozpoznawanie.",
                "Files are on the drive. Recognition can be restored.")
        case "receiptAvailable":
            return t(
                "Sprawdzimy zapisaną kopię danych instalacji przed naprawą.",
                "The saved installation information must be verified before repair.")
        case "notOwned":
            return t(
                "Zalogowane konto NI nie ma licencji na tę bibliotekę.",
                "The signed-in NI account does not own this library.")
        case "registeredElsewhere":
            return t(
                "Native Access używa poprawnej kopii w innym folderze.",
                "Native Access uses a working copy in another folder.")
        case "offline":
            return t(
                "Otwórz Native Access i zaloguj się, potem odśwież listę.",
                "Open Native Access and sign in, then refresh the list.")
        default:
            let s = r.reason.lowercased()
            if s.contains("permission") || s.contains("eacces") {
                return t(
                    "Brak dostępu do folderu. Wybierz go ponownie i zezwól macOS na dostęp.",
                    "Folder access is denied. Select it again and allow macOS access.")
            }
            if s.contains("no recognised content") {
                return t(
                    "Brakuje plików instrumentu. Sprawdź, czy wybrano właściwy folder.",
                    "Instrument files are missing. Check that you selected the correct folder.")
            }
            if s.contains("could not be matched") {
                return t(
                    "Nie znaleziono jednoznacznego dopasowania na koncie NI.",
                    "No unique matching product was found on the NI account.")
            }
            if s.contains("descriptor") || s.contains("nicnt") {
                return t(
                    "Nie udało się jednoznacznie rozpoznać biblioteki.", "The library could not be identified reliably."
                )
            }
            if s.contains("multiple") || s.contains("duplicate") {
                return t(
                    "Znaleziono kilka kopii. Trzeba wybrać właściwy folder.",
                    "Multiple copies were found. Choose the correct folder.")
            }
            return t(
                "Nie można naprawić automatycznie. Szczegóły są w raporcie.",
                "Automatic repair is not possible. See the report for details.")
        }
    }
    func numberOfRows(in tableView: NSTableView) -> Int {
        tableView === updateTable ? model.updates.count : displayRows.count
    }
    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row index: Int) -> NSView? {
        guard let id = tableColumn?.identifier.rawValue else { return nil }
        if tableView === updateTable {
            guard model.updates.indices.contains(index) else { return nil }
            let r = model.updates[index]
            if id == "pick" {
                let b = NSButton(checkboxWithTitle: "", target: self, action: #selector(toggleUpdate(_:)))
                b.tag = index
                b.state = model.selectedUpdates.contains(r.id) ? .on : .off
                b.isEnabled = !model.previewMode && !model.busy && r.state == "ready"
                b.setAccessibilityLabel(t("Wybierz aktualizację: ", "Select update: ") + r.title)
                b.setAccessibilityHelp(
                    t(
                        "Tylko zaznacza tę bibliotekę. Nie rozpoczyna pobierania.",
                        "Selects this library only; starts no download."))
                return b
            }
            if id == "product" {
                let a = text(r.title, size: 15, weight: .medium)
                a.maximumNumberOfLines = 1
                let b = text(
                    r.state == "ready"
                        ? t("Nowa wersja dostępna", "New version available")
                        : r.state == "inProgress"
                            ? t("Aktualizacja już trwa w Native Access", "Already being updated in Native Access")
                            : t(
                                "Otwórz Native Access — wymaga innego sposobu instalacji",
                                "Open Native Access — another installer is needed"), size: 11, secondary: true)
                b.maximumNumberOfLines = 1
                let v = vstack([a, b], gap: 3)
                v.toolTip = r.title + "\n" + r.folder
                return v
            }
            let value =
                id == "versions"
                ? r.installedVersion + " → " + r.targetVersion
                : r.audit.map {
                    $0.estimatedTransferBytes == 0
                        ? t("Pliki już są na dysku", "Files already on drive")
                        : "≈ " + model.bytes($0.estimatedTransferBytes)
                } ?? t("Jeszcze niesprawdzone", "Not compared yet")
            let v = text(value, size: 12, secondary: id == "transfer" && r.audit == nil)
            v.maximumNumberOfLines = 2
            v.toolTip =
                id == "transfer"
                ? t(
                    "Opcjonalnie kliknij „Sprawdź rozmiar pobierania”. Porównamy Twoje pliki z nową wersją NI.",
                    "Optionally check download size to compare your files with NI's new version.") : value
            return v
        }
        guard displayRows.indices.contains(index) else { return nil }
        let r = displayRows[index]
        if id == "pick" {
            guard r.recoverable else { return NSView() }
            let b = NSButton(checkboxWithTitle: "", target: self, action: #selector(toggleRow(_:)))
            b.tag = index
            b.state = model.selected.contains(r.id) ? .on : .off
            b.isEnabled = !model.previewMode && !model.busy
            b.setAccessibilityLabel(t("Zaznacz do naprawy: ", "Select for repair: ") + r.title)
            b.setAccessibilityHelp(
                t(
                    "Tylko zaznacza bibliotekę. Naprawę zatwierdzisz osobno.",
                    "Selects the library only. Repair needs separate confirmation."))
            return b
        }
        if id == "library" {
            let a = text(r.title, size: 15, weight: .medium)
            a.maximumNumberOfLines = 1
            let b = text(libraryReason(r), size: 11, secondary: true)
            b.maximumNumberOfLines = 2
            let s = vstack([a, b], gap: 3)
            s.toolTip = r.folder + "\n" + r.reason
            return s
        }
        if id == "status" {
            let label =
                r.registered
                ? t("Zainstalowana", "Installed")
                : r.recoverable ? t("Dostępna na dysku", "Available on drive") : t("Wymaga uwagi", "Needs attention")
            let icon = NSImageView(
                image: NSImage(
                    systemSymbolName: r.registered
                        ? "checkmark.circle.fill" : r.recoverable ? "wrench" : "exclamationmark.circle",
                    accessibilityDescription: nil)!)
            icon.contentTintColor = r.registered ? AccessStyle.muted : r.recoverable ? blue : .systemOrange
            return hstack([icon, text(label, size: 12)], gap: 6)
        }
        return text(r.version.isEmpty ? "—" : r.version, size: 12, secondary: true)
    }
    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        let index = table.clickedRow >= 0 ? table.clickedRow : table.selectedRow
        guard displayRows.indices.contains(index) else { return }
        for (title, action) in [
            (t("Pokaż folder biblioteki", "Show library folder"), #selector(revealRow(_:))),
            (
                t("Sprawdź pliki z lokalnym opisem NI…", "Verify files against a local NI manifest…"),
                #selector(verifyRow(_:))
            ),
        ] {
            let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
            item.target = self
            item.representedObject = displayRows[index].id
            item.isEnabled = !model.busy && !model.previewMode
            menu.addItem(item)
        }
    }
    @objc func revealRow(_ sender: NSMenuItem) {
        if let id = sender.representedObject as? String, let row = model.rows.first(where: { $0.id == id }) {
            model.reveal(row.folder)
        }
    }
    @objc func verifyRow(_ sender: NSMenuItem) {
        guard !model.previewMode else { return }
        if let id = sender.representedObject as? String, let row = model.rows.first(where: { $0.id == id }) {
            model.verify(row)
        }
    }
    @objc func navigate(_ sender: NSButton) { model.go(Section.allCases[sender.tag]) }
    @objc func openTask(_ sender: NSButton) { model.go(Section.allCases[sender.tag]) }
    @objc func openRecovery() { model.go(.libraries) }
    @objc func openHelp() { model.go(.help) }
    func projectLicenseSummary() -> String {
        t(
            "Nieoficjalne narzędzie, niezależne od Native Instruments. Bezpłatne wyłącznie do użytku prywatnego. Użytek firmowy, organizacyjny, zawodowy i komercyjny jest zabroniony.",
            "An unofficial tool, independent of Native Instruments. Free for private personal use only. Company, organisational, professional and commercial use is prohibited."
        )
    }
    @objc func showAbout() {
        let credits = NSMutableAttributedString(
            string: projectLicenseSummary() + "\n\nNative FixTool Private Use License 1.0\n",
            attributes: [.font: AccessStyle.font(ofSize: 12)])
        if let url = Bundle.main.url(forResource: "Library-Bridge-LICENSE", withExtension: "txt") {
            credits.append(
                NSAttributedString(
                    string: t("Przeczytaj pełną licencję", "Read the full licence"),
                    attributes: [.link: url, .font: AccessStyle.font(ofSize: 12)]))
        }
        NSApp.orderFrontStandardAboutPanel(options: [.credits: credits])
    }
    @objc func choose() { model.chooseFolder() }
    @objc func scan() { model.scan() }
    @objc func openNative() { model.openNative() }
    @objc func cancel() { model.cancel() }
    @objc func snapshot() {
        guard !model.previewMode else { return }
        model.snapshot()
    }
    @objc func export() { model.exportReport() }
    @objc func openBackup() { if let url = model.vaultURL { model.reveal(url.path) } }
    @objc func loadUpdates() { model.loadUpdates() }
    @objc func auditUpdates() {
        guard !model.previewMode else { return }
        model.auditUpdates()
    }
    @objc func updateStatus() {
        model.updatePolling = true
        model.updateSession()
    }
    @objc func pauseUpdates() {
        guard !model.previewMode else { return }
        model.updateSession("update-pause")
    }
    @objc func resumeUpdates() {
        guard !model.previewMode else { return }
        model.updateSession("update-resume")
    }
    @objc func selectUpdates() {
        let eligible = Set(model.updates.filter { $0.state == "ready" }.map(\.id))
        model.selectedUpdates = model.selectedUpdates == eligible ? [] : eligible
    }
    @objc func selectRecoverable() { model.selected.formUnion(model.visibleRows.filter(\.recoverable).map(\.id)) }
    @objc func changeLanguage(_ sender: NSPopUpButton) {
        model.language = sender.indexOfSelectedItem == 0 ? "pl" : "en"
        configureMenus()
        renderKey = ""
        queueRefresh()
    }
    @objc func changeFilter(_ sender: NSSegmentedControl) {
        model.filter = ["all", "registered", "ready", "review"][sender.selectedSegment]
    }
    func controlTextDidChange(_ notification: Notification) {
        if notification.object as? NSSearchField === search { model.query = search.stringValue }
    }
    @objc func toggleRow(_ sender: NSButton) {
        guard displayRows.indices.contains(sender.tag) else { return }
        let id = displayRows[sender.tag].id
        if sender.state == .on { model.selected.insert(id) } else { model.selected.remove(id) }
    }
    @objc func toggleUpdate(_ sender: NSButton) {
        guard model.updates.indices.contains(sender.tag) else { return }
        let id = model.updates[sender.tag].id
        if sender.state == .on { model.selectedUpdates.insert(id) } else { model.selectedUpdates.remove(id) }
    }
    func updateReviewText() -> String {
        let list = model.updateSelection.map { $0.title + "  " + $0.installedVersion + " → " + $0.targetVersion }
            .joined(separator: "\n")
        return list + "\n\n"
            + t(
                "Co się stanie po zatwierdzeniu?\nNative Access sprawdzi istniejące pliki, pobierze potrzebne dane i zainstaluje aktualizacje. Może to potrwać. Niektóre paczki NI mogą wymagać dużego pobrania.\n\nZapisz pracę i zamknij instrumenty. Zapiszemy kopię informacji o instalacji; nie jest to dodatkowa kopia wszystkich dźwięków.",
                "What happens after confirmation?\nNative Access verifies existing files, downloads required data and installs updates. This can take time. Some NI packages can require a large download.\n\nSave your work and close instruments. Installation information is backed up, not all sample content."
            )
    }
    @objc func reviewUpdates() { _ = showUpdateReview(previewOnly: false) }
    func showUpdateReview(previewOnly: Bool) -> NSAlert? {
        guard previewOnly || !model.previewMode, !model.updateSelection.isEmpty else { return nil }
        let a = NSAlert()
        a.messageText = t("Podsumowanie aktualizacji", "Update summary")
        let details = updateReviewText().components(separatedBy: "\n\n").dropFirst().joined(separator: "\n\n")
        a.informativeText =
            (previewOnly ? t("Podgląd — uruchomienie jest wyłączone.\n\n", "Preview — starting is disabled.\n\n") : "")
            + t("Wybrano bibliotek: ", "Libraries selected: ") + String(model.updateSelection.count) + "\n\n" + details
        a.addButton(withTitle: t("Rozpocznij aktualizacje", "Start updates"))
        a.addButton(withTitle: t("Wróć do listy", "Back to list"))
        let list = NSTextView()
        list.isEditable = false
        list.isSelectable = true
        list.font = AccessStyle.font(ofSize: 13)
        list.textContainerInset = NSSize(width: 8, height: 8)
        list.string = model.updateSelection.map { $0.title + "  " + $0.installedVersion + " → " + $0.targetVersion }
            .joined(separator: "\n")
        let scroll = NSScrollView(frame: NSRect(x: 0, y: 0, width: 540, height: 155))
        scroll.documentView = list
        scroll.hasVerticalScroller = true
        scroll.borderType = .bezelBorder
        a.accessoryView = scroll
        if previewOnly { a.buttons[0].isEnabled = false }
        a.beginSheetModal(for: window) { [weak self] r in
            if !previewOnly && r == .alertFirstButtonReturn { self?.model.startUpdates() }
        }
        return a
    }
    @objc func reviewRepair() { _ = showRepairReview(previewOnly: false) }
    func showRepairReview(previewOnly: Bool) -> NSAlert? {
        guard previewOnly || !model.previewMode, !model.recoverableSelection.isEmpty else { return nil }
        let a = NSAlert()
        a.messageText = t("Podsumowanie naprawy", "Repair summary")
        a.informativeText = t(
            "Po zatwierdzeniu przywrócimy rozpoznawanie wybranych bibliotek w Native Access. Dźwięki zostają na dysku. Najpierw zapiszemy kopię danych instalacji. Trwające pobieranie NI może zostać wstrzymane.",
            "After confirmation, we restore recognition of the selected libraries in Native Access. Samples stay on the drive. Installation information is backed up first. Active NI downloads may be paused."
        )
        a.addButton(withTitle: t("Rozpocznij naprawę", "Start repair"))
        a.addButton(withTitle: t("Wróć do listy", "Back to list"))
        let listing = NSTextView()
        listing.isEditable = false
        listing.font = AccessStyle.font(ofSize: 12)
        listing.string = model.recoverableSelection.map { $0.title + "\n" + $0.folder }.joined(separator: "\n\n")
        let scroll = NSScrollView()
        scroll.documentView = listing
        scroll.hasVerticalScroller = true
        scroll.heightAnchor.constraint(equalToConstant: 180).isActive = true
        let content = NSButton(
            checkboxWithTitle: t(
                "Używaj tego folderu dla bibliotek w Native Access", "Use this library folder in Native Access"),
            target: nil, action: nil)
        content.state = model.setContent ? .on : .off
        let redundant = NSButton(
            checkboxWithTitle: t(
                "Anuluj ponowne pobieranie tylko potwierdzonych, aktualnych bibliotek",
                "Cancel redundant downloads only for confirmed up-to-date libraries"), target: nil, action: nil)
        redundant.state = model.cancelRedundant ? .on : .off
        let v = vstack(
            [
                scroll, content,
                text(
                    t(
                        "Zmienia ustawienie folderu bibliotek w Native Access.",
                        "Changes the library folder setting in Native Access."), size: 11, secondary: true), redundant,
                text(
                    t(
                        "Nie anuluje prawdziwych aktualizacji ani innych instalacji.",
                        "Does not cancel genuine updates or other installations."), size: 11, secondary: true),
            ], gap: 8)
        v.frame = NSRect(x: 0, y: 0, width: 570, height: 300)
        scroll.widthAnchor.constraint(equalToConstant: 570).isActive = true
        a.accessoryView = v
        if previewOnly {
            a.buttons[0].isEnabled = false
            content.isEnabled = false
            redundant.isEnabled = false
        }
        a.beginSheetModal(for: window) { [weak self] r in
            guard !previewOnly, r == .alertFirstButtonReturn, let self else { return }
            self.model.setContent = content.state == .on
            self.model.cancelRedundant = redundant.state == .on
            self.model.repair()
        }
        return a
    }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
    func windowShouldClose(_ sender: NSWindow) -> Bool {
        if model.busy {
            NSApp.terminate(nil)
            return false
        }
        return true
    }
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard model.busy else { return .terminateNow }
        let a = NSAlert()
        a.messageText = t("Operacja jeszcze trwa", "An operation is still running")
        a.informativeText = t(
            "Możesz poczekać albo przerwać pracę tej aplikacji. Zadania już przekazane do Native Access pozostaną w Native Access.",
            "Wait or cancel this app's operation. Jobs already accepted by Native Access remain there.")
        a.addButton(withTitle: t("Poczekaj", "Wait"))
        a.addButton(withTitle: t("Przerwij i zamknij", "Cancel and quit"))
        guard a.runModal() == .alertSecondButtonReturn else { return .terminateCancel }
        model.cancel()
        Task {
            while model.busy { try? await Task.sleep(nanoseconds: 300_000_000) }
            sender.reply(toApplicationShouldTerminate: true)
        }
        return .terminateLater
    }
    func runUISmoke(output: String) async {
        guard model.previewMode else { return }
        var passed: [String] = []
        var failed: [String] = []
        func check(_ v: Bool, _ name: String) { if v { passed.append(name) } else { failed.append(name) } }
        check(text("Roboto").font?.familyName == "Roboto", "Bundled Roboto is registered and used by native controls")
        let originalRoot = model.root
        let originalRows = model.rows
        let originalSummary = model.summary
        let originalUpdates = model.updates
        let originalConnection = model.connection
        model.section = .home
        refresh()
        check(
            navButtons.map { $0.title }.prefix(4) == ["Start", "Naprawa", "Aktualizacje", "Przeniesienie"],
            "Task-based Polish navigation")
        model.section = .libraries
        refresh()
        check(
            filters.label(forSegment: 1) == "Zainstalowane" && filters.label(forSegment: 2) == "Dostępne",
            "Familiar NI library filters")
        model.filter = "registered"
        refresh()
        check(displayRows.allSatisfy(\.registered), "Installed filter only shows NI-recognised libraries")
        model.filter = "ready"
        refresh()
        check(
            displayRows.allSatisfy(\.recoverable) && filterExplanation?.stringValue.contains("na dysku") == true,
            "Available filter explains existing files")
        model.filter = "review"
        refresh()
        check(
            filterExplanation?.stringValue.contains("automatycznie") == true, "Problems filter explains the limitation")
        model.filter = "all"
        model.query = "NO_MATCH_UX_12345"
        refresh()
        check(displayRows.isEmpty, "Library search filters actual datasource")
        model.query = ""
        refresh()
        check(!repairButton.isEnabled && !backupButton.isEnabled, "Saved results cannot write registrations or backups")
        model.section = .updates
        refresh()
        check(!updateStartButton.isEnabled && !updateAuditButton.isEnabled, "Saved results cannot start downloads")
        check(updateTable.numberOfRows == originalUpdates.count, "Update table renders actual saved updates")
        check(
            updateAuditButton.title == "Sprawdź rozmiar pobierania"
                && updateAuditButton.accessibilityHelp()?.contains("SSD") == true,
            "Comparison action explains what it compares")
        check(
            updateStartButton.title == "Sprawdź plan aktualizacji"
                && updateStartButton.action == #selector(reviewUpdates), "Primary update action reviews before starting"
        )
        check(
            !updateTable.tableColumns.contains { $0.identifier.rawValue == "size" },
            "Full library size cannot be mistaken for download size")
        model.language = "en"
        renderKey = ""
        refresh()
        check(
            navButtons[1].title == "Repair" && updateAuditButton.title == "Check download size",
            "English UI has matching task labels")
        model.language = "pl"
        model.section = .migration
        renderKey = ""
        refresh()
        check(backupButton.title == "Zapisz dane bibliotek na dysku", "Migration button names the data it saves")
        model.section = .help
        refresh()
        check(navButtons[4].title == "Jak to działa?", "Instructions stay inside the app")
        model.root = ""
        model.section = .updates
        refresh()
        check(
            renderKey.contains("false") && bodyHost.subviews.count == 1,
            "An empty folder starts with folder instructions")
        model.root = originalRoot
        model.rows = originalRows
        model.summary = originalSummary
        model.updates = originalUpdates
        model.connection = originalConnection
        model.updatesLoaded = true
        model.section = .libraries
        model.filter = "all"
        refresh()
        check(
            table.accessibilityRole() == .table && chooseButton.accessibilityRole() == .button,
            "Native table and folder button keep accessibility roles")
        window.makeFirstResponder(chooseButton)
        check(window.firstResponder === chooseButton, "Native keyboard focus can reach folder selection")
        let available = LibraryRow(
            id: "UX-example-available", folder: originalRoot + "/Example", title: "Przykład UX — biblioteka dostępna",
            state: "canLocate", reason: "UI fixture", version: "1.0.0", targetVersion: "1.0.0", upid: "UX-example",
            identitySource: "UI fixture", registeredPath: nil)
        let problem = LibraryRow(
            id: "UX-example-problem", folder: originalRoot + "/Unknown",
            title: "Przykład UX — biblioteka bez identyfikacji", state: "needsReview", reason: "No product descriptor",
            version: "", targetVersion: "", upid: "", identitySource: "UI fixture", registeredPath: nil)
        model.rows = [available, problem] + Array(originalRows.prefix(1))
        model.summary = ScanSummary(
            total: model.rows.count, registered: originalRows.isEmpty ? 0 : 1, recoverable: 1, review: 1)
        model.filter = "ready"
        refresh()
        check(
            displayRows.map(\.id) == [available.id],
            "Available tab selects a real datasource recovery state, not installed libraries")
        selectRecoverable()
        refresh()
        check(
            model.selected == [available.id] && guidanceBody?.stringValue.contains("tylko wybór") == true,
            "Select for repair changes selection only and explains the next step")
        if let alert = showRepairReview(previewOnly: true) {
            try? await Task.sleep(nanoseconds: 200_000_000)
            check(
                alert.window.sheetParent === window && !alert.buttons[0].isEnabled,
                "Native repair review is a modal sheet with preview writes disabled")
            window.endSheet(alert.window, returnCode: .alertSecondButtonReturn)
            alert.window.orderOut(nil)
        }
        model.filter = "review"
        refresh()
        check(displayRows.map(\.id) == [problem.id], "Problems tab isolates libraries needing manual attention")
        model.rows = originalRows
        model.summary = originalSummary
        model.selected = []
        model.filter = "all"
        model.section = .updates
        refresh()
        selectUpdates()
        refresh()
        check(
            model.updateSelection.count == originalUpdates.filter { $0.state == "ready" }.count,
            "Select all picks only eligible update rows")
        check(
            updateReviewText().contains("Co się stanie po zatwierdzeniu?") && !model.busy,
            "Update review explains the next write without launching a process")
        if let alert = showUpdateReview(previewOnly: true) {
            try? await Task.sleep(nanoseconds: 200_000_000)
            check(
                alert.window.sheetParent === window && !alert.buttons[0].isEnabled
                    && alert.accessoryView is NSScrollView,
                "Native update review has a scrollable product list and separate confirmation")
            window.endSheet(alert.window, returnCode: .alertSecondButtonReturn)
            alert.window.orderOut(nil)
        }
        model.selectedUpdates = []
        model.section = .updates
        model.busy = true
        model.activeCommand = "update-audit"
        model.stage = "auditUpdates"
        refresh()
        check(
            !chooseButton.isEnabled && !updateStartButton.isEnabled
                && guidanceBody?.stringValue.contains("Dźwięki nie są pobierane") == true,
            "Simulated comparison blocks conflicting actions and explains disk reading")
        model.busy = false
        model.activeCommand = ""
        model.error = "EACCES permission denied — UI simulation"
        refresh()
        check(
            !noticeHost.isHidden && noticeLabel.stringValue.contains("wybierz go ponownie"),
            "Simulated denied access shows a visible folder recovery instruction")
        model.error = nil
        func feed(_ event: [String: Any]) {
            if var data = try? JSONSerialization.data(withJSONObject: event) {
                data.append(10)
                model.consume(data)
            }
        }
        feed(["type": "error", "message": "CANCELLED", "cancelled": true])
        refresh()
        check(
            model.error == nil && model.notice?.contains("Przerwano") == true && model.previewMode
                && noticeLabel.stringValue.contains("Podgląd"),
            "Simulated cancellation records cancellation while retaining the read-only preview banner")
        feed([
            "type": "result", "command": "repair",
            "errors": [["title": "UI example", "message": "simulated failure"]],
        ])
        refresh()
        check(
            model.notice?.contains("częściowo") == true && model.error?.contains("simulated failure") == true,
            "Simulated partial repair retains an error and does not claim full success")
        model.error = nil
        model.notice = nil
        model.updates = []
        model.updatesLoaded = true
        refresh()
        check(
            guidanceTitle?.stringValue == "Nie ma nowych aktualizacji",
            "An empty update catalogue shows that no download is needed")
        model.updates = originalUpdates
        model.updateSessionFile = nil
        feed(["type": "result", "command": "update-start", "started": 0, "cancelled": true])
        refresh()
        check(
            model.updateSessionFile == nil && updateSummary != nil && !model.busy
                && model.notice?.contains("Przerwano") == true,
            "A zero-start cancelled batch does not create a phantom active session")
        model.updateSessionFile = "/tmp/UX-example-session.json"
        model.updateStatuses = [
            UpdateStatus(
                upid: "UX-example", title: "UI example", targetVersion: "2.0.0", installedVersion: "2.0.0",
                state: "confirmed", progress: 1)
        ]
        refresh()
        func buttonTitles(_ view: NSView) -> [String] {
            (view as? NSButton).map { [$0.title] } ?? view.subviews.flatMap { buttonTitles($0) }
        }
        check(
            buttonTitles(actionHost).contains("Sprawdź pozostałe aktualizacje"),
            "A confirmed session exposes the next update-list action")
        model.updateSessionFile = nil
        model.updateStatuses = []
        model.notice = nil
        model.section = .libraries
        refresh()
        if let i = CommandLine.arguments.firstIndex(of: "--capture-scenarios"), CommandLine.arguments.count > i + 1 {
            let directory = CommandLine.arguments[i + 1]
            try? FileManager.default.createDirectory(atPath: directory, withIntermediateDirectories: true)
            for (name, section) in [
                ("02-start", Section.home), ("03-repair", .libraries), ("04-updates", .updates),
                ("05-migration", .migration), ("06-help", .help),
            ] {
                model.section = section
                refresh()
                window.contentView?.layoutSubtreeIfNeeded()
                try? await Task.sleep(nanoseconds: 150_000_000)
                model.captureOwnWindow(to: directory + "/" + name + ".png")
                try? await Task.sleep(nanoseconds: 500_000_000)
            }
            model.root = ""
            model.section = .updates
            refresh()
            try? await Task.sleep(nanoseconds: 150_000_000)
            model.captureOwnWindow(to: directory + "/07-folder.png")
            try? await Task.sleep(nanoseconds: 500_000_000)
            model.root = originalRoot
            model.section = .updates
            model.busy = true
            model.activeCommand = "update-audit"
            model.stage = "auditUpdates"
            model.total = 100
            model.current = 40
            refresh()
            try? await Task.sleep(nanoseconds: 150_000_000)
            model.captureOwnWindow(to: directory + "/08-reading.png")
            try? await Task.sleep(nanoseconds: 500_000_000)
            model.busy = false
            model.error = "EACCES permission denied"
            refresh()
            try? await Task.sleep(nanoseconds: 150_000_000)
            model.captureOwnWindow(to: directory + "/09-permission.png")
            try? await Task.sleep(nanoseconds: 500_000_000)
            model.error = nil
            model.section = .home
            refresh()
        }
        let report: [String: Any] = [
            "roles": [
                "table": table.accessibilityRole()?.rawValue ?? "nil",
                "choose": chooseButton.accessibilityRole()?.rawValue ?? "nil",
            ], "passed": passed, "failed": failed,
            "source":
                "Native UI with actual saved scans; empty, busy and permission states are explicitly simulated in read-only mode. No download or registration writes. No VoiceOver certification.",
        ]
        if let data = try? JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys]) {
            try? data.write(to: URL(fileURLWithPath: output), options: .atomic)
        }
        model.captureOwnWindowIfRequested()
    }
}

@main struct LibraryBridgeApp {
    @MainActor static func main() {
        let app = NSApplication.shared
        app.setActivationPolicy(.regular)
        let delegate = BridgeAppDelegate()
        app.delegate = delegate
        withExtendedLifetime(delegate) { app.run() }
    }
}
