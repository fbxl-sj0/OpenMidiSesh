<!-- omaGUI: PICTUREBOX_IMAGES.md describes owned image display, not file parsing. -->
# PictureBox images

`picturebox_SetImage(widget, rasterImage)` copies a decoded `RasterImage` into
the widget. The caller retains ownership and may destroy its image immediately.
Pass null to clear it. A failed assignment preserves the previous image.
Use these APIs on the GUI thread, like the other widget methods.

The image starts at the client origin and is clipped inside the current border.
It keeps its original pixel size when the widget resizes. The image is drawn
above the client background, below retained drawing pixels and printed text.
`picturebox_ClearPixels` only clears drawings; `picturebox_SetImage(widget, 0)`
only clears the image. Widget destruction releases both allocations. The copy
uses checked 32-bit gfxlib buffers and works in headless mode without an active
screen. It does not retain pointers to the caller's image.

On a 32-bit display, transparent pixels preserve the current client background
exactly. PictureBox opts into `backend_DrawImage`'s `preserveTransparent`
argument. The default remains the previous gfxlib drawing path. This opt-in
handles gfxlib's `(alpha + 1) / 256` behavior at alpha zero; partial alpha keeps
the same interpolation. Indexed displays retain the existing gfxlib behavior.

The portable raster loader also recognizes ICO files by their signature. It
decodes the first entry's uncompressed, 40-byte DIB header at 1, 4, 8, or 24 bits
per pixel, including padded bottom-up rows and the AND transparency mask.
Directory spans, dimensions, palettes, and both masks are checked before use.
ICO output has `RASTERIMAGE_FORMAT_ICO` and alpha enabled. PNG-compressed icons,
32-bit icon variants, cursors, and destination-dependent XOR colors are rejected
with a diagnostic. WMF remains outside the raster loader's supported formats.

`tests/raster_ico_smoke.bas` covers supported depths, transparency, all truncated
prefixes of a fixture, malformed directory and palette references, explicit XOR
rejection, copied ownership, failed replacement, clipping, and drawing layers.
It also compares nonzero-alpha pixels with gfxlib's original interpolation.

<!-- end of PICTUREBOX_IMAGES.md -->
