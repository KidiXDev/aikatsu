#!/usr/bin/env python3
"""Overwrites MaterialSymbolsRounded.ttf with only the icons the QML names; the full font is 14 MB of RAM.

Release builds run it (release.yml); the repo keeps the full font. Needs `pip install fonttools brotli`.
"""
import io
import pathlib
import re
import urllib.request

from fontTools.ttLib import TTFont

here = pathlib.Path(__file__).resolve().parent
# Every string literal: the API skips the ones that aren't icons.
names = sorted({n for f in (here.parents[1] / "qml").rglob("*.qml") for n in re.findall(r'"([a-z0-9_]+)"', f.read_text(encoding="utf-8"))})
css_url = ("https://fonts.googleapis.com/css2?family=Material+Symbols+Rounded:opsz,wght,FILL,GRAD@20..48,100..700,0..1,-50..200"
           f"&icon_names={','.join(names)}&display=block")


def get(url):
    # A browser user agent gets the variable font; others get one static font per weight.
    req = urllib.request.Request(url, headers={"User-Agent": "Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/130.0 Safari/537.36"})
    with urllib.request.urlopen(req) as r:
        return r.read()


font_url = re.search(r"src: url\((.+?)\) format\('woff2'\)", get(css_url).decode()).group(1)
font = TTFont(io.BytesIO(get(font_url)))
font.flavor = None
font.save(here / "MaterialSymbolsRounded.ttf")
print(f"{len(names)} names, {(here / 'MaterialSymbolsRounded.ttf').stat().st_size // 1024} KB")
