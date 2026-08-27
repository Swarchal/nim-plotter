## Vega-Lite backend: turns a `Chart` into a spec.
##
## Pure — no I/O, no external tools, no globals. This is the part that must
## be right, so it stays callable from a test without a toolchain. Writing
## the result anywhere is `plotter/render`'s job.

import std/[json, tables]
import ./types
import ./themes

const
  vegaLiteSchema* = "https://vega.github.io/schema/vega-lite/v5.json"

# ----------------------------------------------------------------- utils ----

proc mergeInto(node, raw: JsonNode) =
  ## Deep-merge `raw` over `node`; raw wins. This is the escape hatch that
  ## makes it acceptable to type only a subset of the schema.
  if raw == nil or raw.kind != JObject: return
  for key, val in raw:
    if node.hasKey(key) and node[key].kind == JObject and val.kind == JObject:
      mergeInto(node[key], val)
    else:
      node[key] = val

proc put(node: JsonNode, key: string, o: Opt[bool]) =
  if o.isSome: node[key] = newJBool(o.get)

proc put(node: JsonNode, key: string, o: Opt[float]) =
  if o.isSome: node[key] = newJFloat(o.get)

proc put(node: JsonNode, key: string, o: Opt[int]) =
  if o.isSome: node[key] = newJInt(o.get)

proc put(node: JsonNode, key, s: string) =
  if s.len > 0: node[key] = newJString(s)

proc toJson*(x: Value): JsonNode =
  case x.kind
  of vkNull: newJNull()
  of vkNumber: newJFloat(x.num)
  of vkString: newJString(x.str)
  of vkBool: newJBool(x.bval)

proc toJson(xs: seq[Value]): JsonNode =
  result = newJArray()
  for x in xs: result.add(toJson(x))

proc toJson(xs: seq[float]): JsonNode =
  result = newJArray()
  for x in xs: result.add(newJFloat(x))

proc toValues*(df: DataFrame): JsonNode =
  ## The frame as an array of row objects — Vega-Lite's inline data format.
  result = newJArray()
  for i in 0 ..< df.len:
    var row = newJObject()
    for col in df.columns:
      row[col.name] = toJson(col.values[i])
    result.add(row)

# ------------------------------------------------------------ sub-objects ---

proc toJson(m: Mark): JsonNode =
  ## A bare string when nothing but the kind is set, an object otherwise.
  ## Vega-Lite accepts both; matching Altair keeps specs comparable.
  var o = newJObject()
  o.put("filled", m.filled)
  o.put("color", m.color)
  o.put("fill", m.fill)
  o.put("stroke", m.stroke)
  o.put("size", m.size)
  o.put("opacity", m.opacity)
  o.put("strokeWidth", m.strokeWidth)
  if m.strokeDash.len > 0: o["strokeDash"] = toJson(m.strokeDash)
  o.put("point", m.point)
  o.put("interpolate", m.interpolate)
  o.put("tooltip", m.tooltip)
  o.put("align", m.align)
  o.put("baseline", m.baseline)
  o.put("dx", m.dx)
  o.put("dy", m.dy)
  o.put("fontSize", m.fontSize)
  o.put("clip", m.clip)
  mergeInto(o, m.raw)
  if o.len == 0:
    return newJString(markName(m.kind))
  result = newJObject()
  result["type"] = newJString(markName(m.kind))
  for key, val in o: result[key] = val

proc toJson(b: BinDef): JsonNode =
  if b.binned: return newJString("binned")
  var o = newJObject()
  o.put("maxbins", b.maxbins)
  o.put("step", b.step)
  if b.extent.len > 0: o["extent"] = toJson(b.extent)
  o.put("nice", b.nice)
  mergeInto(o, b.raw)
  if o.len == 0: newJBool(true) else: o

proc toJson(s: SortDef): JsonNode =
  case s.kind
  of sortUnset: nil
  of sortNull: newJNull()
  of sortAscending: newJString("ascending")
  of sortDescending: newJString("descending")
  of sortArray: toJson(s.values)
  of sortField:
    if s.op == agNone:
      # The channel-shorthand form Altair emits: "-y" / "y".
      newJString((if s.descending: "-" else: "") & s.field)
    else:
      %*{"field": s.field, "op": aggName(s.op),
         "order": (if s.descending: "descending" else: "ascending")}

