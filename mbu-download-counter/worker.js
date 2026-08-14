// mbu-download-counter - download/install counter for Minecraft Bedrock Unlocker.
// Module worker (Cloudflare Workers), deployed via ./s.py cloudflare workers-deploy.
//
// Endpoints:
//   GET  /      -> SVG badge "downloads: N" (used in the README <img>)
//   POST /hit   -> increments the counter (fire-and-forget ping from the installer)
//   GET  /json  -> { "downloads": N } (debug)
//
// Storage: Workers KV, binding "COUNTER" (key "downloads"). KV is eventually
// consistent and has no atomic increment; for a one-hit-per-install counter the
// lost-update window is negligible (accepted tradeoff vs a Durable Object).
// Only POST /hit increments, so crawlers fetching the badge never inflate it.

const KEY = "downloads";

export default {
  async fetch(request, env) {
    const url = new URL(request.url);
    const cors = { "Access-Control-Allow-Origin": "*" };

    if (url.pathname === "/hit") {
      if (request.method === "OPTIONS") {
        return new Response(null, { status: 204, headers: cors });
      }
      const current = parseInt((await env.COUNTER.get(KEY)) || "0", 10) || 0;
      const next = current + 1;
      await env.COUNTER.put(KEY, String(next));
      return new Response(JSON.stringify({ downloads: next }), {
        headers: {
          "Content-Type": "application/json",
          "Cache-Control": "no-store",
          ...cors,
        },
      });
    }

    if (url.pathname === "/json") {
      const n = parseInt((await env.COUNTER.get(KEY)) || "0", 10) || 0;
      return new Response(JSON.stringify({ downloads: n }), {
        headers: {
          "Content-Type": "application/json",
          "Cache-Control": "no-store",
          ...cors,
        },
      });
    }

    const n = parseInt((await env.COUNTER.get(KEY)) || "0", 10) || 0;
    return new Response(badge(n), {
      headers: {
        "Content-Type": "image/svg+xml;charset=utf-8",
        "Cache-Control": "public, max-age=300",
      },
    });
  },
};

function badge(count) {
  const label = "downloads";
  const value = String(count);
  const labelW = 10 * label.length + 18;
  const valueW = 10 * value.length + 18;
  const totalW = labelW + valueW;
  const labelX = labelW / 2;
  const valueX = labelW + valueW / 2;
  return [
    `<svg xmlns="http://www.w3.org/2000/svg" width="${totalW}" height="20" role="img" aria-label="downloads: ${value}">`,
    `<title>downloads: ${value}</title>`,
    `<linearGradient id="s" x2="0" y2="100%">`,
    `<stop offset="0" stop-color="#bbb" stop-opacity=".1"/>`,
    `<stop offset="1" stop-opacity=".1"/>`,
    `</linearGradient>`,
    `<clipPath id="r"><rect width="${totalW}" height="20" rx="3" fill="#fff"/></clipPath>`,
    `<g clip-path="url(#r)">`,
    `<rect width="${labelW}" height="20" fill="#555"/>`,
    `<rect x="${labelW}" width="${valueW}" height="20" fill="#4c1"/>`,
    `<rect width="${totalW}" height="20" fill="url(#s)"/>`,
    `</g>`,
    `<g fill="#fff" text-anchor="middle" font-family="Verdana,DejaVu Sans,sans-serif" font-size="11">`,
    `<text x="${labelX}" y="15" fill="#010101" fill-opacity=".3">${label}</text>`,
    `<text x="${labelX}" y="14">${label}</text>`,
    `<text x="${valueX}" y="15" fill="#010101" fill-opacity=".3">${value}</text>`,
    `<text x="${valueX}" y="14">${value}</text>`,
    `</g>`,
    `</svg>`,
  ].join("");
}
