## The Altair-shaped front end: `chart(...).markPoint(...).encode(x = ..., y = ...)`.
##
## Every builder takes a `Chart` and returns a copy, so charts compose by
## chaining and a partially-built chart is safe to reuse as a base.
##
## `encode` and the `X`/`Y`/`Color`/… constructors are generated from
## `EncodingChannel` — three dozen near-identical routines are not worth
## hand-writing, and generating them means a new channel is one enum entry.

import std/[json, macros, strutils, tables]
import ./types
import ./adapters
import ./shorthand

export shorthand   # the string -> Encoding converter must reach the caller

# --------------------------------------------------------------- helpers ----

proc parseSort*(s: string): SortDef =
  ## `""`, `"ascending"`, `"descending"`, `"null"`, or a channel/field name
  ## optionally prefixed with `-` for descending — Altair's `sort='-y'`.
  case s.toLowerAscii
  of "": SortDef(kind: sortUnset)
  of "ascending", "asc": SortDef(kind: sortAscending)
  of "descending", "desc": SortDef(kind: sortDescending)
  of "null", "none": SortDef(kind: sortNull)
  else:
    if s.startsWith("-"):
      SortDef(kind: sortField, field: s[1 .. ^1], descending: true)
    else:
      SortDef(kind: sortField, field: s, descending: false)

proc parseStack*(s: string): StackKind =
  case s.toLowerAscii
  of "": stkUnset
  of "zero", "true": stkZero
  of "normalize": stkNormalize
  of "center": stkCenter
  of "none", "null", "false": stkNone
  else:
    raise newException(ValueError,
      "unknown stack '" & s & "' — expected zero, normalize, center or none")

# ---------------------------------------------------------- sub-objects -----

proc Scale*(scaleType = scAuto, domain: seq[Value] = @[],
            domainMin = Opt[float](), domainMax = Opt[float](),
            range: seq[Value] = @[], scheme = "", zero = Opt[bool](),
            nice = Opt[bool](), reverse = Opt[bool](), clamp = Opt[bool](),
            padding = Opt[float](), exponent = Opt[float](),
            base = Opt[float](), raw: JsonNode = nil): ScaleDef =
  ScaleDef(isSet: true, scaleType: scaleType, domain: domain,
           domainMin: domainMin, domainMax: domainMax, range: range,
           scheme: scheme, zero: zero, nice: nice, reverse: reverse,
           clamp: clamp, padding: padding, exponent: exponent, base: base,
           raw: raw)

proc Axis*(title = Opt[string](), format = "", labelAngle = Opt[float](),
           labelFontSize = Opt[float](), titleFontSize = Opt[float](),
           grid = Opt[bool](), ticks = Opt[bool](), labels = Opt[bool](),
           values: seq[Value] = @[], orient = "", tickCount = Opt[int](),
           raw: JsonNode = nil): AxisDef =
  AxisDef(isSet: true, title: title, format: format, labelAngle: labelAngle,
          labelFontSize: labelFontSize, titleFontSize: titleFontSize,
          grid: grid, ticks: ticks, labels: labels, values: values,
          orient: orient, tickCount: tickCount, raw: raw)

proc noAxis*(): AxisDef =
  ## `"axis": null` — draw the encoding but no axis at all.
  AxisDef(isSet: true, hidden: true)

proc Legend*(title = Opt[string](), orient = "", direction = "",
             columns = Opt[int](), symbolType = "", format = "",
             raw: JsonNode = nil): LegendDef =
  LegendDef(isSet: true, title: title, orient: orient, direction: direction,
            columns: columns, symbolType: symbolType, format: format, raw: raw)

proc noLegend*(): LegendDef =
  ## `"legend": null` — colour the marks but hide the key.
  LegendDef(isSet: true, hidden: true)

proc Bin*(maxbins = Opt[int](), step = Opt[float](), extent: seq[float] = @[],
          nice = Opt[bool](), raw: JsonNode = nil): BinDef =
  BinDef(enabled: true, maxbins: maxbins, step: step, extent: extent,
         nice: nice, raw: raw)

proc binned*(): BinDef =
  ## The data is already binned; Vega-Lite should not bin it again.
  BinDef(enabled: true, binned: true)

converter toBin*(b: bool): BinDef =
  ## So `bin = true` works, as it does in Altair.
  BinDef(enabled: b)

# ------------------------------------------------------------- encodings ----

