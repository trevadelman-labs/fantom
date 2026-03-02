//
// Copyright (c) 2026, Brian Frank and Andy Frank
// Licensed under the Academic Free License version 3.0
//
// History:
//   2 Mar 2026  Trevor Adelman  Creation
//

using markdown

**
** DocMarkdownLinkResolver hooks compilerDoc link resolution into the
** markdown rendering pipeline.  It maps markdown link destinations to
** doc URLs using the same `DocEnv.link` entry point the fandoc path uses.
**
internal class DocMarkdownLinkResolver : LinkResolver
{
  new make(DocEnv env, Doc from)
  {
    this.env  = env
    this.from = from
  }

  override protected Void resolve(LinkNode linkNode)
  {
    uri := linkNode.destination
    if (isAbsolute(uri)) return
    link := env.link(from, uri, false)
    if (link == null) return
    linkNode.destination = env.linkUri(link).encode
  }

  private static Bool isAbsolute(Str uri)
  {
    uri.startsWith("http:/")  ||
    uri.startsWith("https:/") ||
    uri.startsWith("ftp:/")
  }

  private DocEnv env
  private Doc from
}
