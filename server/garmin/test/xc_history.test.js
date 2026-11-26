import test from "node:test";
import assert from "node:assert/strict";
import { DatabaseSync } from "node:sqlite";
import { XcHistory } from "../src/xc_history.js";

test("bound ranges are contiguous, rate limits and refusals do not advance, revocation removes jobs", async () => {
  const db = new DatabaseSync(":memory:");
  db.exec("CREATE TABLE subscription(owner TEXT PRIMARY KEY); INSERT INTO subscription VALUES ('one'),('two')");
  const h = new XcHistory(db), now = 1700000000;
  h.enroll("one",["ACTIVITY_EXPORT"],false,now);
  assert.equal(h.status("two").length,0);
  let j = h.next(now), from;
  assert.equal(j.feed,"activities");
  await h.step(j,now,(_,a,b) => {from=a; assert.equal(b,now); return new Response(null,{status:202});});
  let next = h.status("one")[0];
  assert.equal(next.until_s,from-1);
  await h.step({...j,...next},now,() => new Response(null,{status:429,headers:{"retry-after":"900"}}));
  assert.equal(h.status("one")[0].until_s,from-1);
  assert.equal(h.next(now+60),undefined);
  await h.step({...j,...next},now+900,() => new Response(null,{status:403}));
  assert.equal(h.status("one")[0].state,"denied");
  h.enroll("one",["HEALTH_EXPORT","MCT_EXPORT"],false,now);
  assert.equal(h.status("one").some(x=>["activities","mct"].includes(x.feed)),false);
  h.enroll("one",["MCT_EXPORT"],true,now);
  assert.deepEqual(h.status("one").map(x=>x.feed),["mct"]);
  db.close();
});
