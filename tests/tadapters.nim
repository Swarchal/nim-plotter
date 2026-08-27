import std/[json, tables, unittest]
import plotter

type
  Penguin = object
    species: string
    billLength: float
    flipperLength: int
    tagged: bool

suite "objects and tuples":

  test "one column per field, in declaration order":
    let df = toDataFrame(@[
      Penguin(species: "Adelie", billLength: 39.1, flipperLength: 181,
              tagged: true),
      Penguin(species: "Gentoo", billLength: 46.1, flipperLength: 211,
              tagged: false)])
    check df.len == 2
    check df.columns.len == 4
    check df.columns[0].name == "species"
    check df.columns[1].name == "billLength"
    check df["species"].values[1].str == "Gentoo"
    check df["billLength"].values[0].num == 39.1
    check df["flipperLength"].values[1].num == 211.0
    check df["tagged"].values[0].bval

  test "an empty sequence still yields the columns":
    let df = toDataFrame(newSeq[Penguin]())
    check df.columns.len == 4
    check df.len == 0

  test "tuples work the same way":
    let df = toDataFrame(@[(a: 1.0, b: "x"), (a: 2.0, b: "y")])
    check df["a"].values[1].num == 2.0
    check df["b"].values[0].str == "x"

  test "chart takes a sequence of objects directly":
    let c = chart(@[Penguin(species: "Adelie", billLength: 39.1,
                            flipperLength: 181, tagged: true)])
      .markPoint().encode(x = "billLength", color = "species")
    check c.enc(chX).fieldType == ftAuto
    check c.toSpec["encoding"]["x"]["type"].getStr == "quantitative"
    check c.toSpec["encoding"]["color"]["type"].getStr == "nominal"

suite "tables":

  test "a plain Table sorts its keys for a deterministic spec":
    let df = toDataFrame({"z": @[1.0], "a": @[2.0]}.toTable)
    check df.columns[0].name == "a"
    check df.columns[1].name == "z"

  test "an OrderedTable keeps insertion order":
    let df = toDataFrame({"z": @[1.0], "a": @[2.0]}.toOrderedTable)
    check df.columns[0].name == "z"

  test "columns of unequal length are rejected":
    expect ValueError:
      discard toDataFrame({"a": @[1.0, 2.0, 3.0], "b": @[4.0]}.toOrderedTable)

suite "csv":

  test "types are sniffed per column":
    let df = parseCsv("name,score,pass\nada,9.5,true\ngrace,8,false\n")
    check df.len == 2
    check df["name"].values[0].str == "ada"
    check df["score"].values[1].num == 8.0
    check df["pass"].values[0].bval
    check inferType(df["score"]) == ftQuantitative
    check inferType(df["name"]) == ftNominal

  test "a column with one non-numeric value stays text":
    let df = parseCsv("x\n1\n2\nn/a\n")
    check inferType(df["x"]) == ftNominal

  test "empty cells become null":
    let df = parseCsv("x,y\n1,\n2,3\n")
    check df["y"].values[0].kind == vkNull
    check df["y"].values[1].num == 3.0

  test "a row that does not match the header is an error naming the line":
    expect ValueError:
      discard parseCsv("a,b,c\n1,2,3\n4,5\n")
    expect ValueError:
      discard parseCsv("a,b\n1,2,3\n")

  test "an unreadable file raises a catchable IOError naming the path":
    expect IOError:
      discard readCsv("/definitely/not/here.csv")

suite "data sources":

  test "a url is emitted instead of rows, with the format sniffed":
    let spec = chart("https://example.com/cars.csv").markPoint().toSpec
    check spec["data"]["url"].getStr == "https://example.com/cars.csv"
    check spec["data"]["format"]["type"].getStr == "csv"
    check "values" notin spec["data"]

  test "a named dataset":
    let c = chart(DataFrame()).withData(namedData("mine")).markPoint()
    check c.toSpec["data"]["name"].getStr == "mine"

  test "withData keeps everything else":
    let base = chart(dataFrame(col("a", @[1.0])), title = "t")
      .markBar().encode(x = "a:Q")
    let swapped = base.withData(inlineData(dataFrame(col("a", @[9.0]))))
    check swapped.title == "t"
    check swapped.enc(chX).field == "a"
    check swapped.data.frame["a"].values[0].num == 9.0
