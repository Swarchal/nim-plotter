## The gallery: one chart per idea, each the Nim port of a chart from
## Altair's example gallery.
##
## `examples/build.nim` renders these to `examples/out/`, and
## `tests/tgallery.nim` round-trips every one of them and — when
## `vl-convert` is installed — has it validate each spec.

import std/[math, strutils]
import ../src/plotter

proc cars(): DataFrame =
  ## A slice of the cars dataset everyone benchmarks charting libraries on:
  ## a few cars of each origin per model year, 1970-1978, so that grouped and
  ## stacked charts have more than one category per year to show.
  dataFrame(
    col("Name", @["volkswagen 1131 deluxe sedan", "toyota corona mark ii",
                  "amc rebel sst", "buick skylark 320",
                  "chevrolet chevelle malibu", "plymouth satellite",
                  "opel 1900", "datsun pl510", "amc gremlin",
                  "chevrolet vega 2300", "plymouth satellite custom",
                  "volkswagen type 3", "toyota corona hardtop",
                  "chevrolet vega", "dodge colt hardtop",
                  "ford pinto runabout", "volkswagen super beetle",
                  "toyota carina", "amc matador", "buick century 350",
                  "chevrolet malibu", "ford gran torino", "audi fox",
                  "datsun b210", "amc hornet", "plymouth duster",
                  "volkswagen dasher", "toyota corolla", "chevrolet nova",
                  "mercury monarch", "plymouth valiant custom", "fiat 131",
                  "honda civic", "capri ii",
                  "chevrolet chevelle malibu classic", "dodge colt",
                  "dodge coronet brougham", "renault 5 gtl",
                  "honda accord cvcc", "buick opel isuzu deluxe",
                  "chevrolet caprice classic", "plymouth arrow gs",
                  "volkswagen rabbit custom diesel", "mazda glc deluxe",
                  "dodge diplomat", "ford fiesta", "mercury monarch ghia",
                  "oldsmobile cutlass salon brougham"]),
    col("Horsepower", @[46.0, 95.0, 150.0, 165.0, 130.0, 150.0, 90.0, 88.0,
                        100.0, 90.0, 105.0, 54.0, 95.0, 90.0, 80.0, 86.0,
                        46.0, 88.0, 150.0, 175.0, 145.0, 137.0, 83.0, 67.0,
                        100.0, 95.0, 71.0, 75.0, 105.0, 72.0, 95.0, 86.0,
                        53.0, 92.0, 140.0, 79.0, 150.0, 58.0, 68.0, 80.0,
                        145.0, 96.0, 48.0, 52.0, 140.0, 66.0, 139.0, 110.0]),
    col("Miles_per_Gallon", @[26.0, 24.0, 16.0, 15.0, 18.0, 18.0, 28.0, 27.0,
                              19.0, 28.0, 16.0, 23.0, 24.0, 20.0, 25.0, 21.0,
                              26.0, 20.0, 14.0, 13.0, 13.0, 14.0, 29.0, 31.0,
                              19.0, 20.0, 25.0, 29.0, 18.0, 15.0, 19.0, 28.0,
                              33.0, 25.0, 17.5, 26.0, 16.0, 36.0, 31.5, 30.0,
                              17.5, 25.5, 43.1, 32.8, 19.4, 36.1, 20.2, 19.9]),
    col("Origin", @["Europe", "Japan", "USA", "USA", "USA", "USA", "Europe",
                    "Japan", "USA", "USA", "USA", "Europe", "Japan", "USA",
                    "USA", "USA", "Europe", "Japan", "USA", "USA", "USA",
                    "USA", "Europe", "Japan", "USA", "USA", "Europe", "Japan",
                    "USA", "USA", "USA", "Europe", "Japan", "USA", "USA",
                    "USA", "USA", "Europe", "Japan", "USA", "USA", "USA",
                    "Europe", "Japan", "USA", "USA", "USA", "USA"]),
    col("Year", @[1970.0, 1970.0, 1970.0, 1970.0, 1970.0, 1970.0, 1971.0,
                  1971.0, 1971.0, 1971.0, 1971.0, 1972.0, 1972.0, 1972.0,
                  1972.0, 1972.0, 1973.0, 1973.0, 1973.0, 1973.0, 1973.0,
                  1973.0, 1974.0, 1974.0, 1974.0, 1974.0, 1975.0, 1975.0,
                  1975.0, 1975.0, 1975.0, 1976.0, 1976.0, 1976.0, 1976.0,
                  1976.0, 1976.0, 1977.0, 1977.0, 1977.0, 1977.0, 1977.0,
                  1978.0, 1978.0, 1978.0, 1978.0, 1978.0, 1978.0]))

