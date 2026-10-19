"""Official Lucide SVG -> native SwiftUI Path, pinned source and no runtime dependencies.
Run: python -m pip install svgpathtools==1.8.0; python scripts/generate_icons.py
"""
import json
import math
import pathlib
import urllib.request
import xml.etree.ElementTree as ET
from svgpathtools import parse_path, Line, CubicBezier, QuadraticBezier, Arc

ROOT = pathlib.Path(__file__).resolve().parents[1]
REV = "1ef60af944de207e0d5176905a0759ba12e6ee8d"
NAMES = "house clipboard-paste link download list folder-open settings-2 sliders-horizontal ellipsis search video image share-2 copy save pause play x arrow-left check circle-alert trash arrow-up-right info audio-lines rotate-ccw heart grid-2x2 sun moon plus".split()

def point(p):
    return f"CGPoint(x: {p.real:.6f} * s, y: {p.imag:.6f} * s)"

def convert(svg):
    commands = []
    for el in ET.fromstring(svg):
        tag = el.tag.split('}')[-1]
        a = el.attrib
        if tag == 'path':
            path = parse_path(a['d'])
            last = None
            for segment in path:
                if last != segment.start:
                    commands.append(f"p.move(to: {point(segment.start)})")
                segments = list(segment.as_cubic_curves(curves=max(1, math.ceil(abs(segment.delta) / 45)))) if isinstance(segment, Arc) else [segment]
                for seg in segments:
                    if isinstance(seg, Line): commands.append(f"p.addLine(to: {point(seg.end)})")
                    elif isinstance(seg, CubicBezier): commands.append(f"p.addCurve(to: {point(seg.end)}, control1: {point(seg.control1)}, control2: {point(seg.control2)})")
                    elif isinstance(seg, QuadraticBezier): commands.append(f"p.addQuadCurve(to: {point(seg.end)}, control: {point(seg.control)})")
                    else: raise ValueError(type(seg))
                last = segment.end
        elif tag in ('circle', 'ellipse'):
            cx, cy = float(a['cx']), float(a['cy'])
            rx, ry = float(a.get('r', a.get('rx', 0))), float(a.get('r', a.get('ry', 0)))
            commands.append(f"p.addEllipse(in: CGRect(x: {cx-rx:.6f} * s, y: {cy-ry:.6f} * s, width: {2*rx:.6f} * s, height: {2*ry:.6f} * s))")
        elif tag == 'rect':
            x,y,w,h = [float(a.get(k,0)) for k in ('x','y','width','height')]
            r = float(a.get('rx',0))
            commands.append(f"p.addRoundedRect(in: CGRect(x: {x} * s, y: {y} * s, width: {w} * s, height: {h} * s), cornerSize: CGSize(width: {r} * s, height: {r} * s))")
        elif tag in ('line','polyline','polygon'):
            pts = [complex(float(a['x1']),float(a['y1'])),complex(float(a['x2']),float(a['y2']))] if tag == 'line' else [complex(*map(float,p.split(','))) for p in a['points'].strip().split()]
            commands.append(f"p.move(to: {point(pts[0])})")
            commands.extend(f"p.addLine(to: {point(p)})" for p in pts[1:])
            if tag == 'polygon': commands.append('p.closeSubpath()')
        else: raise ValueError(tag)
    return commands

def main():
    source_dir = ROOT / 'Vendor/Lucide'
    source_dir.mkdir(parents=True, exist_ok=True)
    output = ['// Generated from official Lucide SVGs. See Vendor/Lucide/LICENSE.', 'import SwiftUI', '', 'enum IconToken: String, CaseIterable {']
    for name in NAMES:
        output.append('    case ' + name.replace('-', '_') + ' = "' + name + '"')
    output.extend(['}', '', 'struct LucideShape: Shape {', '    let token: IconToken', '    func path(in rect: CGRect) -> Path {', '        let s = min(rect.width, rect.height) / 24', '        var p = Path()', '        switch token {'])
    for name in NAMES:
        file = source_dir / (name + '.svg')
        if not file.exists():
            file.write_bytes(urllib.request.urlopen(f'https://raw.githubusercontent.com/lucide-icons/lucide/{REV}/icons/{name}.svg').read())
        output.append('        case .' + name.replace('-', '_') + ':')
        output.extend('            ' + line for line in convert(file.read_text()))
    output.extend(['        }', '        return p', '    }', '}', ''])
    (ROOT / 'MONOApp/DesignSystem/Lucide.generated.swift').write_text('\n'.join(output), encoding='utf-8')
    license_file = source_dir / 'LICENSE'
    if not license_file.exists(): license_file.write_bytes(urllib.request.urlopen(f'https://raw.githubusercontent.com/lucide-icons/lucide/{REV}/LICENSE').read())
    resources = ROOT / 'MONOApp/Resources'
    resources.mkdir(parents=True, exist_ok=True)
    (resources / 'Lucide-LICENSE.txt').write_bytes(license_file.read_bytes())
    (source_dir / 'source.json').write_text(json.dumps({'repository':'https://github.com/lucide-icons/lucide', 'commit':REV, 'icons':NAMES}, indent=2)+'\n')
    print(f'Generated {len(NAMES)} native vector icons')

if __name__ == '__main__': main()

