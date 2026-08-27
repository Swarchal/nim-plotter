## The chart grammar: marks, encodings, scales, and the `Chart` that binds
## them to data.
##
## Nothing here knows about Vega-Lite — a `Chart` is a plain value object
## describing *what* to draw. Emitting a spec is `plotter/vegalite`'s job.
## The object model is a curated subset of a very large schema; every node
## carries a `raw: JsonNode` escape hatch that is deep-merged over the
## generated node at emit time, so a missing field never blocks anyone.

import std/[json, strutils, tables]
import ./opt
import ./data

export opt, data
# `encodings` is an OrderedTable, so callers need its accessors to inspect
# a chart without importing std/tables themselves.
export tables

type
  MarkKind* = enum
    mkArc
    mkArea
    mkBar
    mkBoxplot
    mkCircle
    mkErrorBand
    mkErrorBar
    mkImage
    mkLine
    mkPoint
    mkRect
    mkRule
    mkSquare
    mkText
    mkTick
    mkTrail

  Mark* = object
    ## A mark and its static properties. Emitted as the bare string
    ## `"bar"` when nothing but `kind` is set, and as an object otherwise —
    ## Vega-Lite accepts both, and matching Altair here keeps specs
    ## comparable.
    kind*: MarkKind
    filled*: Opt[bool]
    color*, fill*, stroke*: string
    size*, opacity*, strokeWidth*: Opt[float]
    strokeDash*: seq[float]
    point*: Opt[bool]
    interpolate*: string
    tooltip*: Opt[bool]
    align*, baseline*: string
    dx*, dy*: Opt[float]
    fontSize*: Opt[float]
    clip*: Opt[bool]
    raw*: JsonNode

  EncodingChannel* = enum
    ## Named `EncodingChannel` rather than `Channel`, which collides with
    ## `system.Channel`. Enum order is emission order.
    chX, chY, chX2, chY2, chXError, chYError
    chTheta, chTheta2, chRadius, chRadius2
    chLongitude, chLatitude, chLongitude2, chLatitude2
    chColor, chFill, chStroke
    chOpacity, chFillOpacity, chStrokeOpacity, chStrokeWidth, chStrokeDash
    chSize, chShape, chAngle
    chText, chTooltip, chHref, chUrl, chDescription
    chOrder, chDetail, chKey
    chFacet, chRow, chColumn

  Aggregate* = enum
    agNone, agCount, agSum, agMean, agAverage, agMedian, agMin, agMax
    agDistinct, agValid, agMissing, agStdev, agStdevp, agVariance
    agVariancep, agQ1, agQ3, agCi0, agCi1, agArgmin, agArgmax

  ScaleType* = enum
    scAuto, scLinear, scLog, scPow, scSqrt, scSymlog, scTime, scUtc
    scOrdinal, scBand, scPoint, scQuantile, scQuantize, scThreshold
    scSequential

  SortKind* = enum
    sortUnset      ## omit the key
    sortNull       ## `"sort": null` — leave the data order alone
    sortAscending
    sortDescending
    sortField      ## sort one channel by another, e.g. `"-y"`
    sortArray      ## an explicit ordering of domain values

  StackKind* = enum
    stkUnset, stkZero, stkNormalize, stkCenter, stkNone

  EncodingKind* = enum
    ekEmpty        ## the sentinel for "this channel was not given"
    ekField        ## bound to a data column (or a bare aggregate like count())
    ekValue        ## a literal visual value, e.g. colour "red"
    ekDatum        ## a literal data value, positioned on the scale
    ekRepeat       ## `{"repeat": "column"}` inside a repeat spec

  BinDef* = object
    enabled*: bool
    binned*: bool          ## data is already binned
    maxbins*: Opt[int]
    step*: Opt[float]
    extent*: seq[float]
    nice*: Opt[bool]
    raw*: JsonNode

  SortDef* = object
    case kind*: SortKind
    of sortField:
      field*: string
      op*: Aggregate
      descending*: bool
    of sortArray:
      values*: seq[Value]
    else: discard

  ScaleDef* = object
    isSet*: bool
    scaleType*: ScaleType
    domain*: seq[Value]
    domainMin*, domainMax*: Opt[float]
    range*: seq[Value]
    scheme*: string
    zero*, nice*, reverse*, clamp*: Opt[bool]
    padding*, exponent*, base*: Opt[float]
    raw*: JsonNode

  AxisDef* = object
    isSet*: bool
    hidden*: bool          ## `"axis": null`
    title*: Opt[string]
    hideTitle*: bool       ## `"title": null`
    format*: string
    labelAngle*: Opt[float]
    labelFontSize*, titleFontSize*: Opt[float]
    grid*, ticks*, labels*: Opt[bool]
    values*: seq[Value]
    orient*: string
    tickCount*: Opt[int]
    raw*: JsonNode

  LegendDef* = object
    isSet*: bool
    hidden*: bool          ## `"legend": null`
    title*: Opt[string]
    hideTitle*: bool
    orient*: string
    direction*: string
    columns*: Opt[int]
    symbolType*: string
    format*: string
    raw*: JsonNode

  Encoding* = object
    ## One channel binding. `ekEmpty` is the default, which is what lets
    ## `encode` take three dozen optional parameters and tell which were
    ## actually passed.
    fieldType*: FieldType
    title*: Opt[string]
    hideTitle*: bool       ## `"title": null`
    aggregate*: Aggregate
    timeUnit*: string
    bin*: BinDef
    sort*: SortDef
    stack*: StackKind
    scale*: ScaleDef
    axis*: AxisDef
    legend*: LegendDef
    raw*: JsonNode
    case kind*: EncodingKind
    of ekField: field*: string
    of ekValue, ekDatum: value*: Value
    of ekRepeat: repeat*: string
    of ekEmpty: discard

  TransformKind* = enum
    tkFilter, tkCalculate, tkAggregate, tkJoinAggregate, tkWindow
    tkBin, tkTimeUnit, tkFold, tkPivot, tkFlatten, tkLookup
    tkSample, tkDensity, tkRegression, tkLoess
    tkRaw          ## anything not modelled above

  AggregatedField* = object
    op*: Aggregate
    field*: string
    to*: string

  WindowField* = object
    ## `op` is a window operation (`row_number`, `rank`, `lag`, …) or the
    ## name of an aggregate.
    op*: string
    field*: string
    param*: Opt[float]
    to*: string

  SortField* = object
    field*: string
    descending*: bool

  Transform* = object
    ## Transforms apply in the order they were added, which is semantically
    ## significant — Vega-Lite pipes each into the next.
    case kind*: TransformKind
    of tkFilter:
      predicate*: string
    of tkCalculate:
      calculate*, calculateAs*: string
    of tkAggregate, tkJoinAggregate:
      fields*: seq[AggregatedField]
      groupby*: seq[string]
    of tkWindow:
      windows*: seq[WindowField]
      windowGroupby*: seq[string]
      windowSort*: seq[SortField]
      frameStart*, frameEnd*: Opt[int]
      ignorePeers*: Opt[bool]
    of tkBin:
      binSpec*: BinDef
      binField*, binAs*: string
    of tkTimeUnit:
      unit*, unitField*, unitAs*: string
    of tkFold:
      foldFields*, foldAs*: seq[string]
    of tkPivot:
      pivotField*, pivotValue*: string
      pivotGroupby*: seq[string]
      pivotLimit*: Opt[int]
    of tkFlatten:
      flattenFields*, flattenAs*: seq[string]
    of tkLookup:
      lookupKey*: string
      lookupFrom*: DataSource
      lookupFromKey*: string
      lookupFields*, lookupAs*: seq[string]
      lookupDefault*: string
    of tkSample:
      sampleSize*: int
    of tkDensity, tkRegression, tkLoess:
      onField*, asField*: string       ## regression/loess: y and x
      fitGroupby*: seq[string]
      bandwidth*: Opt[float]
      fitMethod*: string
      extent*: seq[float]
      steps*: Opt[int]
      counts*: Opt[bool]
    of tkRaw:
      node*: JsonNode

  AxisConfig* = object
    isSet*: bool
    labelFontSize*, titleFontSize*, labelAngle*: Opt[float]
    labelColor*, titleColor*, gridColor*, domainColor*: string
    labelFont*, titleFont*: string
    grid*, domain*, ticks*, labels*: Opt[bool]
    raw*: JsonNode

  LegendConfig* = object
    isSet*: bool
    orient*, direction*, labelColor*, titleColor*: string
    labelFontSize*, titleFontSize*: Opt[float]
    raw*: JsonNode

  ViewConfig* = object
    isSet*: bool
    stroke*: string
    noStroke*: bool          ## `"stroke": null` — drop the plot border
    fill*: string
    continuousWidth*, continuousHeight*: Opt[int]
    discreteWidth*, discreteHeight*: Opt[int]
    raw*: JsonNode

  TitleConfig* = object
    isSet*: bool
    fontSize*: Opt[float]
    font*, color*, anchor*, align*: string
    raw*: JsonNode

  MarkConfig* = object
    isSet*: bool
    color*, fill*, stroke*: string
    opacity*, size*, strokeWidth*: Opt[float]
    filled*: Opt[bool]
    raw*: JsonNode

  Config* = object
    ## Chart-wide defaults. Everything a theme sets, and what
    ## `.configureAxis(...)` and friends write to.
    isSet*: bool
    axis*: AxisConfig
    legend*: LegendConfig
    view*: ViewConfig
    title*: TitleConfig
    mark*: MarkConfig
    background*, font*: string
    categoryScheme*: string      ## config.range.category
    raw*: JsonNode

  SpecKind* = enum
    skUnit, skLayer, skHConcat, skVConcat, skFacet, skRepeat

  FacetDef* = object
    row*, column*, facet*: Encoding
    columns*: Opt[int]
    rowFields*, columnFields*: seq[string]   ## for skRepeat

  Chart* = object
    ## A figure. Recursive through `seq`, which Nim permits, so the tree
    ## keeps value semantics — every builder returns a copy.
    data*: DataSource
    title*, description*: string
    width*, height*: int
    hasSize*: bool
    transforms*: seq[Transform]
    config*: Config
    resolve*: JsonNode
    raw*: JsonNode
    case kind*: SpecKind
    of skUnit:
      mark*: Mark
      encodings*: OrderedTable[EncodingChannel, seq[Encoding]]
    of skLayer, skHConcat, skVConcat:
      children*: seq[Chart]
    of skFacet, skRepeat:
      facet*: FacetDef
      spec*: seq[Chart]    ## exactly one; a seq keeps the recursion legal

