"""Generate original Brohn vector assets and a reusable soft-dark token system."""
import hashlib
import json
from pathlib import Path
from fontTools.ttLib import TTFont
from fontTools.varLib.instancer import instantiateVariableFont
from fontTools.pens.svgPathPen import SVGPathPen
from fontTools.pens.transformPen import TransformPen

repo = Path(__file__).resolve().parents[2]
brand = repo / "www/brand"
brand.mkdir(parents=True, exist_ok=True)
icons_dir = brand / "icons"
icons_dir.mkdir(exist_ok=True)
colours = {
    "canvas": "#11171C", "surface": "#192229", "raised": "#222E36", "hover": "#2C3A43",
    "text": "#EDF2F2", "secondary": "#B7C5CB", "muted": "#99ACB5",
    "line": "#34454F", "control-border": "#718994", "accent": "#97D8C4",
    "accent-ink": "#10251F", "lavender": "#BEB7EA", "blue": "#91BFE6",
    "amber": "#E3C38D", "rose": "#E8A2A8", "focus": "#C5D5FF",
}
tokens = dict(schema="brohn-design-tokens/0.1.0", theme="Soft graphite", colours=colours,
              font=dict(family="Manrope", source="fonts/Manrope-Variable.ttf", licence="fonts/OFL.txt",
                        weights=dict(body=450, label=550, heading=650), base_px=16, line_height=1.55),
              spacing_px=[4, 8, 12, 16, 24, 32, 48, 64],
              radius_px=dict(control=10, card=18, panel=24), target_px=44,
              motion_ms=dict(feedback=120, transition=180), reduced_motion="no movement; instantaneous state changes",
              charts=dict(gaze="accent", eeg="lavender", eda="amber", cardiac="rose", respiration="blue",
                          required_redundancy="Direct labels plus dash/shape; hue alone never encodes condition or quality"))
(brand / "tokens.json").write_text(json.dumps(tokens, indent=2) + "\n", encoding="utf-8")
css = '@font-face{font-family:Manrope;src:url("fonts/Manrope-Variable.ttf") format("truetype");font-weight:200 800;font-display:swap}\n:root{\n'
css += "\n".join(f"  --brohn-{name}: {value};" for name, value in colours.items())
css += '\n  --brohn-font: "Manrope", "Segoe UI", system-ui, sans-serif;\n  --brohn-radius-control:10px;\n  --brohn-radius-card:18px;\n  --brohn-target:44px;\n  --brohn-motion:180ms;\n}\n'
css += '@media(prefers-reduced-motion:reduce){:root{--brohn-motion:0ms}}\n'
(brand / "tokens.css").write_text(css, encoding="utf-8")

# Two counters and an open diagonal join make the original folded B monogram.
outer = "M12 8H31C43 8 50 14 50 23C50 28 47 32 42 34C49 36 53 41 53 47C53 57 45 63 32 63H12Z"
holes = "M22 18V29H31C37 29 40 27 40 23C40 20 37 18 31 18ZM22 39V53H32C39 53 43 51 43 46C43 42 39 39 32 39Z"
def mark(fill):
    return f'<defs><mask id="brohn-fold"><rect width="64" height="72" fill="white"/><path d="M10 34L54 27V31L10 38Z" fill="black"/></mask></defs><path fill="{fill}" fill-rule="evenodd" mask="url(#brohn-fold)" d="{outer}{holes}"/>'
def svg(viewbox, content, title=None):
    label = f'<title>{title}</title>' if title else ''
    return f'<svg xmlns="http://www.w3.org/2000/svg" viewBox="{viewbox}">{label}{content}</svg>\n'
for name, colour in [("brohn-mark", colours["text"]), ("brohn-mark-mint", colours["accent"]), ("brohn-mark-ink", colours["canvas"])]:
    (brand / (name + ".svg")).write_text(svg("0 0 64 72", mark(colour), "Brohn"), encoding="utf-8")

font = instantiateVariableFont(TTFont(brand / "fonts/Manrope-Variable.ttf"), {"wght": 650}, inplace=False)
glyphs, cmap = font.getGlyphSet(), font.getBestCmap()
scale = 46 / font["head"].unitsPerEm
pen = SVGPathPen(glyphs)
x = 0.0
for char in "Brohn":
    name = cmap[ord(char)]
    glyphs[name].draw(TransformPen(pen, (scale, 0, 0, -scale, x, 48)))
    x += glyphs[name].width * scale - 1.4
