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

task racoontest, "Run the racoon bridge test (racoon is not a dependency)":
  # `nimble test` compiles tests/tracoon.nim with the suite switched off, so
  # racoon need not be present for the normal run. Set RACOON_PATH to a
  # checkout's src/ if racoon is not installed as a package.
  let racoonPath = getEnv("RACOON_PATH")
  let extra = if racoonPath.len > 0: " --path:" & racoonPath else: ""
  exec "nim c -r --path:src -d:racoon --hints:off" & extra & " tests/tracoon.nim"
