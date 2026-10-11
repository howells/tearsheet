// Runs in the front browser tab. Reports the viewport and every element in view
// that shows an image, as JSON for PageScan in TearsheetCore. Read-only: it
// changes nothing on the page.
(() => {
  const width = innerWidth;
  const height = innerHeight;
  const elements = [];
  const limit = 4000;

  const inView = (r) => r.width > 0 && r.height > 0 && r.right > 0 && r.bottom > 0 && r.left < width && r.top < height;
  const box = (r) => ({ x: r.left, y: r.top, width: r.width, height: r.height });
  const isHidden = (style) => style.display === "none" || style.visibility === "hidden" || parseFloat(style.opacity) === 0;

  const serialiseSVG = (svg, rect, style) => {
    const clone = svg.cloneNode(true);
    clone.setAttribute("xmlns", "http://www.w3.org/2000/svg");
    if (!clone.getAttribute("width")) clone.setAttribute("width", String(Math.round(rect.width)));
    if (!clone.getAttribute("height")) clone.setAttribute("height", String(Math.round(rect.height)));
    // currentColor is inherited from the page; pin it so the file looks the same alone.
    clone.style.color = style.color;
    // Sprite icons point at symbols elsewhere in the document; bring them along.
    for (const use of clone.querySelectorAll("use")) {
      const ref = use.getAttribute("href") || use.getAttribute("xlink:href") || "";
      if (!ref.startsWith("#")) continue;
      const symbol = document.getElementById(ref.slice(1));
      if (!symbol) continue;
      let defs = clone.querySelector("defs");
      if (!defs) {
        defs = document.createElementNS("http://www.w3.org/2000/svg", "defs");
        clone.insertBefore(defs, clone.firstChild);
      }
      if (!defs.querySelector(`[id="${CSS.escape(symbol.id)}"]`)) defs.appendChild(symbol.cloneNode(true));
    }
    return new XMLSerializer().serializeToString(clone);
  };

  const visit = (el) => {
    if (elements.length >= limit || el.ownerSVGElement) return;
    const rect = el.getBoundingClientRect();
    if (!inView(rect)) return;
    const style = getComputedStyle(el);
    if (isHidden(style)) return;
    const tag = el.localName;

    if (tag === "img") {
      const srcsets = [];
      if (el.srcset) srcsets.push(el.srcset);
      const picture = el.parentElement && el.parentElement.localName === "picture" ? el.parentElement : null;
      if (picture) {
        for (const source of picture.querySelectorAll(":scope > source")) {
          if (source.srcset && (!source.media || matchMedia(source.media).matches)) srcsets.push(source.srcset);
        }
      }
      elements.push({ kind: "img", ...box(rect), src: el.getAttribute("src") ? el.src : "", currentSrc: el.currentSrc || "", srcsets });
    } else if (tag === "svg") {
      elements.push({ kind: "svg", ...box(rect), svg: serialiseSVG(el, rect, style) });
    } else if (tag === "video" && el.poster) {
      elements.push({ kind: "poster", ...box(rect), src: el.poster });
    }

    for (const pseudo of [null, "::before", "::after"]) {
      const layerStyle = pseudo ? getComputedStyle(el, pseudo) : style;
      const background = layerStyle.backgroundImage;
      if (background && background.includes("url(")) elements.push({ kind: "background", ...box(rect), background });
      if (pseudo && layerStyle.content && layerStyle.content.startsWith("url(")) {
        elements.push({ kind: "background", ...box(rect), background: layerStyle.content });
      }
    }
  };

  const walk = (root) => {
    for (const el of root.querySelectorAll("*")) {
      visit(el);
      if (el.shadowRoot) walk(el.shadowRoot);
    }
  };
  walk(document);

  return JSON.stringify({
    metrics: { innerWidth: width, innerHeight: height, devicePixelRatio, baseURL: document.baseURI },
    elements,
  });
})();
