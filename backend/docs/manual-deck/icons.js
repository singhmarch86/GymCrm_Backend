// Renders react-icons (Feather set) to PNG data URIs, tinted white, for use
// as pptxgenjs images inside colored circles.
const React = require("react");
const ReactDOMServer = require("react-dom/server");
const sharp = require("sharp");
const Fi = require("react-icons/fi");

async function iconPng(name, { size = 256, color = "FFFFFF" } = {}) {
  const Icon = Fi[name];
  if (!Icon) throw new Error(`Unknown icon: ${name}`);
  const svg = ReactDOMServer.renderToStaticMarkup(
    React.createElement(Icon, { size, color: `#${color}` })
  );
  const full = `<?xml version="1.0" encoding="UTF-8"?>${svg}`;
  const buf = await sharp(Buffer.from(full)).png().toBuffer();
  return "image/png;base64," + buf.toString("base64");
}

module.exports = { iconPng };