proc stocks(): DataFrame =
  var dates, symbols: seq[string]
  var prices: seq[float]
  for i in 0 ..< 24:
    let month = 1 + i mod 12
    let year = 2019 + i div 12
    for (symbol, base) in {"AAPL": 100.0, "GOOG": 250.0}:
      dates.add($year & "-" & align($month, 2, '0') & "-01")
      symbols.add(symbol)
      prices.add(base + 20.0 * sin(i.float / 3.0) + i.float)
  dataFrame(col("date", dates), col("symbol", symbols), col("price", prices))

proc weather(): DataFrame =
  var cities, months: seq[string]
  var temps: seq[float]
  for city in ["Seattle", "Lisbon", "Oslo"]:
    for m in 1 .. 12:
      cities.add(city)
      months.add(align($m, 2, '0'))
      temps.add(10.0 + 8.0 * sin((m.float - 3.0) / 12.0 * 2.0 * PI) +
                (if city == "Lisbon": 6.0 elif city == "Oslo": -6.0 else: 0.0))
  dataFrame(col("city", cities), col("month", months), col("temp", temps))

proc galleryCharts*(): seq[(string, Chart)] =
  let carsDf = cars()
  let stocksDf = stocks()

  result.add(("scatter", chart(carsDf, title = "Horsepower vs economy")
    .markPoint(filled = true)
    .encode(x = X("Horsepower:Q", scale = Scale(zero = false)),
            y = "Miles_per_Gallon:Q",
            color = "Origin:N")
    .tooltips("Name:N", "Horsepower:Q", "Miles_per_Gallon:Q")))

  result.add(("bar", chart(carsDf, title = "Mean economy by origin")
    .markBar()
    .encode(x = X("Origin:N", sort = "-y"),
            y = Y("mean(Miles_per_Gallon):Q", title = "Average MPG"),
            color = Color("Origin:N", legend = noLegend()))))

  result.add(("histogram", chart(carsDf, title = "Horsepower distribution")
    .markBar()
    .encode(x = X("Horsepower:Q", bin = Bin(maxbins = 8)),
            y = "count()")))

  result.add(("layered", block:
    let base = chart(stocksDf, title = "Prices")
      .encode(x = "yearmonth(date):T",
              y = "mean(price):Q",
              color = "symbol:N")
    base.markLine() + base.markPoint(size = 30, filled = true)))

  result.add(("faceted", chart(stocksDf)
    .markLine()
    .encode(x = "yearmonth(date):T", y = "price:Q", color = "symbol:N")
    .properties(width = 260, height = 180)
    .facet(column = "symbol:N")))

  result.add(("stacked", chart(carsDf, title = "Origin share by year")
    .markBar()
    .encode(x = "Year:O",
            y = Y("count():Q", stack = "normalize", title = "Share"),
            color = "Origin:N")))

  result.add(("regression", block:
    let base = chart(carsDf, title = "Trend")
      .encode(x = "Horsepower:Q", y = "Miles_per_Gallon:Q")
    base.markPoint() +
      base.transformRegression("Miles_per_Gallon", "Horsepower")
          .markLine(color = "firebrick")))

  result.add(("heatmap", chart(weather(), title = "Monthly temperature")
    .markRect()
    .encode(x = "month:O",
            y = "city:N",
            color = Color("temp:Q", scale = Scale(scheme = "viridis")))
    .properties(height = 200)))

  result.add(("filtered", chart(carsDf, title = "Efficient cars only")
    .transformFilter(expr(datum.Miles_per_Gallon > 28))
    .transformCalculate("kpl", "datum.Miles_per_Gallon * 0.425")
    .markBar()
    .encode(x = X("Name:N", sort = "-y"), y = "kpl:Q")))

  result.add(("styled", chart(carsDf, title = "Custom styling")
    .markPoint(filled = true)
    .encode(x = X("Horsepower:Q", scale = Scale(zero = false)),
            y = "Miles_per_Gallon:Q", color = "Origin:N")
    .configureView(noStroke = true)
    .configureAxis(gridColor = "#eeeeee")))

  result.add(("themed", chart(carsDf, title = "Dark theme, one override")
    .markPoint(filled = true)
    .encode(x = X("Horsepower:Q", scale = Scale(zero = false)),
            y = "Miles_per_Gallon:Q", color = "Origin:N")
    .configureAxis(labelAngle = 45)))

proc galleryTheme*(name: string): string =
  ## The theme a gallery chart is meant to be rendered under. A theme is
  ## process-wide state rather than part of the chart, so the renderer has to
  ## enable it around that chart; everything else renders unthemed.
  if name == "themed": "dark" else: ""
