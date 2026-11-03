// The options of Markdown for Agents, shared by the Next config wrapper (index.ts), the build step (build.ts) and the
// conversion (convert.ts).

export interface AgentMarkdownOptions {
  /** The folder under public/ (and the URL prefix) for the Markdown files. Default "md". */
  directory?: string;
  /** Sent as the `Content-Signal` header (contentsignals.org), e.g. "search=yes, ai-input=yes, ai-train=no". */
  contentSignal?: string;
}

export interface ConvertOptions {
  /** More CSS selectors to leave out of every page. */
  omit?: string;
}

export interface BuildOptions extends Pick<AgentMarkdownOptions, "directory">, ConvertOptions {
  /** The Next project. Default: the current directory. */
  root?: string;
  /** Next's distDir. Default ".next". */
  distDir?: string;
  /** Default "public". */
  publicDir?: string;
}
