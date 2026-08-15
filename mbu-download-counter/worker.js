// mbu-download-counter - download/install counter for Minecraft Bedrock Free.
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
  // for-the-badge style (shields.io): 28px tall, square corners, uppercase.
  const label = "DOWNLOADS";
  const value = String(count);
  const charW = 7.7; // approx Verdana uppercase width at 10px
  const pad = 12;
  const labelW = label.length * charW + pad * 2;
  const valueW = Math.max(value.length * charW + pad * 2, 30);
  const totalW = labelW + valueW;
  const labelX = labelW / 2;
  const valueX = labelW + valueW / 2;
  return [
    `<svg xmlns="http://www.w3.org/2000/svg" width="${totalW.toFixed(1)}" height="28" role="img" aria-label="downloads: ${value}">`,
    `<title>downloads: ${value}</title>`,
    `<g shape-rendering="crispEdges">`,
    `<rect width="${labelW}" height="28" fill="#555"/>`,
    `<rect x="${labelW}" width="${valueW}" height="28" fill="#4c1"/>`,
    `</g>`,
    `<g fill="#fff" text-anchor="middle" font-family="Verdana,Geneva,DejaVu Sans,sans-serif" text-rendering="geometricPrecision" font-size="10">`,
    `<text x="${labelX}" y="17.5">${label}</text>`,
    `<text x="${valueX}" y="17.5" font-weight="bold">${value}</text>`,
    `</g>`,
    `</svg>`,
  ].join("");
}
