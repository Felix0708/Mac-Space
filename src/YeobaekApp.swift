import SwiftUI
import AppKit

struct Card<Content:View>: View {
    @ViewBuilder var content: Content
    var body: some View { VStack(alignment:.leading,spacing:16) { content }.padding(24).frame(maxWidth:.infinity,alignment:.leading).background(.white,in:RoundedRectangle(cornerRadius:20)).overlay(RoundedRectangle(cornerRadius:20).stroke(ink.opacity(0.06))) }
}
struct ContentView: View {
    @StateObject var m = SpaceModel()
    var body: some View {
        HStack(spacing:0) {
            VStack(alignment:.leading,spacing:30) {
                HStack(spacing:10) { Image(systemName:"circle.hexagongrid.fill").font(.system(size:27)).foregroundStyle(accent); Text("여백").font(.system(size:26,weight:.bold)) }.padding(.top,22)
                Text("내 Mac을 가볍게").font(.system(size:12)).foregroundStyle(muted).padding(.top,-22)
                VStack(spacing:8) {
                    nav("저장 공간", "chart.pie", 0)
                    nav("폴더 탐색", "folder", 1)
                    nav("앱 정리", "square.grid.2x2", 2)
                }
                Spacer()
                VStack(alignment:.leading,spacing:10) {
                    Image(systemName:"externaldrive").font(.title2)
                    Text("이 Mac의 저장 공간").font(.system(size:12,weight:.medium))
                    ProgressView(value:m.total > 0 ? Double(m.used)/Double(m.total) : 0).tint(accent)
                    Text("\(size(m.free)) 여유").font(.system(size:12)).foregroundStyle(muted)
                }.padding(16).background(.white.opacity(0.75),in:RoundedRectangle(cornerRadius:14))
                Text("파일 정보는 이 Mac에서만 처리해요.").font(.system(size:10)).foregroundStyle(muted)
            }.padding(22).frame(width:216).background(Color(red:0.93,green:0.94,blue:0.94))
            VStack(alignment:.leading,spacing:0) {
                HStack {
                    VStack(alignment:.leading,spacing:6) {
                        Text(["어디에 공간을 쓰고 있을까요?","큰 폴더부터 살펴보세요","사용하지 않는 앱을 정리하세요"][m.page]).font(.system(size:27,weight:.bold))
                        Text(m.page == 0 ? "용량이 큰 항목부터, 이해하기 쉽게." : m.page == 1 ? "폴더를 열어 공간을 차지하는 항목을 찾아보세요." : "앱 본체와 관련 파일을 확인한 뒤 휴지통으로 옮겨요.").font(.system(size:13)).foregroundStyle(muted)
                    }
                    Spacer()
                    Button { m.scan() } label: { Label(m.scanning ? "조사 중" : "재조사",systemImage:"arrow.clockwise").padding(7) }.disabled(m.scanning || m.deleting)
                }.padding(30)
                ScrollView {
                    VStack(alignment:.leading,spacing:20) {
                        if m.page == 0 { overview }
                        else if m.page == 1 { explorer }
                        else { applications }
                    }.padding(.horizontal,30).padding(.bottom,30)
                }
                HStack(spacing:8) {
                    if m.scanning || m.detailBusy { ProgressView().controlSize(.small) }
                    else { Image(systemName:"checkmark.circle").foregroundStyle(Color.green) }
                    Text(m.status).font(.system(size:11)); Spacer()
                    Text("휴지통은 자동으로 비우지 않아요").font(.system(size:11))
                }.foregroundStyle(muted).padding(.horizontal,30).padding(.vertical,12)
            }.background(Color(red:0.97,green:0.97,blue:0.96))
        }.foregroundStyle(ink).frame(minWidth:1000,minHeight:720).preferredColorScheme(.light)
        .onAppear { m.scan() }
        .alert("전체 범위 조사 설정",isPresented:$m.permissionSetup) {
            Button("권한 설정 열기") { m.openPermissions() }
            Button("설정 완료 · 전체 조사") { m.enableFullScan() }
            Button("기본 조사 유지",role:.cancel) {}
        } message: {
            Text("시스템 설정의 개인정보 보호 및 보안 → 전체 디스크 접근 권한에서 여백을 허용해 주세요. macOS가 재실행을 요청하면 먼저 재실행하세요. 설정을 마친 뒤 ‘설정 완료’를 누르면 다음 실행부터 전체 범위를 자동 조사합니다. 이 버튼 자체가 권한을 부여하지는 않습니다.")
        }
        .sheet(item:$m.selectedApp) { app in removal(app) }
    }
    func nav(_ title:String,_ icon:String,_ index:Int) -> some View {
        Button { m.page = index } label: {
            HStack(spacing:12) { Image(systemName:icon).frame(width:20); Text(title).font(.system(size:14,weight:.semibold)); Spacer() }.padding(13).foregroundStyle(m.page == index ? accent : muted).background(m.page == index ? Color.white : Color.clear,in:RoundedRectangle(cornerRadius:12))
        }.buttonStyle(.plain)
    }
    var overview: some View {
        VStack(spacing:20) {
            Card {
                HStack {
                    Label(m.fullScan ? "전체 범위 자동 조사" : "기본 범위 자동 조사",systemImage:"checkmark.shield").font(.system(size:15,weight:.semibold))
                    Spacer()
                    Button("전체 조사 설정") { m.permissionSetup = true }.disabled(m.scanning)
                }
                Text(m.fullScan ? "앱을 열면 자동으로 조사합니다. 재조사를 누르면 다시 계산합니다." : "앱과 일반 폴더는 자동 조사합니다. 앱 데이터·휴지통·문서 등 보호 영역은 전체 조사 설정 전까지 접근하지 않습니다.").font(.system(size:12)).foregroundStyle(muted)
                if m.needsSetup { Text("전체 조사에서 접근 실패 또는 시간 초과가 발생해 기본 범위로 돌아왔습니다. 보호 영역을 계속 재시도하지 않습니다.").font(.system(size:12)).foregroundStyle(.orange) }
            }
            Card {
                HStack(spacing:36) {
                    ZStack {
                        Circle().stroke(accent.opacity(0.10),lineWidth:18)
                        Circle().trim(from:0,to:m.total > 0 ? CGFloat(m.used)/CGFloat(m.total) : 0).stroke(accent,style:StrokeStyle(lineWidth:18,lineCap:.round)).rotationEffect(.degrees(-90))
                        VStack(spacing:4) { Text(m.total > 0 ? "\(Int(Double(m.used)/Double(m.total)*100))%" : "—").font(.system(size:38,weight:.bold,design:.rounded)); Text("사용 중").font(.system(size:12)).foregroundStyle(muted) }
                    }.frame(width:150,height:150).padding(10)
                    VStack(alignment:.leading,spacing:14) {
                        Text("공간을 알면, 정리가 쉬워져요.").font(.system(size:21,weight:.semibold))
                        HStack(spacing:34) { metric("사용 공간",size(m.used),accent); metric("여유 공간",size(m.free),colors[1]); metric("전체 공간",size(m.total),ink) }
                        Text("파일 시스템 기준 · macOS 저장 공간 화면과 계산 방식이 다를 수 있어요.").font(.system(size:11)).foregroundStyle(muted)
                    }; Spacer()
                }
            }
            Card {
                HStack { Text("공간을 많이 쓰는 곳").font(.system(size:18,weight:.bold)); Spacer(); Text(m.scanning ? "조사 결과가 차례로 표시돼요" : "클릭해서 자세히 보기").font(.system(size:12)).foregroundStyle(muted) }
                if m.incomplete > 0 { Label("일부 확인 또는 미확인 항목 \(m.incomplete)개 · 표시된 용량보다 실제 사용량이 클 수 있어요.",systemImage:"exclamationmark.circle").font(.system(size:12)).foregroundStyle(.orange) }
                if m.entries.isEmpty { empty("폴더의 실제 용량을 조사하고 있어요.") }
                else {
                    let top = Array(m.sorted.prefix(6))
                    GeometryReader { geo in
                        HStack(spacing:2) {
                            ForEach(Array(top.enumerated()),id:\.element.id) { i,e in
                                RoundedRectangle(cornerRadius:4).fill(colors[i % colors.count]).frame(width:max(0,(geo.size.width - CGFloat(max(0,top.count-1))*2) * CGFloat(e.bytes)/CGFloat(max(1,top.reduce(Int64(0)) { $0 + $1.bytes }))))
                            }
                        }
                    }.frame(height:16)
                    HStack(spacing:8) {
                        ForEach(Array(top.enumerated()),id:\.element.id) { i,e in
                            Button { m.explore(e.path) } label: {
                                VStack(alignment:.leading,spacing:12) { Image(systemName:icon(e)).font(.title2); Spacer(minLength:4); Text(display(e)).font(.system(size:13,weight:.semibold)).lineLimit(1); Text(e.bytes == 0 && !e.complete ? "미확인" : size(e.bytes) + (e.complete ? "" : "+")).font(.system(size:19,weight:.bold,design:.rounded)) }.frame(maxWidth:.infinity,alignment:.leading).padding(16).frame(height:140).foregroundStyle(.white).background(colors[i % colors.count],in:RoundedRectangle(cornerRadius:14))
                            }.buttonStyle(.plain)
                        }
                    }
                    Text("각 카드는 용량순으로 정렬되어 있어요. 막대는 상위 6개 항목 간 용량 비율입니다.").font(.system(size:11)).foregroundStyle(muted)
                    ForEach(Array(m.sorted.prefix(10).enumerated()),id:\.element.id) { i,e in row(e,index:i,maxBytes:m.sorted.first?.bytes ?? 1) { m.explore(e.path) } }
                }
            }
            Card {
                HStack {
                    Text("개인 폴더 살펴보기").font(.system(size:14,weight:.semibold))
                    Spacer()
                    Button("다운로드") { if m.fullScan { m.explore(home + "/Downloads") } else { m.permissionSetup = true } }
                    Button("데스크탑") { if m.fullScan { m.explore(home + "/Desktop") } else { m.permissionSetup = true } }
                    Button("문서") { if m.fullScan { m.explore(home + "/Documents") } else { m.permissionSetup = true } }
                }
                Text("보호된 폴더는 전체 조사 설정 후 확인할 수 있습니다.").font(.system(size:11)).foregroundStyle(muted)
                Label("숫자가 딱 맞지 않을 수 있어요",systemImage:"info.circle").font(.system(size:14,weight:.semibold))
                Text("위 목록은 현재 조사 범위에서 확인한 결과입니다. 기본 조사에는 보호된 폴더를 포함하지 않습니다. 시스템 파일·다른 사용자·APFS 스냅샷은 전체 사용량에 포함되지만 이 목록에는 포함되지 않을 수 있습니다. 공유 데이터 때문에 폴더 용량의 합계도 실제 디스크 사용량과 다를 수 있어요.").font(.system(size:12)).foregroundStyle(muted)
                if m.incomplete > 0 { Text("\(m.incomplete)개 조사 항목에서 권한 제한 또는 시간 초과로 조사를 완료하지 못했습니다. 표시된 용량은 확인 가능한 범위입니다.").font(.system(size:12)).foregroundStyle(.orange) }
            }
        }
    }
    var explorer: some View {
        Card {
            HStack {
                Button { m.explore((m.folder as NSString).deletingLastPathComponent) } label: { Image(systemName:"arrow.up") }.disabled(m.detailBusy || m.folder == "/" || !m.fullScan)
                Text(m.folder.replacingOccurrences(of:home,with:"~")).font(.system(size:13,design:.monospaced)).textSelection(.enabled)
                Spacer()
                Button("Finder에서 보기") { NSWorkspace.shared.open(URL(fileURLWithPath:m.folder)) }
            }
            if m.detailBusy { Label("폴더별 용량을 계산하고 있어요…",systemImage:"hourglass").foregroundStyle(muted) }
            if m.detailIncomplete > 0 { Text("일부 항목은 권한 제한 또는 시간 초과로 조사하지 못했습니다.").foregroundStyle(.orange).font(.caption) }
            let sorted = m.detail.sorted { $0.bytes > $1.bytes }
            ForEach(Array(sorted.enumerated()),id:\.element.id) { i,e in
                row(e,index:i,maxBytes:sorted.first?.bytes ?? 1) {
                    var dir: ObjCBool = false
                    if FileManager.default.fileExists(atPath:e.path,isDirectory:&dir), dir.boolValue, !e.path.hasSuffix(".app") { m.explore(e.path) }
                    else { NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath:e.path)]) }
                }.disabled(m.detailBusy)
            }
            if sorted.isEmpty && !m.detailBusy { empty("저장 공간 화면에서 조사된 폴더를 선택해 주세요. 접근할 수 없거나 빈 폴더는 항목이 표시되지 않습니다.") }
        }
    }
    var applications: some View {
        Card {
            HStack { Text("설치된 앱").font(.system(size:18,weight:.bold)); Text("\(m.apps.count)").foregroundStyle(muted); Spacer(); TextField("앱 이름 검색",text:$m.search).textFieldStyle(.roundedBorder).frame(width:230) }
            Text("일반 응용 프로그램 폴더의 앱 본체 용량입니다. 앱 데이터는 정리 화면에서 별도로 확인합니다. 하위 폴더에 설치된 앱은 폴더 탐색에서 찾을 수 있어요.").font(.system(size:12)).foregroundStyle(muted)
            if m.apps.isEmpty { empty(m.scanning ? "폴더 조사 후 앱 목록을 불러옵니다." : "표시할 앱이 없습니다.") }
            ForEach(m.filteredApps) { e in
                HStack(spacing:14) {
                    Image(nsImage:NSWorkspace.shared.icon(forFile:e.path)).resizable().frame(width:38,height:38)
                    VStack(alignment:.leading,spacing:5) { Text(e.name.replacingOccurrences(of:".app",with:"")).font(.system(size:14,weight:.semibold)); Text(e.path.replacingOccurrences(of:home,with:"~")).font(.system(size:10)).foregroundStyle(muted) }
                    Spacer(); Text(size(e.bytes)).font(.system(size:14,weight:.medium,design:.rounded)).frame(width:95,alignment:.trailing)
                    Button("정리 검토") { m.prepare(e) }.disabled(e.path == Bundle.main.bundlePath)
                }.padding(.vertical,9)
                Divider().opacity(0.5)
            }
        }
    }
    func removal(_ app:Entry) -> some View {
        VStack(alignment:.leading,spacing:18) {
            HStack { Image(nsImage:NSWorkspace.shared.icon(forFile:app.path)).resizable().frame(width:46,height:46); VStack(alignment:.leading,spacing:4) { Text(app.name).font(.title2.bold()); Text("휴지통으로 옮길 항목을 확인하세요").foregroundStyle(muted) }; Spacer() }
            Text("VPN·보안 프로그램·드라이버는 제조사 제거 기능을 우선 사용하세요. 여기서는 선택한 파일만 옮기며, 서비스·확장 프로그램까지 제거됐다고 보장하지 않습니다.").font(.system(size:12)).padding(14).background(Color.orange.opacity(0.10),in:RoundedRectangle(cornerRadius:10))
            if !m.fullScan { Text("기본 조사에서는 앱 본체만 표시합니다. 관련 데이터는 전체 조사 설정 후 확인할 수 있습니다.").font(.system(size:12)).foregroundStyle(muted) }
            if m.preparing { ProgressView("관련 파일 확인 중…") }
            ScrollView {
                VStack(alignment:.leading,spacing:16) {
                    ForEach(m.candidates) { c in
                        Toggle(isOn:Binding(get:{ m.selected.contains(c.path) },set:{ if $0 { m.selected.insert(c.path) } else { m.selected.remove(c.path) } })) {
                            VStack(alignment:.leading,spacing:4) { HStack { Text(c.label).fontWeight(.medium); Spacer(); Text(size(c.bytes)) }; Text(c.path.replacingOccurrences(of:home,with:"~")).font(.system(size:10)).foregroundStyle(muted).textSelection(.enabled) }
                        }.disabled(m.deleting || !m.result.isEmpty)
                    }
                }
            }.frame(maxHeight:240)
            Text("관련 파일은 앱 식별자가 정확히 일치하는 경로만 제안합니다. 설정·앱 데이터는 기본 선택하지 않으며, 공유 컨테이너와 문서는 자동 선택하지 않습니다.").font(.system(size:11)).foregroundStyle(muted)
            if !m.result.isEmpty { Text(m.result).font(.system(size:12)).textSelection(.enabled).padding(12).frame(maxWidth:.infinity,alignment:.leading).background(accent.opacity(0.07),in:RoundedRectangle(cornerRadius:10)) }
            HStack {
                Button("Finder에서 보기") { NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath:app.path)]) }
                Spacer(); Button("닫기") { m.selectedApp = nil }.disabled(m.deleting)
                Button("휴지통으로 이동") { m.confirm = true }.buttonStyle(.borderedProminent).tint(accent).disabled(m.preparing || m.deleting || !m.selected.contains(app.path))
            }
        }.padding(28).frame(width:650).fixedSize(horizontal:false,vertical:true)
        .alert("선택한 \(m.selected.count)개 항목을 휴지통으로 옮길까요?",isPresented:$m.confirm) { Button("취소",role:.cancel) {}; Button("휴지통으로 이동",role:.destructive) { m.trash() } } message: { Text("선택한 설정이나 앱 데이터도 함께 이동합니다. 휴지통은 비우지 않습니다.") }
    }
    func metric(_ label:String,_ value:String,_ color:Color) -> some View { VStack(alignment:.leading,spacing:7) { Text(label).font(.system(size:12)).foregroundStyle(muted); Text(value).font(.system(size:25,weight:.bold,design:.rounded)).foregroundStyle(color) } }
    func display(_ e:Entry) -> String { switch e.path { case home + "/.Trash": return "휴지통"; case home + "/Downloads": return "다운로드"; case home + "/Library": return "내 앱 데이터"; case "/Applications": return "응용 프로그램"; case "/Library": return "공용 앱 데이터"; case "/private/var": return "시스템 작업 데이터"; default: return e.name } }
    func icon(_ e:Entry) -> String { e.path == "/Applications" ? "square.grid.2x2" : e.name == "Library" ? "externaldrive" : "folder" }
    func empty(_ text:String) -> some View { Text(text).font(.system(size:14)).foregroundStyle(muted).frame(maxWidth:.infinity).padding(35) }
    func row(_ e:Entry,index:Int,maxBytes:Int64, action:@escaping () -> Void) -> some View {
        Button(action:action) {
            HStack(spacing:14) {
                Image(systemName:icon(e)).font(.system(size:18)).foregroundStyle(colors[index % colors.count]).frame(width:34,height:34).background(colors[index % colors.count].opacity(0.10),in:RoundedRectangle(cornerRadius:9))
                VStack(alignment:.leading,spacing:5) { Text(display(e)).font(.system(size:13,weight:.semibold)).lineLimit(1); Text(e.path.replacingOccurrences(of:home,with:"~")).font(.system(size:10)).foregroundStyle(muted).lineLimit(1).truncationMode(.middle) }.frame(maxWidth:.infinity,alignment:.leading)
                GeometryReader { geo in RoundedRectangle(cornerRadius:3).fill(colors[index % colors.count].opacity(0.18)).overlay(alignment:.leading) { RoundedRectangle(cornerRadius:3).fill(colors[index % colors.count]).frame(width:max(2,geo.size.width * min(1,Double(e.bytes)/Double(max(1,maxBytes))))) } }.frame(width:120,height:6)
                Text(e.bytes == 0 && !e.complete ? "미확인" : size(e.bytes) + (e.complete ? "" : "+")).font(.system(size:13,weight:.semibold,design:.rounded)).frame(width:90,alignment:.trailing)
                Image(systemName:"chevron.right").font(.system(size:11)).foregroundStyle(muted)
            }.padding(.vertical,7).contentShape(Rectangle())
        }.buttonStyle(.plain)
    }
}
@main struct SpaceApp: App {
    var body: some Scene { WindowGroup("여백 · Mac 저장 공간") { ContentView() }.defaultSize(width:1160,height:820).windowStyle(.hiddenTitleBar) }
}
