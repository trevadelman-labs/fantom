#! /usr/bin/env fan
//
// Copyright (c) 2026, Brian Frank and Andy Frank
// Licensed under the Academic Free License version 3.0
//
// History:
//   2 Mar 2026  Creation
//
// Convert Fantom source fandoc comments and .fandoc chapter files
// to markdown in-place.  Mirrors the structure of haxall convert4::FixDocs
// but targets ** doc comments in .fan files and .fandoc chapter files.
//
// Usage:
//   fan adm/fandoc2md.fan [-preview] <file-or-dir>...
//
// The -preview flag prints converted output without modifying any files.
// .fandoc files are converted to a doc.md file alongside the original
// (pod.fandoc is renamed to doc.md for consistency with xeto libs).
//

using util
using fandoc

class Main : AbstractMain
{
  @Opt { help = "Preview mode only (do not write files)" }
  Bool preview

  @Arg { help = "Files or directories to convert" }
  Str[]? targets

  override Int run()
  {
    if (targets == null || targets.isEmpty)
    {
      Env.cur.err.printLine("No targets specified")
      return 1
    }
    targets.each |t| { fix(File.os(t)) }
    return 0
  }

//////////////////////////////////////////////////////////////////////////
// Target dispatch
//////////////////////////////////////////////////////////////////////////

  private Void fix(File f)
  {
    if (f.isDir)
    {
      f.list.each |kid| { fix(kid) }
      return
    }
    if (f.ext == "fan")    return fixFan(f)
    if (f.ext == "fandoc") return fixFandoc(f)
  }

//////////////////////////////////////////////////////////////////////////
// .fan files - ** doc comments
//////////////////////////////////////////////////////////////////////////

  private Void fixFan(File f)
  {
    logMsg("Fix [$f.osPath]")
    oldLines := f.readAllLines
    newLines := Str[,] { it.capacity = oldLines.size }
    processLines(f, oldLines, newLines)
    rewrite(f, newLines)
  }

  private Void processLines(File f, Str[] oldLines, Str[] newLines)
  {
    header := false
    for (i := 0; i < oldLines.size; ++i)
    {
      line := oldLines[i]

      // detect and preserve the copyright/history header
      if (i == 0 && line.startsWith("//")) header = true
      if (header)
      {
        newLines.add(line)
        if (line.trimToNull == null) header = false
        continue
      }

      // all-star separator lines used as section dividers between classes
      // (e.g. ****...****) must pass through unchanged - do not treat as doc
      trimmed := line.trimStart
      if (trimmed.size > 2 && trimmed.all |ch| { ch == '*' }) { newLines.add(line); continue }

      // look for ** doc comment block
      if (!trimmed.startsWith("**")) { newLines.add(line); continue }

      // find the leading prefix (whitespace before the **)
      ss     := line.index("**") ?: 0
      prefix := line[0..<ss]

      // accumulate the full comment block; stop at all-star separator lines
      block := Str[,]
      block.add(starStarComment(line, ss))
      while (i+1 < oldLines.size && oldLines[i+1].startsWith(prefix + "**"))
      {
        next := oldLines[i+1].trimStart
        if (next.size > 2 && next.all |ch| { ch == '*' }) break
        i++
        block.add(starStarComment(oldLines[i], ss))
      }

      // fix the block and restore ** prefix
      curLoc = FileLoc(f.osPath, i - block.size + 2)
      fixStarStarDoc(block).each |newLine|
      {
        if (newLine.trimToNull == null)
          newLines.add(prefix + "**")
        else
          newLines.add(prefix + "** " + newLine)
      }
    }
  }

  private Str starStarComment(Str line, Int ss)
  {
    // strip "** " or "**"
    rest := line[ss+2..-1]
    if (!rest.isEmpty && rest[0] == ' ') rest = rest[1..-1]
    // treat lines of all * as section separators - map to blank doc line
    if (rest.all |ch| { ch == '*' }) return ""
    return rest
  }

  private Str[] fixStarStarDoc(Str[] lines)
  {
    FandocConverter(curLoc, lines).fix
  }

//////////////////////////////////////////////////////////////////////////
// .fandoc files - chapter files
//////////////////////////////////////////////////////////////////////////