word = pen.getCommands()
for name, colour in [("brohn-wordmark", colours["text"]), ("brohn-wordmark-ink", colours["canvas"])]:
    (brand / (name + ".svg")).write_text(svg(f"0 0 {x+3:.2f} 60", f'<path fill="{colour}" d="{word}"/>', "Brohn"), encoding="utf-8")
for name, colour in [("brohn-lockup", colours["text"]), ("brohn-lockup-ink", colours["canvas"])]:
    content = f'<g transform="translate(0 2) scale(.78)">{mark(colour)}</g><path transform="translate(62 0)" fill="{colour}" d="{word}"/>'
    (brand / (name + ".svg")).write_text(svg(f"0 0 {x+65:.2f} 62", content, "Brohn"), encoding="utf-8")
app = f'<rect width="128" height="128" rx="30" fill="{colours["surface"]}"/><g transform="translate(20 15) scale(1.35)">{mark(colours["accent"])}</g>'
(brand / "brohn-app-icon.svg").write_text(svg("0 0 128 128", app, "Brohn"), encoding="utf-8")

icons = {
"plan": '<rect x="4" y="4" width="16" height="16" rx="3"/><path d="M8 8h8M8 12h5M8 16h3"/>',
"questions": '<path d="M5 4h14a2 2 0 0 1 2 2v10a2 2 0 0 1-2 2h-8l-5 3v-3H5a2 2 0 0 1-2-2V6a2 2 0 0 1 2-2Z"/><path d="M9 8a3 3 0 0 1 6 0c0 2-3 2-3 4M12 15h.01"/>',
"collect": '<circle cx="12" cy="12" r="3"/><path d="M7 4a10 10 0 0 0 0 16M17 4a10 10 0 0 1 0 16M9 7a6 6 0 0 0 0 10M15 7a6 6 0 0 1 0 10"/>',
"review": '<circle cx="10" cy="10" r="6"/><path d="m15 15 6 6M7 10l2 2 4-4"/>',
"results": '<path d="M4 3v17h17M8 15v-5M13 15V6M18 15v-7"/>',
"eye": '<path d="M2 12s4-7 10-7 10 7 10 7-4 7-10 7S2 12 2 12Z"/><circle cx="12" cy="12" r="3"/>',
"eeg": '<path d="M8 20v-3a7 7 0 1 1 10-6l3 4h-4v5M6 11h3l2-5 3 9 2-4h2"/>',
"eda": '<path d="M3 18h18M4 14h4l2-8 3 10 2-6 2 4h3"/>',
"heart": '<path d="M12 20 4 12C-1 6 6 1 12 7c6-6 13-1 8 5l-8 8Z"/><path d="M5 11h4l2-3 2 6 2-3h4"/>',
"breath": '<path d="M3 9h11c6 0 6-7 1-6M3 13h16c4 0 4 6 0 6M3 17h7c4 0 4 5 0 5"/>',
"emg": '<path d="M3 17h4l3-10 3 10 3-10 2 6h3M4 4h16M4 21h16"/>',
"camera": '<rect x="3" y="6" width="18" height="14" rx="3"/><path d="m7 6 2-3h6l2 3"/><circle cx="12" cy="13" r="4"/>',
"face": '<path d="M5 4h14v9a7 7 0 0 1-14 0V4Z"/><path d="M8 9h.01M16 9h.01M12 10v3h-1M9 16q3 2 6 0"/>',
"motion": '<circle cx="14" cy="4" r="2"/><path d="m7 10 5-3 4 5h5M12 7l-2 7-5 6M10 14l6 2 2 5M3 7h4M2 12h3"/>',
"audio": '<rect x="9" y="3" width="6" height="12" rx="3"/><path d="M5 11a7 7 0 0 0 14 0M12 18v3M8 21h8"/>',
"implicit": '<path d="m13 3-8 11h7l-1 7 8-11h-7l1-7Z"/>',
"aoi": '<path d="M8 3H3v5M16 3h5v5M21 16v5h-5M3 16v5h5"/><rect x="7" y="7" width="10" height="10" rx="2"/>',
"control": '<path d="M12 3v18M4 6h16M6 6l-4 8h8L6 6ZM18 6l-4 8h8l-4-8ZM8 21h8"/>',
"clock": '<circle cx="12" cy="12" r="9"/><path d="M12 7v5l4 2"/>',
"link": '<path d="m10 14 4-4M8 16l-1 1a4 4 0 0 1-6-6l5-5a4 4 0 0 1 6 0M16 8l1-1a4 4 0 0 1 6 6l-5 5a4 4 0 0 1-6 0"/>',
"check": '<path d="m5 12 4 4L19 6"/>',
"warning": '<path d="m12 3 10 18H2L12 3Z"/><path d="M12 9v5M12 17h.01"/>',
"info": '<circle cx="12" cy="12" r="9"/><path d="M12 11v6M12 7h.01"/>',
"upload": '<path d="M12 16V3M7 8l5-5 5 5M4 16v5h16v-5"/>',
"download": '<path d="M12 3v13M7 11l5 5 5-5M4 16v5h16v-5"/>',
"play": '<path d="m8 4 12 8-12 8V4Z"/>',
"pause": '<path d="M8 4v16M16 4v16"/>',
"undo": '<path d="m7 4-5 5 5 5M2 9h12a6 6 0 0 1 0 12h-3"/>',
"settings": '<path d="M4 6h16M4 12h16M4 18h16"/><circle cx="8" cy="6" r="2"/><circle cx="16" cy="12" r="2"/><circle cx="10" cy="18" r="2"/>',
"study": '<rect x="4" y="3" width="16" height="18" rx="3"/><path d="M8 7h8M8 11h3M8 16l2-2 3 3 3-5"/>',
"compare": '<rect x="2" y="5" width="8" height="14" rx="2"/><rect x="14" y="5" width="8" height="14" rx="2"/><path d="M6 9v6M18 9v6"/>',
"spark": '<path d="m12 2 2.5 7.5L22 12l-7.5 2.5L12 22l-2.5-7.5L2 12l7.5-2.5L12 2Z"/>',
}
group_attrs = 'fill="none" stroke="currentColor" stroke-width="1.7" stroke-linecap="round" stroke-linejoin="round"'
for name, paths in icons.items():
    (icons_dir / (name + ".svg")).write_text(svg("0 0 24 24", f'<g {group_attrs}>{paths}</g>'), encoding="utf-8")