proc field*(shorthand = "", fieldType = ftAuto, title = Opt[string](),
            hideTitle = false, aggregate = agNone, timeUnit = "",
            bin = BinDef(), sort = "", stack = "", scale = ScaleDef(),
            axis = AxisDef(), legend = LegendDef(),
            raw: JsonNode = nil): Encoding =
  ## The one real encoding constructor. `X`, `Y`, `Color` and the rest are
  ## generated aliases of it — an `Encoding` does not carry its own channel,
  ## the `encode` parameter it is passed to decides that.
  ##
  ## Explicit arguments win over the shorthand string wherever both speak.
  result = Encoding(kind: ekField)
  applyShorthand(result, shorthand)
  if fieldType != ftAuto: result.fieldType = fieldType
  if aggregate != agNone: result.aggregate = aggregate
  if timeUnit.len > 0: result.timeUnit = timeUnit
  result.title = title
  result.hideTitle = hideTitle
  result.bin = bin
  result.sort = parseSort(sort)
  result.stack = parseStack(stack)
  result.scale = scale
  result.axis = axis
  result.legend = legend
  result.raw = raw

proc value*(x: Value): Encoding = Encoding(kind: ekValue, value: x)
proc value*(x: string): Encoding = Encoding(kind: ekValue, value: v(x))
proc value*(x: float): Encoding = Encoding(kind: ekValue, value: v(x))
proc value*(x: int): Encoding = Encoding(kind: ekValue, value: v(x))
proc value*(x: bool): Encoding = Encoding(kind: ekValue, value: v(x))

proc datum*(x: float): Encoding = Encoding(kind: ekDatum, value: v(x))
proc datum*(x: int): Encoding = Encoding(kind: ekDatum, value: v(x))
proc datum*(x: string): Encoding = Encoding(kind: ekDatum, value: v(x))

proc Rep*(what: string, fieldType = ftAuto): Encoding =
  ## `{"repeat": "column"}` — a field reference inside a repeat spec.
  ##
  ## The repeated field is only known at render time, so its type cannot be
  ## inferred from the data; give `fieldType` for anything but a quantitative
  ## column, as Altair's `alt.repeat(...)` always requires.
  Encoding(kind: ekRepeat, repeat: what, fieldType: fieldType)

macro genChannelCtors(): untyped =
  ## `X(...)`, `Y(...)`, `Color(...)` … as aliases of `field`, so code ported
  ## from Altair reads the same.
  var src = ""
  for ch in EncodingChannel:
    var name = channelName(ch)
    name[0] = name[0].toUpperAscii
    src.add("proc " & name & "*(shorthand = \"\", fieldType = ftAuto, " &
            "title = Opt[string](), hideTitle = false, aggregate = agNone, " &
            "timeUnit = \"\", bin = BinDef(), sort = \"\", stack = \"\", " &
            "scale = ScaleDef(), axis = AxisDef(), legend = LegendDef(), " &
            "raw: JsonNode = nil): Encoding =\n" &
            "  field(shorthand, fieldType, title, hideTitle, aggregate, " &
            "timeUnit, bin, sort, stack, scale, axis, legend, raw)\n\n")
  parseStmt(src)

genChannelCtors()

# --------------------------------------------------- chainable modifiers ----
# Altair 5's `alt.X("a:Q").scale(zero = false).axis(grid = false)`. Each of
# these takes an `Encoding` as its first parameter and returns a modified
# copy, so UFCS flattens what would otherwise be constructors nested inside a
# keyword argument. The `string` -> `Encoding` converter fires on a dot-call
# receiver too, which is why `"a:Q".scale(...)` needs no `X(...)` wrapper.
#
# None of these may ever be overloaded on `string`: that is exactly what
# `shorthand.nim` says would destroy `toEncoding` for the whole library, and
# the converter is what makes the bare-string head of the chain work.
#
# Every setter *folds* its arguments into what the encoding already carries,
# so `.scale(zero = false).scale(scheme = "viridis")` keeps both keys. The
# exceptions are `sort` and `stack`, which name a single spec key and so
# replace it.

proc mergeRaw(dst: var JsonNode, src: JsonNode) =
  ## Later `raw` keys win, and the result is a copy — `raw` is a ref, and
  ## every other builder here has value semantics.
  if src == nil: return
  if dst == nil or dst.kind != JObject or src.kind != JObject:
    dst = copy(src)
    return
  var merged = copy(dst)
  for key, node in src: merged[key] = copy(node)
  dst = merged

