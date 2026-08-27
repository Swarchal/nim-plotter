## Getting real data into a `DataFrame`.
##
## `dataFrame(col(...), col(...))` is the primitive, but nobody wants to
## write it. The important one here is `toDataFrame(seq[T])` for an object
## or tuple type — the Nim analogue of handing Altair a pandas DataFrame.

import std/[algorithm, parsecsv, streams, strutils, tables]
import ./data

proc toValue*[T](x: T): Value =
  ## One cell. Anything without a JSON scalar equivalent is stringified,
  ## which is what a chart wants for enums and dates-as-text anyway.
  when T is Value: x
  elif T is bool: v(x)
  elif T is SomeFloat: v(x.float)
  elif T is SomeInteger: v(x.int)
  elif T is string: v(x)
  elif T is enum: v($x)
  else: v($x)

proc toDataFrame*[T: object | tuple](xs: openArray[T]): DataFrame =
  ## One column per field, named after the field, in declaration order.
  ##
  ## ```nim
  ## type Penguin = object
  ##   species: string
  ##   billLength, flipperLength: float
  ##
  ## chart(toDataFrame(penguins)).markPoint()
  ##   .encode(x = "billLength:Q", y = "flipperLength:Q", color = "species:N")
  ## ```
  var proto: T
  for fname, fval in proto.fieldPairs:
    result.columns.add(DataColumn(name: fname))
  for x in xs:
    var i = 0
    for fname, fval in x.fieldPairs:
      result.columns[i].values.add(toValue(fval))
      inc i

proc toDataFrame*[T](t: Table[string, seq[T]] |
                     OrderedTable[string, seq[T]]): DataFrame =
  ## Column name to column. A plain `Table` has no order, so its keys are
  ## sorted to keep the emitted spec deterministic; an `OrderedTable` keeps
  ## the order it was built in.
  var names: seq[string]
  for name in t.keys: names.add(name)
  when t is Table[string, seq[T]]:
    names.sort()
  for name in names:
    var c = DataColumn(name: name)
    for x in t[name]: c.values.add(toValue(x))
    result.columns.add(c)
  # Same invariant `dataFrame` enforces: a ragged frame has no meaning as a
  # row-oriented table, and the failure is unreadable if it surfaces later.
  for c in result.columns:
    if c.values.len != result.columns[0].values.len:
      raise newException(ValueError,
        "all columns must be the same length: '" & c.name & "' has " &
        $c.values.len & ", '" & result.columns[0].name & "' has " &
        $result.columns[0].values.len)

# -------------------------------------------------------------------- csv ---

proc sniff(values: seq[string]): seq[Value] =
  ## Decide a column's type from all of its values at once: every non-empty
  ## cell has to agree, otherwise it stays text. An empty cell is null.
  var allNumeric = true
  var allBool = true
  for s in values:
    if s.len == 0: continue
    try:
      discard parseFloat(s)
    except ValueError:
      allNumeric = false
    if s.toLowerAscii notin ["true", "false"]:
      allBool = false
    if not allNumeric and not allBool: break
  for s in values:
    if s.len == 0: result.add(nullValue())
    elif allBool: result.add(v(s.toLowerAscii == "true"))
    elif allNumeric: result.add(v(parseFloat(s)))
    else: result.add(v(s))

proc parseCsvStream(s: Stream, filename: string, separator: char): DataFrame =
  if s == nil:
    raise newException(IOError, "cannot open '" & filename & "'")
  var p: CsvParser
  p.open(s, filename, separator = separator)
  defer: p.close()
  p.readHeaderRow()
  var raw: seq[seq[string]] = newSeq[seq[string]](p.headers.len)
  var line = 1
  while p.readRow():
    inc line
    if p.row.len != p.headers.len:
      raise newException(ValueError,
        filename & ":" & $line & ": expected " & $p.headers.len &
        " fields, got " & $p.row.len)
    for i in 0 ..< p.headers.len:
      raw[i].add(p.row[i])
  for i, name in p.headers:
    result.columns.add(DataColumn(name: name, values: sniff(raw[i])))

proc readCsv*(path: string, separator = ','): DataFrame =
  ## Read a CSV with a header row, sniffing each column's type.
  parseCsvStream(newFileStream(path, fmRead), path, separator)

proc parseCsv*(text: string, separator = ','): DataFrame =
  ## The same, from a string already in memory.
  parseCsvStream(newStringStream(text), "<string>", separator)
