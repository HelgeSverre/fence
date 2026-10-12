// Canvas resolves OKLCH/color-mix tokens to the hex colors Mermaid needs.
export function diagramTheme() {
  const css = getComputedStyle(document.documentElement);
  const preview = document.querySelector(".preview-content");
  const typography = getComputedStyle(preview || document.documentElement);
  const canvas = document.createElement("canvas");
  canvas.width = canvas.height = 1;
  const ctx = canvas.getContext("2d", { willReadFrequently: true });
  const color = (token) => {
    ctx.clearRect(0, 0, 1, 1);
    ctx.fillStyle = css.getPropertyValue(token).trim();
    ctx.fillRect(0, 0, 1, 1);
    return `#${[...ctx.getImageData(0, 0, 1, 1).data].slice(0, 3)
      .map((v) => v.toString(16).padStart(2, "0")).join("")}`;
  };
  const t = {
    surface: color("--diagram-surface"), node: color("--diagram-node"),
    border: color("--diagram-node-border"), cluster: color("--diagram-cluster"),
    clusterBorder: color("--diagram-cluster-border"), line: color("--diagram-line"),
    text: color("--diagram-text"), muted: color("--diagram-muted"), alt: color("--diagram-alt"),
    font: typography.fontFamily, size: typography.fontSize,
  };
  const [r, g, b] = t.surface.slice(1).match(/.{2}/g).map((channel) => parseInt(channel, 16));
  t.dark = r * 0.299 + g * 0.587 + b * 0.114 < 128;
  return t;
}

export function diagramConfig(t) {
  const fit = { useMaxWidth: false };
  return {
    startOnLoad: false, securityLevel: "strict", suppressErrorRendering: true,
    // Neo adds drop shadows; classic keeps the diagram flat.
    theme: "base", look: "classic", layout: "elk", htmlLabels: false,
    fontFamily: t.font,
    themeVariables: {
      darkMode: t.dark, fontFamily: t.font, fontSize: t.size,
      background: t.surface, primaryColor: t.node, primaryTextColor: t.text,
      primaryBorderColor: t.border, secondaryColor: t.cluster,
      secondaryTextColor: t.text, secondaryBorderColor: t.clusterBorder,
      tertiaryColor: t.alt, tertiaryTextColor: t.text, tertiaryBorderColor: t.border,
      textColor: t.text, titleColor: t.text, lineColor: t.line,
      mainBkg: t.node, nodeBkg: t.node, nodeBorder: t.border, nodeTextColor: t.text,
      clusterBkg: t.cluster, clusterBorder: t.clusterBorder, edgeLabelBackground: t.surface,
      actorBkg: t.node, actorBorder: t.border, actorTextColor: t.text, actorLineColor: t.line,
      signalColor: t.line, signalTextColor: t.text, labelBoxBkgColor: t.surface,
      labelBoxBorderColor: t.clusterBorder, labelTextColor: t.text, loopTextColor: t.text,
      noteBkgColor: t.cluster, noteTextColor: t.text, noteBorderColor: t.clusterBorder,
      activationBkgColor: t.alt, activationBorderColor: t.border,
      sectionBkgColor: t.cluster, altSectionBkgColor: t.surface, sectionBkgColor2: t.alt,
      taskBkgColor: t.node, taskBorderColor: t.border, taskTextColor: t.text,
      taskTextLightColor: t.text, taskTextOutsideColor: t.text, taskTextDarkColor: t.text,
      activeTaskBkgColor: t.alt, activeTaskBorderColor: t.border,
      doneTaskBkgColor: t.cluster, doneTaskBorderColor: t.clusterBorder,
      critBkgColor: t.alt, critBorderColor: t.border, gridColor: t.clusterBorder,
      todayLineColor: t.border, labelColor: t.text, altBackground: t.cluster,
    },
    themeCSS: `
      .nodeLabel, .node text { font-size: ${t.size}; font-weight: 600; }
      .node rect { rx: 8px; ry: 8px; }
      .cluster rect { rx: 8px; ry: 8px; }
      .edgeLabel rect { rx: 11px; ry: 11px; fill: ${t.surface}; stroke: ${t.clusterBorder}; stroke-width: 1px; opacity: 1; }
      .flowchart-link, .edgePath .path { stroke-width: 1.25px; stroke-linecap: round; stroke-linejoin: round; }
      .cluster-label text { fill: ${t.muted}; font-weight: 600; }
    `,
    flowchart: { ...fit, htmlLabels: false, padding: 14, nodeSpacing: 40, rankSpacing: 50 },
    sequence: { ...fit, actorFontFamily: t.font, noteFontFamily: t.font, messageFontFamily: t.font,
      actorFontSize: parseFloat(t.size), noteFontSize: parseFloat(t.size), messageFontSize: parseFloat(t.size) },
    ...Object.fromEntries(["state", "class", "er", "gantt", "pie", "journey", "timeline", "mindmap",
      "gitGraph", "quadrantChart", "xyChart", "requirement", "c4", "sankey", "block",
      "packet", "architecture", "radar"].map((name) => [name, fit])),
    mindmap: { ...fit, layout: "cose-bilkent" },
  };
}

export function polishDiagram(svg, t) {
  // Use Mermaid's measurements; getBBox cannot measure this detached SVG.
  for (const rect of svg.querySelectorAll(".edgeLabel rect.background")) {
    const width = Number(rect.getAttribute("width"));
    if (!width) continue;
    rect.setAttribute("x", String(Number(rect.getAttribute("x")) - 6));
    rect.setAttribute("width", String(width + 12));
  }
  for (const marker of svg.querySelectorAll('marker[id*="pointEnd"], marker[id*="pointStart"]')) {
    const end = marker.id.includes("pointEnd");
    marker.setAttribute("viewBox", "-5 -5 10 10");
    marker.setAttribute("markerWidth", "10");
    marker.setAttribute("markerHeight", "10");
    marker.setAttribute("refX", end ? "1" : "-1");
    marker.setAttribute("refY", "0");
    for (const path of marker.querySelectorAll("path")) {
      path.setAttribute("d", end ? "M -3 -3.5 L 1 0 L -3 3.5" : "M 3 -3.5 L -1 0 L 3 3.5");
      path.style.cssText = `fill: none; stroke: ${t.line}; stroke-width: 1.25; stroke-linecap: round; stroke-linejoin: round; stroke-dasharray: none`;
    }
  }
}
