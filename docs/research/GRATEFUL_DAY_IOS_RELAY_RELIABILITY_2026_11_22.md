---
title: "Grateful Day iOS: why relay.nostr.band and relay.damus.io fail, and what to do"
tags: [grateful-day, ios, relays, sync, priority-b]
status: draft
created: 2026-11-22
---

# Relay reliability: write-up (Priority B, step 1)

Owner: Sous. Requested by Seth (event a2c4450d, §3 Priority B); sequenced by Chief (event 5f4a1f50,
ruling 3: write-up first, code only after Audit rules on #20, stacked the same way, and any change
to the default relays goes to Seth as a proposal).

Code base: `fix/publish-stuck-saving` at d4aa490 (PR #20).

## 1. Evidence

### From the iPhone (PR #20 body, build of d4aa490, 2026-11-22 21:37)

```
relay list read: nos.lol=answered nostr.wine=answered relay.damus.io=failed(send) relay.nostr.band=timedOut relay.primal.net=answered
read before send: ... relay.damus.io=failed(send) relay.nostr.band=failed(connect) ...
sent: kind 36669 3f49f726: nos.lol=OK relay.damus.io=failed(send) relay.primal.net=OK
never connected, dialed once: relay.nostr.band
```

The PR also says both relays failed this way "all evening, from the iPhone and from a Mac".

### Measured from this Mac (2026-11-22, about 03:10 UTC, read-only handshakes, nothing published)

| Relay | DNS | TCP :443 | WebSocket upgrade (HTTP/1.1) |
|---|---|---|---|
| relay.nostr.band | 95.216.33.150 | **no answer** (`nc -z -G 5` fails; curl times out at 8 s with no connect) | never reached |
| relay.damus.io | 104.21.61.55, 172.67.206.128 (Cloudflare) | 23 ms | **`HTTP/1.1 503 Service Unavailable`** |
| nos.lol | 142.132.206.70 | 121 ms | `101 Switching Protocols` |
| relay.primal.net | Cloudflare | 17 ms | `101 Switching Protocols` |
| nostr.wine | Cloudflare | 23 ms | `101 Switching Protocols` |

Commands: `dig +short`, `nc -z -G 5 <ip> 443`, and `curl --http1.1 -D - -H "Upgrade: websocket" ...`.

## 2. Why each one fails

- **relay.nostr.band is down at the network level.** The host doesn't complete a TCP handshake on
  443 or 80. Nothing in our client can fix that. `URLSessionWebSocketTask` doesn't report it either:
  the task sits in "connecting" and the first `send` waits, up to URLSession's 60 s. #20 puts that
  send inside the 8 s page timeout and dials such a relay only once per pass. The cost now is
  **one 8 s wait per pass**, on the first read (the relay-list lookup), which every pass makes.
- **relay.damus.io is up, but its server refuses WebSocket upgrades with 503.** Cloudflare answers
  instantly, so this costs us almost nothing in time: the handshake fails, `send` throws, and the
  outcome is `failed(send)` within milliseconds. It also failed from a Mac, so it isn't specific to
  the iPhone or our client. Whether this is an outage or a block on our kind of client is
  **unknown**. A 503 to plain curl suggests it's on the server side, not about our User-Agent.

### What it does to the safety rules (unchanged, still holding)

- The write set from the defaults is damus, nos.lol and primal. With damus refusing, exactly two
  write relays are reachable, which is the minimum the two-acknowledgement rule needs. **One more
  outage (nos.lol or primal) and nothing can reach synced.** That's correct: it shows as Saving and
  publishes nothing unsafe. But it's a thin margin for broader testing.
- "No other copy" needs two write relays to answer EOSE. The same two relays carry that too.
- Users with their own kind 10002 list aren't affected by the defaults at all.

## 3. Proposed changes

### Code, no change to any relay list (Chief: after Audit rules on #20, stacked)

1. **Remember a relay that never connected for a short while across passes (e.g. 10 minutes, in
   memory only, cleared on background and on account change).** With the save-triggered pass
   (Priority A), passes run more often while the app is open, and each would pay nostr.band's 8 s
   again. A remembered relay is reported exactly as #20's dialed-once relay is: `failed(connect)`.
   That's unknown, never "answered" and never an acknowledgement, so no safety rule is affected.
   Only a socket that never opened is remembered. A 503 (damus) already fails fast and isn't.
2. **Read the journal and the settings at the same time**, not one after the other. Both go to the
   same read set after the relay list resolves. That saves one read's worth of waiting per pass
   when any read relay is slow. The import still runs only after both are complete, and the
   cancellation and `isCurrent` checks stay where they are.
3. **A shorter wait for a socket to open than for a page** (e.g. 4 s to open, 8 s for the page).
   This needs a way to know the socket opened (a `URLSessionWebSocketDelegate` `didOpen`
   callback). It's a larger transport change, so I'd only do it if 1 and 2 aren't enough.
   Lower priority.

None of these change event formats, encryption, the write set, the two-acknowledgement rule or
fetch-before-publish.

### Default relays: decision for Seth (not to be changed without approval)

- **D-R1: drop relay.nostr.band from the iOS read defaults.** It's unreachable at the network
  level, and every pass waits 8 s on it. Reads only, so the write set and "synced" don't change.
  Note: the web app's defaults (gratefulday `src/App.tsx:40-44`) list it too. iOS mirrors web
  (interop spec), so this should be decided for both, or explicitly allowed to differ.
- **D-R2: the provisional write set.** Core memory has "provisional until damus is re-measured"
  (Seth 3f1c5fd4). It's now measured: 503 on every upgrade from two networks tonight. Options:
  (a) keep it and live with a two-relay margin; (b) replace damus in the write set with a relay
  that answers both reads and writes now (nostr.wine answered here, but it's a paid relay and
  accepts writes only from its members, so it **isn't** a write candidate without checking); or
  (c) add a fourth write relay so one outage doesn't stop synced. Any candidate must first be
  measured from the iPhone and the Mac, for both EOSE and `OK true`. **I recommend measuring
  damus again over a day before deciding.** One evening could be an outage.

## 4. Not verified

- These measurements come from one Mac on one network, over about ten minutes. Not from the
  iPhone tonight, and not over time.
- Not checked: whether damus treats requests differently depending on User-Agent or origin. A
  503 to curl suggests it doesn't.
- No relay was written to. Nothing here published anything.
