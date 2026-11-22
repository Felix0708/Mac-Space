import SwiftUI
import AppKit
import Darwin

struct Entry: Identifiable, Hashable {
    var id: String { path }
    let path: String
    let bytes: Int64
    var complete: Bool = true
    var name: String { URL(fileURLWithPath: path).lastPathComponent }
}
func size(_ n: Int64) -> String { ByteCountFormatter.string(fromByteCount: max(0,n), countStyle: .file) }
let home = FileManager.default.homeDirectoryForCurrentUser.path
let colors: [Color] = [Color(red:0.34,green:0.45,blue:0.86), Color(red:0.40,green:0.64,blue:0.56), Color(red:0.77,green:0.58,blue:0.36), Color(red:0.63,green:0.48,blue:0.76), Color(red:0.80,green:0.48,blue:0.53), Color(red:0.38,green:0.63,blue:0.75)]
let ink = Color(red:0.16,green:0.20,blue:0.24)
let muted = Color(red:0.48,green:0.51,blue:0.54)
let accent = Color(red:0.28,green:0.40,blue:0.77)

func measure(_ path: String) -> (Int64, Bool) {
    let p = Process(); p.executableURL = URL(fileURLWithPath:"/usr/bin/du"); p.arguments = ["-k", "-d", "1", "-x", path]
    let pipe = Pipe(); p.standardOutput = pipe; p.standardError = FileHandle.nullDevice
    do {
        try p.run()
        let timeout = DispatchWorkItem {
            if p.isRunning { p.terminate() }
            DispatchQueue.global().asyncAfter(deadline:.now()+2) { if p.isRunning { kill(p.processIdentifier,SIGKILL) } }
        }
        DispatchQueue.global().asyncAfter(deadline:.now()+20,execute:timeout)
        defer { timeout.cancel() }
        let data = pipe.fileHandleForReading.readDataToEndOfFile(); p.waitUntilExit()
        let text = String(data:data,encoding:.utf8) ?? ""
        var partial: Int64 = 0
        var total: Int64?
        for line in text.split(separator:"\n") {
            let fields = line.split(separator:"\t",maxSplits:1)
            guard fields.count == 2, let k = Int64(fields[0]) else { continue }
            if String(fields[1]) == path { total = k * 1024 }
            else { partial += k * 1024 }
        }
        return (total ?? partial, p.terminationStatus == 0)
    } catch { return (0,false) }
}
func children(_ path: String) throws -> [String] {
    try FileManager.default.contentsOfDirectory(atPath:path).map { (path as NSString).appendingPathComponent($0) }.filter { p in
        // Symbolic links can lead outside the inspected folder or count data twice.
        (try? URL(fileURLWithPath:p).resourceValues(forKeys:[.isSymbolicLinkKey]).isSymbolicLink) != true
    }
}
// Protected trees must not be traversed by the automatic basic scan.
let protectedHomeNames: Set<String> = ["Library", ".Trash", "Desktop", "Documents", "Downloads", "Pictures", "Movies", "Music"]
func basicRoots(_ userHome: String, names: [String]) -> [String] {
    names.filter { !protectedHomeNames.contains($0) && !$0.contains("/") && $0 != "." && $0 != ".." }
        .map { userHome + "/" + $0 } + ["/Applications", "/Library/Developer"]
}
func relatedPaths(_ app: String, library: String = home + "/Library") -> [String] {
    guard let id = Bundle(path:app)?.bundleIdentifier, id.contains("."), !id.contains("/"), !id.contains("..") else { return [] }
    // shortcut: Only exact bundle-ID paths are suggested. Shared containers and vendor-name matches require a vendor uninstaller.
    return ["Caches/" + id, "Preferences/" + id + ".plist", "Application Support/" + id, "Saved Application State/" + id + ".savedState"].map { library + "/" + $0 }
}
struct Candidate: Identifiable {
    var id: String { path }; let path: String; let label: String; let bytes: Int64
}

