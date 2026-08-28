## UFCS: the chainable `Encoding` modifiers, and the receiver-first spellings
## that already worked but were pinned by nothing.

import std/[json, os, unittest]
import plotter

proc enc(c: Chart, ch: string): JsonNode = c.toSpec["encoding"][ch]

proc unit(x: Encoding): Chart =
  chart(dataFrame(col("a", @[1.0, 2.0]), col("g", @["x", "y"])))
    .markPoint().encode(x = x)

suite "chainable encoding modifiers":

  test "a bare shorthand string is the head of the chain":
    let x = unit("a:Q".scale(zero = false).axis(grid = false)).enc("x")
    check x["field"].getStr == "a"
    check x["type"].getStr == "quantitative"
    check x["scale"]["zero"].getBool == false
    check x["axis"]["grid"].getBool == false

  test "an X(...) receiver works the same":
    let x = unit(X("a:Q", title = "T").scale(zero = false)).enc("x")
    check x["title"].getStr == "T"
    check x["scale"]["zero"].getBool == false

  test "the same setter chained twice merges rather than clobbers":
    let x = unit("a:Q".scale(zero = false).scale(scheme = "viridis")).enc("x")
    check x["scale"]["zero"].getBool == false
    check x["scale"]["scheme"].getStr == "viridis"

  test "axis and legend merge too":
    let c = unit("a:Q".axis(grid = false).axis(labelAngle = -45))
      .encode(color = "g:N".legend(orient = "bottom").legend(columns = 2))
    check c.enc("x")["axis"]["grid"].getBool == false
    check c.enc("x")["axis"]["labelAngle"].getFloat == -45.0
    check c.enc("color")["legend"]["orient"].getStr == "bottom"
    check c.enc("color")["legend"]["columns"].getInt == 2

  test "chaining does not disturb what the constructor already set":
    let x = unit(X("a:Q", scale = Scale(scheme = "viridis"))
                 .scale(zero = false)).enc("x")
    check x["scale"]["scheme"].getStr == "viridis"
    check x["scale"]["zero"].getBool == false

  test "an untouched encoding emits no scale, axis or legend key":
    let x = unit("a:Q").enc("x")
    check "scale" notin x
    check "axis" notin x
    check "legend" notin x

  test "raw merges over the generated keys":
    let x = unit("a:Q".scale(zero = false,
                             raw = %*{"paddingInner": 0.2})).enc("x")
    check x["scale"]["zero"].getBool == false
    check x["scale"]["paddingInner"].getFloat == 0.2

  test "the receiver is copied, not mutated":
    let base = X("a:Q")
    discard base.scale(zero = false)
    check not base.scale.isSet

suite "chainable modifiers and the tristate rules":

  test "no title call means no title key":
    check "title" notin unit("a:Q".scale(zero = false)).enc("x")

  test "an empty title is a title":
    let x = unit("a:Q".title("")).enc("x")
    check x["title"].kind == JString
    check x["title"].getStr == ""

  test "noTitle is null":
    check unit("a:Q".noTitle()).enc("x")["title"].kind == JNull

  test "title after noTitle wins, and the other way round":
    check unit("a:Q".noTitle().title("T")).enc("x")["title"].getStr == "T"
    check unit("a:Q".title("T").noTitle()).enc("x")["title"].kind == JNull

  test "a hidden axis or legend is null":
    let c = unit("a:Q".axis(hidden = true))
      .encode(color = "g:N".legend(hidden = true))
    check c.enc("x")["axis"].kind == JNull
    check c.enc("color")["legend"].kind == JNull

  test "hideTitle on an axis is a null axis title":
    check unit("a:Q".axis(hideTitle = true)).enc("x")["axis"]["title"].kind ==
      JNull

  test "stack none is null, and unset omits the key":
    check unit("a:Q".stack("none")).enc("x")["stack"].kind == JNull
    check "stack" notin unit("a:Q").enc("x")

  test "sort null is null, and unset omits the key":
    check unit("g:N".sort("null")).enc("x")["sort"].kind == JNull
    check "sort" notin unit("g:N").enc("x")

suite "chainable bin, sort and stack":

  test "a bare bin call is bin: true":
    check unit("a:Q".bin()).enc("x")["bin"].getBool

  test "bin arguments merge across calls":
    let b = unit("a:Q".bin(maxbins = 20).bin(nice = false)).enc("x")["bin"]
    check b["maxbins"].getInt == 20
    check b["nice"].getBool == false

  test "already-binned data":
    check unit("a:Q".bin(binned = true)).enc("x")["bin"].getStr == "binned"

  test "sort takes the same strings sort = does":
    check unit("g:N".sort("descending")).enc("x")["sort"].getStr ==
      "descending"
    check unit("g:N".sort("-y")).enc("x")["sort"].getStr == "-y"

  test "sort takes an explicit domain order":
    let s = unit("g:N".sort(vals("y", "x"))).enc("x")["sort"]
    check s.kind == JArray
    check s[0].getStr == "y"

  test "sort takes a SortDef for what the strings cannot spell":
    let s = unit("g:N".sort(SortDef(kind: sortField, field: "a",
                                    op: agMean, descending: true)))
      .enc("x")["sort"]
    check s["field"].getStr == "a"
    check s["op"].getStr == "mean"
    check s["order"].getStr == "descending"

  test "sort replaces rather than merges":
    check unit("g:N".sort("ascending").sort("descending"))
      .enc("x")["sort"].getStr == "descending"

  test "stack takes the same strings stack = does":
    check unit("a:Q".stack("normalize")).enc("x")["stack"].getStr ==
      "normalize"

suite "chainable modifiers on non-field encodings":

  test "the settable properties are common to every encoding kind":
    # `title`, `scale` and the rest live ahead of `case kind`, so a setter
    # cannot hit a field-access error on a value/datum/repeat encoding.
    let d = unit(datum(5.0).axis(grid = false)).enc("x")
    check d["datum"].getFloat == 5.0
    check d["axis"]["grid"].getBool == false

suite "receiver-first spellings":
  # These compile against the tree as it stands; the point of the suite is
  # that a signature change cannot break them silently.

  test "a frame is a chart receiver":
    let df = dataFrame(col("a", @[1.0]))
    check df.chart(title = "Cars").markPoint().toSpec["title"].getStr == "Cars"

  test "objects and tuples reach a chart through the adapter":
    let people = @[(name: "a", age: 30), (name: "b", age: 40)]
    let spec = people.toDataFrame().chart().markBar()
      .encode(x = "name:N", y = "age:Q").toSpec
    check spec["data"]["values"].len == 2

  test "read, frame and chart in one line":
    let path = getTempDir() / "plotter_tufcs.csv"
    writeFile(path, "a,b\n1,2\n3,4\n")
    defer: removeFile(path)
    let spec = path.readCsv().chart().markBar().encode(x = "a:Q").toSpec
    check spec["data"]["values"].len == 2

  test "varargs builders take a receiver":
    let base = chart(dataFrame(col("a", @[1.0]))).markLine()
    let rule = chart(DataFrame()).markRule()
    let labels = chart(DataFrame()).markText()
    let spec = base.layer(rule, labels).toSpec
    check spec["layer"].len == 3
    check spec["layer"][0]["mark"].getStr == "line"

  test "the render side takes a receiver":
    let path = getTempDir() / "plotter_tufcs.json"
    defer: removeFile(path)
    chart(dataFrame(col("a", @[1.0]))).markPoint().saveJson(path)
    check parseFile(path)["mark"].getStr == "point"
