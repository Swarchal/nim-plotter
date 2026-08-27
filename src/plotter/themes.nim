## Chart-wide defaults, and a registry of named ones.
##
## Mirrors Altair: `.configureAxis(...)` sets defaults on one chart, and
## `enableTheme("dark")` sets them for every chart emitted afterwards. The
## theme is a process-wide setting — the one piece of global state in the
## library, and the reason `toSpec` is pure only for a fixed theme.
##
## A chart's own config wins over the theme's, field by field.

import std/[json, tables]
import ./types

var
  registry: Table[string, Config]
  active: string

proc configure*(c: Chart, config: Config): Chart =
  ## Replace the whole config.
  result = c
  result.config = config

proc configureAxis*(c: Chart, labelFontSize = Opt[float](),
                    titleFontSize = Opt[float](), labelAngle = Opt[float](),
                    labelColor = "", titleColor = "", gridColor = "",
                    domainColor = "", labelFont = "", titleFont = "",
                    grid = Opt[bool](), domain = Opt[bool](),
                    ticks = Opt[bool](), labels = Opt[bool](),
                    raw: JsonNode = nil): Chart =
  result = c
  result.config.isSet = true
  result.config.axis = AxisConfig(
    isSet: true, labelFontSize: labelFontSize, titleFontSize: titleFontSize,
    labelAngle: labelAngle, labelColor: labelColor, titleColor: titleColor,
    gridColor: gridColor, domainColor: domainColor, labelFont: labelFont,
    titleFont: titleFont, grid: grid, domain: domain, ticks: ticks,
    labels: labels, raw: raw)

proc configureLegend*(c: Chart, orient = "", direction = "",
                      labelColor = "", titleColor = "",
                      labelFontSize = Opt[float](),
                      titleFontSize = Opt[float](),
                      raw: JsonNode = nil): Chart =
  result = c
  result.config.isSet = true
  result.config.legend = LegendConfig(
    isSet: true, orient: orient, direction: direction, labelColor: labelColor,
    titleColor: titleColor, labelFontSize: labelFontSize,
    titleFontSize: titleFontSize, raw: raw)

proc configureView*(c: Chart, stroke = "", noStroke = false, fill = "",
                    continuousWidth = Opt[int](), continuousHeight = Opt[int](),
                    discreteWidth = Opt[int](), discreteHeight = Opt[int](),
                    raw: JsonNode = nil): Chart =
  ## `noStroke = true` is Altair's `configure_view(stroke=None)` — it drops
  ## the border Vega-Lite otherwise draws around the plotting area.
  result = c
  result.config.isSet = true
  result.config.view = ViewConfig(
    isSet: true, stroke: stroke, noStroke: noStroke, fill: fill,
    continuousWidth: continuousWidth, continuousHeight: continuousHeight,
    discreteWidth: discreteWidth, discreteHeight: discreteHeight, raw: raw)

proc configureTitle*(c: Chart, fontSize = Opt[float](), font = "", color = "",
                     anchor = "", align = "", raw: JsonNode = nil): Chart =
  result = c
  result.config.isSet = true
  result.config.title = TitleConfig(isSet: true, fontSize: fontSize,
                                    font: font, color: color, anchor: anchor,
                                    align: align, raw: raw)

proc configureMark*(c: Chart, color = "", fill = "", stroke = "",
                    opacity = Opt[float](), size = Opt[float](),
                    strokeWidth = Opt[float](), filled = Opt[bool](),
                    raw: JsonNode = nil): Chart =
  result = c
  result.config.isSet = true
  result.config.mark = MarkConfig(isSet: true, color: color, fill: fill,
                                  stroke: stroke, opacity: opacity,
                                  size: size, strokeWidth: strokeWidth,
                                  filled: filled, raw: raw)

proc configureBackground*(c: Chart, color: string): Chart =
  result = c
  result.config.isSet = true
  result.config.background = color

proc configureScheme*(c: Chart, category: string): Chart =
  ## The categorical colour scheme every `color` encoding falls back to.
  result = c
  result.config.isSet = true
  result.config.categoryScheme = category

# ---------------------------------------------------------------- themes ----

proc registerTheme*(name: string, config: Config) =
  registry[name] = config

proc enableTheme*(name: string) =
  ## Apply `name` to every chart emitted from now on. `""` turns it off.
  if name.len > 0 and name notin registry:
    raise newException(KeyError, "no theme named '" & name & "'")
  active = name

proc activeTheme*(): string = active

proc themeNames*(): seq[string] =
  for name in registry.keys: result.add(name)

proc mergeSection[T](base, over: T): T =
  ## One config section, field by field. Replacing the whole section instead
  ## would mean `.configureAxis(labelAngle = 45)` silently dropped the theme's
  ## axis colours.
  result = base
  for name, r, o in fieldPairs(result, over):
    when name == "isSet":
      discard
    elif o is Opt:
      if o.isSome: r = o
    elif o is string:
      if o.len > 0: r = o
    elif o is bool:
      if o: r = o
    elif o is JsonNode:
      if o != nil: r = o
    else:
      {.error: "mergeSection: unhandled config field '" & name & "'".}
  result.isSet = base.isSet or over.isSet

proc merge(base, over: Config): Config =
  ## Field-by-field, with `over` winning wherever it set something.
  result = base
  result.isSet = base.isSet or over.isSet
  result.axis = mergeSection(base.axis, over.axis)
  result.legend = mergeSection(base.legend, over.legend)
  result.view = mergeSection(base.view, over.view)
  result.title = mergeSection(base.title, over.title)
  result.mark = mergeSection(base.mark, over.mark)
  if over.background.len > 0: result.background = over.background
  if over.font.len > 0: result.font = over.font
  if over.categoryScheme.len > 0: result.categoryScheme = over.categoryScheme
  if over.raw != nil: result.raw = over.raw

proc applyTheme*(c: Chart): Chart =
  ## Fold the active theme in underneath the chart's own config.
  if active.len == 0 or active notin registry: return c
  result = c
  result.config = merge(registry[active], c.config)

# The two themes worth shipping: one that strips Vega-Lite's default chrome,
# and one for dark backgrounds.
registerTheme("clean", Config(
  isSet: true,
  view: ViewConfig(isSet: true, noStroke: true),
  axis: AxisConfig(isSet: true, domain: false, ticks: false,
                   gridColor: "#e6e6e6", labelFontSize: 11.0,
                   titleFontSize: 12.0)))

registerTheme("dark", Config(
  isSet: true,
  background: "#1e1e1e",
  view: ViewConfig(isSet: true, noStroke: true),
  axis: AxisConfig(isSet: true, labelColor: "#cccccc", titleColor: "#eeeeee",
                   gridColor: "#333333", domainColor: "#555555"),
  legend: LegendConfig(isSet: true, labelColor: "#cccccc",
                       titleColor: "#eeeeee"),
  title: TitleConfig(isSet: true, color: "#eeeeee")))