proc toJson(s: ScaleDef): JsonNode =
  result = newJObject()
  result.put("type", scaleTypeName(s.scaleType))
  if s.domain.len > 0: result["domain"] = toJson(s.domain)
  result.put("domainMin", s.domainMin)
  result.put("domainMax", s.domainMax)
  if s.range.len > 0: result["range"] = toJson(s.range)
  result.put("scheme", s.scheme)
  result.put("zero", s.zero)
  result.put("nice", s.nice)
  result.put("reverse", s.reverse)
  result.put("clamp", s.clamp)
  result.put("padding", s.padding)
  result.put("exponent", s.exponent)
  result.put("base", s.base)
  mergeInto(result, s.raw)

proc toJson(a: AxisDef): JsonNode =
  if a.hidden: return newJNull()
  result = newJObject()
  if a.hideTitle: result["title"] = newJNull()
  elif a.title.isSome: result["title"] = newJString(a.title.get)
  result.put("format", a.format)
  result.put("labelAngle", a.labelAngle)
  result.put("labelFontSize", a.labelFontSize)
  result.put("titleFontSize", a.titleFontSize)
  result.put("grid", a.grid)
  result.put("ticks", a.ticks)
  result.put("labels", a.labels)
  if a.values.len > 0: result["values"] = toJson(a.values)
  result.put("orient", a.orient)
  result.put("tickCount", a.tickCount)
  mergeInto(result, a.raw)

proc toJson(l: LegendDef): JsonNode =
  if l.hidden: return newJNull()
  result = newJObject()
  if l.hideTitle: result["title"] = newJNull()
  elif l.title.isSome: result["title"] = newJString(l.title.get)
  result.put("orient", l.orient)
  result.put("direction", l.direction)
  result.put("columns", l.columns)
  result.put("symbolType", l.symbolType)
  result.put("format", l.format)
  mergeInto(result, l.raw)

# -------------------------------------------------------------- encodings ---

proc toJson(c: Chart, e: Encoding): JsonNode =
  result = newJObject()
  case e.kind
  of ekEmpty: return result
  of ekValue:
    result["value"] = toJson(e.value)
    mergeInto(result, e.raw)
    return result
  of ekDatum:
    result["datum"] = toJson(e.value)
  of ekRepeat:
    result["field"] = %*{"repeat": e.repeat}
  of ekField:
    # A bare aggregate — count() — has no field, and that is legal.
    if e.field.len > 0: result["field"] = newJString(e.field)

  if e.kind != ekDatum or e.fieldType != ftAuto:
    result["type"] = newJString(fieldTypeName(c.resolvedType(e)))
  if e.aggregate != agNone:
    result["aggregate"] = newJString(aggName(e.aggregate))
  result.put("timeUnit", e.timeUnit)
  if e.bin.enabled: result["bin"] = toJson(e.bin)

  let sort = toJson(e.sort)
  if sort != nil: result["sort"] = sort

  case e.stack
  of stkUnset: discard
  of stkNone: result["stack"] = newJNull()
  of stkZero: result["stack"] = newJString("zero")
  of stkNormalize: result["stack"] = newJString("normalize")
  of stkCenter: result["stack"] = newJString("center")

  if e.hideTitle: result["title"] = newJNull()
  elif e.title.isSome: result["title"] = newJString(e.title.get)

  if e.scale.isSet: result["scale"] = toJson(e.scale)
  if e.axis.isSet: result["axis"] = toJson(e.axis)
  if e.legend.isSet: result["legend"] = toJson(e.legend)
  mergeInto(result, e.raw)

proc toJson(c: Chart, channel: EncodingChannel, es: seq[Encoding]): JsonNode =
  ## Array-valued channels (tooltip, detail, order) emit an array as soon as
  ## more than one field is bound.
  if es.len == 1:
    return toJson(c, es[0])
  result = newJArray()
  for e in es: result.add(toJson(c, e))