proc scale*(e: Encoding, scaleType = scAuto, domain: seq[Value] = @[],
            domainMin = Opt[float](), domainMax = Opt[float](),
            range: seq[Value] = @[], scheme = "", zero = Opt[bool](),
            nice = Opt[bool](), reverse = Opt[bool](), clamp = Opt[bool](),
            padding = Opt[float](), exponent = Opt[float](),
            base = Opt[float](), raw: JsonNode = nil): Encoding =
  ## `"x:Q".scale(zero = false)` — the chained spelling of
  ## `X("x:Q", scale = Scale(zero = false))`.
  result = e
  result.scale.isSet = true
  if scaleType != scAuto: result.scale.scaleType = scaleType
  if domain.len > 0: result.scale.domain = domain
  if domainMin.isSome: result.scale.domainMin = domainMin
  if domainMax.isSome: result.scale.domainMax = domainMax
  if range.len > 0: result.scale.range = range
  if scheme.len > 0: result.scale.scheme = scheme
  if zero.isSome: result.scale.zero = zero
  if nice.isSome: result.scale.nice = nice
  if reverse.isSome: result.scale.reverse = reverse
  if clamp.isSome: result.scale.clamp = clamp
  if padding.isSome: result.scale.padding = padding
  if exponent.isSome: result.scale.exponent = exponent
  if base.isSome: result.scale.base = base
  mergeRaw(result.scale.raw, raw)

proc axis*(e: Encoding, title = Opt[string](), hideTitle = false, format = "",
           labelAngle = Opt[float](), labelFontSize = Opt[float](),
           titleFontSize = Opt[float](), grid = Opt[bool](),
           ticks = Opt[bool](), labels = Opt[bool](),
           values: seq[Value] = @[], orient = "", tickCount = Opt[int](),
           hidden = false, raw: JsonNode = nil): Encoding =
  ## `hidden = true` is `"axis": null` — the chained `axis = noAxis()`.
  ## `title = ""` is an empty axis title, `hideTitle = true` is
  ## `"title": null`, and saying neither leaves the key out.
  result = e
  result.axis.isSet = true
  if hidden: result.axis.hidden = true
  if title.isSome: result.axis.title = title
  if hideTitle: result.axis.hideTitle = true
  if format.len > 0: result.axis.format = format
  if labelAngle.isSome: result.axis.labelAngle = labelAngle
  if labelFontSize.isSome: result.axis.labelFontSize = labelFontSize
  if titleFontSize.isSome: result.axis.titleFontSize = titleFontSize
  if grid.isSome: result.axis.grid = grid
  if ticks.isSome: result.axis.ticks = ticks
  if labels.isSome: result.axis.labels = labels
  if values.len > 0: result.axis.values = values
  if orient.len > 0: result.axis.orient = orient
  if tickCount.isSome: result.axis.tickCount = tickCount
  mergeRaw(result.axis.raw, raw)

proc legend*(e: Encoding, title = Opt[string](), hideTitle = false,
             orient = "", direction = "", columns = Opt[int](),
             symbolType = "", format = "", hidden = false,
             raw: JsonNode = nil): Encoding =
  ## `hidden = true` is `"legend": null` — the chained `legend = noLegend()`.
  result = e
  result.legend.isSet = true
  if hidden: result.legend.hidden = true
  if title.isSome: result.legend.title = title
  if hideTitle: result.legend.hideTitle = true
  if orient.len > 0: result.legend.orient = orient
  if direction.len > 0: result.legend.direction = direction
  if columns.isSome: result.legend.columns = columns
  if symbolType.len > 0: result.legend.symbolType = symbolType
  if format.len > 0: result.legend.format = format
  mergeRaw(result.legend.raw, raw)

proc title*(e: Encoding, t: string): Encoding =
  ## The channel's own title. `""` is an empty title, which is a different
  ## spec from an absent one — and from `noTitle()`, which is `null`.
  result = e
  result.title = opt(t)
  result.hideTitle = false

proc noTitle*(e: Encoding): Encoding =
  ## `"title": null` — no label for this channel at all.
  result = e
  result.title = unset[string]()
  result.hideTitle = true

