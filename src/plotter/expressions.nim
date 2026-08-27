## `expr(datum.price > 100 and datum.origin == "USA")`
##
## The Nim analogue of Altair's `alt.datum.price > 100`, and a
## compile-time-checked one: the argument is ordinary Nim syntax, translated
## to a Vega expression string while it is still an AST. A typo in an
## operator is a compile error rather than a chart that silently renders
## empty.
##
## Field names still are not checked — Vega expressions address data the
## renderer has not seen yet. `transformFilter` also takes a plain string,
## which is the way out for anything this does not translate.

import std/[macros, strutils]

proc quoteVega(s: string): string =
  ## Vega expressions conventionally use single quotes for strings.
  result = "'"
  for ch in s:
    case ch
    of '\'': result.add("\\'")
    of '\\': result.add("\\\\")
    of '\n': result.add("\\n")
    else: result.add(ch)
  result.add('\'')

proc translate(n: NimNode): string =
  case n.kind
  of nnkIdent, nnkSym:
    n.strVal
  of nnkDotExpr:
    translate(n[0]) & "." & n[1].strVal
  of nnkBracketExpr:
    translate(n[0]) & "[" & translate(n[1]) & "]"
  of nnkStrLit:
    quoteVega(n.strVal)
  of nnkIntLit .. nnkUInt64Lit:
    $n.intVal
  of nnkFloatLit .. nnkFloat64Lit:
    $n.floatVal
  of nnkNilLit:
    "null"
  of nnkPar, nnkStmtListExpr:
    if n.len == 1: "(" & translate(n[0]) & ")"
    else: error("expr: cannot translate this expression", n)
  of nnkPrefix:
    let op = n[0].strVal
    let inner = translate(n[1])
    case op
    of "not": "!" & inner
    of "-": "-" & inner
    else:
      error("expr: unsupported prefix operator '" & op & "'", n)
  of nnkInfix:
    let op = n[0].strVal
    if op == "div":
      # Nim's `div` truncates toward zero. Vega only has float `/`, and no
      # `trunc`, so the sign has to be handled explicitly — `floor` alone
      # would round -5 div 2 to -3 instead of -2. Both operands are
      # side-effect free, so repeating them is safe.
      let q = "(" & translate(n[1]) & " / " & translate(n[2]) & ")"
      "(" & q & " < 0 ? ceil" & q & " : floor" & q & ")"
    else:
      let vegaOp =
        case op
        of "and": "&&"
        of "or": "||"
        of "==": "==="
        of "!=": "!=="
        of "mod": "%"
        of "<", ">", "<=", ">=", "+", "-", "*", "/": op
        else:
          error("expr: unsupported operator '" & op & "'", n)
      "(" & translate(n[1]) & " " & vegaOp & " " & translate(n[2]) & ")"
  of nnkCall, nnkCommand:
    # Vega's own functions: isValid, year, datetime, lower, test…
    var args: seq[string]
    for i in 1 ..< n.len: args.add(translate(n[i]))
    translate(n[0]) & "(" & args.join(", ") & ")"
  of nnkIfExpr:
    # `if a: b else: c` becomes Vega's ternary.
    if n.len == 2 and n[0].kind == nnkElifExpr and n[1].kind == nnkElseExpr:
      "(" & translate(n[0][0]) & " ? " & translate(n[0][1]) & " : " &
        translate(n[1][0]) & ")"
    else:
      error("expr: only if/else with both branches is supported", n)
  else:
    error("expr: cannot translate " & $n.kind, n)

macro expr*(e: untyped): string =
  ## Translate a Nim expression into a Vega expression string at compile time.
  newLit(translate(e))
