#!/usr/bin/env python3
"""Collect Ubuntu runtime copyright notices and exact corresponding sources.
Run on the Ubuntu builder after enabling deb-src, before linuxdeploy packaging.
"""
from pathlib import Path
import json
import re
import shutil
import subprocess
import sys

root = Path(__file__).resolve().parents[2]
build = Path(sys.argv[1]).resolve()
ffmpeg = Path(sys.argv[2]).resolve()
out = Path(sys.argv[3]).resolve()
docs = out / "notices"
sources = out / "ubuntu-sources"
docs.mkdir(parents=True, exist_ok=True)
sources.mkdir(parents=True, exist_ok=True)
paths = {str(ffmpeg)}
for binary in (build / "opengt4", ffmpeg):
    result = subprocess.run(["ldd", str(binary)], text=True, capture_output=True, check=True)
    if "not found" in result.stdout:
        raise RuntimeError(result.stdout)
    paths.update(re.findall(r"=> (/\S+)", result.stdout))
    paths.update(re.findall(r"^\s*(/\S+)\s+\(", result.stdout, re.M))
packages = set()
for filename in sorted(paths):
    path = Path(filename)
    candidates = list(dict.fromkeys([str(path), str(path.resolve()),
                  str(path).removeprefix('/usr'),
                  str(path.resolve()).removeprefix('/usr')]))
    for candidate in candidates:
        result = subprocess.run(["dpkg-query", "-S", candidate], text=True, capture_output=True)
        if result.returncode == 0:
            packages.update(line.split(": ", 1)[0] for line in result.stdout.splitlines() if ": " in line)
            break
    else:
        raise RuntimeError(f"Cannot identify package owning {filename}")
records = []
for package in sorted(packages):
    fields = subprocess.check_output(["dpkg-query", "-W", "-f=${binary:Package}\t${Version}\t${source:Package}\t${source:Version}", package], text=True).split("\t")
    binary, version, source, source_version = fields
    record = dict(binary=binary, version=version, source=source, source_version=source_version)
    records.append(record)
    copyright_file = Path('/usr/share/doc') / binary.split(':')[0] / 'copyright'
    if not copyright_file.is_file():
        raise RuntimeError(f"Missing copyright notice: {copyright_file}")
    shutil.copyfile(copyright_file, docs / (binary.replace(':', '_') + '-copyright.txt'))
(out / 'runtime-packages.json').write_text(json.dumps(records, indent=2) + '\n')
shutil.copyfile(out / 'runtime-packages.json', docs / 'runtime-packages.json')
# The exact distro source package includes the Ubuntu patches and build rules.
for source, version in sorted({(r['source'], r['source_version']) for r in records}):
    subprocess.run(['apt-get', 'source', '--download-only', '--only-source', f'{source}={version}'], cwd=sources, check=True)
# Include source snapshots for statically linked fetched dependencies.
for name in ('sdl2', 'miniz'):
    destination = out / (name + '-source.tar.gz')
    with destination.open('wb') as stream:
        subprocess.run(['git', '-C', str(build / '_deps' / (name + '-src')), 'archive', '--format=tar.gz', '--prefix='+name+'/', 'HEAD'], stdout=stream, check=True)
(out / 'README-SOURCE.txt').write_text('''Corresponding source for OpenGT4 Steam Deck Edition v0.1.0-experimental

OpenGT4 itself is in opengt4-source.tar.gz (the exact tagged release commit).
SDL2 and miniz sources are in their named source archives. ps2float, stb and FSR1
sources are in the OpenGT4 tree. Ubuntu runtime source packages are downloaded
unchanged into ubuntu-sources, including their original tarballs, Debian/Ubuntu
patches and .dsc metadata. runtime-packages.json maps binaries to exact source
package versions. Extract a distro source package with dpkg-source -x FILE.dsc;
its debian/rules and debian/control describe building and build dependencies.
Build OpenGT4 using docs/STEAM_DECK.md and the release workflow from its tree.
Source licences are retained in these archives and binary copyright notices are
included under usr/share/doc/opengt4 in both binary packages. No game data or BIOS
is included. The ISO must remain supplied separately by the user.
''')
print(json.dumps({'packages': len(records), 'sources': len({(r['source'],r['source_version']) for r in records})}))