final class SpaceModel: ObservableObject {
    @Published var total: Int64 = 0
    @Published var free: Int64 = 0
    @Published var entries: [Entry] = []
    @Published var apps: [Entry] = []
    @Published var detail: [Entry] = []
    @Published var folder = home
    @Published var scanning = false
    @Published var detailBusy = false
    @Published var status = "저장 공간을 확인하고 있어요"
    @Published var incomplete = 0
    @Published var detailIncomplete = 0
    @Published var search = ""
    @Published var page = 0
    @Published var selectedApp: Entry?
    @Published var candidates: [Candidate] = []
    @Published var selected: Set<String> = []
    @Published var preparing = false
    @Published var deleting = false
    @Published var result = ""
    @Published var confirm = false
    @Published var fullScan = UserDefaults.standard.bool(forKey:"fullScanRequested")
    @Published var permissionSetup = false
    @Published var needsSetup = false
    func openPermissions() {
        NSWorkspace.shared.open(URL(string:"x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles")!)
    }
    func enableFullScan() {
        fullScan = true
        UserDefaults.standard.set(true,forKey:"fullScanRequested")
        scan()
    }
    func resetToBasic() {
        fullScan = false
        UserDefaults.standard.set(false,forKey:"fullScanRequested")
        needsSetup = true
    }
    var used: Int64 { max(0,total-free) }
    var sorted: [Entry] { entries.sorted { $0.bytes > $1.bytes } }
    var filteredApps: [Entry] { apps.filter { search.isEmpty || $0.name.localizedCaseInsensitiveContains(search) }.sorted { $0.bytes > $1.bytes } }
    func capacity() {
        if let a = try? FileManager.default.attributesOfFileSystem(forPath:"/System/Volumes/Data") {
            total = (a[.systemSize] as? NSNumber)?.int64Value ?? 0
            free = (a[.systemFreeSize] as? NSNumber)?.int64Value ?? 0
        }
    }
    func scan() {
        guard !scanning && !deleting else { return }; scanning = true; entries = []; apps = []; incomplete = 0; capacity()
        let includeProtected = fullScan
        DispatchQueue.global(qos:.utility).async {
            let fm = FileManager.default
            let names = (try? fm.contentsOfDirectory(atPath:home)) ?? []
            var roots = basicRoots(home,names:names)
            roots = roots.filter { fm.fileExists(atPath:$0) && (try? URL(fileURLWithPath:$0).resourceValues(forKeys:[.isSymbolicLinkKey]).isSymbolicLink) != true }.sorted()
            for path in roots {
                DispatchQueue.main.async { self.status = "조사 중 · " + URL(fileURLWithPath:path).lastPathComponent }
                let (bytes, ok) = measure(path)
                DispatchQueue.main.async {
                    if bytes > 0 || !ok { self.entries.append(Entry(path:path,bytes:bytes,complete:ok)) }
                    if !ok { self.incomplete += 1 }
                }
            }
            if includeProtected {
                let protectedRoots = protectedHomeNames.sorted().map { home + "/" + $0 } + ["/Library/Application Support", "/private/var"]
                for path in protectedRoots {
                    guard fm.fileExists(atPath:path) else { continue }
                    DispatchQueue.main.async { self.status = "전체 범위 조사 중 · " + URL(fileURLWithPath:path).lastPathComponent }
                    let (bytes,ok) = measure(path)
                    DispatchQueue.main.async {
                        self.entries.append(Entry(path:path,bytes:bytes,complete:ok))
                        if !ok { self.incomplete += 1; self.resetToBasic() }
                    }
                    if !ok { break }
                }
            }
            for base in ["/Applications", home + "/Applications"] {
                for path in ((try? children(base)) ?? []).filter({ $0.hasSuffix(".app") }) {
                    let (bytes,_) = measure(path)
                    DispatchQueue.main.async { self.apps.append(Entry(path:path,bytes:bytes)) }
                }
            }
            DispatchQueue.main.async { self.scanning = false; self.status = "조사 완료 · " + Date().formatted(date:.omitted,time:.shortened); self.capacity() }
        }
    }
    func explore(_ path: String) {
        guard !detailBusy else { return }; folder = path; detail = []; detailIncomplete = 0; detailBusy = true; page = 1
        DispatchQueue.global(qos:.utility).async {
            do {
                for p in try children(path) {
                    let (bytes,ok) = measure(p)
                    DispatchQueue.main.async { self.detail.append(Entry(path:p,bytes:bytes,complete:ok)); if !ok { self.detailIncomplete += 1 } }
                }
            } catch { DispatchQueue.main.async { self.detailIncomplete += 1 } }
            DispatchQueue.main.async { self.detail.sort { $0.bytes > $1.bytes }; self.detailBusy = false }
        }
    }
    func prepare(_ app: Entry) {
        guard !preparing && !deleting else { return }
        selectedApp = app; candidates = [Candidate(path:app.path,label:"앱 본체",bytes:app.bytes)]; selected = [app.path]; result = ""; preparing = true
        guard fullScan else { preparing = false; return }
        DispatchQueue.global(qos:.utility).async {
            var found: [Candidate] = []
            for p in relatedPaths(app.path) where FileManager.default.fileExists(atPath:p) {
                if (try? URL(fileURLWithPath:p).resourceValues(forKeys:[.isSymbolicLinkKey]).isSymbolicLink) == true { continue }
                let (bytes,_) = measure(p)
                found.append(Candidate(path:p,label:p.contains("/Caches/") ? "캐시" : "설정 / 앱 데이터",bytes:bytes))
            }
            let items = found
            DispatchQueue.main.async { self.candidates += items; self.preparing = false }
        }
    }
    func trash() {
        guard let app = selectedApp, !deleting, !preparing, selected.contains(app.path) else { return }
        if NSWorkspace.shared.runningApplications.contains(where: { $0.bundleURL?.path == app.path }) {
            result = "실행 중인 앱입니다. 앱을 종료한 뒤 다시 시도해 주세요."; return
        }
        guard !(Bundle(path:app.path)?.bundleIdentifier?.hasPrefix("com.apple.") ?? false) else { result = "Apple 기본 앱은 이 도구에서 제거하지 않습니다."; return }
        if selected.count > 1, let id = Bundle(path:app.path)?.bundleIdentifier {
            let copies = ["/Applications",home + "/Applications"].flatMap { (try? children($0)) ?? [] }
            if copies.contains(where: { $0 != app.path && $0.hasSuffix(".app") && Bundle(path:$0)?.bundleIdentifier == id }) {
                result = "같은 앱의 다른 복사본이 있어 관련 데이터는 보호합니다. 앱 본체만 선택해 주세요."; return
            }
        }
        let allowed = Set([app.path] + relatedPaths(app.path))
        guard selected.isSubset(of:allowed), ["/Applications",home + "/Applications"].contains((app.path as NSString).deletingLastPathComponent), app.path.hasSuffix(".app"), app.path != Bundle.main.bundlePath else {
            result = "이 항목은 여기서 제거할 수 없습니다."; return
        }
        deleting = true
        var messages: [String] = []
        // Remove the app first. Never remove its data if moving the app itself fails.
        let paths = [app.path] + selected.filter { $0 != app.path }.sorted()
        for p in paths {
            if URL(fileURLWithPath:p).resolvingSymlinksInPath().path != URL(fileURLWithPath:p).standardizedFileURL.path { messages.append("건너뜀: 링크 경로 " + p); if p == app.path { break }; continue }
            do {
                var destination: NSURL?
                try FileManager.default.trashItem(at:URL(fileURLWithPath:p),resultingItemURL:&destination)
                let gone = !FileManager.default.fileExists(atPath:p)
                messages.append((gone ? "휴지통 이동 확인: " : "원래 위치 재확인 필요: ") + URL(fileURLWithPath:p).lastPathComponent)
            } catch {
                messages.append("이동 실패: \(URL(fileURLWithPath:p).lastPathComponent) · \(error.localizedDescription)")
                if p == app.path { break }
            }
        }
        result = messages.joined(separator:"\n") + "\n\n선택한 경로만 확인했습니다. 휴지통을 비우기 전까지 공간은 반환되지 않습니다."
        apps.removeAll { !FileManager.default.fileExists(atPath:$0.path) }; selected = []; deleting = false; capacity()
    }
}
