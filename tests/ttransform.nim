import std/[json, unittest]
import plotter

let df = dataFrame(col("mpg", @[18.0, 24.0]), col("origin", @["USA", "Japan"]))
let base = chart(df).markPoint()

proc tf(c: Chart): JsonNode = c.toSpec["transform"]  # `.transforms` is the field

suite "transform pipeline":

  test "transforms apply in call order":
    let t = base
      .transformFilter("datum.mpg > 20")
      .transformCalculate("kpl", "datum.mpg * 0.425")
      .tf
    check t.len == 2
    check t[0]["filter"].getStr == "datum.mpg > 20"
    check t[1]["calculate"].getStr == "datum.mpg * 0.425"
    check t[1]["as"].getStr == "kpl"

  test "no transforms means no key":
    check "transform" notin base.toSpec

  test "the raw escape hatch passes a node straight through":
    let t = base.transform(%*{"impute": "x", "key": "k"}).tf
    check t[0]["impute"].getStr == "x"

suite "aggregate and window":

  test "aggregate with a groupby":
    let t = base.transformAggregate(
      @[agg(agMean, "mpg", "avgMpg"), agg(agCount)],
      groupby = @["origin"]).tf
    check t[0]["aggregate"][0]["op"].getStr == "mean"
    check t[0]["aggregate"][0]["field"].getStr == "mpg"
    check t[0]["aggregate"][0]["as"].getStr == "avgMpg"
    check "field" notin t[0]["aggregate"][1]
    check t[0]["groupby"][0].getStr == "origin"

  test "output names default to op_field":
    let t = base.transformAggregate(@[agg(agSum, "mpg")]).tf
    check t[0]["aggregate"][0]["as"].getStr == "sum_mpg"

  test "joinaggregate uses its own key":
    let t = base.transformJoinAggregate(@[agg(agMean, "mpg")]).tf
    check t[0].hasKey("joinaggregate")

  test "window with a sort and a bounded frame":
    let t = base.transformWindow(
      @[win("rank", to = "rank")],
      groupby = @["origin"],
      sort = @[sortField("mpg", descending = true)],
      frameStart = 0, frameEnd = 2).tf
    check t[0]["window"][0]["op"].getStr == "rank"
    check t[0]["sort"][0]["order"].getStr == "descending"
    check t[0]["frame"][0].getInt == 0
    check t[0]["frame"][1].getInt == 2

  test "an unset frame bound is unbounded, which Vega-Lite spells null":
    let t = base.transformWindow(@[win("sum", "mpg", "running")],
                                 frameEnd = 0).tf
    check t[0]["frame"][0].kind == JNull
    check t[0]["frame"][1].getInt == 0

suite "reshaping":

  test "fold and pivot":
    let f = base.transformFold(@["a", "b"], to = @["key", "val"]).tf
    check f[0]["fold"][1].getStr == "b"
    check f[0]["as"][1].getStr == "val"

    let p = base.transformPivot("origin", "mpg",
                                groupby = @["year"]).tf
    check p[0]["pivot"].getStr == "origin"
    check p[0]["value"].getStr == "mpg"

  test "bin and timeUnit":
    let b = base.transformBin("mpg", "mpgBin", Bin(maxbins = 10)).tf
    check b[0]["bin"]["maxbins"].getInt == 10
    check b[0]["as"].getStr == "mpgBin"

    let t = base.transformTimeUnit("yearmonth", "date", "ym").tf
    check t[0]["timeUnit"].getStr == "yearmonth"

  test "lookup joins a second dataset":
    let t = base.transformLookup(
      "origin", urlData("https://example.com/lookup.json"), "id",
      fields = @["region"]).tf
    check t[0]["lookup"].getStr == "origin"
    check t[0]["from"]["url"].getStr == "https://example.com/lookup.json"
    check t[0]["from"]["key"].getStr == "id"
    check t[0]["from"]["fields"][0].getStr == "region"

suite "fits":

  test "regression and loess":
    let r = base.transformRegression("mpg", "hp",
                                     fitMethod = "poly").tf
    check r[0]["regression"].getStr == "mpg"
    check r[0]["on"].getStr == "hp"
    check r[0]["method"].getStr == "poly"

    let l = base.transformLoess("mpg", "hp", bandwidth = 0.3).tf
    check l[0]["loess"].getStr == "mpg"
    check l[0]["bandwidth"].getFloat == 0.3

  test "density":
    let d = base.transformDensity("mpg", groupby = @["origin"],
                                  counts = true).tf
    check d[0]["density"].getStr == "mpg"
    check d[0]["counts"].getBool

suite "the expr macro":

  test "comparisons and boolean operators":
    check expr(datum.price > 100) == "(datum.price > 100)"
    check expr(datum.a == "USA") == "(datum.a === 'USA')"
    check expr(datum.a != 3) == "(datum.a !== 3)"

  test "and / or / not become their JavaScript spellings":
    check expr(datum.a > 1 and datum.b < 2) ==
      "((datum.a > 1) && (datum.b < 2))"
    check expr(datum.a > 1 or datum.b < 2) ==
      "((datum.a > 1) || (datum.b < 2))"
    check expr(not datum.ok) == "!datum.ok"

  test "arithmetic":
    check expr(datum.a * 2 + 1) == "((datum.a * 2) + 1)"
    check expr(datum.a mod 2) == "(datum.a % 2)"

  test "div keeps Nim's truncating semantics":
    # Vega only has float `/` and no `trunc`, so `div` has to round toward
    # zero explicitly: -5 div 2 is -2, not floor(-2.5) == -3.
    check expr(datum.a div 2) ==
      "((datum.a / 2) < 0 ? ceil(datum.a / 2) : floor(datum.a / 2))"

  test "function calls pass through":
    check expr(isValid(datum.x)) == "isValid(datum.x)"
    check expr(year(datum.date) > 2000) == "(year(datum.date) > 2000)"

  test "strings are single-quoted and escaped":
    check expr(datum.name == "it's") == "(datum.name === 'it\\'s')"

  test "it plugs straight into transformFilter":
    let t = base.transformFilter(expr(datum.mpg > 20)).tf
    check t[0]["filter"].getStr == "(datum.mpg > 20)"
