//
// Copyright (c) 2011, Brian Frank and Andy Frank
// Licensed under the Academic Free License version 3.0
//
// History:
//   15 Aug 11  Brian Frank  Creation
//

using concurrent
using fandoc::FandocParser
using fandoc::Heading
using markdown
using markdown::Heading as MdHeading

**
** DocChapter models a chapter in a manual like docLang.
** Chapters may be authored in fandoc (legacy) or markdown (new-style),
** as determined by `DocFormat` at load time.
**
const class DocChapter : Doc
{
  ** Constructor
  internal new make(DocPodLoader loader, File f, DocFormat format)
  {
    this.pod    = loader.pod
    this.format = format
    this.name   = f.name == format.podDocFile ? "pod-doc" : f.basename
    this.loc    = DocLoc("${pod}::${f.name}", 1)
    this.doc    = DocFandoc(this.loc, f.in.readAllStr)
    this.qname  = "$pod.name::$name"

    // parse and build the headings tree
    headingTop := DocHeading[,]
    headingMap := Str:DocHeading[:]
    meta := Str:Str[:]
    try
    {
      if (format == DocFormat.markdown)
      {
        // parse markdown and generate heading anchors
        mdDoc := Xetodoc().parse(doc.text)
        HeadingProcessor().process(mdDoc)
        buildMdHeadingsTree(loader, mdDoc, headingTop, headingMap)
      }
      else
      {
        // parse fandoc silently - catch and report errors at render time
        parser := FandocParser()
        parser.silent = true
        fandocDoc := parser.parse(f.name, doc.text.in)
        meta = fandocDoc.meta
        buildFandocHeadingsTree(loader, fandocDoc.findHeadings, headingTop, headingMap)
      }
    }
    catch (Err e)
    {
      loader.err("Cannot parse chapter", loc, e)
    }
    this.headings = headingTop
    this.headingMap = headingMap
    this.meta = meta
  }

  private Void buildFandocHeadingsTree(DocPodLoader loader, Heading[] fandoc, DocHeading[] top, Str:DocHeading map)
  {
    // if no headings just bail
    if (fandoc.isEmpty) return

    // first map Fandoc headings to DocHeadings and map by anchor id
    headings := DocHeading[,]
    children := DocHeading:DocHeading[][:]
    fandoc.each |d|
    {
      h := DocHeading { it.level = d.level; it.title = d.title; it.anchorId = d.anchorId }
      addHeading(loader, h, headings, map, children)
    }

    // map into a tree structure; fandoc top-level headings are level 2
    buildHeadingsTree(loader, headings, top, map, children, 2)
  }

  private Void buildMdHeadingsTree(DocPodLoader loader, Document mdDoc, DocHeading[] top, Str:DocHeading map)
  {
    // walk top-level block nodes collecting Heading nodes
    headings := DocHeading[,]
    children := DocHeading:DocHeading[][:]
    Node? node := mdDoc.firstChild
    while (node != null)
    {
      if (node is MdHeading)
      {
        mdH := (MdHeading)node
        words := Str[,]
        mdH.eachDescendant |n|
        {
          if (n is Text)      words.add(((Text)n).literal)
          else if (n is Code) words.add(((Code)n).literal)
        }
        h := DocHeading { it.level = mdH.level; it.title = words.join; it.anchorId = mdH.anchor }
        addHeading(loader, h, headings, map, children)
      }
      node = node.next
    }

    // map into a tree structure; markdown top-level headings are level 1
    buildHeadingsTree(loader, headings, top, map, children, 1)
  }

  private Void addHeading(DocPodLoader loader, DocHeading h,
                           DocHeading[] headings, Str:DocHeading map,
                           DocHeading:DocHeading[] children)
  {
    id := h.anchorId
    if (id == null) loader.err("Heading missing anchor id: $h.title", loc)
    else if (map[id] != null) loader.err("Heading duplicate anchor id: $id", loc)
    else map[id] = h
    headings.add(h)
    children[h] = DocHeading[,]
  }

  private Void buildHeadingsTree(DocPodLoader loader, DocHeading[] headings,
                                  DocHeading[] top, Str:DocHeading map,
                                  DocHeading:DocHeading[] children, Int topLevel)
  {
    stack := DocHeading[,]
    headings.each |h|
    {
      while (stack.peek != null && stack.peek.level >= h.level)
        stack.pop

      // top level heading
      if (stack.isEmpty)
      {
        if (h.level != topLevel && pod.name != "fandoc")
          loader.err("Expected top-level heading to be level $topLevel: $h.title", loc)
        top.add(h)
      }

      // child level heading
      else
      {
        if (stack.peek.level + 1 != h.level)
          loader.err("Expected heading to be level ${stack.peek.level+1}: $h.title", loc)
        children[stack.peek].add(h)
      }

      stack.add(h)
    }

    // map children map to immutable list fields
    children.each |kids, h| { h.childrenRef.val = kids.toImmutable }
  }

  ** Pod which defines this chapter such as "docLang"
  const DocPod pod

  ** Documentation format for this chapter
  const DocFormat format

  ** Simple name of the chapter such as "Overview" or "pod-doc"
  const Str name

  ** Document name under space is same as `name`
  override Str docName() { name }

  ** The space for this doc is `pod`
  override DocSpace space() { pod }

  ** Title is 'meta.title', or qualified name if not specified.
  override Str title() { meta["title"] ?: qname }

  ** Use title for breadcrumb
  override Str breadcrumb() { title }

  ** Default renderer is `DocChapterRenderer`
  override Type renderer() { DocChapterRenderer# }

  ** Return if this chapter is the special "pod-doc" file
  Bool isPodDoc() { name == "pod-doc" }

  ** Qualified name as "pod::name"
  const Str qname

  ** Location for chapter file
  const DocLoc loc

  ** Fandoc heating metadata
  const Str:Str meta

  ** Chapter contents as Fandoc string
  const DocFandoc doc

  ** Top-level chapter headings
  const DocHeading[] headings

  ** Chapter number (one-based)
  Int num() { numRef.val }
  internal const AtomicInt numRef := AtomicInt()

  ** Summary for TOC
  Str summary() { summaryRef.val }
  internal const AtomicRef summaryRef := AtomicRef("")

  ** Previous chapter in TOC order or null if first
  DocChapter? prev() { prevRef.val }
  internal const AtomicRef prevRef := AtomicRef(null)

  ** Next chapter in TOC order or null if last
  DocChapter? next() { nextRef.val }
  internal const AtomicRef nextRef := AtomicRef(null)

  ** Get a chapter heading by its anchor id or raise NameErr/return null.
  override DocHeading? heading(Str id, Bool checked := true)
  {
    h := headingMap[id]
    if (h != null) return h
    return super.heading(id, checked)
  }

  ** Return qname
  override Str toStr() { qname }

  private const Str:DocHeading headingMap

  ** Index the chapter name and body
  override Void onCrawl(DocCrawler crawler)
  {
    summary := DocFandoc(this.loc, this.summary)
    crawler.addKeyword(name, title, summary, null)
    crawler.addKeyword(qname, title, summary, null)
    crawler.addFandoc(doc)
  }
}

**
** DocHeader models a heading in a table of contents for pod/chapter.
**
const class DocHeading
{
  ** Constructor
  internal new make(|This| f) { f(this) }

  ** Heading level; fandoc top-level sections start at level 2,
  ** markdown top-level sections start at level 1
  const Int level

  ** Display title for the heading
  const Str title

  ** Anchor id for heading or null if not available
  const Str? anchorId

  ** Children headings
  DocHeading[] children() { childrenRef.val }
  internal const AtomicRef childrenRef := AtomicRef()
}