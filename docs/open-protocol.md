# Fallout Forecast Open Protocol v1

The Open Protocol lets clients participate in the same four-player Fallout Forecast lobby
and run as native Godot clients. The **Thin** tier runs world simulation, player movement,
and combat on the dedicated server. A Thin client sends controls and draws the resulting
state. The **Full** tier is reserved for clients that run their own simulation. Native
Godot clients use their existing endpoint and game protocol.

## Common envelope and transport

| Transport | Default port | Framing |
| --- | ---: | --- |
| WebSocket | 7780 | One complete Open Protocol message per WebSocket message. UTF-8 JSON uses the text opcode. Binary uses the binary opcode. WebSocket fragmentation is handled by the transport. |
| Raw TCP | 7781 | Four-byte unsigned little-endian payload length, followed by exactly that many bytes. The length excludes its own four bytes. There are no delimiters or padding. Buffer fragmented reads and split coalesced frames. |
| Native Godot WebSocket | 7777 | Existing game endpoint. The Open Protocol described here uses the other two ports. |

Both Open Protocol listeners accept plaintext. Use a TLS-terminating proxy for
public `wss://`. The raw TCP listener provides no encryption. Both ports can be configured
or disabled independently. A shared code, when configured, applies to both transports and
both tiers. It is sent inside the hello message. An Open Protocol connection identifies
one player, and players from all transports share the four-player cap.

Send a JSON object with a string `t` on every JSON message. UTF-8 has no BOM.
A raw TCP frame whose first payload byte is `0x00` through `0x08` is binary. JSON may
start with `{` or JSON whitespace. The server accepts payload lengths from 1 to
65,536 bytes inclusive. A server-to-client raw payload can be larger, up to 524,284
bytes. Read a complete frame before interpreting it. There is no application-level
compression. Binary payloads and their lengths use little-endian byte order. Ignore
unrecognized JSON keys and message types from a compatible server. A major incompatible
change requires a new `v`. The separate `game_protocol` number is the native game's
protocol version.

### Connection lifecycle

1. Open the transport. On WebSocket, wait for the upgrade. Send a JSON `hello`
   within five seconds after transport acceptance. Send one hello per connection
   and wait for the response before sending any tier messages.
2. The server can reply with `error` and close, or hand the connection to the selected
   tier, which sends `welcome`. Thin sends `welcome`, `status` with `state:"lobby"`,
   then the first `lobby`. A thin client joining during a run receives the loading
   sequence immediately after that initial lobby.
3. Exchange messages for the chosen tier. A client can send `ping` at any time
   after welcome. The server replies with `pong`. Either side may use those messages
   to measure round-trip time without synchronizing clocks.
4. To leave, Thin sends `{"t":"leave"}`. The server sends `status` with
   `state:"disconnected"`, removes the player, and closes the connection. A detected
   socket closure also removes the player. Use a new connection to rejoin.

| JSON message | Direction | Fields |
| --- | --- | --- |
| `hello` | Client → server, first | `v` integer `1`. `tier` string `"thin"` or `"full"`, default `"thin"`. `enc` string `"json"` or `"bin"`, default `"json"`. `name` string, visible callsign of up to 18 characters. `client` optional client/version string. `code` string required only when the server requires a join code. Tier-specific fields are listed below. |
| `welcome` | Server → client | `v` integer. `game_protocol` integer. `you` positive integer peer ID scoped to the server session. `tier` and `enc` are the accepted values. Thin includes the negotiated settings and maps below. |
| `error` | Server → client | `msg` string. Terminal error. Close follows. Clients can display the string without parsing it. |
| `ping`, `pong` | Either direction | `ms` integer sender clock in milliseconds. Echo the value unchanged as `pong`. These JSON messages are separate from WebSocket control frames. |

Blank or missing callsigns become `THIN PLAYER` on the Thin tier. The server
removes control characters, replaces square brackets with parentheses, strips
outer whitespace and limits the result to 18 characters.

Error examples include `Expected hello with Open Protocol v1` for an incorrect
first message or version, `Expected an Open Protocol message` for an invalid
message envelope or binary input frame, `Invalid join code`, `Unsupported encoding`,
`Unsupported tier`, `SERVER FULL` and `full tier unavailable` when that tier
is absent from the server. A malformed transport frame, hello timeout, or exhausted
output buffer can close the socket without an `error`. The server accepts at most
12 concurrent Thin/listener-side connections including pending hellos. The game
still admits at most four players across transports.

### Raw TCP framing example

The JSON payload `{"t":"ping","ms":7}` is 19 bytes. Write these 23 bytes on raw TCP:

```text
13 00 00 00 7b 22 74 22 3a 22 70 69 6e 67 22 2c 22 6d 73 22 3a 37 7d
```

On WebSocket send only the 19-byte JSON payload as text.

### Server-side tier handoff

A Full hello that passes common validation transfers ownership of the connection to
`load("res://game/open_protocol/full_tier.gd").accept(conn, hello)`. The Full tier
sends its welcome or error. The listener reads only the first frame before transfer,
leaves queued frames in the connection, and stops polling it. The tier must retain
and poll the connection, handle messages and disconnections, and release it.

| Connection member | Contract |
| --- | --- |
| `peer_address: String` | TCP peer IP as seen by the server, possibly the reverse proxy. |
| `encoding: String` | Negotiated `"json"` or `"bin"`. |
| `poll(limit = 64)` | Advances the transport and returns up to `limit` messages in order as dictionaries with `data: PackedByteArray` and `text: bool`. Poll at least once per server frame while open or closing. |
| `send_message(message: Dictionary)` | Serializes one JSON text message and queues it on the active transport. |
| `send_binary(payload: PackedByteArray)` | Queues one already-encoded binary message without adding a type byte. The wire adds TCP framing when it applies. |
| `close(reason = "")` | Initiates a close, allowing queued data to flush for up to one second. Send any JSON status or error before calling this. An optional reason is carried in the WebSocket close frame. |
| `closing: bool`, `closed: bool` | Close in progress and terminal transport state. Check `closed` after polling. |
| `dispose()` | Releases the transport immediately. Use after polling to `closed`, or when aborting. |

## Thin tier

Thin clients send controls at 30 Hz while playing. The server applies accepted frames
in increasing sequence order on simulation ticks and publishes snapshots at the
negotiated rate. Clients can interpolate between snapshots. All positions are metres
in world coordinates, with +Y up and -Z forward at yaw 0. Velocities are metres per
second. Yaws and pitches are radians. JSON vectors are arrays of length 3 rounded
to centimetres, and angles are rounded to milliradians.

### Negotiation and controls

Thin accepts the following extra `hello` fields and echoes the accepted values in
`welcome`. The server also includes `maps` in welcome as an array of
`{"id":string,"name":string}`. E.g. `pinecrest`, `harbor` and `maple_hollow`.
The constants here are protocol limits. Discover actual map choices from welcome.

| Field | Type and default | Meaning |
| --- | --- | --- |
| `rate` | Integer 2–20, default 20 | Snapshot Hz. Missing or invalid values select the default. |
| `radius` | Positive finite number, default 0 | Metres from local player's position, in 3D. Positive inputs are clamped to 1–500. Zero means no distance filter. Only `enemies`, `pickups`, `projectiles` are filtered. When enabled, each filtered list is ordered nearest first. |
| `max_enemies` | Integer 0–256, default -1 | Maximum returned enemies after filtering and sorting. Zero returns no enemy rows, and -1 means unlimited. If set, enemies are sorted nearest first even without a radius. |

All the following messages are JSON except `in` can also use its Thin binary layout.
Send lobby actions during the lobby. During `results`, the server can accept votes,
chat, and readiness for the next run. Gameplay input and choices apply during
`run`. Invalid individual controls or out-of-state actions are ignored.

| `t` | Fields | Meaning |
| --- | --- | --- |
| `lobby` | `a:"ready"`, `v` boolean | Set lobby readiness. All ready starts a run. |
| `lobby` | `a:"vote"`, `map` string | Vote for a map ID or `"random"`. Highest-voted selection wins, ties are randomized. |
| `lobby` | `a:"start"` | Force start regardless of readiness. |
| `lobby` | `a:"chat"`, `text` string | Trimmed, control characters removed, brackets replaced, up to 100 characters. The server accepts at most one message per player per 700 ms. |
| `in` | `seq` integer 0–9,007,199,254,740,991 in JSON. `mv` array of two finite numbers. `yaw`, `pitch` finite numbers. `b` integer 0–8191, `slot` integer 0–5, `wheel` integer -1–1. | Replace current movement, desired view and held buttons, and apply slot/wheel edges. Binary sequences use the range 0–4,294,967,294. |
| `choice` | `kind:"mutation"`, `i` integer 0–2 | Vote for a dealt card at that zero-based index. A later vote replaces the earlier one. |
| `choice` | `kind:"tape"`, `i` integer 0–1 | Index 0 continues into endless mode. Index 1 ends the run. Only the tape decision-maker can choose. |
| `map_req` | No extra fields | Request the current level's coarse collision outline. |
| `leave` | No extra fields | Leave the game and close the connection. |

The X component of `mv` is right. The Y component is back, so `[0,-1]` moves
forward. Components are clamped to [-1,1] and the vector is limited to length 1.
Yaw is absolute body rotation about +Y, wrapped to [-π,π). Pitch is absolute head
rotation about the local X axis, clamped to ±88°. Positive pitch looks up.
Zero slot or wheel means no action. Each nonzero value is applied only on change
from the preceding applied frame. Wheel -1 selects the previous slot and +1 the next.
Slot selection takes priority when both slot and wheel change in the same frame.

Sequence numbers must increase during a run. Resetting to zero is allowed at the next
`load`. Stale or duplicate sequences are ignored. The server bounds the queue at
32 inputs and drops the oldest pending inputs on overflow. If no valid frame arrives
for 500 ms, movement and held buttons return to neutral. The server retains the
last applied view. Buttons fire on held or edge semantics according to gameplay.

