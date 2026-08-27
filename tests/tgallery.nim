## Every gallery chart, checked two ways: the JSON it emits must parse back
## to the same spec, and — when `vl-convert` is installed — must compile to
## a Vega spec, which is real schema validation rather than our own opinion
## of what is valid.

import std/[json, os, osproc, strutils, unittest]
import plotter
import ../examples/gallery

let charts = galleryCharts()

suite "gallery":

  test "the gallery is not empty":
    check charts.len >= 8

  test "every chart round-trips through its own JSON":
    for (name, c) in charts:
      checkpoint(name)
      check parseJson(c.toJson) == c.toSpec
      check parseJson(c.toJson(indent = 0)) == c.toSpec

  test "every chart declares the schema and a mark or a composition":
    for (name, c) in charts:
      checkpoint(name)
      let spec = c.toSpec
      check spec["$schema"].getStr == vegaLiteSchema
      check spec.hasKey("mark") or spec.hasKey("layer") or
            spec.hasKey("hconcat") or spec.hasKey("vconcat") or
            spec.hasKey("facet") or spec.hasKey("repeat")

  test "every chart renders to a page":
    for (name, c) in charts:
      checkpoint(name)
      check c.toHtml.contains("vegaEmbed")

  test "vl-convert accepts every spec":
    let exe = findExe(vlConvertExe)
    if exe.len == 0:
      skip()
    else:
      let dir = getTempDir() / "plotter-gallery"
      createDir(dir)
      defer: removeDir(dir)
      for (name, c) in charts:
        checkpoint(name)
        let specPath = dir / (name & ".vl.json")
        writeFile(specPath, c.toJson(indent = 0))
        let (output, code) = execCmdEx(quoteShellCommand(
          [exe, "vl2vg", "--input", specPath,
           "--output", dir / (name & ".vg.json")]))
        checkpoint(output)
        check code == 0