symbols = ''.join(f'<symbol id="brohn-{name}" viewBox="0 0 24 24"><g {group_attrs}>{paths}</g></symbol>' for name, paths in icons.items())
(brand / "icons.svg").write_text(f'<svg xmlns="http://www.w3.org/2000/svg">{symbols}</svg>\n', encoding="utf-8")
field = '<defs><radialGradient id="field"><stop stop-color="#97D8C4" stop-opacity=".14"/><stop offset="1" stop-color="#97D8C4" stop-opacity="0"/></radialGradient></defs><rect width="1600" height="900" fill="#11171C"/><ellipse cx="1130" cy="430" rx="590" ry="540" fill="url(#field)"/>'
for i in range(11):
    y = 120 + i * 55
    field += f'<path d="M580 {y}C920 {y-80} 780 {690-i*25} 1390 {y+10}" fill="none" stroke="#97D8C4" stroke-opacity="{0.06+i*.009:.3f}" stroke-width="1"/>'
(brand / "brohn-field.svg").write_text(svg("0 0 1600 900", field), encoding="utf-8")
empty = '<g fill="none" stroke="#718994" stroke-width="2"><rect x="55" y="28" width="150" height="140" rx="18"/><path d="M82 64h92M82 88h63M82 135h35"/><rect x="137" y="112" width="58" height="58" rx="16" fill="#192229" stroke="#97D8C4"/><path d="M153 141h26M166 128v26" stroke="#97D8C4"/></g>'
(brand / "empty-study.svg").write_text(svg("0 0 260 200", empty), encoding="utf-8")
manifest = dict(schema="brohn-brand-assets/0.1.0", original_artwork=True, icon_count=len(icons),
                assets=[str(p.relative_to(repo)).replace('\\','/') for p in sorted(brand.rglob('*.svg'))],
                font=dict(name="Manrope variable", source_commit="fb629caaa15ad25c051089c98f09cf6c8e30a86b",
                          source_url="https://github.com/google/fonts/tree/fb629caaa15ad25c051089c98f09cf6c8e30a86b/ofl/manrope",
                          sha256=hashlib.sha256((brand / "fonts/Manrope-Variable.ttf").read_bytes()).hexdigest(), licence="OFL-1.1"),
                usage="Original Brohn assets prepared for this project; project distribution licence remains to be selected. Font retains its own OFL.")
(brand / "asset-manifest.json").write_text(json.dumps(manifest, indent=2) + "\n", encoding="utf-8")
print(json.dumps(dict(icons=len(icons), svg_assets=len(manifest["assets"]))))
