import std/unittest
import plotter

suite "dataframe":

  test "columns must be the same length":
    expect AssertionDefect:
      discard dataFrame(col("x", @[1.0, 2.0]), col("y", @[3.0]))

  test "len is the row count, lookup is by name":
    let df = dataFrame(col("x", @[1.0, 2.0]), col("g", @["a", "b"]))
    check df.len == 2
    check "g" in df
    check "nope" notin df
    check df["g"].values[1].str == "b"

  test "an empty frame has no rows":
    check DataFrame().len == 0

  test "type inference: numbers quantitative, strings nominal":
    check inferType(col("x", @[1.0])) == ftQuantitative
    check inferType(col("g", @["a"])) == ftNominal
    check inferType(col("b", @[true])) == ftNominal

  test "inference skips leading nulls":
    let c = DataColumn(name: "x", values: @[nullValue(), v(1.0)])
    check inferType(c) == ftQuantitative

  test "vals builds heterogeneous lists":
    check vals(1.0, 2.0).len == 2
    check vals("a", "b")[1].str == "b"

suite "series":

  test "mismatched xs/ys is rejected":
    expect AssertionDefect:
      discard newSeries(@[1.0, 2.0], @[3.0])

  test "longFrame melts series into a grouping column":
    let df = longFrame(@[newSeries(@[1.0], @[2.0], "a"),
                         newSeries(@[3.0], @[4.0], "b")])
    check df.len == 2
    check df["series"].values[0].str == "a"
    check df["y"].values[1].num == 4.0

  test "unnamed series get positional names":
    let df = longFrame(@[newSeries(@[1.0], @[2.0])])
    check df["series"].values[0].str == "series 1"

  test "longFrame rejects a hand-built Series with mismatched vectors":
    expect AssertionDefect:
      discard longFrame(@[Series(name: "s", xs: @[1.0, 2.0], ys: @[1.0])])

suite "Opt":

  test "unset is distinct from set-to-false":
    check Opt[bool]().isNone
    let o: Opt[bool] = false
    check o.isSome
    check o.get == false

  test "ints convert to Opt[float]":
    let o: Opt[float] = 60
    check o.get == 60.0
