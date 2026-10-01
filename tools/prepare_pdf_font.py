"""Generate a static Roboto Slab font compatible with dart_pdf's TTF writer.

Run with fonttools installed. Composite glyphs referencing an empty space
glyph can make the PDF parser recurse into the following glyph indefinitely.
Decompose outlines and represent empty outlines with an invisible point.
The original advance widths and complete Unicode character map are retained.
"""

from array import array
from pathlib import Path

from fontTools.ttLib import TTFont
from fontTools.ttLib.tables._g_l_y_f import Glyph, GlyphCoordinates
from fontTools.ttLib.tables.ttProgram import Program
from fontTools.varLib.instancer import instantiateVariableFont


root = Path(__file__).resolve().parent.parent
font = instantiateVariableFont(
    TTFont(root / "assets/fonts/RobotoSlab-VariableFont_wght.ttf"),
    {"wght": 400},
    inplace=True,
)
glyf = font["glyf"]
outlines = {}
for name in font.getGlyphOrder():
    coordinates, endpoints, flags = glyf[name].getCoordinates(glyf)
    glyph = Glyph()
    glyph.numberOfContours = len(endpoints)
    glyph.coordinates = coordinates
    glyph.endPtsOfContours = endpoints
    glyph.flags = flags
    glyph.program = Program()
    if not endpoints:
        glyph.numberOfContours = 1
        glyph.coordinates = GlyphCoordinates([(0, 0)])
        glyph.endPtsOfContours = [0]
        glyph.flags = array("B", [1])
    outlines[name] = glyph
for name, glyph in outlines.items():
    glyf[name] = glyph
font.save(root / "assets/fonts/RobotoSlab-Regular.ttf")
