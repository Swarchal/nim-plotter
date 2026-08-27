## Turning a spec into a file.
##
## Layered so that the correctness-critical part (`plotter/vegalite`) stays
## pure and testable without a toolchain:
##
## * `saveJson`  — the spec itself.
## * `saveHtml`  — a page that renders it in a browser via vega-embed.
## * `savePng` / `saveSvg` / `savePdf` / `saveVega` — shell out to
##   `vl-convert`, a standalone Rust binary (no Node). Absent, these raise
##   with an install hint.

import std/[os, osproc, strutils, tempfiles]
import ./types
import ./vegalite

const
  vlConvertExe* = "vl-convert"

type
  Renderer* = enum
    rdSvg, rdCanvas

  EmbedOptions* = object
    ## How `toHtml` builds its page.
    vegaVersion*, vegaLiteVersion*, embedVersion*: string
    renderer*: Renderer
    actions*: bool           ## the "..." export menu vega-embed adds
    runtimeFiles*: seq[string]
      ## Local vega/vega-lite/vega-embed builds to inline instead of loading
      ## from the CDN, in that order. The way to get a page that renders
      ## with no network access; the files are yours to supply.

proc defaultEmbed*(): EmbedOptions =
  EmbedOptions(vegaVersion: "5", vegaLiteVersion: "5", embedVersion: "6",
               renderer: rdSvg, actions: true)

proc saveJson*(c: Chart, path: string, indent = 2) =
  writeFile(path, toJson(c, indent) & "\n")

const htmlTemplate = """<!doctype html>
<meta charset="utf-8">
<title>__TITLE__</title>
__SCRIPTS__
<style>
  body { margin: 0; padding: 1.5rem; font-family: system-ui, sans-serif; }
</style>
<div id="chart"></div>
<script>
  vegaEmbed("#chart", __SPEC__, __OPTIONS__);
</script>
"""

proc scriptTags(o: EmbedOptions): string =
  if o.runtimeFiles.len > 0:
    for path in o.runtimeFiles:
      result.add("<script>" & readFile(path) & "</script>\n")
  else:
    for (name, version) in {"vega": o.vegaVersion,
                            "vega-lite": o.vegaLiteVersion,
                            "vega-embed": o.embedVersion}:
      result.add("<script src=\"https://cdn.jsdelivr.net/npm/" & name & "@" &
                 version & "\"></script>\n")
  result.setLen(result.len - 1)

proc escapeHtml(s: string): string =
  ## Enough for text and quoted attributes; the page has no other HTML holes.
  s.multiReplace(("&", "&amp;"), ("<", "&lt;"), (">", "&gt;"),
                 ("\"", "&quot;"), ("\'", "&#39;"))

proc toHtml*(c: Chart, embed = defaultEmbed()): string =
  ## A standalone page that renders the chart with vega-embed.
  ##
  ## By default the vega runtime is loaded from a CDN, so the page needs
  ## network access the first time it is opened. Set `embed.runtimeFiles` to
  ## inline local copies instead, or use `savePng` for a static image.
  let options = "{renderer: \"" &
    (if embed.renderer == rdSvg: "svg" else: "canvas") &
    "\", actions: " & (if embed.actions: "true" else: "false") & "}"
  # The spec sits inside a <script>, where the parser stops at the first
  # "</script>" even inside a string literal; "<\/" is the same JSON string.
  let spec = toJson(c, indent = 0).replace("</", "<\\/")
  # One pass, so a placeholder appearing in substituted text — a title, a
  # spec value, an inlined runtime file — is not itself expanded.
  htmlTemplate.multiReplace(
    ("__TITLE__", escapeHtml(if c.title.len > 0: c.title else: "plotter chart")),
    ("__SCRIPTS__", scriptTags(embed)),
    ("__SPEC__", spec),
    ("__OPTIONS__", options))

proc saveHtml*(c: Chart, path: string, embed = defaultEmbed()) =
  writeFile(path, toHtml(c, embed))

proc convert(c: Chart, path, subcommand: string, scale: float) =
  let exe = findExe(vlConvertExe)
  if exe.len == 0:
    raise newException(OSError, "`" & vlConvertExe & "` not found on PATH. " &
      "It renders Vega-Lite specs without a Node toolchain; install it with " &
      "`cargo install vl-convert` or from " &
      "https://github.com/vega/vl-convert/releases. " &
      "Alternatively use `saveHtml` to render in a browser.")
  # Random, not PID-keyed: two charts written at once must not collide.
  let specPath = genTempPath("plotter-", ".vl.json")
  writeFile(specPath, toJson(c, indent = 0))
  defer: removeFile(specPath)
  let (output, code) = execCmdEx(quoteShellCommand([
    exe, subcommand, "--input", specPath, "--output", path,
    "--scale", $scale]))
  if code != 0:
    raise newException(OSError,
      vlConvertExe & " " & subcommand & " failed (exit " & $code & "):\n" &
      output.strip())

proc savePng*(c: Chart, path: string, scale = 1.0) =
  ## Render to PNG via `vl-convert`. `scale` > 1 gives a hidpi image.
  convert(c, path, "vl2png", scale)

proc saveSvg*(c: Chart, path: string, scale = 1.0) =
  convert(c, path, "vl2svg", scale)

proc savePdf*(c: Chart, path: string, scale = 1.0) =
  convert(c, path, "vl2pdf", scale)

proc saveVega*(c: Chart, path: string) =
  ## Compile down to a full Vega spec. Also the cheapest way to validate a
  ## spec: `vl-convert` rejects an invalid one.
  convert(c, path, "vl2vg", 1.0)

proc save*(c: Chart, path: string, scale = 1.0) =
  ## Dispatch on the file extension.
  case path.splitFile.ext.toLowerAscii
  of ".json": c.saveJson(path)
  of ".html", ".htm": c.saveHtml(path)
  of ".png": c.savePng(path, scale)
  of ".svg": c.saveSvg(path, scale)
  of ".pdf": c.savePdf(path, scale)
  of ".vg": c.saveVega(path)
  else:
    raise newException(ValueError,
      "don't know how to write '" & path.splitFile.ext &
      "' — expected .json, .html, .png, .svg, .pdf or .vg")

proc show*(c: Chart, embed = defaultEmbed()) =
  ## Write the chart to a temporary page and open it in the default browser.
  # Random, so a second `show()` does not overwrite a page the browser has
  # not finished loading yet.
  let path = genTempPath("plotter-", ".html")
  c.saveHtml(path, embed)
  let opener =
    when defined(macosx): "open"
    elif defined(windows): "cmd /c start \"\""
    else: "xdg-open"
  discard execShellCmd(opener & " " & quoteShell(path))
