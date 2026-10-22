#!/usr/bin/env python3
"""Render the bundled, unmodified SVG sources to crisp PNGs using macOS sips."""
import pathlib
import subprocess
import tempfile
import xml.etree.ElementTree as ET

ET.register_namespace('', 'http://www.w3.org/2000/svg')
ET.register_namespace('xlink', 'http://www.w3.org/1999/xlink')
artwork = pathlib.Path(__file__).resolve().parents[1] / 'Sources/CliProxyQuota/Resources/ProviderIcons'
with tempfile.TemporaryDirectory(prefix='cliproxy-provider-icons-') as tmp:
    for source in sorted(artwork.glob('*.svg')):
        tree = ET.parse(source)
        root = tree.getroot()
        if 'viewBox' not in root.attrib:
            width = float(root.attrib['width'].removesuffix('px'))
            height = float(root.attrib['height'].removesuffix('px'))
            root.set('viewBox', f'0 0 {width} {height}')
        box = [float(n) for n in root.attrib['viewBox'].replace(',', ' ').split()]
        scale = 256 / max(box[2], box[3])
        root.set('width', str(round(box[2] * scale)))
        root.set('height', str(round(box[3] * scale)))
        # SVG currentColor defaults to black. Resolve it for CoreSVG's renderer.
        for element in root.iter():
            for key, value in list(element.attrib.items()):
                if value == 'currentColor':
                    element.set(key, '#000000')
        rendering_source = pathlib.Path(tmp) / source.name
        tree.write(rendering_source, encoding='utf-8', xml_declaration=True)
        subprocess.run(['sips', '-s', 'format', 'png', str(rendering_source),
                        '--out', str(source.with_suffix('.png'))], check=True, stdout=subprocess.DEVNULL)
