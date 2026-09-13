
const KEY = "downloads"
const DEDUPE_TTL_SECONDS = 900
const CORS = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
  "Access-Control-Allow-Headers": "Content-Type",
}

export default {
  async fetch(request, env) {
    const url = new URL(request.url)

    if (url.pathname === "/hit") {
      if (request.method === "OPTIONS") {
        return new Response(null, { status: 204, headers: CORS })
      }
      if (request.method !== "POST") {
        return new Response(JSON.stringify({ error: "use POST" }), {
          status: 405,
          headers: { "Content-Type": "application/json", Allow: "POST, OPTIONS", ...CORS },
        })
      }

      const current = await readCount(env)

      let deduped = false
      try {
        const window = Math.floor(Date.now() / (DEDUPE_TTL_SECONDS * 1000))
        const ip = request.headers.get("CF-Connecting-IP") || ""
        const dedupeKey = "dedupe:" + window + ":" + (await hashShort(ip))
        if (await env.COUNTER.get(dedupeKey)) {
          deduped = true
        } else {
          await env.COUNTER.put(dedupeKey, "1", { expirationTtl: DEDUPE_TTL_SECONDS })
        }
      } catch {
        deduped = false
      }

      if (deduped) {
        return json({ downloads: current, counted: false, reason: "dup" })
      }

      const next = current + 1
      await env.COUNTER.put(KEY, String(next))
      return json({ downloads: next, counted: true })
    }

    if (url.pathname === "/json") {
      return json({ downloads: await readCount(env) })
    }

    const n = await readCount(env)
    return new Response(badge(n), {
      headers: {
        "Content-Type": "image/svg+xml",
        "Cache-Control": "public, max-age=300",
      },
    })
  },
}

async function readCount(env) {
  return parseInt((await env.COUNTER.get(KEY)) || "0", 10) || 0
}

function json(body) {
  return new Response(JSON.stringify(body), {
    headers: { "Content-Type": "application/json", "Cache-Control": "no-store", ...CORS },
  })
}

async function hashShort(value) {
  if (!value) return "none"
  const data = new TextEncoder().encode(value)
  const digest = await crypto.subtle.digest("SHA-256", data)
  return [...new Uint8Array(digest)]
    .map((b) => b.toString(16).padStart(2, "0"))
    .join("")
    .slice(0, 16)
}

function badge(count) {
  const label = "DOWNLOADS"
  const value = String(count)
  const charW = 7.7
  const pad = 12
  const labelW = label.length * charW + pad * 2
  const valueW = Math.max(value.length * charW + pad * 2, 30)
  const totalW = labelW + valueW
  const labelX = labelW / 2
  const valueX = labelW + valueW / 2
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
  ].join("")
}
