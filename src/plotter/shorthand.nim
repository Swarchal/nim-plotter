## Altair's shorthand strings.
##
## ```
## field            a bare column name
## field:Q          column name with an explicit type
## mean(sales):Q    an aggregate
## count()          an aggregate with no field
## yearmonth(date)  a time unit
## ```
##
## Type codes are `Q`/`N`/`O`/`T` or the full names. A `:` inside a field
## name is escaped `\:`; a `.` (which Vega-Lite treats as a nested-field
## separator) is passed through untouched, so escape it as Vega-Lite wants.
##
## The `converter` at the bottom is what lets `encode(x = "mean(sales):Q")`
## and `encode(x = X("sales", aggregate = agMean))` both typecheck against
## one parameter. Consequence, and it is a real constraint: **no proc in
## this library may be overloaded on both `string` and `Encoding`.**

import std/strutils
import ./types

proc parseFieldType*(s: string): FieldType =
  case s.toLowerAscii
  of "q", "quantitative": ftQuantitative
  of "n", "nominal": ftNominal
  of "o", "ordinal": ftOrdinal
  of "t", "temporal": ftTemporal
  else:
    raise newException(ValueError,
      "unknown field type '" & s & "' — expected Q, N, O or T")

proc splitType(s: string): tuple[body, typeCode: string] =
  ## Split on the last unescaped `:`.
  var i = s.high
  while i > 0:
    if s[i] == ':' and s[i - 1] != '\\':
      return (s[0 ..< i], s[i + 1 .. ^1])
    dec i
  (s, "")

proc unescape(s: string): string =
  result = newStringOfCap(s.len)
  var i = 0
  while i < s.len:
    if s[i] == '\\' and i + 1 < s.len and s[i + 1] == ':':
      result.add(':')
      inc i, 2
    else:
      result.add(s[i])
      inc i

proc applyShorthand*(e: var Encoding, s: string) =
  ## Parse `s` into `e`, leaving anything the shorthand does not mention
  ## alone — so explicit arguments to `X(...)` win over what the string says
  ## only where the string is silent.
  if s.len == 0: return
  let (body, typeCode) = splitType(s)
  if typeCode.len > 0:
    e.fieldType = parseFieldType(typeCode)

  let open = body.find('(')
  if open >= 0:
    if not body.endsWith(')'):
      raise newException(ValueError,
        "malformed shorthand '" & s & "' — unbalanced parenthesis")
    let fn = body[0 ..< open]
    let inner = body[open + 1 ..< body.high]
    let agg = parseAggregate(fn)
    if agg != agNone:
      e.aggregate = agg
    elif isTimeUnit(fn):
      e.timeUnit = fn
    else:
      raise newException(ValueError,
        "unknown function '" & fn & "' in shorthand '" & s &
        "' — expected an aggregate or a time unit")
    e.field = unescape(inner)
  else:
    e.field = unescape(body)

proc parseShorthand*(s: string): Encoding =
  ## A field encoding described by `s`. An empty string gives the `ekEmpty`
  ## sentinel, which is how `encode` tells an unset channel from a set one.
  if s.len == 0: return Encoding()
  result = Encoding(kind: ekField)
  applyShorthand(result, s)

converter toEncoding*(s: string): Encoding = parseShorthand(s)
