# Package

version       = "0.2.0"
author        = "Scott Warchal"
description   = "Build 2D static charts in Nim and emit them as Vega-Lite specs"
license       = "MIT"
srcDir        = "src"
skipDirs      = @["out"]

# Dependencies

requires "nim >= 2.0.0"

task examples, "Render every gallery chart to examples/out":
  exec "nim c -r --path:src --hints:off examples/build.nim"

task docimages, "Render the gallery to docs/images for the README":
  exec "nim c -r --path:src --hints:off examples/docimages.nim"
