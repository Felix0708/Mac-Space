#!/usr/bin/env python3
"""Package the existing app without rebuilding or modifying it."""
import atexit
import hashlib
import plistlib
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import unicodedata
import xml.etree.ElementTree as ET

project = Path(sys.argv[1]) if len(sys.argv) > 1 else Path(__file__).resolve().parents[1]
out = project / 'dist'
app = out / '여백.app'
info = plistlib.loads((app / 'Contents/Info.plist').read_bytes())
version = info['CFBundleShortVersionString']
minimum = info['LSMinimumSystemVersion']
prefix = 'Yeobaek-' + version + '-arm64'
build_dir = project / '.build'
build_dir.mkdir(exist_ok=True)
stage_context = tempfile.TemporaryDirectory(prefix='package-', dir=build_dir)
atexit.register(stage_context.cleanup)
stage = Path(stage_context.name)
def run(*args):
    subprocess.run([str(a) for a in args], check=True)

run('/usr/bin/codesign', '--verify', '--deep', '--strict', app)
payload = stage / 'payload'
# macOS BOM tooling requires consistent decomposed Unicode bundle paths.
app_copy = payload / 'Applications' / unicodedata.normalize('NFD', app.name)
app_copy.parent.mkdir(parents=True)
run('/usr/bin/ditto', app, app_copy)
component_plist = stage / 'components.plist'
run('/usr/bin/pkgbuild', '--analyze', '--root', payload, component_plist)
components = plistlib.loads(component_plist.read_bytes())
for component in components:
    component['BundleIsRelocatable'] = False
    component['BundleIsVersionChecked'] = True
    component['BundleHasStrictIdentifier'] = True
    component['BundleOverwriteAction'] = 'upgrade'
component_plist.write_bytes(plistlib.dumps(components))
component_pkg = stage / 'Yeobaek-component.pkg'
run('/usr/bin/pkgbuild', '--root', payload, '--component-plist', component_plist,
    '--identifier', 'io.github.Felix0708.Yeobaek.installer', '--version', version,
    '--install-location', '/', '--ownership', 'recommended', component_pkg)
requirements = stage / 'requirements.plist'
requirements.write_bytes(plistlib.dumps({'os': [minimum], 'arch': ['arm64']}))
distribution = stage / 'Distribution.xml'
run('/usr/bin/productbuild', '--synthesize', '--product', requirements,
    '--package', component_pkg, distribution)
tree = ET.parse(distribution)
root = tree.getroot()
ET.SubElement(root, 'title').text = '여백 ' + version
ET.SubElement(root, 'domains', {'enable_anywhere': 'false', 'enable_currentUserHome': 'false', 'enable_localSystem': 'true'})
tree.write(distribution, encoding='utf-8', xml_declaration=True)
pkg = out / (prefix + '.pkg')
run('/usr/bin/productbuild', '--distribution', distribution, '--package-path', stage, pkg)
pkg_hash = hashlib.sha256(pkg.read_bytes()).hexdigest()