  private Void fixFandoc(File f)
  {
    logMsg("Fix [$f.osPath]")

    oldLines := f.readAllLines

    // strip leading ** comment metadata (wrap in HTML comment for markdown)
    comment := Str[,]
    while (!oldLines.isEmpty && oldLines.first.startsWith("**"))
    {
      line := oldLines.removeAt(0).trimStart
      while (!line.isEmpty && line[0] == '*') line = line[1..-1]
      line = line.trim
      if (!line.isEmpty) comment.add(line)
    }

    newLines := FandocConverter(FileLoc(f.osPath), oldLines).fix

    if (!comment.isEmpty)
    {
      comment.insert(0, "<!--")
      comment.add("-->")
      newLines.insertAll(0, comment)
    }

    // pod.fandoc -> doc.md for consistency with xeto libs; others keep basename
    mdName := f.basename == "pod" ? "doc" : f.basename
    mdFile := f.parent + `${mdName}.md`
    rewrite(mdFile, newLines)
  }

//////////////////////////////////////////////////////////////////////////
// Output
//////////////////////////////////////////////////////////////////////////

  private Void rewrite(File f, Str[] lines)
  {
    if (preview)
    {
      Env.cur.out.printLine("=== $f.osPath ===")
      Env.cur.out.printLine(lines.join("\n"))
      Env.cur.out.printLine
    }
    else
    {
      f.out.printLine(lines.join("\n")).close
    }
  }

  private Void logMsg(Str msg) { Env.cur.out.printLine(msg) }

//////////////////////////////////////////////////////////////////////////
// Fields
//////////////////////////////////////////////////////////////////////////

  private FileLoc curLoc := FileLoc.unknown
}

**************************************************************************
** FandocConverter
**************************************************************************

**
** Core fandoc-to-markdown converter.  Adapted from haxall convert4::FixFandoc
** with the following changes:
**   - No FixLinks dependency (link rewriting is a separate pass)
**   - pre> blocks use ```fantom fences (with language hint)
**
internal class FandocConverter
{
  new make(FileLoc loc, Str[] lines)
  {
    this.loc   = loc
    this.lines = lines
    this.types = FandocParser().parseLineTypes(lines)
  }

  internal Str[] fix()
  {
    acc := Str[,]
    acc.capacity = lines.size

    lastCodeIndent := false
    for (i := 0; i < lines.size; ++i)
    {
      linei = i
      line  := lines[i]
      type  := types[i]

      // fandoc headings use two-line underline style
      if (i+1 < types.size && types[i+1].isHeading)
      {
        acc.add(fixHeading(line, types[i+1].headingLevel))
        i++
      }
      else
      {
        // ensure code indentation is preceded/followed by blank line
        newLine         := fixLine(line, type)
        newIsCodeIndent := mode == FandocConverterMode.preIndent
        if (newIsCodeIndent && !isBlank(acc.last) && !lastCodeIndent) acc.add("")
        if (lastCodeIndent && !newIsCodeIndent && !isBlank(newLine))  acc.add("")
        lastCodeIndent = newIsCodeIndent

        acc.add(newLine)
      }
    }

    return acc
  }

  private Bool isBlank(Str? line) { line?.trimToNull == null }

//////////////////////////////////////////////////////////////////////////
// Block Lines
//////////////////////////////////////////////////////////////////////////

  private Str fixLine(Str line, LineType type)
  {
    curIndent := indent(line)

    if (mode === FandocConverterMode.preBlock)
    {
      if (type === LineType.preEnd)
      {
        mode = FandocConverterMode.norm
        return "```"
      }
      return line
    }

    if (mode === FandocConverterMode.preIndent)
    {
      if (curIndent >= modeIndent) return "  " + line
    }

    if (mode === FandocConverterMode.list && type === LineType.normal)
    {
      if (curIndent >= modeIndent) return line
    }

    mode       = FandocConverterMode.norm
    modeIndent = 0

    switch (type)
    {
      case LineType.blank:      return ""
      case LineType.ul:         return fixList(line, curIndent, "-")
      case LineType.ol:         return fixList(line, curIndent, ".")
      case LineType.blockquote: return line
      case LineType.hr:         return line
      case LineType.preStart:   return fixPreStart
      case LineType.normal:     return fixNorm(line, curIndent)
      default:                  throw Err("$type.name: $line")
    }
  }

  private Str fixHeading(Str line, Int level)
  {
    // strip [#anchor] - we now use title itself like github
    i := line.index("[#")
    if (i != null) line = line[0..<i].trim

    // fandoc top-level headings are h2; shift all levels down by one for markdown
    level = (level - 1).clamp(1, 4)

    s := StrBuf()
    level.times { s.addChar('#') }
    s.add(" ").add(line.trim)
    return s.toStr
  }

  private Str fixList(Str line, Int curIndent, Str sep)
  {
    mode       = FandocConverterMode.list
    modeIndent = curIndent

    i    := line.index(sep) ?: throw Err("Missing sep $sep - $line")
    rest := line[i+1..-1].trimStart
    rest  = fixInline(rest)
    return line[0..i] + " " + rest
  }

  private Str fixPreStart()
  {
    mode = FandocConverterMode.preBlock
    return "```fantom"
  }

  private Str fixNorm(Str line, Int curIndent)
  {
    if (curIndent >= 2)
    {
      mode       = FandocConverterMode.preIndent
      modeIndent = curIndent
      return "  " + line
    }
    return fixInline(line)
  }

