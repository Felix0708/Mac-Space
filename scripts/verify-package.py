from pathlib import Path
import hashlib, os, plistlib, shutil, subprocess, tempfile, xml.etree.ElementTree as E
project=Path(__file__).resolve().parents[1]
out=project/'dist'
expected=plistlib.loads((project/'resources/Info.plist').read_bytes())
prefix='Yeobaek-' + expected['CFBundleShortVersionString'] + '-arm64'
(project/'.build').mkdir(exist_ok=True)
with tempfile.TemporaryDirectory(prefix='verify-',dir=project/'.build') as directory:
 expanded=Path(directory)/'expanded'
 mounted=Path(directory)/'mounted'
 mounted.mkdir()
 subprocess.run(['/usr/sbin/pkgutil','--expand-full',str(out/(prefix+'.pkg')),str(expanded)],check=True)
 subprocess.run(['/usr/bin/hdiutil','verify',str(out/(prefix+'.dmg'))],check=True)
 subprocess.run(['/usr/bin/hdiutil','attach','-readonly','-nobrowse','-mountpoint',str(mounted),str(out/(prefix+'.dmg'))],check=True)
 try:
  apps=list(expanded.glob('**/Payload/Applications/*.app'))
  assert len(apps)==1
  app=apps[0]
  info=plistlib.loads((app/'Contents/Info.plist').read_bytes())
  assert info['CFBundleIdentifier']==expected['CFBundleIdentifier']
  assert info['CFBundleIconFile']=='Yeobaek'
  source=out/'여백.app'
  for rel in ('Contents/MacOS/Space','Contents/Resources/Yeobaek.icns'):
   assert hashlib.sha256((app/rel).read_bytes()).digest()==hashlib.sha256((source/rel).read_bytes()).digest()
  subprocess.run(['codesign','--verify','--deep','--strict',str(app)],check=True)
  d=E.parse(expanded/'Distribution').getroot()
  assert d.find('options').get('hostArchitectures')=='arm64'
  assert d.find('.//os-version').get('min')==expected['LSMinimumSystemVersion']
  assert d.find('domains').get('enable_currentUserHome')=='false'
  pkginfo=list(expanded.glob('**/PackageInfo'))
  assert len(pkginfo)==1
  p=E.parse(pkginfo[0]).getroot()
  assert p.get('install-location')=='/'
  assert p.get('relocatable')=='false'
  assert not p.findall('./relocate/bundle')
  assert not list(expanded.glob('**/Scripts'))
  assert (mounted/'Applications').is_symlink()
  assert os.readlink(mounted/'Applications')=='/Applications'
  mounted_apps=list(mounted.glob('*.app'))
  assert len(mounted_apps)==1
  subprocess.run(['codesign','--verify','--deep','--strict',str(mounted_apps[0])],check=True)
  pkg='Yeobaek-' + expected['CFBundleShortVersionString'] + '-arm64.pkg'
  assert hashlib.sha256((mounted/pkg).read_bytes()).digest()==hashlib.sha256((out/pkg).read_bytes()).digest()
  subprocess.run(['/bin/bash',str(mounted/'install-yeobaek.sh'),'--check'],check=True)
  if os.getuid()!=0:
   r=subprocess.run(['/bin/bash',str(mounted/'install-yeobaek.sh')],capture_output=True,text=True)
   assert r.returncode==1 and 'sudo' in r.stderr
  with tempfile.TemporaryDirectory(prefix='yeobaek-installer-check-') as temp:
   dest=Path(temp)
   shutil.copy2(out/'install-yeobaek.sh',dest/'install-yeobaek.sh')
   r=subprocess.run(['/bin/bash',str(dest/'install-yeobaek.sh'),'--check'],capture_output=True,text=True)
   assert r.returncode==1 and 'not found' in r.stderr
   (dest/pkg).write_bytes(b'not the approved package')
   r=subprocess.run(['/bin/bash',str(dest/'install-yeobaek.sh'),'--check'],capture_output=True,text=True)
   assert r.returncode==1 and 'checksum mismatch' in r.stderr
  print('PASS: package destination, app/icon integrity, OS/CPU restrictions, no relocation, no install scripts, mounted DMG contents, non-root refusal, missing/tampered package rejection. No installation performed.')
 finally:
  subprocess.run(["/usr/bin/hdiutil","detach",str(mounted)],check=True)
