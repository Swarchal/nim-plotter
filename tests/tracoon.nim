## The racoon bridge. Racoon is not a dependency, so this file compiles
## without it and the suite is only built under `-d:racoon`
## (`nimble racoontest`, with `RACOON_PATH` set if it is not installed).

import std/unittest

when defined(racoon):
  import std/json
  import plotter
  import plotter/racoon
  import racoon/dataframe as rdataframe

  const csv = "name,age,score,member\n" &
              "ann,31,4.5,true\n" &
              "bob,44,,false\n" &
              "cal,,2.0,true\n"

  suite "racoon frames":

    test "every column kind crosses over":
      let df = rdataframe.toDataFrame(csv).toDataFrame()
      check df.len == 3
      check df.columns.len == 4
      check df.columns[0].name == "name"
      check df["name"].values[2].str == "cal"
      check df["age"].values[0].num == 31.0     # ckInt widens to float
      check df["score"].values[0].num == 4.5
      check df["member"].values[1].bval == false

    test "a missing cell becomes null, not a payload default":
      let df = rdataframe.toDataFrame(csv).toDataFrame()
      check df["score"].values[1].kind == vkNull
      check df["age"].values[2].kind == vkNull

    test "column names and order are preserved":
      let df = rdataframe.toDataFrame(csv).toDataFrame()
      var names: seq[string]
      for c in df.columns: names.add(c.name)
      check names == @["name", "age", "score", "member"]

    test "types are inferred from the crossed-over columns":
      let df = rdataframe.toDataFrame(csv).toDataFrame()
      check df["age"].inferType == ftQuantitative
      check df["name"].inferType == ftNominal

    test "a racoon frame charts like any other":
      let spec = rdataframe.toDataFrame(csv).toDataFrame()
        .chart().markPoint().encode(x = "age:Q", y = "score:Q").toSpec()
      check spec["data"]["values"].len == 3
      check spec["data"]["values"][1]["score"].kind == JNull
      check spec["encoding"]["x"]["field"].getStr == "age"

    test "a filtered racoon frame keeps only the surviving rows":
      let rdf = rdataframe.toDataFrame(csv)
      let df = rdf[rdf["member"]].toDataFrame()
      check df.len == 2
      check df["name"].values[1].str == "cal"

else:
  suite "racoon frames":
    test "skipped: compile with -d:racoon":
      skip()