//////////////////////////////////////////////////////////////////////////
// Inline
//////////////////////////////////////////////////////////////////////////

  private Str fixInline(Str line)
  {
    lineLoc := FileLoc(loc.file, loc.line + linei)
    try
    {
      buf    := StrBuf(line.size)
      parser := FandocParser()
      parser.parseHeader = false
      doc := parser.parse(lineLoc.toStr, line.in)
      fixNode(doc, buf)
      return buf.toStr
    }
    catch (Err e)
    {
      Env.cur.err.printLine("ERROR: $lineLoc\n  $e")
    }
    return line
  }

  private Void fixNode(DocNode n, StrBuf buf)
  {
    switch (n.id)
    {
      case DocNodeId.doc:      fixElem(n, buf)
      case DocNodeId.text:     buf.add(n.toText)
      case DocNodeId.emphasis: fixElem(n, buf, "*")
      case DocNodeId.strong:   fixElem(n, buf, "**")
      case DocNodeId.code:     fixElem(n, buf, "`")
      case DocNodeId.link:     fixLink(n, buf)
      case DocNodeId.image:    fixImage(n, buf)
      case DocNodeId.para:
        a := ((Para)n).admonition
        if (a != null) buf.add(a).add(": ")
        fixElem(n, buf)
      default: throw Err("Unhandled node: $n.id $n")
    }
  }

  private Void fixElem(DocElem n, StrBuf buf, Str? wrap := null)
  {
    if (wrap != null) buf.add(wrap)
    kids := n.children
    for (i := 0; i < kids.size; ++i)
    {
      kid := kids[i]
      fixNode(kid, buf)
      // [link]: would be misread as a markdown link reference definition;
      // escape the colon when a link is immediately followed by ": ..."
      if (kid.id === DocNodeId.link && i+1 < kids.size)
      {
        next := kids[i+1]
        if (next.id === DocNodeId.text && next.toText.startsWith(":"))
          buf.addChar('\\')
      }
    }
    if (wrap != null) buf.add(wrap)
  }

  private Void fixLink(Link n, StrBuf buf)
  {
    text := n.toText
    uri  := n.uri
    if (text == uri)
      buf.add("[").add(uri).add("]")
    else
      buf.add("[").add(text).add("](").add(uri).add(")")
  }

  private Void fixImage(Image n, StrBuf buf)
  {
    buf.add("![").add(n.toText).add("](").add(n.uri).add(")")
  }

//////////////////////////////////////////////////////////////////////////
// Utils
//////////////////////////////////////////////////////////////////////////

  private static Int indent(Str line)
  {
    i := 0
    while (i < line.size && line[i].isSpace) ++i
    return i
  }

//////////////////////////////////////////////////////////////////////////
// Fields
//////////////////////////////////////////////////////////////////////////

  private FileLoc loc
  private Str[] lines
  private LineType[] types
  private Int linei
  private FandocConverterMode mode := FandocConverterMode.norm
  private Int modeIndent
}

**************************************************************************
** FandocConverterMode
**************************************************************************

internal enum class FandocConverterMode { norm, list, preIndent, preBlock }