| `b` bit value | Action | `b` bit value | Action |
| ---: | --- | ---: | --- |
| 1 | Fire | 2 | Aim |
| 4 | Jump | 8 | Crouch |
| 16 | Sprint | 32 | Reload |
| 64 | Interact | 128 | Use utility, such as a tarp |
| 256 | Drop selected item | 512 | Context ping |
| 1024 | Ready for next wave phase | 2048 | Select frag grenade pouch |
| 4096 | Select shield dome pouch |  |  |

Pouch buttons select a pouch item. Fire uses the selected pouch. The server grants the
Thin player the pump shotgun starter kit, ammo, two frags and a dome when the run is ready.

### State messages

| `t` | Fields and ordering |
| --- | --- |
| `status` | `state` string `"connecting"`, `"lobby"`, `"loading"`, `"run"`, `"results"` or `"disconnected"`. `msg` is a human-readable string, often empty. The dedicated server normally begins with `lobby`. |
| `lobby` | `players` array of `{id:int,name:string,ready:bool,vote:string,car:bool}`. Empty vote means no vote. The legacy field `car` is true for any Thin player. `maps` is the welcome map list. `countdown` is `-1` because the server has no lobby countdown. `chat` is up to 30 `{from:string,text:string}` entries oldest first. `vote_counts` maps IDs to integer totals. The server sends a new lobby on changes. |
| `load` | `map` string ID of the chosen, concrete level. Sent after `status loading`. Load or reset local level resources and wait for `status run`. |
| `snap` | One full state snapshot as defined below. Starts after `status run`. In binary mode, the server sends the packed snapshot instead. |
| `ev` | `list` array of one-shot events defined below. Sent after a snapshot when the array is nonempty. Pending events can also flush before results. |
| `draft` | `kind:"mutation"`, `cards` array of `{id:string,title:string,desc:string,icon:string}`. `icon` is the same catalog ID as `id`. There are at most three cards. `time_left` is the remaining number of seconds when emitted. |
| `draft_done` | No extra fields. The draft resolved, so close its controls. |
| `tape` | `time_left:null` because the choice has no automatic timeout. `can_choose` boolean indicates whether this player is the dedicated server's current decision-maker. |
| `results` | `won` boolean, `time_s` elapsed integer seconds, `waves` integer completed waves, `kills` integer total attributed kills, `players` array of `{name:string,kills:int,downs:int,revives:int}`, `score` integer endless score. Sent after `status results`. The server returns the connection to the lobby after the end-of-run interval (about 5 s). |
| `map` | `id` map ID string, `boxes` array of `[cx,cy,cz,sx,sy,sz,yaw]`, and `bounds` with `min` and `max` world vectors. Center and full dimensions are metres. Yaw units match snapshots. Before a level is available, `id` and `bounds` are null and `boxes` is empty. |

`map` replies are cached per level. They approximate static world collision using
upright oriented boxes or axis-aligned bounds. Dynamic props, boolean cutouts and
complex mesh detail need assets or a separate map exporter for accurate rendering.
Clients should use the outline as visual context and use snapshots for game authority.

### JSON snapshot fields

`tick` is an integer snapshot counter increasing across the connection, `t_ms`
is integer monotonic server milliseconds when generated, and `ack` is the most
recent input sequence actually applied to this player, or -1 before any input.
All arrays are complete lists for that snapshot and the negotiated filter. Remove
entities that disappear from the corresponding list. IDs are unique within an
entity category for the run and can be reused on another run.

| Object | Fields |
| --- | --- |
| `you` | `id` integer, `pos` vector, `vel` vector, `yaw` and `pitch` angles, `state` string `ok/downed/turned/out`. `hp`, `hp_max` are health points. `suit` and `suit_max` are suit points, with 100 maximum. `exposed`, `sheltered`, `in_puddle`, `crouch`, `aiming`, `reloading` are booleans. `slot` is the selected 1-based hotbar slot. `slots` lists exactly five slot entries. `scrap` is an integer. `revive` is revive progress [0,1] and `interact_progress` is progress for any held interaction [0,1]. `prompt` is interaction text or the empty string. `pouch` is `"frag"`, `"shield_dome"`, or empty. `grenades` and `domes` are integer pouch counts. |
| `you.slots[]` | Null if empty, otherwise `item` catalog ID string, `name` display string, `ammo` integer loaded rounds, `mag` integer magazine size, `reserve` integer shared-caliber rounds, `count` integer stack count (1 for guns). The three ammo fields are null for non-guns. |
| `players[]` | Other players. `id` integer, `name` string, `pos` vector, `yaw`, `pitch` angles, `state` as above, `item` equipped catalog ID or empty, `crouch` boolean for Thin and null for native peers because the native transform does not report crouch, `suit_color` CSS `#rrggbb`, `skin` display string. |
| `enemies[]` | `id` integer, `type` string `drip/gutter/mister/hailstone/sleet/smog/static/thunderhead/undertow/cloudburst/cumulus/turned`, `pos` vector, `yaw` angle, `hp` normalized fraction [0,1], `anim` string `spawn/idle/walk/attack/windup/stagger/die`. Normal infected have positive IDs, Cumulus has ID 0, and Turned enemies use the negative of their player ID. Ordinary infected disappear on death and emit a kill event. Cumulus remains briefly with `anim:"die"`. Motion and attack state choose an animation hint. |
| `pickups[]` | `id` signed integer, `item` catalog ID or supply ID string, `pos` vector, `kind` string `weapon/ammo/health/suit/scrap/item/airdrop/station`. Cabinets and airdrops use negative IDs. |
| `projectiles[]` | `id` signed integer, `kind` weapon/catalog ID string or `"spore"`/`"acid_glob"`, `pos` vector and `vel` vector. Enemy hazard shots use negative IDs. Deployed items are stationary. |
| `weather` | `phase` string `calm/drizzle/downpour/acid_storm/clearing`, `intensity` number in [0,1], `wave` integer starting at 1, `phase_time_left` seconds, `lightning` boolean true if a strike occurred since the previous snapshot for this client. |
| `run` | `alive_enemies` integer before distance/cap filters, including Turned players and a live boss. `wave` integer equal to weather wave. `endless` boolean. `shared_decon` integer shared charges. `score` integer endless score. |

### Events

| `e` | Fields |
| --- | --- |
| `shot` | `by` integer shooter peer ID, `weapon` catalog ID string, `from` muzzle world vector, `to` hit or trace endpoint world vector. A shotgun can produce one event per pellet. Projectile poses arrive in snapshots. |
| `hit` | For the receiving player's shots only. `at` impact world vector, `head` boolean, `dmg` integer damage. |
| `kill` | `enemy` integer enemy ID, `type` enum from the enemy table above. |
| `hurt` | For the receiving player only. `amt` damage points accumulated since the last batch. `dir` world unit vector from player toward the source, or null when no source direction is known. |
| `lightning` | `at` strike world vector. |
| `sound` | `name` sound cue string. `at` world vector for spatial cues or null for nonspatial cues. Sound events represent cues available to the dedicated server. |
| `banner` | `text` string to display. |
| `puddle` | `id` integer puddle/lobe ID, `pos` center vector, `radius` metres, `on` boolean. On creates or updates the puddle. Off removes it. |
| `pickup` | For the receiving collector only. `item` catalog/supply ID string. |

At most 256 events are buffered per client between batches. Snapshot lists are
authoritative even when their corresponding transient events are lost.

### Thin binary layout

Negotiate `enc:"bin"` in the JSON hello. Control and event messages remain JSON on
both transports. Thin then sends binary snapshots and accepts binary or JSON input.
Binary layouts below are packed, with no alignment or padding. `uN` and `iN`
mean unsigned and signed N-bit integers. Signed values use two's complement.
Use `u8` 0 or 1 for booleans. `str` is `u16 byte_length` followed by that many
UTF-8 bytes without a terminator. Array counts precede their rows. Unknown enum
value is 255. For nullable `u16` fields, 65535 means null. Position uses three
`i32` centimetre values. Velocity uses three `i16` centimetre-per-second values
saturated to [-32768,32767]. Angles use `i16` milliradians. Health, suit and the
phase timer use hundredths of the corresponding unit. Fractions use thousandths.

**Input** is exactly 17 bytes:

| Byte offset | Type | Value |
| ---: | --- | --- |
| 0 | u8 | Tag 1 |
| 1 | u32 | Sequence, with 0xffffffff reserved |
| 5 | i16 | Move X × 32767 |
| 7 | i16 | Move Y × 32767 |
| 9 | i16 | Absolute yaw × 1000 |
| 11 | i16 | Absolute pitch × 1000 |
| 13 | u16 | Button mask |
| 15 | u8 | Slot |
| 16 | i8 | Wheel |

Example sequence 42, forward at full strength, yaw 1.2, pitch -0.25, fire+aim,
slot 1, wheel -1:

```text
01 2a 00 00 00 00 00 01 80 b0 04 06 ff 03 00 01 ff
```

Use the payload as-is in a WebSocket binary message, or prepend `11 00 00 00`
on raw TCP.

**Snapshot** fields appear in this order. The rows below expand the variable blocks.

| Part | Ordered fields |
| --- | --- |
| Header | `u8 tag=2, u32 tick, u64 t_ms, u32 ack`. `0xffffffff` means ack=-1. |
| Local player | `u32 id, position, velocity, i16 yaw, i16 pitch, u8 state, u16 hp, u16 hp_max, u16 suit, u16 suit_max, u8 flags, u8 slot`, then five slot entries, then `u32 scrap, u16 revive, u16 interact_progress, str prompt, str pouch, u16 grenades, u16 domes`. |
| Each slot entry | `u8 present`. If nonzero, `str item, str name, u16 ammo, u16 mag, u16 reserve, u16 count`. Ammo, mag and reserve can be null. |
| Players | `u16 count`, then each `u32 id, position, i16 yaw, i16 pitch, u8 state, u8 crouch, str name, str item, u32 suit_color, str skin`. Crouch 2 is null. Color is integer `0xRRGGBBFF`, so little-endian bytes are `FF BB GG RR`. |
| Enemies | `u16 count`, then each `i32 id, u8 type, position, i16 yaw, u16 hp, u8 anim`. HP is a fraction. |
| Pickups | `u16 count`, then each `i64 id, u8 kind, position, str item`. |
| Projectiles | `u16 count`, then each `i64 id, position, velocity, str kind`. |
| Weather | `u8 phase, u16 intensity, u32 wave, u32 phase_time_left, u8 lightning`. Intensity is a fraction. |
| Run | `u16 alive_enemies, u8 endless, u16 shared_decon, u32 score`. Read the run wave from weather. |

