#!/usr/bin/env python3
"""Build an Xcursor theme from apple_cursor's SVGs and clickgen config.

Does what `ctgen <config> -p x11` does with bitmaps rendered by cbmp, without
clickgen, whose numpy cannot run on every x86_64 CPU: each SVG is recoloured,
rendered by rsvg-convert at every size of the config, and packed by
xcursorgen. Hotspots, sizes, delays and alias symlinks come from the config,
with clickgen's rules: a cursor's own value, else [cursors.fallback_settings];
hotspots are given in the SVG's pixels and scaled to each size, truncated.

Usage: xcursor-theme.py RSVG-CONVERT XCURSORGEN CONFIG SVG-DIR OUT NAME COMMENT
COLOURS, where OUT is the theme's directory and COLOURS is a list of FROM=TO
colour replacements (render.json's), e.g. "#00FF00=#000000".
"""

import fnmatch
import os
import re
import subprocess
import sys
import tomllib
import xml.etree.ElementTree as ET


def main(rsvg, xcursorgen, config, svg_dir, out, name, comment, *colours):
    with open(config, "rb") as f:
        cursors = tomllib.load(f)["cursors"]
    fallback = cursors.pop("fallback_settings")
    work = os.path.abspath("xcursor-work")
    os.makedirs(work)

    # Frames of animated cursors are in subdirectories; the config names
    # every bitmap by its file name alone.
    svgs = {}
    for root, _, files in os.walk(svg_dir):
        for f in files:
            if f.endswith(".svg"):
                svgs[f[: -len(".svg")] + ".png"] = os.path.join(root, f)

    def recoloured(png):
        with open(svgs[png], encoding="utf-8") as f:
            text = f.read()
        for pair in colours:
            old, new = pair.split("=")
            text = re.sub(re.escape(old), new, text, flags=re.IGNORECASE)
        path = os.path.join(work, png[: -len(".png")] + ".svg")
        with open(path, "w", encoding="utf-8") as f:
            f.write(text)
        root = ET.parse(path).getroot()
        return path, int(root.get("width")), int(root.get("height"))

    cursor_dir = os.path.join(out, "cursors")
    os.makedirs(cursor_dir)
    for section in cursors.values():
        def get(key, default=None):
            return section.get(key, fallback.get(key, default))

        x11_name = section.get("x11_name")
        if x11_name is None:
            continue
        sizes = get("x11_sizes")
        sizes = [sizes] if isinstance(sizes, int) else sizes
        hot_x, hot_y = get("x_hotspot"), get("y_hotspot")
        delay = get("x11_delay", 0)
        frames = sorted(fnmatch.filter(svgs, section["png"]))
        if not frames:
            sys.exit(f"no SVG for {section['png']}")

        lines = []
        for png in frames:
            svg, width, height = recoloured(png)
            for size in sizes:
                bitmap = os.path.join(work, f"{png[:-4]}-{size}.png")
                subprocess.run([rsvg, "-w", str(size), "-h", str(size),
                                "-o", bitmap, svg], check=True)
                lines.append(f"{size} {int(hot_x * size / width)} "
                             f"{int(hot_y * size / height)} {bitmap} {delay}\n")
        spec = os.path.join(work, x11_name + ".in")
        with open(spec, "w") as f:
            f.writelines(lines)
        subprocess.run([xcursorgen, spec, os.path.join(cursor_dir, x11_name)],
                       check=True)
        for link in section.get("x11_symlinks", []):
            os.symlink(x11_name, os.path.join(cursor_dir, link))

    # clickgen's theme files.
    with open(os.path.join(out, "cursor.theme"), "w") as f:
        f.write(f'[Icon Theme]\nName={name}\nInherits="{name}"')
    with open(os.path.join(out, "index.theme"), "w") as f:
        f.write(f'[Icon Theme]\nName={name}\nComment={comment}\n'
                'Inherits="hicolor"')


if __name__ == "__main__":
    main(*sys.argv[1:])
