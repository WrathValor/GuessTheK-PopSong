// likes-worker: a Cloudflare Worker that tells the game how many likes it has.
// Roblox game servers can't call roblox.com themselves, so Engine/LikeGoalService calls this:
//   GET https://<your-worker>.workers.dev/?universeId=<game.GameId>
//   → { "universeId": 123, "likes": 1240, "dislikes": 80 }
// Each universe's count is kept for 60 seconds, so busy servers don't hammer Roblox.

const CACHE_SECONDS = 60;

function json(body, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { "content-type": "application/json", "cache-control": `max-age=${CACHE_SECONDS}` },
  });
}

export default {
  async fetch(request, env, ctx) {
    const url = new URL(request.url);
    const id = url.searchParams.get("universeId") || "";
    if (!/^\d{1,15}$/.test(id)) {
      return json({ error: "add ?universeId=<your game's universe id>" }, 400);
    }

    const cache = caches.default;
    const key = new Request(`https://likes-cache/${id}`);
    const cached = await cache.match(key);
    if (cached) return cached;

    const res = await fetch(`https://games.roblox.com/v1/games/votes?universeIds=${id}`, {
      headers: { accept: "application/json" },
    });
    if (!res.ok) return json({ error: `roblox said ${res.status}` }, 502);
    const data = await res.json();
    const votes = data && data.data && data.data[0];
    if (!votes) return json({ error: "no game with that universe id" }, 404);

    const out = json({ universeId: Number(id), likes: votes.upVotes, dislikes: votes.downVotes });
    ctx.waitUntil(cache.put(key, out.clone()));
    return out;
  },
};