installer = out / 'install-yeobaek.sh'
installer.write_text('''#!/bin/bash
set -euo pipefail
case "${1:-}" in
  --help|-h)
    echo 'Usage: sudo /bin/bash install-yeobaek.sh'
    echo 'Check only: /bin/bash install-yeobaek.sh --check'
    exit 0 ;;
  ''|--check) ;;
  *) echo 'Unknown argument. Use --help.' >&2; exit 2 ;;
esac
script_dir="$(cd -- "$(dirname -- "$0")" && pwd)"
pkg="$script_dir/''' + pkg.name + '''"
if [[ ! -f "$pkg" ]]; then
  echo "Package not found: $pkg" >&2; exit 1
fi
actual="$(/usr/bin/shasum -a 256 "$pkg")"
actual="${actual%% *}"
if [[ "$actual" != "''' + pkg_hash + '''" ]]; then
  echo 'Package checksum mismatch. Installation stopped.' >&2; exit 1
fi
if [[ "$(/usr/bin/uname -m)" != arm64 ]]; then
  echo 'This build requires Apple Silicon. Use a native terminal, not Rosetta.' >&2; exit 1
fi
os_version="$(/usr/bin/sw_vers -productVersion)"
if (( ${os_version%%.*} < 27 )); then
  echo 'This build requires macOS 27 or later.' >&2; exit 1
fi
if [[ "${1:-}" == --check ]]; then
  echo 'PASS: package checksum and system requirements. No installation performed.'
  exit 0
fi
if [[ "$(/usr/bin/id -u)" != 0 ]]; then
  echo 'Run this installer with sudo /bin/bash install-yeobaek.sh' >&2; exit 1
fi
# Only install files. Never launch the GUI app as root or change privacy settings.
exec /usr/sbin/installer -pkg "$pkg" -target /
''')
installer.chmod(0o755)
readme = out / '설치안내.txt'
readme.write_text(f'''여백 {version} 설치 안내

지원 환경: Apple Silicon (M1 이상), macOS {minimum} 이상.

1. 드래그 설치
DMG를 열고 여백.app을 Applications 바로가기로 드래그하세요.
설치 후 /Applications/여백.app을 실행하세요. DMG 안에서 직접 실행하지 마세요.

2. PKG 설치
{pkg.name}을 더블클릭하면 macOS 설치 프로그램으로 설치합니다.

3. 터미널 / sudo 설치
DMG를 연 뒤:
sudo /usr/sbin/installer -pkg "/Volumes/Yeobaek/{pkg.name}" -target /

또는 DMG 안의 스크립트로:
sudo /bin/bash "/Volumes/Yeobaek/install-yeobaek.sh"

설치 없이 패키지를 검사하려면:
/bin/bash "/Volumes/Yeobaek/install-yeobaek.sh" --check

이미 같은 이름의 볼륨이 열려 있으면 마운트 경로에 숫자가 붙을 수 있습니다.
PKG를 따로 받은 경우에는 명령의 경로를 다운로드한 파일 경로로 바꿔주세요.
스크립트를 별도로 받았다면 PKG와 같은 폴더에 두어야 합니다.

설치 위치: /Applications/여백.app
업데이트 전 여백 앱을 종료하세요. 이전 앱을 교체하며 사용자 문서/설정은 삭제하지 않습니다.
sudo는 설치에만 사용합니다. 앱을 sudo로 실행하지 마세요.
sudo 설치는 전체 디스크 접근 권한을 부여하지 않습니다.
보호 폴더 조사에는 설치된 여백 앱의 전체 조사 설정 안내를 따라주세요.

이 패키지는 로컬 시험판입니다. Developer ID 서명과 Apple 공증을 하지 않았습니다.
다른 Mac에서 다운로드해 열면 보안 경고 또는 실행 차단이 발생할 수 있습니다.
지원 OS/CPU 조건은 패키지에 포함했지만 다른 Mac에서 실제 설치는 아직 검증하지 않았습니다.
Gatekeeper 비활성화나 격리 속성 제거는 설치 스크립트에 포함하지 않습니다.
''')
dmg_root = stage / 'dmg'
dmg_root.mkdir()
run('/usr/bin/ditto', app, dmg_root / app.name)
(dmg_root / 'Applications').symlink_to('/Applications')
for file in (pkg, installer, readme):
    shutil.copy2(file, dmg_root / file.name)
dmg = out / (prefix + '.dmg')
run('/usr/bin/hdiutil', 'create', '-volname', 'Yeobaek', '-srcfolder', dmg_root,
    '-format', 'UDZO', '-ov', dmg)
checksums = out / (prefix + '-SHA256.txt')
checksums.write_text(''.join(hashlib.sha256(f.read_bytes()).hexdigest() + '  ' + f.name + '\n' for f in (dmg, pkg, installer)))
print('DMG=' + str(dmg))