const
  defaultWidth* = 640
  defaultHeight* = 480

  arrayChannels* = {chTooltip, chDetail, chOrder}
    ## Channels Vega-Lite lets you bind more than one field to.

# ------------------------------------------------------------ inspection ----

proc enc*(c: Chart, channel: EncodingChannel): Encoding =
  ## The (first) encoding on a channel, or an `ekEmpty` one if unbound.
  if c.kind == skUnit and channel in c.encodings and
     c.encodings[channel].len > 0:
    c.encodings[channel][0]
  else:
    Encoding()

proc encAll*(c: Chart, channel: EncodingChannel): seq[Encoding] =
  if c.kind == skUnit and channel in c.encodings: c.encodings[channel] else: @[]

proc hasEnc*(c: Chart, channel: EncodingChannel): bool =
  c.kind == skUnit and channel in c.encodings and c.encodings[channel].len > 0

proc hasData*(c: Chart): bool =
  c.data.kind != dsNone

proc isFaceted*(c: Chart): bool =
  ## Facet channels size their sub-plots, not the outer container, so a
  ## faceted unit spec must not carry top-level width/height.
  c.kind == skUnit and
    (chFacet in c.encodings or chRow in c.encodings or chColumn in c.encodings)

proc resolvedType*(c: Chart, e: Encoding): FieldType =
  ## The field type a backend should emit: the declared one, or inferred
  ## from the data when left as `ftAuto`.
  if e.fieldType != ftAuto: return e.fieldType
  if e.bin.enabled or e.aggregate notin {agNone, agArgmin, agArgmax}:
    return ftQuantitative
  if e.timeUnit.len > 0: return ftTemporal
  case e.kind
  of ekField:
    if e.field.len == 0: return ftQuantitative
    if e.field in c.data: return inferType(c.data[e.field])
    ftQuantitative
  of ekDatum:
    if e.value.kind == vkNumber: ftQuantitative else: ftNominal
  else:
    ftQuantitative

