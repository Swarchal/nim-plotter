## Render every gallery chart to `examples/out/` as HTML and JSON, plus PNG
## when `vl-convert` is installed.

import std/[os, strformat]
import ../src/plotter
import ./gallery

when isMainModule:
  let outDir = currentSourcePath().parentDir / "out"
  createDir(outDir)
  let haveVlConvert = findExe(vlConvertExe).len > 0
  for (name, c) in galleryCharts():
    enableTheme(galleryTheme(name))
    c.saveHtml(outDir / &"{name}.html")
    c.saveJson(outDir / &"{name}.json")
    if haveVlConvert:
      c.savePng(outDir / &"{name}.png", scale = 2.0)
    enableTheme("")
  echo &"wrote {galleryCharts().len} charts to {outDir}"
  if not haveVlConvert:
    echo "vl-convert not on PATH — HTML and JSON only, no PNG"