proc bin*(e: Encoding, maxbins = Opt[int](), step = Opt[float](),
          extent: seq[float] = @[], nice = Opt[bool](), binned = false,
          raw: JsonNode = nil): Encoding =
  ## `.bin()` on its own is `bin = true`; `binned = true` says the data
  ## arrives already binned.
  result = e
  result.bin.enabled = true
  if binned: result.bin.binned = true
  if maxbins.isSome: result.bin.maxbins = maxbins
  if step.isSome: result.bin.step = step
  if extent.len > 0: result.bin.extent = extent
  if nice.isSome: result.bin.nice = nice
  mergeRaw(result.bin.raw, raw)

proc sort*(e: Encoding, order: string): Encoding =
  ## `"ascending"`, `"descending"`, `"null"` (leave the data order alone),
  ## or a channel/field name with an optional `-` for descending — the same
  ## strings `sort =` takes. Replaces any previous sort.
  result = e
  result.sort = parseSort(order)

proc sort*(e: Encoding, values: seq[Value]): Encoding =
  ## An explicit domain order: `.sort(vals("Jan", "Feb", "Mar"))`.
  result = e
  result.sort = SortDef(kind: sortArray, values: values)

proc sort*(e: Encoding, def: SortDef): Encoding =
  ## For a sort this library's strings cannot spell — sorting by another
  ## field under an aggregate, say.
  result = e
  result.sort = def

proc stack*(e: Encoding, how: string): Encoding =
  ## `"zero"`, `"normalize"`, `"center"` or `"none"`. `"none"` emits
  ## `"stack": null`, which is not the same as leaving it unset.
  result = e
  result.stack = parseStack(how)

# ----------------------------------------------------------------- chart ----

proc chart*(data: DataFrame, title = "", description = "",
            width = defaultWidth, height = defaultHeight): Chart =
  ## Start a chart from a frame.
  Chart(kind: skUnit, data: inlineData(data), title: title,
        description: description, width: width, height: height, hasSize: true,
        mark: Mark(kind: mkPoint),
        encodings: initOrderedTable[EncodingChannel, seq[Encoding]]())

proc chart*[T: object | tuple](data: openArray[T], title = "",
                               description = "", width = defaultWidth,
                               height = defaultHeight): Chart =
  ## Start a chart from a sequence of objects or tuples — one column per
  ## field. The usual way in.
  chart(toDataFrame(data), title, description, width, height)

proc chart*(url: string, title = "", description = "",
            width = defaultWidth, height = defaultHeight): Chart =
  ## Start a chart from a URL or path the renderer will fetch, rather than
  ## inlining the rows. The format is taken from the extension.
  let format =
    if url.endsWith(".csv"): "csv"
    elif url.endsWith(".tsv"): "tsv"
    else: ""
  result = chart(DataFrame(), title, description, width, height)
  result.data = urlData(url, format)

proc withData*(c: Chart, data: DataSource): Chart =
  ## Swap a chart's data, keeping everything else — the natural way to reuse
  ## one chart definition across several datasets.
  result = c
  result.data = data

proc properties*(c: Chart, width = Opt[int](), height = Opt[int](),
                 title = "", description = ""): Chart =
  ## Altair's `.properties(...)`.
  result = c
  if width.isSome or height.isSome:
    # A composite starts out without a size, so setting one dimension has to
    # give the other a sensible value before the pair can be emitted.
    if not result.hasSize:
      if result.width == 0: result.width = defaultWidth
      if result.height == 0: result.height = defaultHeight
      result.hasSize = true
    if width.isSome: result.width = width.get
    if height.isSome: result.height = height.get
  if title.len > 0: result.title = title
  if description.len > 0: result.description = description

proc addTransform(c: Chart, t: Transform): Chart =
  result = c
  result.transforms.add(t)

proc transform*(c: Chart, node: JsonNode): Chart =
  ## Append a transform this library does not model — the escape hatch.
  c.addTransform(Transform(kind: tkRaw, node: node))

proc mark*(c: Chart, m: MarkKind): Chart =
  ## Set the mark kind without touching its properties.
  result = c
  doAssert result.kind == skUnit, "only a unit chart has a mark"
  result.mark.kind = m

