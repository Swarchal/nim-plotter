## The tabular data model: values, columns, frames.
##
## Deliberately knows nothing about charts — this is the layer a chart's
## encodings address by column name.

type
  ValueKind* = enum
    ## The cell types a `Column` can hold. Mirrors the JSON scalar types,
    ## which is what any spec-based backend ultimately needs.
    vkNull
    vkNumber
    vkString
    vkBool

  Value* = object
    case kind*: ValueKind
    of vkNull: discard
    of vkNumber: num*: float
    of vkString: str*: string
    of vkBool: bval*: bool

  DataColumn* = object
    ## A named vertical slice of a `DataFrame`.
    name*: string
    values*: seq[Value]

  DataFrame* = object
    ## Tidy, long-format data: every row is one observation, every column a
    ## variable. Encodings address columns by name.
    columns*: seq[DataColumn]

  FieldType* = enum
    ## How a column should be interpreted by the scale machinery.
    ## `ftAuto` defers to `inferType`.
    ftAuto
    ftQuantitative
    ftNominal
    ftOrdinal
    ftTemporal

  Series* = object
    ## Convenience input shape: a named pair of parallel x/y vectors.
    ## Melted into long form by `longFrame` before it reaches a chart.
    name*: string
    xs*: seq[float]
    ys*: seq[float]

# ---------------------------------------------------------------- values ----

proc v*(x: float): Value = Value(kind: vkNumber, num: x)
proc v*(x: int): Value = Value(kind: vkNumber, num: x.float)
proc v*(x: string): Value = Value(kind: vkString, str: x)
proc v*(x: bool): Value = Value(kind: vkBool, bval: x)
proc nullValue*(): Value = Value(kind: vkNull)

proc `$`*(x: Value): string =
  case x.kind
  of vkNull: "null"
  of vkNumber: $x.num
  of vkString: x.str
  of vkBool: $x.bval

# ------------------------------------------------------------- dataframe ----

proc col*(name: string, xs: seq[float]): DataColumn =
  result = DataColumn(name: name)
  for x in xs: result.values.add(v(x))

proc col*(name: string, xs: seq[int]): DataColumn =
  result = DataColumn(name: name)
  for x in xs: result.values.add(v(x))

proc col*(name: string, xs: seq[string]): DataColumn =
  result = DataColumn(name: name)
  for x in xs: result.values.add(v(x))

proc col*(name: string, xs: seq[bool]): DataColumn =
  result = DataColumn(name: name)
  for x in xs: result.values.add(v(x))

proc dataFrame*(cols: varargs[DataColumn]): DataFrame =
  ## All columns must be the same length — a ragged frame has no meaning as
  ## a row-oriented table, and every backend consumes rows.
  for c in cols:
    doAssert c.values.len == cols[0].values.len,
      "all columns must be the same length: '" & c.name & "' has " &
      $c.values.len & ", '" & cols[0].name & "' has " & $cols[0].values.len
    result.columns.add(c)

proc len*(df: DataFrame): int =
  ## Number of rows.
  if df.columns.len == 0: 0 else: df.columns[0].values.len

proc contains*(df: DataFrame, name: string): bool =
  for c in df.columns:
    if c.name == name: return true

proc `[]`*(df: DataFrame, name: string): DataColumn =
  for c in df.columns:
    if c.name == name: return c
  raise newException(KeyError, "no such column: " & name)

proc inferType*(c: DataColumn): FieldType =
  ## Numbers are quantitative, everything else nominal. Deliberately dumb —
  ## dates and ordinals need to be declared, since they are not inferable
  ## from a string column without guessing.
  for x in c.values:
    if x.kind == vkNull: continue
    return if x.kind == vkNumber: ftQuantitative else: ftNominal
  ftNominal

# ---------------------------------------------------------------- series ----

proc newSeries*(xs, ys: seq[float], name = ""): Series =
  doAssert xs.len == ys.len, "xs and ys must be the same length"
  Series(name: name, xs: xs, ys: ys)

proc longFrame*(series: openArray[Series], xName = "x", yName = "y",
                groupName = "series"): DataFrame =
  ## Melt parallel x/y vectors into one long-format frame with a grouping
  ## column, which is how multi-series charts are expressed in a grammar:
  ## one table, colour mapped to the group.
  var xs, ys, group: seq[Value]
  for i, s in series:
    # `newSeries` checks this, but `Series` has public fields and can be
    # built directly; the alternative is an IndexDefect further down.
    doAssert s.xs.len == s.ys.len,
      "xs and ys must be the same length: series " & $i & " has " &
      $s.xs.len & " xs and " & $s.ys.len & " ys"
    let name = if s.name.len > 0: s.name else: "series " & $(i + 1)
    for j in 0 ..< s.xs.len:
      xs.add(v(s.xs[j]))
      ys.add(v(s.ys[j]))
      group.add(v(name))
  dataFrame(DataColumn(name: xName, values: xs),
            DataColumn(name: yName, values: ys),
            DataColumn(name: groupName, values: group))

# ----------------------------------------------------------- value lists ----

proc vals*(xs: varargs[float]): seq[Value] =
  ## Build a `seq[Value]` for places a spec takes a heterogeneous list —
  ## scale domains and ranges, axis tick values, sort orders. Needed because
  ## Nim converters do not apply elementwise inside an `@[...]` literal.
  for x in xs: result.add(v(x))

proc vals*(xs: varargs[string]): seq[Value] =
  for x in xs: result.add(v(x))

proc vals*(xs: varargs[int]): seq[Value] =
  for x in xs: result.add(v(x))

proc `==`*(a, b: Value): bool =
  ## Nim's structural `==` cannot walk a variant object, so every case
  ## object in the grammar needs one of these written by hand.
  if a.kind != b.kind: return false
  case a.kind
  of vkNull: true
  of vkNumber: a.num == b.num
  of vkString: a.str == b.str
  of vkBool: a.bval == b.bval

# ----------------------------------------------------------- data source ----

type
  DataSourceKind* = enum
    dsNone     ## no data of its own — inherits from an enclosing spec
    dsInline   ## rows embedded in the spec
    dsUrl      ## fetched by the renderer
    dsNamed    ## a named dataset supplied at runtime

  DataSource* = object
    case kind*: DataSourceKind
    of dsInline: frame*: DataFrame
    of dsUrl: url*, format*: string
    of dsNamed: name*: string
    of dsNone: discard

proc inlineData*(df: DataFrame): DataSource =
  DataSource(kind: dsInline, frame: df)

proc urlData*(url: string, format = ""): DataSource =
  ## Let the renderer fetch the data instead of inlining it — the way to
  ## keep a spec small when the frame is large.
  DataSource(kind: dsUrl, url: url, format: format)

proc namedData*(name: string): DataSource =
  DataSource(kind: dsNamed, name: name)

proc len*(d: DataSource): int =
  if d.kind == dsInline: d.frame.len else: 0

proc contains*(d: DataSource, name: string): bool =
  d.kind == dsInline and name in d.frame

proc `[]`*(d: DataSource, name: string): DataColumn =
  if d.kind != dsInline:
    raise newException(KeyError, "this chart has no inline data")
  d.frame[name]

proc `==`*(a, b: DataSource): bool =
  if a.kind != b.kind: return false
  case a.kind
  of dsNone: true
  of dsInline: a.frame == b.frame
  of dsUrl: a.url == b.url and a.format == b.format
  of dsNamed: a.name == b.name
