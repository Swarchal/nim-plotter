import std/[json, unittest]
import plotter

proc enc(c: Chart, ch: string): JsonNode = c.toSpec["encoding"][ch]

suite "spec shape":

  test "the skeleton":
    let spec = chart(dataFrame(col("a", @[1.0])), title = "t",
                     description = "d").markBar().encode(x = "a:Q").toSpec
    check spec["$schema"].getStr == vegaLiteSchema
    check spec["title"].getStr == "t"
    check spec["description"].getStr == "d"
    check spec["width"].getInt == defaultWidth
    check spec["height"].getInt == defaultHeight
    check spec["mark"].getStr == "bar"

  test "unset strings are omitted, not emitted empty":
    let spec = chart(dataFrame(col("a", @[1.0]))).markBar()
      .encode(x = "a:Q").toSpec
    check "title" notin spec
    check "description" notin spec
    check "transform" notin spec
    check "config" notin spec

  test "data is inlined as row objects":
    let spec = chart(dataFrame(col("x", @[1.0, 2.0]),
                               col("g", @["a", "b"]))).toSpec
    let values = spec["data"]["values"]
    check values.len == 2
    check values[1]["x"].getFloat == 2.0
    check values[1]["g"].getStr == "b"

  test "noSize drops width and height":
    let spec = chart(dataFrame(col("a", @[1.0]))).noSize().toSpec
    check "width" notin spec
    check "height" notin spec

suite "marks":

  test "a bare mark is a string":
    check chart(DataFrame()).markPoint().toSpec["mark"].getStr == "point"

  test "a mark with properties is an object":
    let m = chart(DataFrame()).markPoint(filled = true, size = 60,
                                         opacity = 0.5).toSpec["mark"]
    check m.kind == JObject
    check m["type"].getStr == "point"
    check m["filled"].getBool
    check m["size"].getFloat == 60.0
    check m["opacity"].getFloat == 0.5

  test "line marks carry point and interpolate":
    let m = chart(DataFrame()).markLine(point = true,
                                        interpolate = "monotone").toSpec["mark"]
    check m["point"].getBool
    check m["interpolate"].getStr == "monotone"