proc setMark(c: Chart, m: MarkKind, filled: Opt[bool], color, fill,
             stroke: string, size, opacity, strokeWidth: Opt[float],
             strokeDash: seq[float], point: Opt[bool], interpolate: string,
             tooltip: Opt[bool], align, baseline: string,
             dx, dy, fontSize: Opt[float], clip: Opt[bool],
             raw: JsonNode): Chart =
  result = c
  doAssert result.kind == skUnit, "only a unit chart has a mark"
  result.mark = Mark(kind: m, filled: filled, color: color, fill: fill,
                     stroke: stroke, size: size, opacity: opacity,
                     strokeWidth: strokeWidth, strokeDash: strokeDash,
                     point: point, interpolate: interpolate, tooltip: tooltip,
                     align: align, baseline: baseline, dx: dx, dy: dy,
                     fontSize: fontSize, clip: clip, raw: raw)

macro genMarkBuilders(): untyped =
  ## `markPoint`, `markBar`, `markLine` … — Altair's `mark_*` in camelCase.
  const params =
    "filled = Opt[bool](), color = \"\", fill = \"\", stroke = \"\", " &
    "size = Opt[float](), opacity = Opt[float](), " &
    "strokeWidth = Opt[float](), strokeDash: seq[float] = @[], " &
    "point = Opt[bool](), interpolate = \"\", tooltip = Opt[bool](), " &
    "align = \"\", baseline = \"\", dx = Opt[float](), dy = Opt[float](), " &
    "fontSize = Opt[float](), clip = Opt[bool](), raw: JsonNode = nil"
  const args =
    "filled, color, fill, stroke, size, opacity, strokeWidth, strokeDash, " &
    "point, interpolate, tooltip, align, baseline, dx, dy, fontSize, clip, raw"
  var src = ""
  for m in MarkKind:
    var name = $m
    name = "mark" & name[2 .. ^1]
    src.add("proc " & name & "*(c: Chart, " & params & "): Chart =\n" &
            "  setMark(c, " & $m & ", " & args & ")\n\n")
  parseStmt(src)

genMarkBuilders()

# ---------------------------------------------------------------- encode ----

proc bindChannel*(c: Chart, channel: EncodingChannel, es: seq[Encoding]): Chart =
  result = c
  doAssert result.kind == skUnit, "only a unit chart has encodings"
  result.encodings[channel] = es

macro genEncode(): untyped =
  ## `.encode(x = ..., y = ..., color = ...)` — one optional parameter per
  ## channel, named exactly as Vega-Lite names it. `ekEmpty` (the default)
  ## marks a channel that was not passed.
  var src = "proc encode*(c: Chart"
  for ch in EncodingChannel:
    src.add(",\n    " & channelName(ch) & ": Encoding = Encoding()")
  src.add("): Chart =\n" &
          "  ## Repeated calls merge; a channel given twice keeps the last.\n" &
          "  result = c\n")
  for ch in EncodingChannel:
    src.add("  if " & channelName(ch) & ".kind != ekEmpty: " &
            "result = result.bindChannel(" & $ch & ", @[" &
            channelName(ch) & "])\n")
  parseStmt(src)

genEncode()

proc tooltips*(c: Chart, fields: varargs[Encoding]): Chart =
  ## Vega-Lite lets `tooltip`, `detail` and `order` take a list, and Nim's
  ## converter does not reach inside a `@[...]` literal — hence these.
  c.bindChannel(chTooltip, @fields)

proc details*(c: Chart, fields: varargs[Encoding]): Chart =
  c.bindChannel(chDetail, @fields)

proc orderBy*(c: Chart, fields: varargs[Encoding]): Chart =
  c.bindChannel(chOrder, @fields)

proc noSize*(c: Chart): Chart =
  ## Drop the explicit width/height and let Vega-Lite size the view. Needed
  ## for sub-plots of a composite, and for comparing a spec against Altair's
  ## output, which leaves the size unset by default.
  result = c
  result.hasSize = false

# ----------------------------------------------------------- composition ----
# Altair composes with operators, and Nim can overload all three. `layer`,
# `hconcat` and `vconcat` are the same thing spelled out, for anyone who
# finds `&` cryptic in a language where it usually concatenates strings.

proc layer*(charts: varargs[Chart]): Chart =
  ## Draw charts on top of each other, sharing one pair of axes.
  doAssert charts.len > 0, "layer needs at least one chart"
  result = Chart(kind: skLayer, children: @charts,
                 width: charts[0].width, height: charts[0].height,
                 hasSize: charts[0].hasSize)

proc hconcat*(charts: varargs[Chart]): Chart =
  doAssert charts.len > 0, "hconcat needs at least one chart"
  Chart(kind: skHConcat, children: @charts)

