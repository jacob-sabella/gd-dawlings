// The realm listing (docs/realms.md, step 1): which realms are open now, for the lobby.
//
// A host that is online by a noray code posts a short card about its realm every 30 seconds or so; a card not
// refreshed for CARD_TTL_MS is gone. A player asking for the list gets the cards it may see: every "anyone" card,
// and the "friends" cards whose owner has put this player's id among its friends. Nothing is written to disk, and
// nothing is kept about a realm once its card has gone.
//
// Who is who: each game makes a realm id (its friend code) and a secret token once, and keeps them. The first
// request naming an id binds the token to it; every later one must carry the same token. Not accounts: enough
// that knowing someone's friend code does not let you post their card or see what their friends see.
//
// Plain node:http, no packages, so it runs the same on bun (the VPS, beside noray) and on node (the tests).
//
// POST /realms/open   {id, token, card}  -> {ok, ttl}
// POST /realms/close  {id, token}        -> {ok}
// POST /realms/list   {id, token}        -> {ok, realms: [card + {id}]}
// GET  /realms/health                    -> ok

import http from "node:http";

export const CARD_TTL_MS = 90_000;
export const MAX_BODY = 8 * 1024;
export const MAX_CARDS = 5000;
export const MAX_BINDINGS = 50_000;
export const MAX_FRIENDS = 200;
export const RATE_PER_MINUTE = 60;
const ID = /^[A-Z0-9]{10}$/;
const TOKEN = /^[a-f0-9]{32}$/;
const CODE = /^[A-Za-z0-9]{4,24}$/;
// A noray server, host or host:port: where the code is good.
const SERVER = /^[A-Za-z0-9.-]{1,80}(:[0-9]{1,5})?$/;
const VISIBILITY = ["anyone", "friends"];

// One line of text: no control characters, at most `most` characters.
function line(v, most) {
  if (typeof v !== "string") return "";
  return v.replace(/[\u0000-\u001f\u007f]/g, " ").trim().slice(0, most);
}

// The card as it is kept: only the fields the lobby shows, each checked. Null for one that will not do.
export function cleanCard(c) {
  if (c === null || typeof c !== "object" || Array.isArray(c)) return null;
  const code = typeof c.code === "string" ? c.code : "";
  if (!CODE.test(code)) return null;
  const visibility = VISIBILITY.includes(c.visibility) ? c.visibility : null;
  if (visibility === null) return null;
  const friends = Array.isArray(c.friends) ? c.friends.filter((f) => typeof f === "string" && ID.test(f)).slice(0, MAX_FRIENDS) : [];
  const players = Number.isInteger(c.players) ? Math.min(Math.max(c.players, 1), 64) : 1;
  const tempo = typeof c.tempo === "number" && Number.isFinite(c.tempo) ? Math.min(Math.max(Math.round(c.tempo), 0), 999) : 0;
  return {
    name: line(c.name, 40) || "A realm",
    owner: line(c.owner, 32) || "Someone",
    code,
    server: typeof c.server === "string" && SERVER.test(c.server) ? c.server : "",
    players,
    song: line(c.song, 60),
    tempo,
    door: c.door === true,
    visibility,
    friends,
  };
}

export class Listing {
  constructor(now = () => Date.now()) {
    this.now = now;
    this.cards = new Map(); // id -> {card, until}
    this.tokens = new Map(); // id -> token, oldest first
    this.hits = new Map(); // address -> [minute, count]
  }

  // Whether `address` may ask again this minute.
  allowed(address) {
    const minute = Math.floor(this.now() / 60_000);
    const h = this.hits.get(address);
    if (h === undefined || h[0] !== minute) {
      if (this.hits.size > 20_000) this.hits.clear();
      this.hits.set(address, [minute, 1]);
      return true;
    }
    h[1] += 1;
    return h[1] <= RATE_PER_MINUTE;
  }

  // True when `token` is the one bound to `id`, binding it if `id` has none yet.
  owns(id, token) {
    if (typeof id !== "string" || typeof token !== "string" || !ID.test(id) || !TOKEN.test(token)) return false;
    const had = this.tokens.get(id);
    if (had !== undefined) {
      // Kept as the newest, so a busy id is the last to be forgotten.
      this.tokens.delete(id);
      this.tokens.set(id, had);
      return had === token;
    }
    if (this.tokens.size >= MAX_BINDINGS) this.tokens.delete(this.tokens.keys().next().value);
    this.tokens.set(id, token);
    return true;
  }