suite "encodings":

  test "field type is inferred from the data when not declared":
    let c = chart(dataFrame(col("g", @["a"]), col("n", @[1.0])))
      .markBar().encode(x = "g", y = "n")
    check c.enc("x")["type"].getStr == "nominal"
    check c.enc("y")["type"].getStr == "quantitative"

  test "a declared type overrides inference":
    let c = chart(dataFrame(col("n", @[1.0]))).markBar().encode(x = "n:O")
    check c.enc("x")["type"].getStr == "ordinal"

  test "aggregates":
    let c = chart(dataFrame(col("g", @["a"]), col("n", @[1.0])))
      .markBar().encode(x = "g:N", y = "mean(n):Q")
    check c.enc("y")["aggregate"].getStr == "mean"
    check c.enc("y")["field"].getStr == "n"

  test "a bare count has no field":
    let c = chart(dataFrame(col("g", @["a"]))).markBar()
      .encode(x = "g:N", y = "count()")
    check "field" notin c.enc("y")
    check c.enc("y")["aggregate"].getStr == "count"
    check c.enc("y")["type"].getStr == "quantitative"

  test "bin: true, and with parameters":
    let plain = chart(dataFrame(col("n", @[1.0]))).markBar()
      .encode(x = X("n:Q", bin = true))
    check plain.enc("x")["bin"].getBool

    let params = chart(dataFrame(col("n", @[1.0]))).markBar()
      .encode(x = X("n:Q", bin = Bin(maxbins = 20)))
    check params.enc("x")["bin"]["maxbins"].getInt == 20

    let pre = chart(dataFrame(col("n", @[1.0]))).markBar()
      .encode(x = X("n:Q", bin = binned()))
    check pre.enc("x")["bin"].getStr == "binned"

  test "time units":
    let c = chart(dataFrame(col("d", @["2020-01-01"]))).markLine()
      .encode(x = "yearmonth(d):T")
    check c.enc("x")["timeUnit"].getStr == "yearmonth"
    check c.enc("x")["type"].getStr == "temporal"

  test "value and datum encodings":
    let c = chart(DataFrame()).markRule()
      .encode(color = value("red"), y = datum(50.0))
    check c.enc("color")["value"].getStr == "red"
    check "type" notin c.enc("color")
    check c.enc("y")["datum"].getFloat == 50.0

  test "scale, axis and legend":
    let c = chart(dataFrame(col("n", @[1.0]))).markPoint()
      .encode(x = X("n:Q", scale = Scale(scaleType = scLog, zero = false),
                    axis = Axis(labelAngle = -45.0, grid = false)),
              color = Color("n:N", legend = Legend(orient = "bottom")))
    check c.enc("x")["scale"]["type"].getStr == "log"
    check c.enc("x")["scale"]["zero"].getBool == false
    check c.enc("x")["axis"]["labelAngle"].getFloat == -45.0
    check c.enc("color")["legend"]["orient"].getStr == "bottom"

  test "noAxis and noLegend emit null, which is how Vega-Lite hides them":
    let c = chart(dataFrame(col("n", @[1.0]))).markPoint()
      .encode(x = X("n:Q", axis = noAxis()),
              color = Color("n:N", legend = noLegend()))
    check c.enc("x")["axis"].kind == JNull
    check c.enc("color")["legend"].kind == JNull

  test "an empty title differs from an absent one, and from null":
    let absent = chart(DataFrame()).markBar().encode(x = "a:Q")
    check "title" notin absent.enc("x")

    let empty = chart(DataFrame()).markBar().encode(x = X("a:Q", title = ""))
    check empty.enc("x")["title"].getStr == ""

    let nulled = chart(DataFrame()).markBar()
      .encode(x = X("a:Q", hideTitle = true))
    check nulled.enc("x")["title"].kind == JNull

  test "sort, in both its forms":
    let channelSort = chart(DataFrame()).markBar()
      .encode(x = X("a:N", sort = "-y"))
    check channelSort.enc("x")["sort"].getStr == "-y"

    let nullSort = chart(DataFrame()).markBar()
      .encode(x = X("a:N", sort = "null"))
    check nullSort.enc("x")["sort"].kind == JNull

  test "stack: none emits null, not the string":
    let c = chart(DataFrame()).markBar().encode(y = Y("a:Q", stack = "none"))
    check c.enc("y")["stack"].kind == JNull
    let norm = chart(DataFrame()).markBar()
      .encode(y = Y("a:Q", stack = "normalize"))
    check norm.enc("y")["stack"].getStr == "normalize"

  test "array-valued channels":
    let one = chart(DataFrame()).markPoint().tooltips("a:N")
    check one.toSpec["encoding"]["tooltip"].kind == JObject

    let many = chart(DataFrame()).markPoint().tooltips("a:N", "b:Q")
    let t = many.toSpec["encoding"]["tooltip"]
    check t.kind == JArray
    check t.len == 2
    check t[1]["field"].getStr == "b"

  test "repeated encode calls merge, last wins":
    let c = chart(DataFrame()).markPoint()
      .encode(x = "a:Q", y = "b:Q")
      .encode(x = "c:Q", color = "d:N")
    check c.enc("x")["field"].getStr == "c"
    check c.enc("y")["field"].getStr == "b"
    check c.enc("color")["field"].getStr == "d"

  test "faceted charts drop top-level width and height":
    let spec = chart(dataFrame(col("a", @[1.0]), col("g", @["x"])))
      .markPoint().encode(x = "a:Q", column = "g:N").toSpec
    check "width" notin spec
    check "height" notin spec
    check spec["encoding"]["column"]["type"].getStr == "nominal"

