# Fallout Forecast car bridge protocol, v1 (shared contract)

Goal: play Fallout Forecast co-op on the cloud server from a 2017 Honda head unit
(Android 5.1.1 / API 22, armeabi-v7a, PowerVR SGX 544MP = OpenGL ES 2.0 only, 1280x720 touch,
~1240x606 usable app area under Honda's 80 px top bar). Godot 4 cannot run there, so:

    car app (Godot 3.6, GLES2)  <--WSS, this protocol-->  car bridge (Godot 4.7.2 headless game client)  <--normal game protocol-->  cloud dedicated server

The bridge is the real game running headless as an ordinary Cloud Play client. It owns one
`Player` node for the car's peer, drives it from car input, and streams compact snapshots back.
The dedicated server needs no changes and sees the car as a normal player.

## Transport
- WebSocket, text frames, one JSON object per frame, key `t` = message type.
- Production URL: `wss://fallout-car.drew.place/` (TLS terminated by the host proxy). Local dev: `ws://127.0.0.1:8790/`.
- One car per WebSocket connection. The bridge service must support at least 4 concurrent cars
  (e.g. a supervisor that spawns one headless Godot bridge process per connection).
- Vectors are arrays `[x, y, z]` in the game's world space (Godot: Y up, -Z forward), metres, rounded to 2 decimals.
  Angles in radians, 3 decimals. Unknown keys must be ignored by both sides (forward compatible).
- Bridge -> car `snap` at 20 Hz. Car -> bridge `in` at 30 Hz while in a run. Either side may send `ping`/`pong` ({"t":"ping","ms":<sender clock>}, echoed back as `pong` with same `ms`).
- If the car connection drops, the bridge leaves the cloud server and exits/cleans up within 5 s.

## Car -> bridge
- `{"t":"hello","v":1,"name":"Honda","client":"car/0.1"}` first message. Bridge replies `welcome` or `error`.
- `{"t":"lobby","a":"ready","v":true}` | `{"t":"lobby","a":"vote","map":"harbor"}` | `{"t":"lobby","a":"start"}` (force start) | `{"t":"lobby","a":"chat","text":"hi"}`
- `{"t":"in","seq":123,"mv":[x,y],"yaw":1.57,"pitch":-0.2,"b":<bitmask>,"slot":0,"wheel":0}`
  - `mv`: move stick, x = right, y = back (same sign convention as `Input.get_vector("move_left","move_right","move_forward","move_back")`), length <= 1.
  - `yaw`/`pitch`: ABSOLUTE desired camera yaw (player body rotation.y) and pitch (head rotation.x), radians. The car owns look; the bridge applies them directly to its player each frame (clamped to the game's pitch limits).
  - `b` held-button bitmask: fire 1, aim 2, jump 4, crouch 8, sprint 16, reload 32, interact 64, use_item 128, drop_item 256, ping 512, ready_up 1024, throw_grenade 2048, throw_dome 4096. The bridge turns bit edges into `Input.action_press/release` so "just pressed" logic works.
  - `slot`: 0 = no change, 1..5 = select that hotbar slot (edge: only acted on when it changes from the previous `in`). `wheel`: -1/0/+1 = weapon_prev/none/weapon_next (edge).
- `{"t":"choice","kind":"mutation","i":0}` (card 0..2) | `{"t":"choice","kind":"tape","i":0}` (0 = CONTINUE, 1 = END TAPE)
- `{"t":"leave"}` return to lobby / disconnect cleanly.

## Bridge -> car
- `{"t":"welcome","v":1,"game_protocol":<Net.PROTOCOL>,"you":<peer_id>,"maps":[{"id":"pinecrest","name":"Pinecrest"},...]}`
- `{"t":"error","msg":"..."}` then close.
- `{"t":"status","state":"connecting|lobby|loading|run|results|disconnected","msg":"..."}`
- `{"t":"lobby","players":[{"id":2,"name":"Drew","ready":true,"vote":"harbor","car":false}],"maps":[...],"countdown":-1,"chat":[{"from":"Drew","text":"hi"}]}` sent on every change.
- `{"t":"load","map":"pinecrest"}` when the run scene loads (car loads its matching level), then `status` `run` once the bridge's player exists.
- `{"t":"snap","tick":n,"t_ms":<bridge ms>,"ack":<last in.seq applied>,"you":{...},"players":[...],"enemies":[...],"pickups":[...],"projectiles":[...],"weather":{...},"run":{...}}`
  - `you`: `{"id","pos","vel","yaw","pitch","state":"ok|downed|turned|out","hp","hp_max","suit","suit_max","exposed","sheltered","in_puddle","crouch","aiming","reloading","slot","slots":[{"item":"pump_shotgun","name":"Pump","ammo":5,"mag":6,"reserve":18,"count":1} or null x5],"scrap","revive":0..1,"prompt":"Hold E to ..."|""}`
  - `players` (others): `[{"id","name","pos","yaw","pitch","state","item","crouch","suit_color":"#rrggbb","skin":"..."}]`
  - `enemies`: `[{"id","type":"drip|gutter|mister|hailstone|sleet|smog|static|thunderhead|undertow|cloudburst|cumulus|turned","pos","yaw","hp":0..1,"anim":"spawn|idle|walk|attack|windup|stagger|die"}]` (only alive or dying; the car removes ids that disappear)
  - `pickups`: `[{"id","item","pos","kind":"weapon|ammo|health|suit|scrap|item|airdrop|station"}]` (may be sent at a lower rate, e.g. every 5th snap, with `"full":true`)
  - `projectiles`: `[{"id","kind","pos","vel"}]`
  - `weather`: `{"phase":"calm|drizzle|downpour|acid_storm|clearing","intensity":0..1,"wave":1,"phase_time_left":12.3,"lightning":false}`
  - `run`: `{"alive_enemies","wave","endless":false,"shared_decon":2,"score":0}`
- `{"t":"ev","list":[...]}` one-shot events, batched per tick:
  - `{"e":"shot","by":<peer|enemy id>,"weapon":"...","from":[...],"to":[...]}` tracer/muzzle
  - `{"e":"hit","at":[...],"head":false,"dmg":12}` (hit markers / damage numbers for the car's own shots)
  - `{"e":"kill","enemy":<id>,"type":"gutter"}`
  - `{"e":"hurt","dir":[...],"amt":10}` car player took damage (direction for the damage vignette)
  - `{"e":"lightning","at":[...]}`, `{"e":"sound","name":"<Sound cue name>","at":[...]|null}`
  - `{"e":"banner","text":"WAVE 2 — DRIZZLE"}`, `{"e":"puddle","id","pos","radius","on":true|false}`, `{"e":"pickup","item":"..."}`
- `{"t":"draft","kind":"mutation","cards":[{"id","title","desc","icon"}],"time_left":15}` / `{"t":"draft_done"}`
- `{"t":"tape","time_left":20}` (Endless CONTINUE / END TAPE prompt)
- `{"t":"results","won":true,"time_s":612,"waves":5,"kills":120,"players":[{"name","kills","downs","revives"}],"score":0}`

The bridge documents any field it cannot fill (send null) in `docs/car-bridge-protocol.md`, which is the
authoritative copy once committed. Additive changes are fine; renames/removals need `v` bumped.
