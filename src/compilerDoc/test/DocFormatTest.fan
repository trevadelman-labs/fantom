//
// Copyright (c) 2026, Brian Frank and Andy Frank
// Licensed under the Academic Free License version 3.0
//
// History:
//   2 Mar 2026  Trevor Adelman  Creation
//

**
** DocFormatTest verifies the DocFormat enum and DocChapter format-aware
** loading for both the markdown and fandoc paths.
**
class DocFormatTest : Test
{

//////////////////////////////////////////////////////////////////////////
// DocFormat
//////////////////////////////////////////////////////////////////////////

  Void testDocFormat()
  {
    verifyEq(DocFormat.fandoc.name,  "fandoc")
    verifyEq(DocFormat.markdown.name, "markdown")
    verifyEq(DocFormat.vals.size, 2)
  }

//////////////////////////////////////////////////////////////////////////
// Markdown chapter
//////////////////////////////////////////////////////////////////////////

  Void testMarkdownChapter()
  {
    md := "# Overview\n\nSome text.\n\n## Details\n\nMore text.\n"
    pod := loadPod([`/doc/doc.md`: md])
    ch  := pod.podDoc ?: throw Err("Missing pod-doc chapter")

    // format and name
    verifyEq(ch.format, DocFormat.markdown)
    verifyEq(ch.name,   "pod-doc")

    // top-level heading at level 1
    verifyEq(ch.headings.size, 1)
    h := ch.headings.first
    verifyEq(h.level, 1)
    verifyEq(h.title, "Overview")
    verifyNotNull(h.anchorId)

    // child heading at level 2
    verifyEq(h.children.size, 1)
    verifyEq(h.children.first.level, 2)
    verifyEq(h.children.first.title, "Details")
    verifyNotNull(h.children.first.anchorId)
  }

//////////////////////////////////////////////////////////////////////////
// Fandoc chapter - backward compat
//////////////////////////////////////////////////////////////////////////

  Void testFandocChapter()
  {
    // use an existing built pod with a pod.fandoc chapter; we just verify
    // that the fandoc path is still taken and headings are still extracted
    f   := Env.cur.findPodFile("util") ?: throw Err("Cannot find util.pod")
    pod := DocPod.loadFile(f) |err| { /* ignore link resolution errors */ }
    ch  := pod.podDoc ?: throw Err("Missing pod-doc chapter")

    // fandoc path taken; not markdown
    verifyEq(ch.format, DocFormat.fandoc)
    verifyEq(ch.name,   "pod-doc")

    // headings still extracted (count varies by pod version, just verify non-empty)
    verify(ch.headings.size > 0)
    ch.headings.each |h|
    {
      verifyNotNull(h.anchorId)
      verify(h.level > 0)
    }
  }

//////////////////////////////////////////////////////////////////////////
// Utils
//////////////////////////////////////////////////////////////////////////

  private DocPod loadPod([Uri:Str] content)
  {
    f    := tempDir + `test.pod`
    zip  := Zip.write(f.out)
    errs := DocErr[,]
    try
    {
      writeMeta(zip)
      content.each |text, uri| { writeEntry(zip, uri, text) }
    }
    finally zip.close
    pod := DocPod.loadFile(f) |err| { errs.add(err) }
    if (!errs.isEmpty) fail("Pod load errors: " + errs.join(", "))
    return pod
  }

  private Void writeMeta(Zip zip)
  {
    out := zip.writeNext(`/meta.props`)
    out.printLine("pod.name=testpod")
    out.printLine("pod.summary=Test pod for DocFormatTest")
    out.printLine("pod.version=1.0")
    out.close
  }

  private Void writeEntry(Zip zip, Uri uri, Str text)
  {
    out := zip.writeNext(uri)
    out.print(text)
    out.close
  }

}
