// node --test deploy/realms/  (or: bun test deploy/realms/)
import { test } from "node:test";
import assert from "node:assert/strict";
import { Listing, cleanCard, serve, CARD_TTL_MS, RATE_PER_MINUTE } from "./realms.mjs";

const ADA = { id: "ADA0000001", token: "a".repeat(32) };
const GRACE = { id: "GRACE00002", token: "b".repeat(32) };
const MALLORY = { id: "MALL000003", token: "c".repeat(32) };
const card = (extra = {}) => ({ name: "Ada's room", owner: "Ada", code: "N6UU9K", players: 2, song: "Tune", tempo: 120, door: false, visibility: "anyone", friends: [], ...extra });

test("a card is cleaned: the fields kept, each checked", () => {
  assert.equal(cleanCard({ ...card(), code: "bad code" }), null);
  assert.equal(cleanCard({ ...card(), visibility: "everyone" }), null);
  const c = cleanCard({ ...card(), name: "x".repeat(99) + "\n", players: 900, tempo: -4, extra: 1, friends: ["nope", GRACE.id] });
  assert.equal(c.name.length, 40);
  assert.equal(c.players, 64);
  assert.equal(c.tempo, 0);
  assert.equal(c.extra, undefined);
  assert.deepEqual(c.friends, [GRACE.id]);
});

test("open, listed for others, not for its owner, closed", () => {
  const l = new Listing();
  assert.equal(l.open({ ...ADA, card: card() }).status, 200);
  assert.deepEqual(l.list(ADA).body.realms, []);
  const seen = l.list(GRACE).body.realms;
  assert.equal(seen.length, 1);
  assert.equal(seen[0].id, ADA.id);
  assert.equal(seen[0].friends, undefined, "a card never shows its owner's friends");
  assert.equal(l.close(ADA).status, 200);
  assert.deepEqual(l.list(GRACE).body.realms, []);
});

test("a friends card is seen only by its owner's friends", () => {
  const l = new Listing();
  l.open({ ...ADA, card: card({ visibility: "friends", friends: [GRACE.id] }) });
  assert.equal(l.list(GRACE).body.realms.length, 1);
  assert.equal(l.list(GRACE).body.realms[0].friend, true);
  assert.equal(l.list(MALLORY).body.realms.length, 0);
});

test("an id is its first token's: nobody else posts, closes or lists as it", () => {
  const l = new Listing();
  l.open({ ...ADA, card: card({ visibility: "friends", friends: [GRACE.id] }) });
  l.list(GRACE);
  assert.equal(l.open({ id: ADA.id, token: MALLORY.token, card: card() }).status, 403);
  assert.equal(l.close({ id: ADA.id, token: MALLORY.token }).status, 403);
  assert.equal(l.list({ id: GRACE.id, token: MALLORY.token }).status, 403);
  assert.equal(l.list({ id: "short", token: GRACE.token }).status, 403);
});

test("a card not refreshed is gone after its time", () => {
  let t = 1_000_000;
  const l = new Listing(() => t);
  l.open({ ...ADA, card: card() });
  t += CARD_TTL_MS - 1;
  assert.equal(l.list(GRACE).body.realms.length, 1);
  t += 2;
  assert.equal(l.list(GRACE).body.realms.length, 0);
});

test("an address asking too often is slowed", () => {
  const l = new Listing(() => 0);
  for (let i = 0; i < RATE_PER_MINUTE; i++) assert.ok(l.allowed("1.2.3.4"));
  assert.ok(!l.allowed("1.2.3.4"));
  assert.ok(l.allowed("5.6.7.8"));
});

test("over HTTP: health, open, list, refusals", async () => {
  const server = serve(new Listing(), 0);
  await new Promise((r) => server.once("listening", r));
  const base = `http://127.0.0.1:${server.address().port}/realms`;
  const post = async (path, body) => {
    const r = await fetch(base + path, { method: "POST", body: typeof body === "string" ? body : JSON.stringify(body) });
    return { status: r.status, body: await r.json() };
  };
  try {
    assert.equal(await (await fetch(base + "/health")).text(), "ok");
    assert.equal((await post("/open", { ...ADA, card: card() })).status, 200);
    const listed = await post("/list", GRACE);
    assert.equal(listed.body.realms[0].code, "N6UU9K");
    assert.equal((await post("/list", "not json")).status, 400);
    assert.equal((await post("/open", { ...ADA, card: card(), pad: "x".repeat(9000) })).status, 413);
    assert.equal((await fetch(base + "/nothing", { method: "POST", body: "{}" })).status, 404);
  } finally {
    server.close();
  }
});
