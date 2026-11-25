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
