"use client";

import { useEffect, useRef } from "react";

/** Starts downloading `url` once the page opens; the page stays, since the file comes as an attachment. */
export function StartDownload({ url }: { url: string }) {
  // Once per visit, also when development mode runs effects twice.
  const started = useRef(false);
  useEffect(() => {
    if (started.current || !url.endsWith(".dmg")) return;
    started.current = true;
    window.location.assign(url);
  }, [url]);
  return null;
}