# ------------------------------------------------------------------ spec ----

proc toJson(d: DataSource): JsonNode

proc toJson(a: AxisConfig): JsonNode =
  if not a.isSet: return nil
  result = newJObject()
  result.put("labelFontSize", a.labelFontSize)
  result.put("titleFontSize", a.titleFontSize)
  result.put("labelAngle", a.labelAngle)
  result.put("labelColor", a.labelColor)
  result.put("titleColor", a.titleColor)
  result.put("gridColor", a.gridColor)
  result.put("domainColor", a.domainColor)
  result.put("labelFont", a.labelFont)
  result.put("titleFont", a.titleFont)
  result.put("grid", a.grid)
  result.put("domain", a.domain)
  result.put("ticks", a.ticks)
  result.put("labels", a.labels)
  mergeInto(result, a.raw)

proc toJson(l: LegendConfig): JsonNode =
  if not l.isSet: return nil
  result = newJObject()
  result.put("orient", l.orient)
  result.put("direction", l.direction)
  result.put("labelColor", l.labelColor)
  result.put("titleColor", l.titleColor)
  result.put("labelFontSize", l.labelFontSize)
  result.put("titleFontSize", l.titleFontSize)
  mergeInto(result, l.raw)

proc toJson(vw: ViewConfig): JsonNode =
  if not vw.isSet: return nil
  result = newJObject()
  if vw.noStroke: result["stroke"] = newJNull()
  else: result.put("stroke", vw.stroke)
  result.put("fill", vw.fill)
  result.put("continuousWidth", vw.continuousWidth)
  result.put("continuousHeight", vw.continuousHeight)
  result.put("discreteWidth", vw.discreteWidth)
  result.put("discreteHeight", vw.discreteHeight)
  mergeInto(result, vw.raw)

proc toJson(t: TitleConfig): JsonNode =
  if not t.isSet: return nil
  result = newJObject()
  result.put("fontSize", t.fontSize)
  result.put("font", t.font)
  result.put("color", t.color)
  result.put("anchor", t.anchor)
  result.put("align", t.align)
  mergeInto(result, t.raw)

proc toJson(m: MarkConfig): JsonNode =
  if not m.isSet: return nil
  result = newJObject()
  result.put("color", m.color)
  result.put("fill", m.fill)
  result.put("stroke", m.stroke)
  result.put("opacity", m.opacity)
  result.put("size", m.size)
  result.put("strokeWidth", m.strokeWidth)
  result.put("filled", m.filled)
  mergeInto(result, m.raw)

proc toJson*(c: Config): JsonNode =
  if not c.isSet: return nil
  result = newJObject()
  for (key, node) in {"axis": toJson(c.axis), "legend": toJson(c.legend),
                      "view": toJson(c.view), "title": toJson(c.title),
                      "mark": toJson(c.mark)}:
    if node != nil and node.len > 0: result[key] = node
  result.put("background", c.background)
  result.put("font", c.font)
  if c.categoryScheme.len > 0:
    result["range"] = %*{"category": {"scheme": c.categoryScheme}}
  mergeInto(result, c.raw)
  if result.len == 0: return nil

proc toJson(fs: seq[AggregatedField]): JsonNode =
  result = newJArray()
  for f in fs:
    var o = newJObject()
    o["op"] = newJString(aggName(f.op))
    o.put("field", f.field)
    o["as"] = newJString(f.to)
    result.add(o)

proc toJson(ss: seq[SortField]): JsonNode =
  result = newJArray()
  for s in ss:
    result.add(%*{"field": s.field,
                  "order": (if s.descending: "descending" else: "ascending")})

proc names(xs: seq[string]): JsonNode =
  result = newJArray()
  for x in xs: result.add(newJString(x))

