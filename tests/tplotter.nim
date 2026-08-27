import std/[json, unittest]
import plotter

suite "one-line constructors":

  test "scatter builds a point chart bound to x and y":
    let c = scatter(@[1.0, 2.0, 3.0], @[4.0, 5.0, 6.0], title = "demo")
    check c.mark.kind == mkPoint
    check c.title == "demo"
    check c.data.len == 3
    check c.enc(chX).field == "x"
    check c.enc(chY).field == "y"

  test "line and bar set their mark":
    check line(@[1.0], @[2.0]).mark.kind == mkLine
    check bar(@[1.0], @[2.0]).mark.kind == mkBar

  test "categorical bars declare a nominal x":
    check bar(@["a", "b"], @[1.0, 2.0]).enc(chX).fieldType == ftNominal

  test "multi-series charts map colour to the group":
    let c = line(@[newSeries(@[1.0], @[2.0], "a"),
                   newSeries(@[3.0], @[4.0], "b")])
    check c.data.len == 2
    check c.enc(chColor).field == "series"

  test "mismatched lengths are rejected":
    expect AssertionDefect:
      discard scatter(@[1.0, 2.0], @[3.0])

  test "hist bins and counts":
    let spec = hist(@[1.0, 2.0, 3.0], maxbins = 5).toSpec
    check spec["encoding"]["x"]["bin"]["maxbins"].getInt == 5
    check spec["encoding"]["y"]["aggregate"].getStr == "count"

  test "heatmap and boxplot":
    check heatmap(@["a"], @["b"], @[1.0]).mark.kind == mkRect
    check boxplot(@["a"], @[1.0]).mark.kind == mkBoxplot

  test "default canvas size":
    let c = line(@[1.0], @[2.0])
    check c.width == defaultWidth
    check c.height == defaultHeight

suite "builders are functional":

  test "a base chart is reusable":
    let base = chart(dataFrame(col("x", @[1.0]), col("y", @[2.0])))
      .encode(x = "x:Q", y = "y:Q")
    let a = base.markBar()
    let b = base.markLine().properties(width = 100)
    check base.mark.kind == mkPoint
    check a.mark.kind == mkBar
    check b.width == 100
    check base.width == defaultWidth

  test "properties only overwrites what it is given":
    let c = chart(DataFrame(), title = "keep").properties(width = 10)
    check c.title == "keep"
    check c.width == 10
    check c.height == defaultHeight