Local player flag bits 0–5 are exposed, sheltered, in_puddle, crouch, aiming, reloading.
Bits 6–7 are reserved, currently zero.

Enum indices start at zero and follow these fixed orders:

| Enum | Order |
| --- | --- |
| State | ok, downed, turned, out |
| Enemy type | drip, gutter, mister, hailstone, sleet, smog, static, thunderhead, undertow, cloudburst, cumulus, turned |
| Enemy animation | spawn, idle, walk, attack, windup, stagger, die |
| Pickup kind | weapon, ammo, health, suit, scrap, item, airdrop, station |
| Weather phase | calm, drizzle, downpour, acid_storm, clearing |

A snapshot header with tick 1, time 1000 ms, and ack 42 is
`02 01 00 00 00 e8 03 00 00 00 00 00 00 2a 00 00 00`. If the next fields are
local ID 2 and position [1.25, 0, -2], those bytes are
`02 00 00 00 7d 00 00 00 00 00 00 00 38 ff ff ff`. The remaining fields follow
immediately. For a WebSocket connection, use the message boundary to delimit the
snapshot. For raw TCP, its length prefix counts the entire packed payload including
the tag.

This complete 104-byte snapshot uses the header above. The local player is
exposed, has 100 health and suit, has five empty slots, and is in wave 1 calm
with 12 seconds left and four shared decon charges. All entity lists are empty.

```text
02 01 00 00 00 e8 03 00 00 00 00 00 00 2a 00 00
00 02 00 00 00 7d 00 00 00 00 00 00 00 38 ff ff
ff 00 00 00 00 00 00 00 00 00 00 00 10 27 10 27
10 27 10 27 01 01 00 00 00 00 00 00 00 00 00 00
00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00
00 00 00 00 00 00 01 00 00 00 b0 04 00 00 00 00
00 00 04 00 00 00 00 00
```

### JSON session transcript

`C` is the client and `S` is the server. The prefixes are explanatory and are
not part of any payload. This is a one-player run with a single map shown for
brevity. Repeating inputs and snapshots between representative updates are omitted.

```text
C {"t":"hello","v":1,"name":"Honda","client":"dashboard/1","tier":"thin","enc":"json","rate":20}
S {"t":"welcome","v":1,"game_protocol":19,"you":2,"maps":[{"id":"pinecrest","name":"PINECREST"}],"tier":"thin","enc":"json","rate":20,"radius":0,"max_enemies":-1}
S {"t":"status","state":"lobby","msg":""}
S {"t":"lobby","players":[{"id":2,"name":"Honda","ready":false,"vote":"","car":true}],"maps":[{"id":"pinecrest","name":"PINECREST"}],"countdown":-1,"chat":[],"vote_counts":{}}
C {"t":"ping","ms":7}
S {"t":"pong","ms":7}
C {"t":"lobby","a":"vote","map":"pinecrest"}
S {"t":"lobby","players":[{"id":2,"name":"Honda","ready":false,"vote":"pinecrest","car":true}],"maps":[{"id":"pinecrest","name":"PINECREST"}],"countdown":-1,"chat":[],"vote_counts":{"pinecrest":1}}
C {"t":"lobby","a":"ready","v":true}
S {"t":"lobby","players":[{"id":2,"name":"Honda","ready":true,"vote":"pinecrest","car":true}],"maps":[{"id":"pinecrest","name":"PINECREST"}],"countdown":-1,"chat":[],"vote_counts":{"pinecrest":1}}
S {"t":"lobby","players":[{"id":2,"name":"Honda","ready":false,"vote":"pinecrest","car":true}],"maps":[{"id":"pinecrest","name":"PINECREST"}],"countdown":-1,"chat":[],"vote_counts":{"pinecrest":1}}
S {"t":"status","state":"loading","msg":""}
S {"t":"load","map":"pinecrest"}
S {"t":"status","state":"run","msg":""}
C {"t":"in","seq":1,"mv":[0,-0.7],"yaw":0,"pitch":-0.2,"b":0,"slot":0,"wheel":0}
S {"t":"snap","tick":2,"t_ms":2100,"ack":1,"you":{"id":2,"pos":[1,0,-2],"vel":[0,0,-3.5],"yaw":0,"pitch":-0.2,"state":"ok","hp":100,"hp_max":100,"suit":100,"suit_max":100,"exposed":true,"sheltered":false,"in_puddle":false,"crouch":false,"aiming":false,"reloading":false,"slot":1,"slots":[{"item":"pump_shotgun","name":"Pump Shotgun","ammo":6,"mag":6,"reserve":18,"count":1},null,null,null,null],"scrap":0,"revive":0,"interact_progress":0,"prompt":"","pouch":"","grenades":2,"domes":1},"players":[],"enemies":[],"pickups":[],"projectiles":[],"weather":{"phase":"calm","intensity":0,"wave":1,"phase_time_left":11.8,"lightning":false},"run":{"alive_enemies":0,"wave":1,"endless":false,"shared_decon":4,"score":0}}
C {"t":"in","seq":2,"mv":[0,0],"yaw":0,"pitch":-0.2,"b":1,"slot":0,"wheel":0}
S {"t":"ev","list":[{"e":"shot","by":2,"weapon":"pump_shotgun","from":[1,1.5,-2.5],"to":[1,0,-10]}]}
S {"t":"draft","kind":"mutation","cards":[{"id":"chitin_suit","title":"CHITIN SUIT","desc":"+25 max health and suit drains 35% slower in rain","icon":"chitin_suit"}],"time_left":15}
C {"t":"choice","kind":"mutation","i":0}
S {"t":"draft_done"}
S {"t":"status","state":"results","msg":""}
S {"t":"results","won":false,"time_s":221,"waves":1,"kills":20,"players":[{"name":"Honda","kills":20,"downs":1,"revives":0}],"score":0}
S {"t":"status","state":"lobby","msg":""}
S {"t":"lobby","players":[{"id":2,"name":"Honda","ready":false,"vote":"","car":true}],"maps":[{"id":"pinecrest","name":"PINECREST"}],"countdown":-1,"chat":[],"vote_counts":{}}
C {"t":"leave"}
S {"t":"status","state":"disconnected","msg":"Left session"}
```

### Binary and TCP conformance examples

Binary WebSocket follows the same transcript with `enc:"bin"` in the hello and
welcome. Replace each `in` and `snap` with their packed frames. All other lines
remain WebSocket text messages. For example, a client can send the 17-byte input
above between `status run` and the first acknowledged binary snapshot. On raw TCP,
write the length prefix for every line or binary payload, and use its first byte
to select JSON or binary.

From the repository root, with a local dedicated server running:

```sh
uv run tools/thin_client/fake_client.py
uv run tools/thin_client/fake_client.py --enc bin --rate 12 --radius 45 --max-enemies 5
uv run tools/thin_client/fake_client.py --transport tcp
uv run tools/thin_client/fake_client.py --transport tcp --enc bin
```

Use `--connect-only` for a lobby-only check. Use `--code VALUE` or
`FALLOUT_THIN_JOIN_CODE` if the server requires a code. `--expect-error TEXT`
checks a rejected handshake. The scripted run checks map outline, movement, aim,
firing, enemy snapshots, cadence and optional radius/cap constraints. The optional
`--require-results` also waits for damage and a result row.

## Full tier

The **Full** tier is the primary path for complete non-Godot ports (handhelds,
consoles, native C/C++/Rust/Unity/Unreal clients) that run their own movement,
physics, prediction, audio, and rendering and only need an engine-neutral
networking protocol instead of Godot's `SceneMultiplayer`.

On the dedicated server, each accepted Full-tier connection is admitted beneath
`SceneMultiplayer` as a first-class peer with a real positive peer ID (`you >= 2`).
Full-tier peers share the 4-player cap, lobby roster, map voting, chat, runs,
late join, endless mode, and results with native Godot clients and Thin-tier
peers. The server translates Godot's `SceneMultiplayer` RPC packets to and from
the engine-neutral Full-tier wire format and handles Godot's internal path-cache
(`SIMPLIFY_PATH` / `CONFIRM_PATH`), node-ID compression, and sorted method-index
tables transparently. Full-tier clients never see Godot cache IDs or method
indices — every RPC addresses nodes by scene-tree path string (relative to
`/root`) and methods by name.

The complete, machine-readable list of every `@rpc` method, node path pattern,
direction, scope, transfer mode, channel, and argument signature is generated
into [`docs/open-protocol-schema.json`](open-protocol-schema.json) by
`tools/open_protocol/gen_schema.gd`. **Regenerate and commit
`docs/open-protocol-schema.json` on every `Net.PROTOCOL` bump.**

### Handshake and session lifecycle

Control frames (`hello`, `welcome`, `error`, `ping`, `pong`, `leave`) are
**always** UTF-8 JSON text frames, even when `enc:"bin"` is negotiated. Only
`rpc` and `raw` frames switch to binary in `enc:"bin"` mode.