suite "raw escape hatch":

  test "raw is deep-merged over the generated node, and wins":
    let c = chart(dataFrame(col("a", @[1.0]))).markPoint()
      .encode(x = X("a:Q", raw = %*{"type": "ordinal", "impute": {"value": 0}}))
    check c.enc("x")["type"].getStr == "ordinal"
    check c.enc("x")["impute"]["value"].getInt == 0
    check c.enc("x")["field"].getStr == "a"

  test "raw on a scale merges without dropping typed fields":
    let c = chart(DataFrame()).markPoint()
      .encode(x = X("a:Q", scale = Scale(zero = false,
                                         raw = %*{"nice": false})))
    check c.enc("x")["scale"]["zero"].getBool == false
    check c.enc("x")["scale"]["nice"].getBool == false

suite "Altair parity":
  # These fixtures are the Vega-Lite shape Altair produces for the same
  # chart, written by hand — Altair is not installed here to generate them,
  # so they encode what the port is aiming at rather than a captured
  # ground truth. `noSize` is used because Altair leaves the size unset.

  proc core(c: Chart): JsonNode =
    ## Just the parts parity is about: mark and encoding.
    let s = c.toSpec
    %*{"mark": s["mark"], "encoding": s["encoding"]}

  test "simple bar chart":
    let df = dataFrame(col("a", @["A", "B"]), col("b", @[28.0, 55.0]))
    let got = chart(df).noSize().markBar()
      .encode(x = "a:N", y = "average(b):Q")
    check core(got) == %*{
      "mark": "bar",
      "encoding": {
        "x": {"field": "a", "type": "nominal"},
        "y": {"aggregate": "average", "field": "b", "type": "quantitative"}}}

  test "scatter with colour and a non-zero scale":
    let df = dataFrame(col("hp", @[130.0]), col("mpg", @[18.0]),
                       col("origin", @["USA"]))
    let got = chart(df).noSize().markPoint(filled = true)
      .encode(x = X("hp:Q", scale = Scale(zero = false)),
              y = "mpg:Q", color = "origin:N")
    check core(got) == %*{
      "mark": {"type": "point", "filled": true},
      "encoding": {
        "x": {"field": "hp", "type": "quantitative",
              "scale": {"zero": false}},
        "y": {"field": "mpg", "type": "quantitative"},
        "color": {"field": "origin", "type": "nominal"}}}

  test "histogram":
    let df = dataFrame(col("IMDB_Rating", @[7.4]))
    let got = chart(df).noSize().markBar()
      .encode(x = X("IMDB_Rating:Q", bin = true), y = "count()")
    check core(got) == %*{
      "mark": "bar",
      "encoding": {
        "x": {"bin": true, "field": "IMDB_Rating", "type": "quantitative"},
        "y": {"aggregate": "count", "type": "quantitative"}}}

  test "normalized stacked bar":
    let df = dataFrame(col("site", @["a"]), col("yield", @[1.0]),
                       col("variety", @["v"]))
    let got = chart(df).noSize().markBar()
      .encode(x = X("sum(yield):Q", stack = "normalize"),
              y = "site:N", color = "variety:N")
    check core(got) == %*{
      "mark": "bar",
      "encoding": {
        "x": {"aggregate": "sum", "field": "yield",
              "stack": "normalize", "type": "quantitative"},
        "y": {"field": "site", "type": "nominal"},
        "color": {"field": "variety", "type": "nominal"}}}

  test "time series with a sorted categorical axis":
    let df = dataFrame(col("date", @["2020-01-01"]), col("price", @[3.0]),
                       col("symbol", @["AAPL"]))
    let got = chart(df).noSize().markLine()
      .encode(x = "yearmonth(date):T",
              y = "mean(price):Q",
              color = Color("symbol:N", sort = "-y"))
    check core(got) == %*{
      "mark": "line",
      "encoding": {
        "x": {"field": "date", "timeUnit": "yearmonth", "type": "temporal"},
        "y": {"aggregate": "mean", "field": "price", "type": "quantitative"},
        "color": {"field": "symbol", "sort": "-y", "type": "nominal"}}}