  sweep() {
    const t = this.now();
    for (const [id, c] of this.cards) if (c.until <= t) this.cards.delete(id);
  }

  // Each answer is {status, body}.
  open(req) {
    if (!this.owns(req.id, req.token)) return { status: 403, body: { ok: false, error: "not your realm" } };
    const card = cleanCard(req.card);
    if (card === null) return { status: 400, body: { ok: false, error: "that card will not do" } };
    this.sweep();
    if (!this.cards.has(req.id) && this.cards.size >= MAX_CARDS) return { status: 503, body: { ok: false, error: "the lobby is full" } };
    this.cards.set(req.id, { card, until: this.now() + CARD_TTL_MS });
    return { status: 200, body: { ok: true, ttl: CARD_TTL_MS / 1000 } };
  }

  close(req) {
    if (!this.owns(req.id, req.token)) return { status: 403, body: { ok: false, error: "not your realm" } };
    this.cards.delete(req.id);
    return { status: 200, body: { ok: true } };
  }

  list(req) {
    if (!this.owns(req.id, req.token)) return { status: 403, body: { ok: false, error: "who is asking?" } };
    this.sweep();
    const realms = [];
    for (const [id, c] of this.cards) {
      if (id === req.id) continue;
      if (c.card.visibility === "friends" && !c.card.friends.includes(req.id)) continue;
      const { friends, ...shown } = c.card;
      realms.push({ id, ...shown, friend: friends.includes(req.id) });
    }
    realms.sort((a, b) => Number(b.friend) - Number(a.friend) || b.players - a.players || a.name.localeCompare(b.name));
    return { status: 200, body: { ok: true, realms: realms.slice(0, 200) } };
  }
}

// The address a request came from: Caddy's X-Forwarded-For when it came through Caddy on this machine.
function addressOf(req) {
  const direct = req.socket.remoteAddress || "";
  const forwarded = req.headers["x-forwarded-for"];
  if ((direct === "127.0.0.1" || direct === "::1" || direct === "::ffff:127.0.0.1") && typeof forwarded === "string") {
    return forwarded.split(",")[0].trim();
  }
  return direct;
}

export function serve(listing = new Listing(), port = 8891, host = "127.0.0.1") {
  const server = http.createServer((req, res) => {
    const send = (status, body) => {
      const text = typeof body === "string" ? body : JSON.stringify(body);
      res.writeHead(status, { "content-type": typeof body === "string" ? "text/plain" : "application/json", "cache-control": "no-store" });
      res.end(text);
    };
    const path = (req.url || "").split("?")[0];
    if (req.method === "GET" && path === "/realms/health") return send(200, "ok");
    const route = { "/realms/open": "open", "/realms/close": "close", "/realms/list": "list" }[path];
    if (req.method !== "POST" || route === undefined) return send(404, { ok: false, error: "no such thing" });
    if (!listing.allowed(addressOf(req))) return send(429, { ok: false, error: "too many asks: wait a minute" });
    let size = 0;
    const chunks = [];
    let refused = false;
    req.on("data", (c) => {
      size += c.length;
      if (size > MAX_BODY) {
        refused = true;
        send(413, { ok: false, error: "too big" });
        req.destroy();
        return;
      }
      chunks.push(c);
    });
    req.on("end", () => {
      if (refused) return;
      let body;
      try {
        body = JSON.parse(Buffer.concat(chunks).toString("utf8"));
      } catch {
        return send(400, { ok: false, error: "not JSON" });
      }
      if (body === null || typeof body !== "object") return send(400, { ok: false, error: "not an object" });
      const answer = listing[route](body);
      send(answer.status, answer.body);
    });
  });
  server.listen(port, host);
  return server;
}

// Run as a program: REALMS_PORT (8891) on REALMS_HOST (127.0.0.1, behind Caddy).
if (import.meta.main || (typeof process !== "undefined" && process.argv[1] && import.meta.url === `file://${process.argv[1]}`)) {
  const port = Number(process.env.REALMS_PORT || 8891);
  const host = process.env.REALMS_HOST || "127.0.0.1";
  serve(new Listing(), port, host);
  console.log(`realms: listening on ${host}:${port}`);
}
