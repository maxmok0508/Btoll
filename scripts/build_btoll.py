#!/usr/bin/env python3
"""Reproducible portable Btoll installer; never copies the builder's home data."""
import argparse, hashlib, json, os, plistlib, re, shutil, subprocess, tarfile, urllib.request
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]
WORK=ROOT/'.build.noindex'
OUT=ROOT/'dist'
VERSION='1.1.0'
def run(*args, **kwargs):
    print('+', ' '.join(map(str,args)),flush=True)
    subprocess.run(list(map(str,args)),check=True,**kwargs)
def sign(path):run('/usr/bin/codesign','--force','--sign','-',path)
def copy(src,dst):
    dst.parent.mkdir(parents=True,exist_ok=True)
    if src.is_dir():shutil.copytree(src,dst,dirs_exist_ok=True,symlinks=True)
    else:shutil.copy2(src,dst)
def main():
    parser=argparse.ArgumentParser();parser.add_argument('--app',type=Path,help='Reuse a verified Release app instead of invoking xcodebuild');args=parser.parse_args()
    WORK.mkdir(exist_ok=True);OUT.mkdir(exist_ok=True)
    bridge=WORK/'Bridge'
    if bridge.exists():shutil.rmtree(bridge)
    copy(ROOT/'portable/Bridge',bridge)
    node=json.loads((ROOT/'portable/vendor/node-source.json').read_text())
    archive=WORK/node['archive']
    if not archive.exists() or hashlib.sha256(archive.read_bytes()).hexdigest()!=node['sha256']:
        urllib.request.urlretrieve(node['url'],archive)
    if hashlib.sha256(archive.read_bytes()).hexdigest()!=node['sha256']:raise RuntimeError('Node SHA-256 mismatch')
    with tarfile.open(archive) as tf:
        prefix=node['archive'].removesuffix('.tar.gz')
        for member,name in [(prefix+'/bin/node','node'),(prefix+'/LICENSE','NODE-LICENSE.txt')]:
            (bridge/name).write_bytes(tf.extractfile(member).read())
    (bridge/'node').chmod(0o755)
    run('xcrun','swiftc','-O','-target','arm64-apple-macos14.6',ROOT/'portable/SMCReadOnly.swift',ROOT/'portable/main.swift','-o',bridge/'temperature-reader')
    run('xcrun','swiftc','-O','-target','arm64-apple-macos14.6',ROOT/'portable/metadata-src/main.swift','-lsqlite3','-o',bridge/'metadata-reader')
    for name in ['node','temperature-reader','metadata-reader']:sign(bridge/name)
    files=sorted(str(p.relative_to(bridge)) for p in bridge.rglob('*') if p.is_file() and p.name!='manifest.json')
    h=hashlib.sha256()
    for name in files:h.update(name.encode());h.update((bridge/name).read_bytes())
    (bridge/'manifest.json').write_text(json.dumps({'buildID':'portable-'+h.hexdigest()[:20],'files':files},indent=2)+'\n')
    # Real parser tests and the same native installer used by the host.
    run(bridge/'node','--test',ROOT/'portable/tests/dashboard.test.mjs',ROOT/'portable/tests/thermal.test.mjs',ROOT/'portable/tests/work-animation.test.mjs',ROOT/'portable/tests/codex-animation.test.mjs')
    run('xcrun','swiftc',ROOT/'DynamicIsland/components/Extensions/BsstollBridgeFiles.swift',ROOT/'portable/tests/native/main.swift','-o',WORK/'bridge-setup-test')
    test_home=WORK/'Clean User Home'
    if test_home.exists():shutil.rmtree(test_home)
    run(WORK/'bridge-setup-test',bridge,test_home)
    shutil.rmtree(test_home)
    run('xcrun','swiftc','-parse-as-library',ROOT/'DynamicIsland/managers/BtollSystemSampler.swift',ROOT/'portable/tests/system/main.swift','-o',WORK/'system-test')
    run(WORK/'system-test')
    run('cmake','-S',ROOT/'portable/vendor/mediaremote-adapter','-B',WORK/'mediaremote-build','-DCMAKE_BUILD_TYPE=Release','-DCMAKE_OSX_DEPLOYMENT_TARGET=14.6')
    run('cmake','--build',WORK/'mediaremote-build','--target','MediaRemoteAdapter','-j','4')
    if args.app:app=args.app.resolve()
    else:
        run('xcodebuild','-project',ROOT/'DynamicIsland.xcodeproj','-scheme','DynamicIsland','-configuration','Release','-derivedDataPath',WORK/'DerivedData','-disableAutomaticPackageResolution','ARCHS=arm64','MACOSX_DEPLOYMENT_TARGET=14.6','CODE_SIGN_IDENTITY=-','CODE_SIGNING_ALLOWED=YES','build')
        app=WORK/'DerivedData/Build/Products/Release/Btoll.app'
    if not app.is_dir():raise RuntimeError('Release app missing: '+str(app))
    payload=WORK/'payload'
    if payload.exists():shutil.rmtree(payload)
    fanroot=WORK/'fan-root'
    if fanroot.exists():shutil.rmtree(fanroot)
    helper=fanroot/'Library/PrivilegedHelperTools/local.bsstoll.fan-helper';helper.parent.mkdir(parents=True)
    run('xcrun','swiftc','-O','-target','arm64-apple-macos14.6',ROOT/'portable/fan-service/SMC.swift',ROOT/'portable/fan-service/main.swift','-o',helper)
    helper.chmod(0o755);sign(helper)
    copy(ROOT/'portable/fan-service/local.bsstoll.fan-helper.plist',fanroot/'Library/LaunchDaemons/local.bsstoll.fan-helper.plist')
    scripts=ROOT/'portable/fan-service/pkg-scripts'
    run('pkgbuild','--root',fanroot,'--scripts',scripts,'--identifier','local.bsstoll.fan-service','--version','1.1.0','--install-location','/',WORK/'bsstoll-fan-service.pkg')
    copy(fanroot,payload)
    target=payload/'Applications/Btoll.app';copy(app,target)
    framework=target/'Contents/Resources/MediaRemoteAdapter.framework'
    if framework.exists():shutil.rmtree(framework)
    copy(WORK/'mediaremote-build/MediaRemoteAdapter.framework',framework)
    copy(ROOT/'portable/vendor/mediaremote-adapter/bin/mediaremote-adapter.pl',target/'Contents/Resources/mediaremote-adapter.pl')
    for source,name in [(ROOT/'LICENSE','GPL-3.0'),(ROOT/'NOTICE','NOTICE'),(ROOT/'THIRD_PARTY_NOTICES.md','THIRD_PARTY_NOTICES.md'),(ROOT/'portable/vendor/mediaremote-adapter/LICENSE','MediaRemoteAdapter-BSD-3-Clause')]:
        copy(source,target/'Contents/Resources/Licenses'/name)
    info_path=target/'Contents/Info.plist'
    release_info=plistlib.loads(info_path.read_bytes())
    release_info['CFBundleShortVersionString']=VERSION
    release_info['CFBundleVersion']='1100'
    info_path.write_bytes(plistlib.dumps(release_info))
    # Validate every Mach-O, including prebuilt resources, before creating an installer.
    for binary in target.rglob('*'):
        if binary.is_symlink() or not binary.is_file():continue
        with binary.open('rb') as stream:magic=stream.read(4)
        if magic not in [b'\xcf\xfa\xed\xfe',b'\xca\xfe\xba\xbe',b'\xbe\xba\xfe\xca']:continue
        commands=subprocess.check_output(['otool','-l',str(binary)],text=True)
        for minimum in re.findall(r'minos\s+(\d+\.\d+(?:\.\d+)?)',commands):
            version=tuple(map(int,minimum.split('.')))
            if version+(0,)*(3-len(version))>(14,6,0):raise RuntimeError('Unsupported minimum OS: '+str(binary)+' '+minimum)
        dependencies=subprocess.check_output(['otool','-L',str(binary)],text=True)
        if '/opt/homebrew/' in dependencies or '/usr/local/' in dependencies:raise RuntimeError('External dependency: '+str(binary))
    # Strip builder metadata and signatures that are regenerated below.
    run('xattr','-cr',target)
    copy(bridge,target/'Contents/Resources/PortableBridge')
    copy(WORK/'bsstoll-fan-service.pkg',target/'Contents/Resources/FanControl/bsstoll-fan-service.pkg')
    run('codesign','--force','--deep','--preserve-metadata=entitlements,requirements,flags,runtime','--sign','-',target)
    run('codesign','--verify','--deep','--strict',target)
    info=plistlib.loads((target/'Contents/Info.plist').read_bytes())
    assert info['CFBundleName']=='Btoll' and info['LSMinimumSystemVersion']=='14.6',info.get('CFBundleName')
    # Fixed installation path: Installer must not relocate to a build/backup copy.
    components=WORK/'components.plist';run('pkgbuild','--analyze','--root',payload,components)
    data=plistlib.loads(components.read_bytes())
    for item in data:
        item['BundleIsRelocatable']=False;item['BundleIsVersionChecked']=False;item['BundleOverwriteAction']='upgrade'
    components.write_bytes(plistlib.dumps(data))
    component=WORK/'Btoll-component.pkg'
    run('pkgbuild','--root',payload,'--scripts',scripts,'--component-plist',components,'--identifier','local.bsstoll.portable','--version',VERSION,'--install-location','/',component)
    req=WORK/'requirements.plist';req.write_bytes(plistlib.dumps({'os':['14.6'],'arch':['arm64'],'home':False}))
    distribution=WORK/'Distribution.xml'
    run('productbuild','--synthesize','--product',req,'--package',component,distribution)
    text=distribution.read_text().replace('<installer-gui-script minSpecVersion="2">','<installer-gui-script minSpecVersion="2">\n    <title>Btoll</title>')
    distribution.write_text(text)
    package=OUT/f'Btoll-{VERSION}-arm64.pkg'
    run('productbuild','--distribution',distribution,'--package-path',WORK,package)
    expanded=WORK/'verified-package'
    if expanded.exists():shutil.rmtree(expanded)
    run('pkgutil','--expand-full',package,expanded)
    assert 'arm64' in (expanded/'Distribution').read_text() and '14.6' in (expanded/'Distribution').read_text()
    for binary in [target/'Contents/MacOS'/info['CFBundleExecutable'],helper,*[bridge/n for n in ['node','temperature-reader','metadata-reader']]]:
        run('file',binary);run('codesign','--verify','--strict',binary)
    for language in ['zh-CN','en']:
        shutil.copy2(ROOT/f'docs/INSTALL.{language}.md',OUT/f'INSTALL.{language}.md')
    print('Installer:',package,flush=True)
if __name__=='__main__':main()