proc vconcat*(charts: varargs[Chart]): Chart =
  doAssert charts.len > 0, "vconcat needs at least one chart"
  Chart(kind: skVConcat, children: @charts)

proc combine(a, b: Chart, kind: static SpecKind): Chart =
  ## `a + b + c` gives one three-child spec, not a nest of two-child ones.
  if a.kind == kind and a.data.kind == dsNone and a.transforms.len == 0:
    result = a
    result.children.add(b)
  else:
    result = Chart(kind: kind, children: @[a, b])
    if kind == skLayer:
      result.width = a.width
      result.height = a.height
      result.hasSize = a.hasSize

proc `+`*(a, b: Chart): Chart = combine(a, b, skLayer)
proc `|`*(a, b: Chart): Chart = combine(a, b, skHConcat)
proc `&`*(a, b: Chart): Chart = combine(a, b, skVConcat)

proc facet*(c: Chart, row = Encoding(), column = Encoding(),
            facet = Encoding(), columns = Opt[int]()): Chart =
  ## Wrap a chart in a facet spec: one small multiple per value.
  ## `facet =` with `columns =` is the wrapped form; `row`/`column` is the
  ## grid form.
  Chart(kind: skFacet, spec: @[c],
        facet: FacetDef(row: row, column: column, facet: facet,
                        columns: columns))

proc repeat*(c: Chart, row: seq[string] = @[],
             column: seq[string] = @[]): Chart =
  ## Repeat a chart across a list of fields, referenced inside it with
  ## `Rep("row")` / `Rep("column")`.
  Chart(kind: skRepeat, spec: @[c],
        facet: FacetDef(rowFields: row, columnFields: column))

proc resolveScale*(c: Chart, color = "", x = "", y = "", size = "",
                   opacity = "", shape = ""): Chart =
  ## `"independent"` or `"shared"` per channel.
  result = c
  # `resolve` is a ref, so it has to be copied to keep the value semantics
  # every other builder has.
  result.resolve = if c.resolve == nil: newJObject() else: copy(c.resolve)
  var node = newJObject()
  for (name, val) in {"color": color, "x": x, "y": y, "size": size,
                      "opacity": opacity, "shape": shape}:
    if val.len > 0: node[name] = newJString(val)
  result.resolve["scale"] = node

proc resolveAxis*(c: Chart, x = "", y = ""): Chart =
  result = c
  # `resolve` is a ref, so it has to be copied to keep the value semantics
  # every other builder has.
  result.resolve = if c.resolve == nil: newJObject() else: copy(c.resolve)
  var node = newJObject()
  if x.len > 0: node["x"] = newJString(x)
  if y.len > 0: node["y"] = newJString(y)
  result.resolve["axis"] = node

proc resolveLegend*(c: Chart, color = "", size = "", shape = ""): Chart =
  result = c
  # `resolve` is a ref, so it has to be copied to keep the value semantics
  # every other builder has.
  result.resolve = if c.resolve == nil: newJObject() else: copy(c.resolve)
  var node = newJObject()
  for (name, val) in {"color": color, "size": size, "shape": shape}:
    if val.len > 0: node[name] = newJString(val)
  result.resolve["legend"] = node

# ------------------------------------------------------------ transforms ----
# Altair's `transform_*`, in camelCase. They append in call order, which is
# semantically significant: Vega-Lite pipes each into the next.

proc transformFilter*(c: Chart, predicate: string): Chart =
  ## `predicate` is a Vega expression. `expr(...)` builds one from Nim
  ## syntax if you would rather have the compiler check it.
  c.addTransform(Transform(kind: tkFilter, predicate: predicate))

proc transformCalculate*(c: Chart, name, expression: string): Chart =
  ## A new column from an expression: `transformCalculate("kpl",
  ## "datum.mpg * 0.425")`. Call it repeatedly for several columns.
  c.addTransform(Transform(kind: tkCalculate, calculate: expression,
                           calculateAs: name))

proc agg*(op: Aggregate, field = "", to = ""): AggregatedField =
  ## One output of an aggregate transform. `to` defaults to a Vega-Lite-ish
  ## `op_field` name when left empty.
  AggregatedField(op: op, field: field,
                  to: (if to.len > 0: to
                       elif field.len > 0: aggName(op) & "_" & field
                       else: aggName(op)))

proc transformAggregate*(c: Chart, fields: seq[AggregatedField],
                         groupby: seq[string] = @[]): Chart =
  c.addTransform(Transform(kind: tkAggregate, fields: fields, groupby: groupby))