proc toJson(t: Transform): JsonNode =
  if t.kind == tkRaw: return t.node
  result = newJObject()
  case t.kind
  of tkRaw: discard
  of tkFilter:
    result["filter"] = newJString(t.predicate)
  of tkCalculate:
    result["calculate"] = newJString(t.calculate)
    result["as"] = newJString(t.calculateAs)
  of tkAggregate, tkJoinAggregate:
    result[(if t.kind == tkAggregate: "aggregate" else: "joinaggregate")] =
      toJson(t.fields)
    if t.groupby.len > 0: result["groupby"] = names(t.groupby)
  of tkWindow:
    var ws = newJArray()
    for w in t.windows:
      var o = newJObject()
      o["op"] = newJString(w.op)
      o.put("field", w.field)
      o.put("param", w.param)
      o["as"] = newJString(w.to)
      ws.add(o)
    result["window"] = ws
    if t.windowGroupby.len > 0: result["groupby"] = names(t.windowGroupby)
    if t.windowSort.len > 0: result["sort"] = toJson(t.windowSort)
    if t.frameStart.isSome or t.frameEnd.isSome:
      # An unset bound is an unbounded one, which Vega-Lite spells `null`.
      var f = newJArray()
      f.add(if t.frameStart.isSome: newJInt(t.frameStart.get) else: newJNull())
      f.add(if t.frameEnd.isSome: newJInt(t.frameEnd.get) else: newJNull())
      result["frame"] = f
    result.put("ignorePeers", t.ignorePeers)
  of tkBin:
    result["bin"] = toJson(t.binSpec)
    result["field"] = newJString(t.binField)
    result["as"] = newJString(t.binAs)
  of tkTimeUnit:
    result["timeUnit"] = newJString(t.unit)
    result["field"] = newJString(t.unitField)
    result["as"] = newJString(t.unitAs)
  of tkFold:
    result["fold"] = names(t.foldFields)
    if t.foldAs.len > 0: result["as"] = names(t.foldAs)
  of tkPivot:
    result["pivot"] = newJString(t.pivotField)
    result["value"] = newJString(t.pivotValue)
    if t.pivotGroupby.len > 0: result["groupby"] = names(t.pivotGroupby)
    result.put("limit", t.pivotLimit)
  of tkFlatten:
    result["flatten"] = names(t.flattenFields)
    if t.flattenAs.len > 0: result["as"] = names(t.flattenAs)
  of tkLookup:
    result["lookup"] = newJString(t.lookupKey)
    var f = newJObject()
    let d = toJson(t.lookupFrom)
    if d != nil:
      for key, val in d: f[key] = val
    f["key"] = newJString(t.lookupFromKey)
    if t.lookupFields.len > 0: f["fields"] = names(t.lookupFields)
    result["from"] = f
    if t.lookupAs.len > 0: result["as"] = names(t.lookupAs)
    result.put("default", t.lookupDefault)
  of tkSample:
    result["sample"] = newJInt(t.sampleSize)
  of tkDensity:
    result["density"] = newJString(t.onField)
    if t.fitGroupby.len > 0: result["groupby"] = names(t.fitGroupby)
    result.put("bandwidth", t.bandwidth)
    if t.extent.len > 0: result["extent"] = toJson(t.extent)
    result.put("steps", t.steps)
    result.put("counts", t.counts)
  of tkRegression, tkLoess:
    let key = if t.kind == tkRegression: "regression" else: "loess"
    result[key] = newJString(t.onField)
    result["on"] = newJString(t.asField)
    if t.fitGroupby.len > 0: result["groupby"] = names(t.fitGroupby)
    result.put("method", t.fitMethod)
    result.put("bandwidth", t.bandwidth)
    if t.extent.len > 0: result["extent"] = toJson(t.extent)

proc commonData(children: seq[Chart]): DataSource =
  ## The data every child shares, if they all share one — which lets a layer
  ## of three marks over the same frame inline the rows once instead of
  ## three times.
  if children.len == 0: return DataSource()
  result = children[0].data
  if result.kind == dsNone: return DataSource()
  for c in children[1 .. ^1]:
    if c.data != result: return DataSource()

proc toJson(d: DataSource): JsonNode =
  case d.kind
  of dsNone: return nil
  of dsInline: return %*{"values": toValues(d.frame)}
  of dsNamed: return %*{"name": d.name}
  of dsUrl:
    result = newJObject()
    result["url"] = newJString(d.url)
    if d.format.len > 0:
      result["format"] = %*{"type": d.format}

