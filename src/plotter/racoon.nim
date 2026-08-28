## Bridge to [racoon](https://github.com/Swarchal/Racoon) DataFrames.
##
## Not imported by `plotter` — racoon is not a dependency of this package,
## and Nim has no optional ones. Importing this module is what pulls it in:
##
## ```nim
## import plotter
## import plotter/racoon        # adds toDataFrame(racoon.DataFrame)
## import racoon
##
## let df = readFile("cars.csv").toDataFrame()   # racoon
## df[df["mpg"] > 20].toDataFrame().chart()      # ... and over to plotter
##   .markPoint().encode(x = "hp:Q", y = "mpg:Q")
## ```
##
## Both libraries can be imported unqualified: their procs differ in their
## parameter types, so overloading resolves them. Only the bare type names
## `Value` and `DataFrame` are ambiguous, and only where a user writes one —
## qualify those as `racoon.DataFrame` / `plotter.DataFrame`.

import racoon/value as rvalue
import racoon/dataframe as rdataframe
import ./data

proc toValue*(x: rvalue.Value): data.Value =
  ## One cell. A missing cell becomes null — the only thing a spec-based
  ## backend understands, and what Vega-Lite's invalid-data handling
  ## already expects.
  if x.isNA: nullValue()
  else:
    case x.kind
    of ckInt: v(x.i)
    of ckFloat: v(x.f)
    of ckBool: v(x.b)
    of ckString: v(x.s)

proc toDataColumn*(c: rvalue.Column): DataColumn =
  ## Read through `[]` rather than the payload seq: under a missing cell the
  ## payload holds the branch default and must never be read as a value.
  result = DataColumn(name: c.name)
  for i in 0 ..< c.len:
    result.values.add(toValue(c[i]))

proc toDataFrame*(df: rdataframe.DataFrame): data.DataFrame =
  ## Both frames are column-major and tidy already, so this is a copy, not a
  ## reshape. Racoon's int columns widen to float, since a `Value` has one
  ## numeric kind.
  for c in df.columns:
    result.columns.add(toDataColumn(c))