proc transformJoinAggregate*(c: Chart, fields: seq[AggregatedField],
                             groupby: seq[string] = @[]): Chart =
  ## Like `transformAggregate`, but the result is joined back onto every row
  ## rather than replacing them.
  c.addTransform(Transform(kind: tkJoinAggregate, fields: fields,
                           groupby: groupby))

proc win*(op: string, field = "", to = "", param = Opt[float]()): WindowField =
  WindowField(op: op, field: field, to: (if to.len > 0: to else: op),
              param: param)

proc sortField*(field: string, descending = false): SortField =
  SortField(field: field, descending: descending)

proc transformWindow*(c: Chart, windows: seq[WindowField],
                      groupby: seq[string] = @[],
                      sort: seq[SortField] = @[],
                      frameStart = Opt[int](), frameEnd = Opt[int](),
                      ignorePeers = Opt[bool]()): Chart =
  ## Running totals, ranks, lags. `frameStart`/`frameEnd` unset means an
  ## unbounded frame in that direction.
  c.addTransform(Transform(kind: tkWindow, windows: windows,
                           windowGroupby: groupby, windowSort: sort,
                           frameStart: frameStart, frameEnd: frameEnd,
                           ignorePeers: ignorePeers))

proc transformBin*(c: Chart, field, to: string, bin = BinDef()): Chart =
  let spec = if bin.enabled: bin else: Bin()
  c.addTransform(Transform(kind: tkBin, binSpec: spec, binField: field,
                           binAs: to))

proc transformTimeUnit*(c: Chart, unit, field, to: string): Chart =
  c.addTransform(Transform(kind: tkTimeUnit, unit: unit, unitField: field,
                           unitAs: to))

proc transformFold*(c: Chart, fields: seq[string],
                    to: seq[string] = @[]): Chart =
  ## Wide to long. `to` names the key and value columns, defaulting to
  ## `["key", "value"]`.
  c.addTransform(Transform(kind: tkFold, foldFields: fields, foldAs: to))

proc transformPivot*(c: Chart, field, value: string,
                     groupby: seq[string] = @[],
                     limit = Opt[int]()): Chart =
  ## Long to wide — the inverse of fold.
  c.addTransform(Transform(kind: tkPivot, pivotField: field,
                           pivotValue: value, pivotGroupby: groupby,
                           pivotLimit: limit))

proc transformFlatten*(c: Chart, fields: seq[string],
                       to: seq[string] = @[]): Chart =
  c.addTransform(Transform(kind: tkFlatten, flattenFields: fields,
                           flattenAs: to))

proc transformLookup*(c: Chart, key: string, source: DataSource,
                      fromKey: string, fields: seq[string] = @[],
                      to: seq[string] = @[], default = ""): Chart =
  ## Join columns in from a second dataset.
  c.addTransform(Transform(kind: tkLookup, lookupKey: key,
                           lookupFrom: source, lookupFromKey: fromKey,
                           lookupFields: fields, lookupAs: to,
                           lookupDefault: default))

proc transformSample*(c: Chart, size: int): Chart =
  c.addTransform(Transform(kind: tkSample, sampleSize: size))

proc transformDensity*(c: Chart, field: string, groupby: seq[string] = @[],
                       bandwidth = Opt[float](), extent: seq[float] = @[],
                       steps = Opt[int](), counts = Opt[bool]()): Chart =
  ## A kernel density estimate, emitted as `value`/`density` columns.
  c.addTransform(Transform(kind: tkDensity, onField: field,
                           fitGroupby: groupby, bandwidth: bandwidth,
                           extent: extent, steps: steps, counts: counts))

proc transformRegression*(c: Chart, y, x: string, groupby: seq[string] = @[],
                          fitMethod = "", extent: seq[float] = @[]): Chart =
  ## A fitted trend line. `fitMethod` is linear, log, exp, pow, quad or poly.
  c.addTransform(Transform(kind: tkRegression, onField: y, asField: x,
                           fitGroupby: groupby, fitMethod: fitMethod,
                           extent: extent))

proc transformLoess*(c: Chart, y, x: string, groupby: seq[string] = @[],
                     bandwidth = Opt[float]()): Chart =
  c.addTransform(Transform(kind: tkLoess, onField: y, asField: x,
                           fitGroupby: groupby, bandwidth: bandwidth))
