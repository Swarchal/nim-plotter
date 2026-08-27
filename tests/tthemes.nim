import std/[json, unittest]
import plotter

let base = chart(dataFrame(col("a", @[1.0]))).markBar().encode(x = "a:Q")

suite "per-chart config":

  test "no config means no key":
    check "config" notin base.toSpec

  test "axis config":
    let cfg = base.configureAxis(labelFontSize = 12, grid = false)
      .toSpec["config"]
    check cfg["axis"]["labelFontSize"].getFloat == 12.0
    check cfg["axis"]["grid"].getBool == false

  test "configureView(noStroke) emits null, which is what removes the border":
    let cfg = base.configureView(noStroke = true).toSpec["config"]
    check cfg["view"]["stroke"].kind == JNull

  test "background, font and colour scheme":
    let cfg = base.configureBackground("#fff").configureScheme("tableau10")
      .toSpec["config"]
    check cfg["background"].getStr == "#fff"
    check cfg["range"]["category"]["scheme"].getStr == "tableau10"

  test "config sections accumulate across calls":
    let cfg = base.configureAxis(grid = false).configureTitle(fontSize = 20)
      .toSpec["config"]
    check cfg["axis"]["grid"].getBool == false
    check cfg["title"]["fontSize"].getFloat == 20.0

suite "themes":

  teardown:
    enableTheme("")

  test "the shipped themes are registered":
    check "dark" in themeNames()
    check "clean" in themeNames()

  test "a theme is off until enabled":
    check "config" notin base.toSpec
    enableTheme("dark")
    check base.toSpec["config"]["background"].getStr == "#1e1e1e"

  test "enabling an unknown theme is an error":
    expect KeyError:
      enableTheme("nosuchtheme")

  test "a chart's own config wins over the theme's":
    enableTheme("dark")
    let themed = base.configureBackground("#ffffff").toSpec["config"]
    check themed["background"].getStr == "#ffffff"
    # untouched sections still come from the theme
    check themed["axis"]["gridColor"].getStr == "#333333"

  test "a chart's config merges into the theme's section, field by field":
    enableTheme("dark")
    let axis = base.configureAxis(labelAngle = 45).toSpec["config"]["axis"]
    check axis["labelAngle"].getFloat == 45.0
    # the rest of the theme's axis section survives
    check axis["labelColor"].getStr == "#cccccc"
    check axis["gridColor"].getStr == "#333333"

  test "disabling restores plain specs":
    enableTheme("dark")
    enableTheme("")
    check "config" notin base.toSpec
    check activeTheme() == ""

  test "a custom theme can be registered":
    registerTheme("mine", Config(isSet: true, font: "Inter"))
    enableTheme("mine")
    check base.toSpec["config"]["font"].getStr == "Inter"