proc `$`*(c: Chart): string =
  case c.kind
  of skUnit:
    var chans: seq[string]
    for ch, es in c.encodings:
      for e in es:
        let what =
          case e.kind
          of ekField: e.field
          of ekValue, ekDatum: $e.value
          of ekRepeat: "repeat:" & e.repeat
          of ekEmpty: ""
        chans.add($ch & "=" & what)
    "Chart(" & $c.mark.kind & ", " & $c.data.len & " rows, " &
      chans.join(", ") & ")"
  of skLayer: "Layer(" & $c.children.len & " charts)"
  of skHConcat: "HConcat(" & $c.children.len & " charts)"
  of skVConcat: "VConcat(" & $c.children.len & " charts)"
  of skFacet: "Facet(" & $c.spec.len & ")"
  of skRepeat: "Repeat(" & $c.spec.len & ")"

# ------------------------------------------------------- canonical names ----
# The canonical spelling of each enum, shared by the shorthand parser (which
# reads them) and the emitter (which writes them), so the two can never drift.

proc aggName*(a: Aggregate): string =
  case a
  of agNone: ""
  of agCount: "count"
  of agSum: "sum"
  of agMean: "mean"
  of agAverage: "average"
  of agMedian: "median"
  of agMin: "min"
  of agMax: "max"
  of agDistinct: "distinct"
  of agValid: "valid"
  of agMissing: "missing"
  of agStdev: "stdev"
  of agStdevp: "stdevp"
  of agVariance: "variance"
  of agVariancep: "variancep"
  of agQ1: "q1"
  of agQ3: "q3"
  of agCi0: "ci0"
  of agCi1: "ci1"
  of agArgmin: "argmin"
  of agArgmax: "argmax"

