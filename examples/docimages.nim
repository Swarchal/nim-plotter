## Render the gallery to `docs/images/` for the README.
##
## Separate from `examples/build.nim` because these images are committed:
## they are sized for a README column rather than for viewing on their own,
## and they force a white background so the axis labels stay readable
## against GitHub's dark theme as well as its light one.

import std/[os, strformat]
import ../src/plotter
import ./gallery

const
  docWidth = 520
  docHeight = 320
  docScale = 2.0

when isMainModule:
  let repoRoot = currentSourcePath().parentDir.parentDir
  let outDir = repoRoot / "docs" / "images"
  createDir(outDir)

  if findExe(vlConvertExe).len == 0:
    quit(&"`{vlConvertExe}` is not on PATH — these images cannot be built " &
         "without it. See the README for how to install it.", 1)

  for (name, c) in galleryCharts():
    let theme = galleryTheme(name)
    enableTheme(theme)
    # A themed chart brings its own background, and forcing white would
    # paint over the one thing that image is there to show.
    var doc = if theme.len > 0: c else: c.configureBackground("#ffffff")
    # Faceted and concatenated specs size their sub-plots, so only resize
    # the ones that carry a top-level size of their own.
    if doc.hasSize:
      doc = doc.properties(width = docWidth, height = docHeight)
    doc.savePng(outDir / &"{name}.png", scale = docScale)
    enableTheme("")
    echo &"  {name}.png"
  echo &"wrote {galleryCharts().len} images to {outDir}"
