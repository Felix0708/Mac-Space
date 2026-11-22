import SwiftUI
import AppKit

@main struct Tests {
 static func main() throws {
 let planned = basicRoots("/Users/test",names:["Library",".Trash","Downloads","Desktop","Documents","Pictures","Music","Movies","Projects",".npm","../escape"])
 assert(planned.contains("/Users/test/Projects"))
 assert(planned.contains("/Users/test/.npm"))
 assert(planned.contains("/Applications"))
 for name in protectedHomeNames { assert(!planned.contains("/Users/test/" + name)) }
 assert(!planned.contains("/Library"))
 assert(!planned.contains("/private/var"))
 assert(!planned.contains("/Users/test/../escape"))
 let fm = FileManager.default
 let root = FileManager.default.temporaryDirectory.appendingPathComponent("mac-space-test-" + UUID().uuidString).path
 try fm.createDirectory(atPath:root,withIntermediateDirectories:true)
 defer { try? fm.removeItem(atPath:root) }
 let app = root + "/Example.app"
 try fm.createDirectory(atPath:app + "/Contents",withIntermediateDirectories:true)
 let info: [String:Any] = ["CFBundleIdentifier":"org.example.fixture", "CFBundlePackageType":"APPL"]
 let data = try PropertyListSerialization.data(fromPropertyList:info,format:.xml,options:0)
 try data.write(to:URL(fileURLWithPath:app + "/Contents/Info.plist"))
 let paths = relatedPaths(app,library:root + "/Library")
 assert(paths.count == 4)
 assert(paths.contains(root + "/Library/Caches/org.example.fixture"))
 assert(!paths.contains(where: { $0.contains("Group Containers") }))
 assert(relatedPaths(root + "/missing.app").isEmpty)
 try Data(repeating:42,count:8192).write(to:URL(fileURLWithPath:root + "/data"))
 try fm.createSymbolicLink(atPath:root + "/link",withDestinationPath:root + "/data")
 let listed = try children(root)
 assert(!listed.contains(root + "/link"))
 let (bytes,ok) = measure(root)
 assert(ok && bytes >= 8192)
 let (_,missingOK) = measure(root + "/absent")
 assert(!missingOK)
 let model = SpaceModel()
 model.selectedApp = Entry(path:app,bytes:8192)
 model.selected = [app,root + "/data"]
 model.trash()
 assert(fm.fileExists(atPath:app))
 assert(fm.fileExists(atPath:root + "/data"))
 assert(model.result.contains("제거할 수 없습니다"))
 model.capacity()
 assert(model.total > 0 && model.free >= 0 && model.free <= model.total)
 print("PASS: bundle-ID matching, missing bundle, symlink exclusion, disk measurement, read failure, deletion scope rejection, disk capacity")
 }
}