proc parseAggregate*(s: string): Aggregate =
  ## `agNone` when `s` names no aggregate — callers use that to fall through
  ## to the time-unit check.
  for a in Aggregate:
    if a != agNone and aggName(a) == s: return a
  agNone

const timeUnits* = [
  "year", "quarter", "month", "week", "date", "day", "dayofyear", "hours",
  "minutes", "seconds", "milliseconds",
  "yearquarter", "yearquartermonth", "yearmonth", "yearmonthdate",
  "yearmonthdatehours", "yearmonthdatehoursminutes",
  "yearmonthdatehoursminutesseconds", "yearweek", "yeardayofyear",
  "quartermonth", "monthdate", "monthdatehours", "weekday", "weeksdayhours",
  "dayhours", "dayhoursminutes", "hoursminutes", "hoursminutesseconds",
  "minutesseconds", "secondsmilliseconds"]

proc isTimeUnit*(s: string): bool =
  ## `utc`/`local` prefixes are accepted, as Vega-Lite does.
  var base = s
  for prefix in ["utc", "local"]:
    if base.len > prefix.len and base.startsWith(prefix):
      base = base[prefix.len .. ^1]
      break
  base in timeUnits

proc scaleTypeName*(t: ScaleType): string =
  case t
  of scAuto: ""
  of scLinear: "linear"
  of scLog: "log"
  of scPow: "pow"
  of scSqrt: "sqrt"
  of scSymlog: "symlog"
  of scTime: "time"
  of scUtc: "utc"
  of scOrdinal: "ordinal"
  of scBand: "band"
  of scPoint: "point"
  of scQuantile: "quantile"
  of scQuantize: "quantize"
  of scThreshold: "threshold"
  of scSequential: "sequential"

proc fieldTypeName*(t: FieldType): string =
  case t
  of ftAuto, ftQuantitative: "quantitative"
  of ftNominal: "nominal"
  of ftOrdinal: "ordinal"
  of ftTemporal: "temporal"

proc markName*(m: MarkKind): string =
  case m
  of mkArc: "arc"
  of mkArea: "area"
  of mkBar: "bar"
  of mkBoxplot: "boxplot"
  of mkCircle: "circle"
  of mkErrorBand: "errorband"
  of mkErrorBar: "errorbar"
  of mkImage: "image"
  of mkLine: "line"
  of mkPoint: "point"
  of mkRect: "rect"
  of mkRule: "rule"
  of mkSquare: "square"
  of mkText: "text"
  of mkTick: "tick"
  of mkTrail: "trail"

proc channelName*(c: EncodingChannel): string =
  ## The Vega-Lite spelling — identical to the enum name minus the `ch`
  ## prefix, with the first letter lowercased. Also the parameter name
  ## `encode` uses for that channel.
  let s = $c
  result = s[2 .. ^1]
  result[0] = result[0].toLowerAscii

# -------------------------------------------------------------- equality ----
# Nim's structural `==` refuses to walk variant objects, so the case objects
# in the grammar each need one written by hand.

proc `==`*(a, b: SortDef): bool =
  if a.kind != b.kind: return false
  case a.kind
  of sortField: a.field == b.field and a.op == b.op and
                a.descending == b.descending
  of sortArray: a.values == b.values
  else: true

proc `==`*(a, b: Encoding): bool =
  if a.kind != b.kind: return false
  let sameVariant =
    case a.kind
    of ekField: a.field == b.field
    of ekValue, ekDatum: a.value == b.value
    of ekRepeat: a.repeat == b.repeat
    of ekEmpty: true
  sameVariant and
    a.fieldType == b.fieldType and a.title == b.title and
    a.hideTitle == b.hideTitle and a.aggregate == b.aggregate and
    a.timeUnit == b.timeUnit and a.bin == b.bin and a.sort == b.sort and
    a.stack == b.stack and a.scale == b.scale and a.axis == b.axis and
    a.legend == b.legend and a.raw == b.raw
