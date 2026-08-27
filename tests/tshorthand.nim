import std/unittest
import plotter

suite "shorthand parsing":

  test "a bare field name":
    let e = parseShorthand("sales")
    check e.kind == ekField
    check e.field == "sales"
    check e.fieldType == ftAuto

  test "field with an explicit type":
    check parseShorthand("sales:Q").fieldType == ftQuantitative
    check parseShorthand("region:N").fieldType == ftNominal
    check parseShorthand("size:O").fieldType == ftOrdinal
    check parseShorthand("date:T").fieldType == ftTemporal

  test "long type names work too":
    check parseShorthand("sales:quantitative").fieldType == ftQuantitative

  test "aggregates":
    let e = parseShorthand("mean(sales):Q")
    check e.aggregate == agMean
    check e.field == "sales"
    check e.fieldType == ftQuantitative

  test "a bare count() has no field":
    let e = parseShorthand("count()")
    check e.aggregate == agCount
    check e.field == ""

  test "time units":
    let e = parseShorthand("yearmonth(date):T")
    check e.timeUnit == "yearmonth"
    check e.field == "date"
    check e.aggregate == agNone

  test "utc-prefixed time units":
    check parseShorthand("utcyearmonth(d)").timeUnit == "utcyearmonth"

  test "an empty string is the unset sentinel":
    check parseShorthand("").kind == ekEmpty

  test "a colon in a field name can be escaped":
    check parseShorthand("odd\\:name:Q").field == "odd:name"

  test "bad type codes and unknown functions are rejected":
    expect ValueError: discard parseShorthand("sales:Z")
    expect ValueError: discard parseShorthand("nosuchfn(sales)")
    expect ValueError: discard parseShorthand("mean(sales")

suite "shorthand vs explicit arguments":

  test "explicit arguments win over the string":
    let e = X("sales:Q", fieldType = ftOrdinal, aggregate = agSum)
    check e.fieldType == ftOrdinal
    check e.aggregate == agSum
    check e.field == "sales"

  test "the string fills in what the arguments leave out":
    let e = X("mean(sales):Q", title = "Average")
    check e.aggregate == agMean
    check e.title.get == "Average"

  test "channel constructors are aliases of field()":
    check X("a:Q") == Y("a:Q")
    check Color("a:N") == field("a:N")

suite "sort shorthand":

  test "channel sort":
    let s = parseSort("-y")
    check s.kind == sortField
    check s.field == "y"
    check s.descending

  test "named orders":
    check parseSort("ascending").kind == sortAscending
    check parseSort("null").kind == sortNull
    check parseSort("").kind == sortUnset
