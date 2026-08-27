## plotter — a library for 2D static charts.
##
## Charts are built as data and emitted as a Vega-Lite spec, which a browser
## or `vl-convert` turns into pixels. The API follows Altair closely enough
## that ported code usually reads the same:
##
## ```nim
## import plotter
##
## chart(cars)
##   .markPoint(filled = true)
##   .encode(
##     x = X("Horsepower:Q", scale = Scale(zero = false)),
##     y = "Miles_per_Gallon:Q",
##     color = "Origin:N")
##   .properties(width = 400, height = 300, title = "Cars")
##   .save("cars.html")
## ```
##
## Channel arguments take either a shorthand string (`"mean(sales):Q"`) or a
## constructor (`X(...)`, `Color(...)`) — they are the same `Encoding` type.
## The one-liners below cover the common cases.

import std/json
import plotter/types
import plotter/adapters
import plotter/builders
import plotter/expressions
import plotter/themes
import plotter/vegalite
import plotter/render

export json   # `raw = %*{...}` and inspecting `toSpec` both need it
export types
export adapters
export builders
export expressions
export themes
export vegalite
export render

proc simple(m: MarkKind, xs, ys: seq[float], title: string): Chart =
  doAssert xs.len == ys.len, "xs and ys must be the same length"
  chart(dataFrame(col("x", xs), col("y", ys)), title = title)
    .mark(m).encode(x = "x:Q", y = "y:Q")

proc simple(m: MarkKind, xs: seq[string], ys: seq[float],
            title: string): Chart =
  doAssert xs.len == ys.len, "xs and ys must be the same length"
  chart(dataFrame(col("x", xs), col("y", ys)), title = title)
    .mark(m).encode(x = "x:N", y = "y:Q")

proc simple(m: MarkKind, series: openArray[Series], title: string): Chart =
  chart(longFrame(series), title = title)
    .mark(m).encode(x = "x:Q", y = "y:Q", color = "series:N")

proc scatter*(xs, ys: seq[float], title = ""): Chart =
  simple(mkPoint, xs, ys, title)

proc scatter*(series: openArray[Series], title = ""): Chart =
  ## Multi-series: melted to long form, one colour per series.
  simple(mkPoint, series, title)

proc line*(xs, ys: seq[float], title = ""): Chart =
  simple(mkLine, xs, ys, title)

proc line*(series: openArray[Series], title = ""): Chart =
  simple(mkLine, series, title)

proc bar*(xs, ys: seq[float], title = ""): Chart =
  simple(mkBar, xs, ys, title)

proc bar*(xs: seq[string], ys: seq[float], title = ""): Chart =
  ## Categorical bars — the usual case, so `xs` is allowed to be strings.
  simple(mkBar, xs, ys, title)

proc bar*(series: openArray[Series], title = ""): Chart =
  simple(mkBar, series, title)

proc hist*(xs: seq[float], title = "", maxbins = 20): Chart =
  ## A histogram: bin the values, count what lands in each bucket.
  chart(dataFrame(col("x", xs)), title = title)
    .markBar()
    .encode(x = X("x:Q", bin = Bin(maxbins = maxbins)),
            y = Y(aggregate = agCount))

proc heatmap*(xs, ys: seq[string], values: seq[float], title = ""): Chart =
  ## A categorical grid coloured by value.
  doAssert xs.len == ys.len and xs.len == values.len,
    "xs, ys and values must be the same length"
  chart(dataFrame(col("x", xs), col("y", ys), col("value", values)),
        title = title)
    .markRect()
    .encode(x = "x:N", y = "y:N", color = "value:Q")

proc boxplot*(groups: seq[string], values: seq[float], title = ""): Chart =
  ## One box per group.
  doAssert groups.len == values.len, "groups and values must be the same length"
  chart(dataFrame(col("group", groups), col("value", values)), title = title)
    .markBoxplot()
    .encode(x = "group:N", y = "value:Q")