proc toNode(c: Chart, topLevel: bool, suppressData = false,
            suppressSize = false): JsonNode =
  result = newJObject()
  if topLevel:
    result["$schema"] = newJString(vegaLiteSchema)
  result.put("description", c.description)
  result.put("title", c.title)

  var ownData = c.data
  if ownData.kind == dsNone:
    # A composite has no data of its own; take it from the children, so a
    # layer over one frame inlines the rows once and a facet holds the data
    # its sub-plots share.
    case c.kind
    of skLayer, skHConcat, skVConcat: ownData = commonData(c.children)
    of skFacet, skRepeat: ownData = commonData(c.spec)
    of skUnit: discard
  let hoisted = ownData.kind != dsNone and ownData != c.data
  if not suppressData:
    let d = toJson(ownData)
    if d != nil: result["data"] = d

  if c.transforms.len > 0:
    var ts = newJArray()
    for t in c.transforms: ts.add(toJson(t))
    result["transform"] = ts

  case c.kind
  of skUnit:
    # Facet channels size their sub-plots, not the outer container, so a
    # faceted spec must not carry top-level width/height.
    if c.hasSize and not c.isFaceted and not suppressSize:
      result["width"] = newJInt(c.width)
      result["height"] = newJInt(c.height)
    result["mark"] = toJson(c.mark)
    var enc = newJObject()
    for channel, es in c.encodings:
      if es.len > 0:
        enc[channelName(channel)] = toJson(c, channel, es)
    if enc.len > 0:
      result["encoding"] = enc
  of skLayer, skHConcat, skVConcat:
    # A layer sizes itself and its children must not; concatenated charts
    # each keep their own size.
    let isLayer = c.kind == skLayer
    if isLayer and c.hasSize and not suppressSize:
      result["width"] = newJInt(c.width)
      result["height"] = newJInt(c.height)
    var kids = newJArray()
    for child in c.children:
      kids.add(toNode(child, topLevel = false,
                      suppressData = hoisted or child.data.kind == dsNone,
                      suppressSize = isLayer))
    result[(case c.kind
            of skLayer: "layer"
            of skHConcat: "hconcat"
            else: "vconcat")] = kids
  of skFacet:
    # Facet encodings infer their field type from the data, which a facet
    # node holds only after hoisting it out of the spec inside it.
    var dataCtx = c
    dataCtx.data = ownData
    var f = newJObject()
    if c.facet.facet.kind != ekEmpty:
      f = toJson(dataCtx, c.facet.facet)
      # `columns` is a sibling of `facet`, not part of the field definition.
      if c.facet.columns.isSome:
        result["columns"] = newJInt(c.facet.columns.get)
    else:
      if c.facet.row.kind != ekEmpty: f["row"] = toJson(dataCtx, c.facet.row)
      if c.facet.column.kind != ekEmpty:
        f["column"] = toJson(dataCtx, c.facet.column)
    result["facet"] = f
    # The data belongs to the facet, never to the spec inside it.
    result["spec"] = toNode(c.spec[0], topLevel = false, suppressData = true)
  of skRepeat:
    var r = newJObject()
    if c.facet.rowFields.len > 0:
      r["row"] = %c.facet.rowFields
    if c.facet.columnFields.len > 0:
      r["column"] = %c.facet.columnFields
    result["repeat"] = r
    result["spec"] = toNode(c.spec[0], topLevel = false, suppressData = true)

  if c.resolve != nil: result["resolve"] = c.resolve
  let cfg = toJson(c.config)
  if cfg != nil: result["config"] = cfg
  mergeInto(result, c.raw)

proc toSpec*(c: Chart): JsonNode =
  ## The chart as a Vega-Lite spec. Pure for a fixed theme — the active
  ## theme (see `plotter/themes`) is the one piece of global state it reads.
  toNode(applyTheme(c), topLevel = true)

proc toJson*(c: Chart, indent = 2): string =
  ## The spec as JSON text.
  if indent <= 0: $toSpec(c) else: pretty(toSpec(c), indent)
