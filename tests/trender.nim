import std/[json, os, strutils, unittest]
import plotter

let sample = chart(dataFrame(col("x", @[1.0, 2.0]), col("y", @[3.0, 4.0])),
                   title = "t").markPoint().encode(x = "x:Q", y = "y:Q")

suite "text output":

  test "json round-trips":
    check parseJson(sample.toJson)["title"].getStr == "t"

  test "indent = 0 is compact":
    check "\n" notin sample.toJson(indent = 0)

  test "html embeds the spec and names the page":
    let html = sample.toHtml
    check html.contains("vegaEmbed")
    check html.contains("<title>t</title>")
    check html.contains("\"mark\":\"point\"")

  test "the page title is html-escaped":
    let html = sample.properties(title = "</title><script>x</script> & \"q\"")
      .toHtml
    check "<script>x</script>" notin html
    check html.contains(
      "<title>&lt;/title&gt;&lt;script&gt;x&lt;/script&gt; &amp; &quot;q&quot;</title>")

  test "the spec cannot close the script tag it sits in":
    let c = chart(dataFrame(col("x", @[1.0]), col("s", @["</script><b>"])))
      .markPoint().encode(x = "x:Q", tooltip = "s:N")
    let html = c.toHtml
    check "</script><b>" notin html
    check html.contains("<\\/script>")

  test "an untitled chart still gets a page title":
    check sample.properties(title = "").toHtml.contains("<title>t</title>")

suite "embed options":

  test "the renderer and action menu are configurable":
    var embed = defaultEmbed()
    embed.renderer = rdCanvas
    embed.actions = false
    let html = sample.toHtml(embed)
    check html.contains("renderer: \"canvas\"")
    check html.contains("actions: false")

  test "versions land in the CDN urls":
    var embed = defaultEmbed()
    embed.vegaLiteVersion = "5.17.0"
    check sample.toHtml(embed).contains("vega-lite@5.17.0")

  test "local runtime files are inlined instead of fetched":
    let dir = getTempDir() / "plotter-runtime"
    createDir(dir)
    defer: removeDir(dir)
    writeFile(dir / "vega.js", "/* pretend vega */")
    var embed = defaultEmbed()
    embed.runtimeFiles = @[dir / "vega.js"]
    let html = sample.toHtml(embed)
    check html.contains("/* pretend vega */")
    check not html.contains("cdn.jsdelivr.net")

suite "files":

  setup:
    let dir = getTempDir() / "plotter-test"
    createDir(dir)

  teardown:
    removeDir(dir)

  test "save dispatches on extension":
    sample.save(dir / "a.json")
    sample.save(dir / "b.html")
    check parseJson(readFile(dir / "a.json"))["mark"].getStr == "point"
    check readFile(dir / "b.html").contains("vegaEmbed")

  test "an unknown extension is rejected":
    expect ValueError:
      sample.save(dir / "c.txt")

  test "png rendering, when vl-convert is installed":
    if findExe(vlConvertExe).len == 0:
      skip()
    else:
      sample.savePng(dir / "d.png")
      check getFileSize(dir / "d.png") > 0

  test "png rendering explains itself when vl-convert is missing":
    if findExe(vlConvertExe).len > 0:
      skip()
    else:
      try:
        sample.savePng(dir / "e.png")
        check false
      except OSError as err:
        check err.msg.contains("cargo install vl-convert")
        check err.msg.contains("saveHtml")