1. **Open transport.** Connect to WebSocket port `7780` (wait for HTTP 101
   upgrade) or raw TCP port `7781` (4-byte little-endian `u32` length prefix on
   every frame, see [Raw TCP framing example](#raw-tcp-framing-example)).
2. **Send Open Protocol `hello`** (within 5 seconds of connect):
   ```json
   {"t":"hello","v":1,"tier":"full","enc":"json"}
   ```
   Set `"enc":"bin"` for compact binary RPCs. Include `"code":"<secret>"` only
   when the server requires a join code. Any `"name"` field in the Open Protocol
   `hello` is ignored on Full tier because player identity and cosmetics are
   sent in step 4 (`Net._hello`).
3. **Receive Open Protocol `welcome`** (or terminal `error`):
   ```json
   {"t":"welcome","v":1,"tier":"full","enc":"json","you":89786151,"game_protocol":19,"maps":[{"id":"pinecrest","name":"PINECREST"},{"id":"harbor","name":"HARBOR POINT"},{"id":"maple_hollow","name":"MAPLE HOLLOW"}]}
   ```
   Store `you` (your assigned Godot peer ID; your player node during runs is
   `Main/Players/P_<you>`). Verify `game_protocol` matches the version your
   client implements (currently `19`).
4. **Send game-level handshake `Net._hello`:**
   Call `Net._hello(hello_json: String, protocol: int)` (reliable, channel 0):
   - `hello_json`: a JSON-encoded **string** containing:
     `{"name":"<up to 32 chars>","color":<0..9>,"skin":<0..4>,"colors":[<unlocked color indices, or [] for unrestricted>]}`
   - `protocol`: integer equal to `game_protocol` (`19`).
   - **On rejection** (wrong protocol or 4/4 players already in roster): server
     sends `Net._reject(reason: String)` (for example
     `"UPDATE REQUIRED (v19, YOU HAVE v18)"` or `"SERVER FULL"`) and closes the
     connection ~0.5 seconds later.
   - **On acceptance:** server adds `you` to `Net.roster`, assigns a unique suit
     color from the 10-color palette (nudging if another player already wears
     your requested color), and broadcasts `Net._push_roster(roster, lobby_map_id,
     lobby_votes_enabled, lobby_vote_counts, your_vote)`.
   - **Late join:** if a run is already in progress when `Net._hello` succeeds,
     the server immediately follows `_push_roster` with `Net._start_run(map_id)`.
5. **Lobby phase (optional RPCs on node `Net`):**
   - `Net._request_name(new_name: String)` — rename (trimmed, max 18 chars).
   - `Net._request_cosmetic(color: int, skin: int, unlocked: Array)` — request
     a suit color (0–9) and skin (0–4).
   - `Net._request_map_vote(map_id: String)` — vote for a concrete map ID from
     `welcome.maps` or `"random"`.
   - `Net._request_chat(text: String)` — lobby chat (max 100 chars, control
     chars stripped, `[`/`]` replaced with `(`/`)`, 700 ms per-peer rate limit).
     Broadcast back to all peers as `Net._chat_rpc(sender: String, text: String)`.
   - `Net._request_ready(value: bool)` — toggle lobby readiness. When every peer
     in `Net.roster` has `ready == true`, the server starts the run.
   - `Net._request_force_start()` — start immediately without waiting for other
     peers to ready up.
6. **Run start and loading barrier:**
   - Server resets everyone's `ready` to `false` (`Net._push_roster`), then
     sends `Net._start_run(map_id: String)`.
   - Server waits `1.8` seconds (`MAP_REVEAL_SECONDS`), loads the level, spawns
     `Main/Players/P_<peer_id>` for each peer in sorted peer-ID order, starts
     the run, and waits for peers to report ready.
   - Client loads the map and builds local player entities for every peer in
     `Net.roster` (sorted ascending by integer peer ID, spawned at
     `player_spawn[i % spawns.size()]`).
   - Client sends `Net._report_in_run(true)`.
   - Once both the server and client have loaded the run, the server sends the
     initial catch-up burst in order:
     1. `GameManager._sync_tape_state(awaiting_tape_choice, endless, victory_locked)`
     2. `WeatherManager._receive_phase(phase, wave, phase_time_left)`,
        `WeatherManager._receive_intensity(storm_intensity)`,
        `WeatherManager._override(intensity_override)`
     3. `GameManager._sync_decon(decon_charges)`
     4. `GameManager/MutationRoll._sync_active(enemy_mutations, player_mutations)`
        (plus `_deal_rpc(enemy_pick, cards)` if a draft is open)
     5. `GameManager/CrateManager._snapshot(run_id, cabinets, drop)`
     6. `Main/Enemies._spawn_enemy(...)` for each live enemy (late join) and
        `Main/Enemies._sync_progress(wave, remaining, total, recovery, endless_score)`
     7. `GameManager._spawn_boss(pos)` (late join if Wave 5 Cumulus is alive)
     8. `WeatherManager._sync_puddles(puddle_growth_dict)`
     9. `Main/RunLoot._snapshot(run_id, pickups, effects, discoveries, starter_chosen)`
     10. `Main/Players/P_<id>/Head/Camera3D/WeaponHolder._equip_state(...)` for
         every player, plus `_private_state(...)` for `you`
     11. `Net._confirm_run_ready()`
   - **Gate rule:** wait for `Net._confirm_run_ready()` before sending any
     run-scoped RPCs (`_push_transform`, `_report_exposure`, `_request_starter`,
     `_request_shot`, `_request_ping`, etc.). The server ignores run RPCs from
     peers not yet in `run_peers`.
7. **Active run:** pick a starter kit (`Main/RunLoot._request_starter(run_id,
   0|1|2)`), report exposure (`Main/Players/P_<you>._report_exposure`), stream
   transforms at 20 Hz (`Main/Players/P_<you>._push_transform`), answer
   `Net._rtt_ping` with `Net._rtt_pong`, and process combat/enemy/weather RPCs.
8. **Run end and return to lobby:**
   - Server sends `GameManager._finish(won: bool, results: Dictionary)`.
   - Client sends `Net._report_in_run(false)` when unloading the run scene.
   - After `5.0` seconds (`RESULTS_DELAY`), the server unloads the run, clears
     map votes, resets mutations/weather, and broadcasts a fresh
     `Net._push_roster` for the next lobby.
9. **Clean disconnect:** send JSON `{"t":"leave"}` and close the transport. The
   server removes your peer from `Net.roster`, broadcasts the updated roster to
   remaining players, and closes the socket.

### JSON encoding (`enc:"json"`)

Every RPC travels as one JSON text message:

```json
{"t":"rpc","node":"Main/Players/P_5","method":"_push_transform","args":[{"_t":"v3","v":[3.0,0.2,0.0]},1.5,-0.25,{"_t":"v3","v":[0.0,0.0,-5.0]}],"ch":0,"rel":false}
```

| Field | Required (C→S) | Type | Meaning |
| --- | --- | --- | --- |
| `t` | Yes | `"rpc"` | Full-tier RPC envelope. |
| `node` | Yes | `String` | Scene path relative to `/root` (e.g. `"Net"`, `"Main/Players/P_5"`). Leading `"/root/"` is accepted and stripped on input; server always omits `"/root/"`. |
| `method` | Yes | `String` | Exact GDScript `@rpc` method name. |
| `args` | No (default `[]`) | `Array` | Positional arguments encoded using the Variant↔JSON table below. Optional trailing arguments may be omitted. |
| `ch` | No | `int` (0–255) | Transfer channel. Defaults to the method's configured channel (`0` for all current RPCs). |
| `rel` | No | `bool` | `true` for reliable, `false` for unreliable / unreliable-ordered. Defaults to the method's configured mode. |

If `SceneMultiplayer.send_bytes` is ever used, it maps to
`{"t":"raw","data":"<base64>","ch":0,"rel":true}` (not used by Fallout Forecast).

#### Variant ↔ JSON type mapping

JSON has no native distinction between `int` and `float` or Godot math/packed
types. Types without a native JSON form are encoded as two-key objects
`{"_t":"<tag>","v":<payload>}`:

| Godot `Variant::Type` | ID | JSON representation | Notes |
| --- | ---: | --- | --- |
| `NIL` | 0 | `null` | |
| `BOOL` | 1 | `true` / `false` | |
| `INT` | 2 | JSON number (e.g. `19`) | If `|n| > 9007199254740991`, server emits `{"_t":"i64","v":"<decimal>"}`. Client may always send plain JSON numbers when the target RPC arg is typed `int`, or explicit `{"_t":"i","v":19}` / `{"_t":"i64","v":"..."}`. |
| `FLOAT` | 3 | JSON number (e.g. `12.5`) | Non-finite values use `{"_t":"f","v":"NaN"|"Inf"|"-Inf"}`. Client may also send `{"_t":"f","v":1.0}`. |
| `STRING` | 4 | JSON string | UTF-8. |
| `VECTOR2` / `VECTOR2I` | 5 / 6 | `{"_t":"v2","v":[x,y]}` / `{"_t":"v2i","v":[x,y]}` | |
| `RECT2` / `RECT2I` | 7 / 8 | `{"_t":"rect2","v":[x,y,w,h]}` / `{"_t":"rect2i","v":[x,y,w,h]}` | |
| `VECTOR3` / `VECTOR3I` | 9 / 10 | `{"_t":"v3","v":[x,y,z]}` / `{"_t":"v3i","v":[x,y,z]}` | |
| `TRANSFORM2D` | 11 | `{"_t":"xform2d","v":[[xx,xy],[yx,yy],[ox,oy]]}` | Columns `x`, `y`, `origin`. |
| `VECTOR4` / `VECTOR4I` | 12 / 13 | `{"_t":"v4","v":[x,y,z,w]}` / `{"_t":"v4i","v":[x,y,z,w]}` | |
| `PLANE` | 14 | `{"_t":"plane","v":[nx,ny,nz,d]}` | Normal `(nx,ny,nz)` + distance `d`. |
| `QUATERNION` | 15 | `{"_t":"quat","v":[x,y,z,w]}` | |
| `AABB` | 16 | `{"_t":"aabb","v":[[px,py,pz],[sx,sy,sz]]}` | `[position, size]`. |
| `BASIS` | 17 | `{"_t":"basis","v":[[xx,xy,xz],[yx,yy,yz],[zx,zy,zz]]}` | Three column basis vectors `[basis.x, basis.y, basis.z]`. |
| `TRANSFORM3D` | 18 | `{"_t":"xform3d","v":[[xx,xy,xz],[yx,yy,yz],[zx,zy,zz],[ox,oy,oz]]}` | `[basis.x, basis.y, basis.z, origin]`. |
| `PROJECTION` | 19 | `{"_t":"proj","v":[[x0..3],[y0..3],[z0..3],[w0..3]]}` | Four 4-component columns. |
| `COLOR` | 20 | `{"_t":"color","v":[r,g,b,a]}` | Linear 0.0–1.0 RGBA floats (`a` defaults to `1.0` on input). |
| `STRING_NAME` | 21 | `{"_t":"sn","v":"..."}` | Plain JSON strings are auto-coerced when the target arg is `StringName`. |
| `NODE_PATH` | 22 | `{"_t":"np","v":"..."}` | Plain JSON strings are auto-coerced when the target arg is `NodePath` (e.g. `GameManager._request_interact`). |
| `OBJECT`, `RID`, `CALLABLE`, `SIGNAL` | 23–26 | `null` | `SceneMultiplayer` disallows object decoding. |
| `DICTIONARY` | 27 | `{...}` **or** `{"_t":"dict","v":[[k,v],...]}` | Plain JSON object when **all** keys are `String` and none equals `"_t"`. Dictionaries with non-string keys (such as `Net.roster`, keyed by integer `peer_id`, or `WeatherManager._sync_puddles`, keyed by `NodePath`) always encode as `{"_t":"dict","v":[[k,v],...]}`. |
| `ARRAY` | 28 | `[...]` | Recursive elements. |
| `PACKED_BYTE_ARRAY` | 29 | `{"_t":"bytes","v":"<base64>"}` | |
| `PACKED_INT32_ARRAY` | 30 | `{"_t":"pi32","v":[...]}` | Plain JSON arrays are also accepted when target arg is `PackedInt32Array`. |
| `PACKED_INT64_ARRAY` | 31 | `{"_t":"pi64","v":[...]}` | Elements follow `INT` safe-range rule. |
| `PACKED_FLOAT32_ARRAY` | 32 | `{"_t":"pf32","v":[...]}` | |
| `PACKED_FLOAT64_ARRAY` | 33 | `{"_t":"pf64","v":[...]}` | |
| `PACKED_STRING_ARRAY` | 34 | `{"_t":"pstr","v":[...]}` | |
| `PACKED_VECTOR2_ARRAY` | 35 | `{"_t":"pv2","v":[[x,y],...]}` | |
| `PACKED_VECTOR3_ARRAY` | 36 | `{"_t":"pv3","v":[[x,y,z],...]}` | Used by `Main/Enemies._sync_enemies`. |
| `PACKED_COLOR_ARRAY` | 37 | `{"_t":"pcol","v":[[r,g,b,a],...]}` | |
| `PACKED_VECTOR4_ARRAY` | 38 | `{"_t":"pv4","v":[[x,y,z,w],...]}` | |

**Number coercion rule (C→S JSON):** The server inspects the target RPC method's
declared GDScript parameter types and coerces plain JSON numbers to `int` or
`float` automatically, so clients can write `[19]` instead of `[{"_t":"i","v":19}]`
for typed RPC arguments. Inside untyped containers (`Dictionary`, `Array`), use
`{"_t":"i","v":...}` if an exact integer type matters (for `{"_t":"dict"}` keys,
whole-number JSON numbers are automatically treated as `int`).

### Binary encoding (`enc:"bin"`)

Negotiate `"enc":"bin"` in the JSON `hello`. Control frames (`hello`, `welcome`,
`error`, `ping`, `pong`, `leave`) remain JSON text frames. All `rpc` and `raw`
frames travel as WebSocket binary messages (or raw TCP frames whose first byte
is `< 0x09`). All multi-byte fields are **little-endian**.

Binary tag allocation across the Open Protocol:

| Tag byte | Tier | Frame kind |
| ---: | --- | --- |
| `0x01` | Thin | Input (17 bytes) |
| `0x02` | Thin | Snapshot |
| `0x03` | Full | RPC (`FULL_BIN_RPC`) |
| `0x04` | Full | Raw bytes (`FULL_BIN_RAW`) |

#### `0x03` Full RPC frame layout

| Offset | Size | Type | Field |
| ---: | ---: | --- | --- |
| `0` | 1 | `u8` | Tag `0x03` |
| `1` | 1 | `u8` | `flags`: bits `0..1` = transfer mode (`0` = unreliable, `1` = unreliable_ordered, `2` = reliable); bits `2..7` = `0` |
| `2` | 1 | `u8` | `channel` (`0..255`) |
| `3` | 2 | `u16` LE | `node_path_len` (`N`) |
| `5` | `N` | UTF-8 | `node_path` relative to `/root` (no NUL terminator) |
| `5+N` | 1 | `u8` | `method_len` (`M`) |
| `6+N` | `M` | UTF-8 | `method` name (no NUL terminator) |
| `6+N+M` | 1 | `u8` | `argc` (`0..255`) |
| `7+N+M` | var | `var[]` | `argc` Godot 4.7.2 `encode_var` (`var_to_bytes`, `allow_objects=false`) values concatenated with no separator |

#### `0x04` Full RAW frame layout

| Offset | Size | Type | Field |
| ---: | ---: | --- | --- |
| `0` | 1 | `u8` | Tag `0x04` |
| `1` | 1 | `u8` | `flags` (bits `0..1` = transfer mode) |
| `2` | 1 | `u8` | `channel` (`0..255`) |
| `3` | var | bytes | Raw payload (remainder of frame) |

#### Godot 4.7.2 `encode_var` binary Variant format

Each argument in a `0x03` frame is encoded with Godot's standard
`encode_variant(..., full_objects=false)` format (not `SceneMultiplayer`'s
compressed variant format — standard 4-byte aligned `encode_var` only). Every
value begins with a **4-byte little-endian `u32` header**:

- Bits `0..7`: `Variant::Type` ID (see table above: `0` = NIL .. `38` = PACKED_VECTOR4_ARRAY).
- Bit `16` (`0x00010000`, `HEADER_DATA_FLAG_64`):
  - On `INT` (`2`): `0` = `i32` (4 bytes), `1` = `i64` (8 bytes).
  - On `FLOAT` (`3`): `0` = IEEE 754 `f32` (4 bytes), `1` = IEEE 754 `f64` (8 bytes). Godot sets this bit whenever `double(float(d)) != d` (for example `2.1` or `0.2`!). **Decoders MUST check bit 16 on every `FLOAT` and `INT`.**
  - On math types (`Vector2/3/4`, `Transform3D`, etc.): `0` on standard single-precision Godot builds (including the Fallout Forecast dedicated server).
- Bits `16..17` on `ARRAY` (`28`), and bits `16..17` (key) + `18..19` (value) on `DICTIONARY` (`27`): **typed container kind**:
  - `0` (`NONE`): untyped, no extra header field.
  - `1` (`BUILTIN`): followed immediately by `u32` LE builtin `Variant::Type` ID before `count`. (Example: `MutationRoll._sync_active` sends `Array[String]`, whose header is `0x0001001c` followed by `0x00000004` (`TYPE_STRING`) before `u32 count`!)
  - `2` (`CLASS_NAME`) or `3` (`SCRIPT`): followed immediately by one padded string (`u32 len` + UTF-8 + 0–3 NUL pad bytes) before `count`.

Payload layout after the 4-byte header (and optional container type field):

- **Padded string helper (`str4`)**: `u32 byte_len` + `byte_len` UTF-8 bytes + `((4 - (byte_len % 4)) % 4)` zero pad bytes.
- `NIL` (`0`): 0 bytes.
- `BOOL` (`1`): `u32` (`0` = false, nonzero = true).
- `INT` (`2`): `i32` (if flag 64 clear) or `i64` (if flag 64 set).
- `FLOAT` (`3`): `f32` (if flag 64 clear) or `f64` (if flag 64 set).
- `STRING` (`4`) / `STRING_NAME` (`21`): `str4`.
- `VECTOR2` (`5`): `f32 x, f32 y`. `VECTOR2I` (`6`): `i32 x, i32 y`.
- `RECT2` (`7`): `4 × f32 (x, y, w, h)`. `RECT2I` (`8`): `4 × i32`.
- `VECTOR3` (`9`): `f32 x, f32 y, f32 z`. `VECTOR3I` (`10`): `3 × i32`.
- `TRANSFORM2D` (`11`): `6 × f32 (xx, xy, yx, yy, ox, oy)`.
- `VECTOR4` (`12`) / `PLANE` (`14`) / `QUATERNION` (`15`) / `COLOR` (`20`): `4 × f32`. `VECTOR4I` (`13`): `4 × i32`.
- `AABB` (`16`): `6 × f32 (px, py, pz, sx, sy, sz)`.
- `BASIS` (`17`): `9 × f32` in **row-major** order (`x.x, y.x, z.x, x.y, y.y, z.y, x.z, y.z, z.z`).
- `TRANSFORM3D` (`18`): `12 × f32` = 9 row-major `Basis` floats followed by `origin.x, origin.y, origin.z`.
- `PROJECTION` (`19`): `16 × f32`.
- `NODE_PATH` (`22`): `u32 (name_count | 0x80000000)`, `u32 subname_count`, `u32 flags` (bit 0 = absolute leading `/`), followed by `name_count` `str4` segments and `subname_count` `str4` subnames.
- `DICTIONARY` (`27`): (optional key/value container type fields), `u32 count` (mask `& 0x7FFFFFFF`), followed by `count` pairs of `(encode_var(key), encode_var(value))`.
- `ARRAY` (`28`): (optional element container type field), `u32 count` (mask `& 0x7FFFFFFF`), followed by `count` `encode_var(element)` values.
- `PACKED_BYTE_ARRAY` (`29`): `u32 count`, `count` raw bytes, plus `((4 - (count % 4)) % 4)` zero pad bytes.
- `PACKED_INT32_ARRAY` (`30`): `u32 count`, `count × i32`.
- `PACKED_INT64_ARRAY` (`31`): `u32 count`, `count × i64`.
- `PACKED_FLOAT32_ARRAY` (`32`): `u32 count`, `count × f32`.
- `PACKED_FLOAT64_ARRAY` (`33`): `u32 count`, `count × f64`.
- `PACKED_STRING_ARRAY` (`34`): `u32 count`, `count × str4`.
- `PACKED_VECTOR2_ARRAY` (`35`): `u32 count`, `count × 2 × f32`.
- `PACKED_VECTOR3_ARRAY` (`36`): `u32 count`, `count × 3 × f32`.
- `PACKED_COLOR_ARRAY` (`37`): `u32 count`, `count × 4 × f32`.
- `PACKED_VECTOR4_ARRAY` (`38`): `u32 count`, `count × 4 × f32`.

#### Worked binary hex examples

All examples below show the exact WebSocket binary payload; on raw TCP, prepend
the 4-byte little-endian payload length shown in parentheses.

**1. `Net._hello('{"name":"3DS","color":1,"skin":0,"colors":[]}', 19)`** (80 bytes; TCP prefix `50 00 00 00`):
```text
03 02 00 03 00 4e 65 74 06 5f 68 65 6c 6c 6f 02
04 00 00 00 2d 00 00 00 7b 22 6e 61 6d 65 22 3a
22 33 44 53 22 2c 22 63 6f 6c 6f 72 22 3a 31 2c
22 73 6b 69 6e 22 3a 30 2c 22 63 6f 6c 6f 72 73
22 3a 5b 5d 7d 00 00 00 02 00 00 00 13 00 00 00
```
Breakdown: `03` tag · `02` reliable · `00` ch 0 · `03 00` len 3 · `4e 65 74` `"Net"` · `06` len 6 · `5f 68 65 6c 6c 6f` `"_hello"` · `02` argc=2 · `04 00 00 00` TYPE_STRING · `2d 00 00 00` len 45 + 45 UTF-8 bytes + `00 00 00` 3 pad bytes · `02 00 00 00` TYPE_INT (32-bit) · `13 00 00 00` value `19`.

**2. `Net._request_ready(true)`** (32 bytes; TCP prefix `20 00 00 00`):
```text
03 02 00 03 00 4e 65 74 0e 5f 72 65 71 75 65 73
74 5f 72 65 61 64 79 01 01 00 00 00 01 00 00 00
```
Breakdown: header + `"Net"` + `"_request_ready"` + `01` argc=1 + `01 00 00 00` TYPE_BOOL + `01 00 00 00` `true`.

**3. `Net._confirm_run_ready()`** (28 bytes; TCP prefix `1c 00 00 00`):
```text
03 02 00 03 00 4e 65 74 12 5f 63 6f 6e 66 69 72
6d 5f 72 75 6e 5f 72 65 61 64 79 00
```

**4. `Main/Players/P_5._push_transform(Vector3(3.0, 0.2, 0.0), 1.5, -0.25, Vector3(0.0, 0.0, -5.0))`** (86 bytes; TCP prefix `56 00 00 00`):
```text
03 01 00 10 00 4d 61 69 6e 2f 50 6c 61 79 65 72
73 2f 50 5f 35 0f 5f 70 75 73 68 5f 74 72 61 6e
73 66 6f 72 6d 04 09 00 00 00 00 00 40 40 cd cc
4c 3e 00 00 00 00 03 00 00 00 00 00 c0 3f 03 00
00 00 00 00 80 be 09 00 00 00 00 00 00 00 00 00
00 00 00 00 a0 c0
```
Breakdown: `03` tag · `01` unreliable_ordered · `00` ch 0 · `10 00` len 16 `"Main/Players/P_5"` · `0f` len 15 `"_push_transform"` · `04` argc=4 · `09 00 00 00` TYPE_VECTOR3 + `(3.0, 0.2, 0.0)` · `03 00 00 00` TYPE_FLOAT (f32) `1.5` · `03 00 00 00` TYPE_FLOAT (f32) `-0.25` · `09 00 00 00` TYPE_VECTOR3 `(0.0, 0.0, -5.0)`.

**5. `Main/Enemies._sync_enemies(PackedInt32Array([1]), PackedVector3Array([(10.0, 0.5, -4.0)]), PackedFloat32Array([1.5]))`** (76 bytes; TCP prefix `4c 00 00 00`):
```text
03 01 00 0c 00 4d 61 69 6e 2f 45 6e 65 6d 69 65
73 0d 5f 73 79 6e 63 5f 65 6e 65 6d 69 65 73 03
1e 00 00 00 01 00 00 00 01 00 00 00 24 00 00 00
01 00 00 00 00 00 20 41 00 00 00 3f 00 00 80 c0
20 00 00 00 01 00 00 00 00 00 c0 3f
```
Breakdown: `03 01 00` + `"Main/Enemies"` + `"_sync_enemies"` + `03` argc=3 · `1e 00 00 00` TYPE_PACKED_INT32_ARRAY, count=1, `[1]` · `24 00 00 00` TYPE_PACKED_VECTOR3_ARRAY, count=1, `(10.0, 0.5, -4.0)` · `20 00 00 00` TYPE_PACKED_FLOAT32_ARRAY, count=1, `[1.5]`.

**6. `Main/RunLoot._request_starter(1, 0)`** (51 bytes; TCP prefix `33 00 00 00`):
```text
03 02 00 0c 00 4d 61 69 6e 2f 52 75 6e 4c 6f 6f
74 10 5f 72 65 71 75 65 73 74 5f 73 74 61 72 74
65 72 02 02 00 00 00 01 00 00 00 02 00 00 00 00
00 00 00
```

### Error handling

- **Pre-welcome fatal errors:** the common listener (or Full tier if the
  dedicated server is inactive/refusing connections) sends
  `{"t":"error","msg":"..."}` and closes the socket.
- **Game-level rejection:** after `welcome`, a bad `Net._hello` (protocol
  mismatch or full roster) triggers the RPC `Net._reject(reason: String)`
  followed ~0.5 s later by transport close.
- **Post-welcome framing/RPC errors:** sending malformed JSON, an unknown
  message `t`, a binary frame while `enc:"json"`, a truncated/invalid binary
  frame, or an unknown RPC method on an existing node causes the server to reply
  with `{"t":"error","msg":"..."}` **without** disconnecting the peer.
- **Transient missing nodes:** an RPC targeting a node that is not currently in
  the server's scene tree (for example, an in-flight `_push_transform` arriving
  just as a run unloads) is silently dropped so scene transitions never kick
  clients.

### Client responsibilities

Because Fallout Forecast is a hybrid client-predicted / host-authoritative game,
a Full-tier client must perform the same local simulation and reporting that a
native Godot client performs:

1. **Coordinate system and units:** right-handed 3D metres, **+Y up**, **-Z
   forward** at yaw `0`. Yaw rotates around +Y (radians, counter-clockwise when
   viewed from above); pitch rotates the camera head around local +X (radians,
   clamped to `±88°`, positive looks up). Velocities are metres/second.
2. **Owner-authoritative movement and 20 Hz transform push:**
   - You own physics and collision for your own avatar `Main/Players/P_<you>`.
     Reference movement constants: `walk_speed = 5.0`, `sprint_speed = 8.0`,
     `crouch_speed = 2.5`, `crawl_speed = 1.0` (while `downed`),
     `turned_speed = 5.5` (while `turned`), `jump_velocity = 4.8`,
     `ground_accel = 60.0`, `air_accel = 12.0`, `gravity = 9.8` m/s²,
     capsule radius `0.4`, `stand_height = 1.8`, `crouch_height = 1.1`,
     `downed_height = 0.7`, camera eye height `height - 0.15`.
     With squad mutation `adrenaline_glands`, multiply horizontal speeds by
     `1.18` and jump velocity by `1.20`.
   - Stream `Main/Players/P_<you>._push_transform(pos: Vector3, yaw: float,
     pitch: float, vel: Vector3)` at **20 Hz** (every 50 ms) once
     `Net._confirm_run_ready` has arrived.
   - Honor server overrides immediately:
     - `Main/Players/P_<you>._teleport(xf: Transform3D)` — snap position/basis
       and zero velocity (used on Clearing respawn).
     - `Main/Players/P_<you>._receive_enemy_pull(impulse: Vector3)` — apply
       enemy knockback/pull impulse (e.g. Undertow drag) to your local movement.
   - Ignore `Main/Players/P_<you>._relay_transform` for your own peer ID (the
     host broadcasts `_relay_transform` to all `run_peers`, including the
     originator!). For teammates `P_<other>`, extrapolate along `vel` up to
     `0.1` s and exponentially blend (`1 - exp(-14 * dt)`), snapping if error
     exceeds `4.0` m.
3. **Shelter and puddle exposure reporting (critical for suit/health drain!):**
   - The host does **not** raycast shelter/puddles for remote players — it trusts
     each owning client's `Main/Players/P_<you>._report_exposure(is_sheltered:
     bool, is_in_puddle: bool)`!
   - Compute `sheltered = roof_ray_40m_up_hits_layer1 OR head_inside_layer4_shelter_area`
     (including teammates' raised tarps). Compute `in_puddle = (pos + (0,0.05,0))
     inside layer5_puddle_area`.
   - Send `_report_exposure(sheltered, in_puddle)` once immediately after
     `Net._confirm_run_ready` and reliably on every state change.
   - Note: active Shield Domes (`WeaponProjectile` with `id == "shield_dome"`)
     override exposure on the host automatically.
4. **RTT keepalive (required for lag-compensated shooting):**
   - Every `1.0` s, the host sends `Net._rtt_ping(seq: int, measured_rtt_ms:
     float)`. Immediately reply with `Net._rtt_pong(seq: int)` (unreliable).
     The host uses smoothed RTT (`clamp(rtt * 0.5 + 33, 0, 250)` ms) to rewind
     enemy and Turned-player hitboxes when resolving your shots.
5. **Vitals, player states, and Turned melee:**
   - The host owns `health`, `suit_integrity`, `state` (`"ok"`, `"downed"`,
     `"turned"`, `"out"`), `bleed_left`, `tarp_raised`, `max_health`,
     `static_charge`, and `invulnerable`, pushing `Main/Players/P_<id>._apply_vitals`
     at **5 Hz** (`0.2` s).
   - While `state == "turned"`, press fire to send
     `Main/Players/P_<you>._request_melee()` (host validates `2.2` m range and
     forward cone).
   - If granted a tarp (`_grant_tarp()`), toggle raising it with
     `Main/Players/P_<you>._push_tarp(value: bool)` (relayed via `_apply_tarp`).
6. **Inventory, starter kit, weapons, and hitscan prediction:**
   - All 5 hotbar slots, reserves, scrap, grenades, and domes are **host-authoritative**
     via `Main/Players/P_<you>/Head/Camera3D/WeaponHolder._private_state(...)`
     (ignore updates with `rev <= last_private_rev` or wrong `run_id`). Other
     players' visible held item and reload state arrive via `_equip_state(...)`.
   - At run start, pick a starter kit with `Main/RunLoot._request_starter(run_id,
     index)` where `index` is `0` (`pump_shotgun`), `1` (`nail_driver`), or `2`
     (`service_revolver`), confirmed by `Main/RunLoot._starter_accepted(run_id)`.
   - Inventory actions go through `WeaponHolder._action(run_id, action, expected_serial, slot)`:
     - `"select"` (`slot = 0..4`), `"select_pouch"` (`slot = 0` frag, `1` shield_dome, `-1` unequip pouch)
     - `"reload"`, `"drop"`, `"charge"` (`expected_serial` = currently held item's `serial`)
     - `"swap"` (`expected_serial` = source item's `serial`, `slot = from_slot * 5 + to_slot`)
     - `"drop_slot"` (`expected_serial` = slot item's `serial`, `slot = 0..4`)
   - **Firing guns:** send `WeaponHolder._request_shot(run_id, serial, origin:
     Vector3, dir: Vector3, is_aiming: bool, predicted: bool)`. Host validates
     `origin` is within `3.0` m of your camera with clear line of sight. If your
     client plays immediate local muzzle/recoil/audio feedback, pass
     `predicted = true` so when the host relays `_shot_fx(..., predicted)` back
     to all `run_peers`, your client skips duplicating its own audio/gesture and
     only draws the authoritative `traces`. Hitmarkers and floating damage
     numbers arrive via `Main/Players/P_<you>._receive_hits(run_id, hits)`.
   - **Throwing pouch items:** equip pouch (`select_pouch`), then send
     `WeaponHolder._request_throw(run_id, id, origin, dir)` (`id` is `"frag"` or
     `"shield_dome"`).
   - **World pickups & interactables:**
     - Ground weapon/item pickup: `Main/RunLoot._claim(run_id, pickup_id,
       expected_serial, current_slot)`. (Supply/scrap pickups auto-collect on
       the host by proximity every `0.12` s.)
     - Vending cabinets & airdrops: `GameManager/CrateManager._hold_request(run_id,
       key, mode, step, offer_serial)` — send `step = "begin"`, hold at least
       `0.48` s within reach and LOS, then send `step = "finish"` (or `"cancel"`
       if aborted). `key` is `"Airdrop"` or cabinet node name; `mode` is
       `"airdrop"`, `"ammo"`, or bay pad name (`"bay_0"`, `"bay_1"`, `"bay_2"`).
     - Generic interactables (Decon Showers, teammate `ReviveSpot`): send
       `GameManager._request_interact(target_node_path: NodePath)` after
       completing the local hold (`1.0` s for decon, `3.0` s for revive).
7. **Projectiles and deployables:**
   - The host simulates authoritative projectile physics and damage. Clients
     spawn visual replicas on `Main/RunLoot._effect_spawn(run_id, seq, row)`,
     integrate gravity locally between **10 Hz** (`0.1` s) `Main/RunLoot._flight`
     corrections, switch to deployed state on `_effect_deploy`, and destroy/blast
     on `_effect_end`. Never apply damage locally.
8. **Enemies, Boss, and wave progress:**
   - The host runs all enemy AI and navigation. Clients instantiate/track enemies
     by `net_id` from `Main/Enemies._spawn_enemy`, interpolate positions and yaws
     from **20 Hz** `Main/Enemies._sync_enemies(ids, places, yaws)`, update HUD
     counters from **~3.6 Hz** (`0.28` s) `Main/Enemies._sync_progress`, and
     remove enemies on `_despawn_enemy` or `_retire_enemies`.
   - Wave 5 spawns `Main/Enemies/BossCumulus` via `GameManager._spawn_boss(at)`;
     track its position, `[sac0_hp, sac1_hp, sac2_hp, core_hp]`, `sacs_left`,
     and `burn_left` from `BossCumulus._sync`, and destroy on `BossCumulus._died`.
9. **Weather and storm easing:**
   - The host only broadcasts phase transitions (`WeatherManager._receive_phase(phase,
     wave, phase_time_left)`) and boss/mutation intensity overrides (`_override`).
   - Clients MUST locally count `phase_time_left` down each frame (pausing the
     countdown while a `MutationRoll` draft holds `CALM`) and linearly ramp
     `storm_intensity` toward the phase target (`CALM/CLEARING = 0.0`,
     `DRIZZLE = 0.3`, `DOWNPOUR waves 1–4 = 0.7`, `DOWNPOUR wave 5+ = 1.0`, or
     `intensity_override` if `>= 0`) at **`0.1` intensity/second**.
   - Lightning arrives via `WeatherManager._strike(pos, strike_seed)`: a
     **negative** `strike_seed` is purely atmospheric ambient lightning; a
     **positive** `strike_seed` is a tactical/item strike (Lightning Rod Spike).
10. **Calm/Clearing ready-up, Mutation Draft, Pings, Pause, and Endless Tape:**
    - Skip Calm/Clearing wait (> 3 s remaining): `GameManager._request_ready()`
      (host broadcasts `GameManager._ready_changed(count, needed)`).
    - Wave 2+ Mutation Draft: on `GameManager/MutationRoll._deal_rpc(enemy_id,
      cards)`, vote with `_request_vote(0|1|2)`; watch `_votes_rpc(counts)` and
      `_result_rpc(pick, enemy_list, player_list, granted)`.
    - Squad pings: `Main/Pings._request_ping(kind, pos, enemy_id)` (rate-limited
      to 4/s, max 120 m, `"revive"` only while `downed`) -> relayed via
      `Main/Pings._show_ping(peer, kind, pos, enemy_id)`.
    - Global pause: `GameManager._request_pause_rpc(paused, who)` -> relayed via
      `GameManager._sync_pause(paused, who)`.
    - Post-Cumulus Endless Tape choice: when `GameManager._sync_tape_state(true,
      false, true)` arrives, the first peer in `Net.roster` (the tape decider)
      sends `GameManager._request_tape_choice(keep_playing: bool)` (`true` =
      Endless Mode wave 6+, `false` = finish with victory).
11. **`call_local` and self-relayed RPCs:**
    - **Zero** RPCs in Fallout Forecast use `call_local` — all 102 RPCs are
      `call_remote`.
    - Eight relayed RPCs (`Net._chat_rpc`, `GameManager._sync_pause`,
      `Main/Pings._show_ping`, `Player._relay_transform`, `Player._apply_tarp`,
      `WeaponHolder._shot_fx`, `WeaponHolder._throw_fx`,
      `WeaponHolder._equip_state`) are sent back to **all** peers including the
      originator. Guard local state accordingly (ignore `_relay_transform` and
      `_equip_state` for your own peer ID, and honor `predicted` on `_shot_fx`
      and `_throw_fx`).

#### Wire payload tables (arrays & enums inside RPC arguments)

| Structure | Wire format |
| --- | --- |
| `ItemInstance.encode()` | `[serial: int, id: String, tier: int (0=Standard, 1=Tuned, 2=Overclocked, 3=Apex), count: int]` (empty `[]` = empty slot / no item) |
| `RunLoot._spawn` `row` | `[pos: Vector3, item_encoded: Array, flavor: String, claim_peer: int]` |
| `RunLoot._snapshot` `rows[]` | `[[pickup_id: int, row: Array], ...]` |
| `WeaponProjectile.snapshot()` | `[id: String, pos: Vector3, vel: Vector3, tier: int, deployed: bool, life_left: float, yaw: float]` |
| `RunLoot._snapshot` `effects[]` | `[[seq: int, snapshot: Array], ...]` |
| `RunLoot._flight` `rows[]` | `[[seq: int, pos: Vector3, vel: Vector3], ...]` |
| `CrateManager` vending offer | `[item_id: String, tier: int, price_scrap: int, offer_serial: int]` |
| `CrateManager._snapshot` `drop` | `[]` if no airdrop, else `[pos: Vector3, descent_left: float]` |
| `WeaponHolder._shot_fx` `traces[]` | `[[end_pos: Vector3, hit_surface_or_enemy: bool, ...], ...]` |
| `Player._receive_hits` `hits[]` | `[[killed: bool, critical: bool, hit_pos: Vector3, damage: int, enemy_id: int], ...]` |
| `EnemySpawner._enemy_impacts` `rows[]` | `[[enemy_net_id: int, dir: Vector3, critical: bool], ...]` |
| `EnemySpawner.Kind` (`int`) | `0`=Drip, `1`=Gutter, `2`=Mister, `3`=Sleet, `4`=Hailstone, `5`=Undertow, `6`=Static, `7`=Smog, `8`=Thunderhead |
| `WeatherManager.Phase` (`int`) | `0`=Calm, `1`=Mutation Roll (legacy), `2`=Drizzle, `3`=Downpour, `4`=Clearing |
| `Cosmetics.COLORS` (`0..9`) | `0`=Hazmat Yellow, `1`=Teal, `2`=Hot Pink, `3`=Lime, `4`=Orange, `5`=Purple, `6`=White, `7`=Red, `8`=Storm Blue, `9`=Rust |
| `Cosmetics.SKINS` (`0..4`) | `0`=Standard, `1`=Gas Mask, `2`=Firefighter, `3`=Bio-Tech, `4`=Ion Rig |

### Complete JSON session transcript (handshake → lobby → run → results)

`C` is the client and `S` is the server (prefixes are explanatory). High-rate
repeats between representative frames are elided.

```text
C {"t":"hello","v":1,"tier":"full","enc":"json"}
S {"t":"welcome","v":1,"tier":"full","enc":"json","you":89786151,"game_protocol":19,"maps":[{"id":"pinecrest","name":"PINECREST"},{"id":"harbor","name":"HARBOR POINT"},{"id":"maple_hollow","name":"MAPLE HOLLOW"}]}
C {"t":"ping","ms":12345}
S {"t":"pong","ms":12345}
C {"t":"rpc","node":"Net","method":"_hello","args":["{\"name\":\"3DS\",\"color\":1,\"skin\":0,\"colors\":[]}",19],"ch":0,"rel":true}
S {"t":"rpc","node":"Net","method":"_push_roster","args":[{"_t":"dict","v":[[89786151,{"name":"3DS","ready":false,"color":1,"skin":0}]]},"pinecrest",true,{},""],"ch":0,"rel":true}
S {"t":"rpc","node":"Net","method":"_rtt_ping","args":[1,0.0],"ch":0,"rel":false}
C {"t":"rpc","node":"Net","method":"_rtt_pong","args":[1],"ch":0,"rel":false}
C {"t":"rpc","node":"Net","method":"_request_map_vote","args":["pinecrest"],"ch":0,"rel":true}
C {"t":"rpc","node":"Net","method":"_request_chat","args":["ready to roll"],"ch":0,"rel":true}
S {"t":"rpc","node":"Net","method":"_chat_rpc","args":["3DS","ready to roll"],"ch":0,"rel":true}
C {"t":"rpc","node":"Net","method":"_request_ready","args":[true],"ch":0,"rel":true}
S {"t":"rpc","node":"Net","method":"_push_roster","args":[{"_t":"dict","v":[[89786151,{"name":"3DS","ready":false,"color":1,"skin":0}]]},"pinecrest",true,{"pinecrest":1},"pinecrest"],"ch":0,"rel":true}
S {"t":"rpc","node":"Net","method":"_start_run","args":["pinecrest"],"ch":0,"rel":true}
C {"t":"rpc","node":"Net","method":"_report_in_run","args":[true],"ch":0,"rel":true}
S {"t":"rpc","node":"GameManager","method":"_sync_tape_state","args":[false,false,false],"ch":0,"rel":true}
S {"t":"rpc","node":"WeatherManager","method":"_receive_phase","args":[0,1,12.0],"ch":0,"rel":true}
S {"t":"rpc","node":"WeatherManager","method":"_receive_intensity","args":[0.0],"ch":0,"rel":true}
S {"t":"rpc","node":"WeatherManager","method":"_override","args":[-1.0],"ch":0,"rel":true}
S {"t":"rpc","node":"GameManager","method":"_sync_decon","args":[4],"ch":0,"rel":true}
S {"t":"rpc","node":"GameManager/MutationRoll","method":"_sync_active","args":[[],[]],"ch":0,"rel":true}
S {"t":"rpc","node":"GameManager/CrateManager","method":"_snapshot","args":[1,{"HardwareStation":[["med_tin",0,6,1],["spray_rifle",0,11,2],["harpoon",1,18,3]]},[]],"ch":0,"rel":true}
S {"t":"rpc","node":"Main/Enemies","method":"_sync_progress","args":[1,26,26,2.1,0],"ch":0,"rel":false}
S {"t":"rpc","node":"WeatherManager","method":"_sync_puddles","args":[{"_t":"dict","v":[[{"_t":"np","v":"/root/Main/Level/Puddles/MainW"},0.0]]}],"ch":0,"rel":true}
S {"t":"rpc","node":"Main/RunLoot","method":"_snapshot","args":[1,[],[],[],false],"ch":0,"rel":true}
S {"t":"rpc","node":"Main/Players/P_89786151/Head/Camera3D/WeaponHolder","method":"_equip_state","args":[1,1,"",0,0.0,1.0],"ch":0,"rel":true}
S {"t":"rpc","node":"Main/Players/P_89786151/Head/Camera3D/WeaponHolder","method":"_private_state","args":[1,1,[[],[],[],[],[]],{},0,"",0,0,0,0.0,1.0,0.0,0.0],"ch":0,"rel":true}
S {"t":"rpc","node":"Net","method":"_confirm_run_ready","args":[],"ch":0,"rel":true}
C {"t":"rpc","node":"Main/RunLoot","method":"_request_starter","args":[1,0],"ch":0,"rel":true}
S {"t":"rpc","node":"Main/RunLoot","method":"_starter_accepted","args":[1],"ch":0,"rel":true}
C {"t":"rpc","node":"Main/Players/P_89786151","method":"_report_exposure","args":[false,false],"ch":0,"rel":true}
C {"t":"rpc","node":"GameManager","method":"_request_ready","args":[],"ch":0,"rel":true}
C {"t":"rpc","node":"Main/Players/P_89786151","method":"_push_transform","args":[{"_t":"v3","v":[3.0,0.2,0.0]},0.0,0.0,{"_t":"v3","v":[0.0,0.0,2.0]}],"ch":0,"rel":false}
S {"t":"rpc","node":"WeatherManager","method":"_receive_phase","args":[2,1,30.0],"ch":0,"rel":true}
S {"t":"rpc","node":"Main/Enemies","method":"_spawn_enemy","args":[1,0,{"_t":"v3","v":[-56.55,0.65,0.85]},false,false],"ch":0,"rel":true}
S {"t":"rpc","node":"Main/Enemies","method":"_sync_enemies","args":[{"_t":"pi32","v":[1]},{"_t":"pv3","v":[[-56.42,0.63,0.84]]},{"_t":"pf32","v":[-1.56]}],"ch":0,"rel":false}
S {"t":"rpc","node":"Main/Players/P_89786151","method":"_apply_vitals","args":[100.0,100.0,"ok",0.0,false,100.0,0.0,false],"ch":0,"rel":false}
S {"t":"rpc","node":"GameManager","method":"_finish","args":[false,{"won":false,"map_id":"pinecrest","waves":1,"wave_reached":1,"endless":false,"endless_score":0,"seconds":120,"squad_mutations":[],"players":{"_t":"dict","v":[[89786151,{"name":"3DS","kills":12,"revives":0,"turned":0,"cursed":"","weapon":"Pump Shotgun"}]]}}],"ch":0,"rel":true}
C {"t":"rpc","node":"Net","method":"_report_in_run","args":[false],"ch":0,"rel":true}
C {"t":"leave"}
```

### Binary session transcript (raw TCP hex excerpt)

Negotiate `"enc":"bin"` in the JSON `hello` (sent with a 4-byte LE TCP length
prefix). After `welcome`, every `rpc` frame uses tag `0x03` (preceded by its
4-byte LE length on raw TCP; sent directly as a WebSocket binary message on
port `7780`):

```text
C (text, 45B) 2d 00 00 00 {"t":"hello","v":1,"tier":"full","enc":"bin"}
S (text)      <len32>     {"t":"welcome","v":1,"tier":"full","enc":"bin","you":5,"game_protocol":19,"maps":[...]}
C (bin, 80B)  50 00 00 00 03 02 00 03 00 4e 65 74 06 5f 68 65 6c 6c 6f 02 04 00 00 00 2d 00 00 00 7b 22 6e 61 6d 65 22 3a 22 33 44 53 22 2c 22 63 6f 6c 6f 72 22 3a 31 2c 22 73 6b 69 6e 22 3a 30 2c 22 63 6f 6c 6f 72 73 22 3a 5b 5d 7d 00 00 00 02 00 00 00 13 00 00 00
C (bin, 32B)  20 00 00 00 03 02 00 03 00 4e 65 74 0e 5f 72 65 71 75 65 73 74 5f 72 65 61 64 79 01 01 00 00 00 01 00 00 00
S (bin, 28B)  1c 00 00 00 03 02 00 03 00 4e 65 74 12 5f 63 6f 6e 66 69 72 6d 5f 72 75 6e 5f 72 65 61 64 79 00
C (bin, 51B)  33 00 00 00 03 02 00 0c 00 4d 61 69 6e 2f 52 75 6e 4c 6f 6f 74 10 5f 72 65 71 75 65 73 74 5f 73 74 61 72 74 65 72 02 02 00 00 00 01 00 00 00 02 00 00 00 00 00 00 00
C (bin, 86B)  56 00 00 00 03 01 00 10 00 4d 61 69 6e 2f 50 6c 61 79 65 72 73 2f 50 5f 35 0f 5f 70 75 73 68 5f 74 72 61 6e 73 66 6f 72 6d 04 09 00 00 00 00 00 40 40 cd cc 4c 3e 00 00 00 00 03 00 00 00 00 00 c0 3f 03 00 00 00 00 00 80 be 09 00 00 00 00 00 00 00 00 00 00 00 00 00 a0 c0
S (bin, 76B)  4c 00 00 00 03 01 00 0c 00 4d 61 69 6e 2f 45 6e 65 6d 69 65 73 0d 5f 73 79 6e 63 5f 65 6e 65 6d 69 65 73 03 1e 00 00 00 01 00 00 00 01 00 00 00 24 00 00 00 01 00 00 00 00 00 20 41 00 00 00 3f 00 00 80 c0 20 00 00 00 01 00 00 00 00 00 c0 3f
C (text, 13B) 0d 00 00 00 {"t":"leave"}
```

### Schema generation and conformance checker

Regenerate [`docs/open-protocol-schema.json`](open-protocol-schema.json) after
any RPC or `Net.PROTOCOL` change:

```sh
godot --headless --path . --audio-driver Dummy -s tools/open_protocol/gen_schema.gd
```

Run the stdlib-only reference client and conformance checker
(`tools/open_protocol/full_client.py`) against a local dedicated server:

```sh
python tools/open_protocol/full_client.py --transport ws  --enc json --port 7780 --mode check --require-enemies
python tools/open_protocol/full_client.py --transport tcp --enc bin  --port 7781 --mode check --require-enemies
python tools/open_protocol/full_client.py --transport ws  --enc bin  --port 7780 --mode check
python tools/open_protocol/full_client.py --transport tcp --enc json --port 7781 --mode check
python tools/open_protocol/full_client.py --transport ws  --enc json --port 7780 --mode reject
```

Pass `--expect-peers 2` when testing alongside a native Godot client, `--code
VALUE` if the server enforces a join code, `--dump-transcript FILE` to record
every frame with binary hex, or `--mode play` to keep the client walking in a
run while logging decoded RPCs.
