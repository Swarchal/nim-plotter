import std/[json, unittest]
import plotter

let df = dataFrame(col("date", @[1.0, 2.0]), col("price", @[3.0, 4.0]),
                   col("symbol", @["A", "B"]))
let base = chart(df).encode(x = "date:Q", y = "price:Q")

suite "layering":

  test "operator and named form agree":
    let viaOp = base.markLine() + base.markPoint()
    let viaProc = layer(base.markLine(), base.markPoint())
    check viaOp.toSpec == viaProc.toSpec

  test "a layer emits its children under \"layer\"":
    let spec = (base.markLine() + base.markPoint()).toSpec
    check spec["layer"].len == 2
    check spec["layer"][0]["mark"].getStr == "line"
    check spec["layer"][1]["mark"].getStr == "point"

  test "three layers are one spec, not a nest of two":
    let spec = (base.markLine() + base.markPoint() + base.markRule()).toSpec
    check spec["layer"].len == 3
    check "layer" notin spec["layer"][0]

  test "shared data is hoisted to the layer, not repeated per child":
    let spec = (base.markLine() + base.markPoint()).toSpec
    check spec["data"]["values"].len == 2
    for child in spec["layer"]:
      check "data" notin child

  test "differing data stays with each child":
    let other = chart(dataFrame(col("date", @[9.0]), col("price", @[9.0])))
      .encode(x = "date:Q", y = "price:Q")
    let spec = (base.markLine() + other.markPoint()).toSpec
    check "data" notin spec
    check spec["layer"][0]["data"]["values"].len == 2
    check spec["layer"][1]["data"]["values"].len == 1

  test "the layer sizes itself and its children do not":
    let spec = (base.markLine() + base.markPoint()).toSpec
    check spec["width"].getInt == defaultWidth
    for child in spec["layer"]:
      check "width" notin child

  test "only the outermost spec carries $schema":
    let spec = (base.markLine() + base.markPoint()).toSpec
    check spec["$schema"].getStr == vegaLiteSchema
    for child in spec["layer"]:
      check "$schema" notin child

suite "concatenation":

  test "hconcat and vconcat":
    let h = (base.markLine() | base.markBar()).toSpec
    check h["hconcat"].len == 2
    let v = (base.markLine() & base.markBar()).toSpec
    check v["vconcat"].len == 2

  test "concatenated charts keep their own sizes":
    let spec = (base.markLine().properties(width = 100) |
                base.markBar().properties(width = 200)).toSpec
    check spec["hconcat"][0]["width"].getInt == 100
    check spec["hconcat"][1]["width"].getInt == 200
    check "width" notin spec

  test "mixed composition nests":
    let spec = ((base.markLine() + base.markPoint()) | base.markBar()).toSpec
    check spec["hconcat"].len == 2
    check spec["hconcat"][0]["layer"].len == 2
    check spec["hconcat"][1]["mark"].getStr == "bar"

suite "faceting":

  test "the grid form":
    let spec = base.markPoint().facet(column = "symbol:N").toSpec
    check spec["facet"]["column"]["field"].getStr == "symbol"
    check spec["spec"]["mark"].getStr == "point"

  test "the wrapped form takes a column count":
    let spec = base.markPoint()
      .facet(facet = "symbol:N", columns = 3).toSpec
    check spec["facet"]["field"].getStr == "symbol"
    # `columns` is a top-level sibling of `facet`, not part of the field def.
    check "columns" notin spec["facet"]
    check spec["columns"].getInt == 3

  test "facet channels infer their type from the hoisted data":
    # The facet node holds no data of its own; the frame lives on the spec
    # inside it, so inference has to see the hoisted copy.
    let byColumn = base.markPoint().facet(column = Column("symbol")).toSpec
    check byColumn["facet"]["column"]["type"].getStr == "nominal"
    let byRow = base.markPoint().facet(row = Row("symbol")).toSpec
    check byRow["facet"]["row"]["type"].getStr == "nominal"
    let wrapped = base.markPoint().facet(facet = Facet("symbol")).toSpec
    check wrapped["facet"]["type"].getStr == "nominal"

  test "data belongs to the facet, never to the spec inside it":
    let spec = base.markPoint().facet(column = "symbol:N").toSpec
    check spec["data"]["values"].len == 2
    check "data" notin spec["spec"]

suite "repeat":

  test "fields are repeated and referenced with Rep":
    let spec = chart(df).markPoint()
      .encode(x = Rep("column"), y = Rep("row"))
      .repeat(row = @["price"], column = @["date"]).toSpec
    check spec["repeat"]["column"][0].getStr == "date"
    check spec["repeat"]["row"][0].getStr == "price"
    check spec["spec"]["encoding"]["x"]["field"]["repeat"].getStr == "column"

  test "a repeated field can declare its type":
    # The field is only known at render time, so nothing can infer it.
    let spec = chart(df).markBar()
      .encode(x = Rep("column", ftNominal), y = "price:Q")
      .repeat(column = @["symbol"]).toSpec
    check spec["spec"]["encoding"]["x"]["type"].getStr == "nominal"

suite "resolve":

  test "independent scales":
    let spec = (base.markLine() + base.markBar())
      .resolveScale(color = "independent").toSpec
    check spec["resolve"]["scale"]["color"].getStr == "independent"

  test "resolve builders do not mutate the chart they came from":
    let shared = (base.markLine() + base.markBar())
      .resolveScale(color = "independent")
    discard shared.resolveAxis(x = "independent")
    check "axis" notin shared.toSpec["resolve"]

  test "axis and legend resolution":
    let spec = (base.markLine() | base.markBar())
      .resolveAxis(y = "independent")
      .resolveLegend(color = "shared").toSpec
    check spec["resolve"]["axis"]["y"].getStr == "independent"
    check spec["resolve"]["legend"]["color"].getStr == "shared"

suite "size":

  test "properties sizes a composite that had no size of its own":
    let spec = layer(base.markLine(), base.markBar())
      .properties(width = 400, height = 300).toSpec
    check spec["width"].getInt == 400
    check spec["height"].getInt == 300
