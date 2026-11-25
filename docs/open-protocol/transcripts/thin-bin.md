# Thin tier session — tcp/bin

Captured from a local dedicated server (Godot 4.7.2, game protocol from `welcome`), transport **tcp**, encoding **bin**, by `tools/open_protocol/capture_transcripts.py` under `tools/open_protocol/capture_harness.gd` (real server code; only the storm timers were shortened, wave-1 stragglers were finished off after 9 s and the run was ended through `GameManager.finish(false)` 6 s into wave 2 so the session fits in about two minutes). A second bot of the other tier played in the same lobby, so its traffic appears too.

`C→S` is client to server, `S→C` server to client, `+t` is seconds since capture start. Binary frames are shown as hex (the raw TCP length prefix is shown on its own line) with the decoded value underneath. Long previews can be truncated; TCP prefixes always describe the full payload. Repeats are counted at the end of the section. The order-preserving sampled log is [`thin-bin.jsonl`](thin-bin.jsonl).

> First frame on the socket, always JSON text even for `enc:"bin"` (spec-common §4, spec-thin §2).

```text
+  2.753s C→S text (raw TCP prefix 63 00 00 00)
     {"t":"hello","v":1,"tier":"thin","enc":"bin","name":"Thin Bot","client":"capture-thin/1","rate":20}
```

## Handshake and lobby

> Server accepted the hello: `you` is the roster id, `rate/radius/max_enemies` echo the negotiated values (spec-thin §2).

```text
+  2.755s S→C text (raw TCP prefix f3 00 00 00)
     {"t":"welcome","v":1,"game_protocol":19,"you":2,"maps":[{"id":"pinecrest","name":"PINECREST"},{"id":"harbor","name":"HARBOR POINT"},{"id":"maple_hollow","name":"MAPLE HOLLOW"}],"tier":"thin","enc":"bin","rate":20,"radius":0.0,"max_enemies":-1}
```
> Connection state machine update (spec-thin §3). `run` is the only state where `in`/`choice` are applied.

```text
+  2.755s S→C text (raw TCP prefix 27 00 00 00)
     {"t":"status","state":"lobby","msg":""}
```
> Full lobby state; sent on every change, never as a delta (spec-thin §4).

```text
+  2.755s S→C text (raw TCP prefix 02 01 00 00)
     {"t":"lobby","players":[{"id":2,"name":"Thin Bot","ready":false,"vote":"","car":true}],"maps":[{"id":"pinecrest","name":"PINECREST"},{"id":"harbor","name":"HARBOR POINT"},{"id":"maple_hollow","name":"MAPLE HOLLOW"}],"countdown":-1,"chat":[],"vote_counts":{}}
+  3.354s S→C text (raw TCP prefix 49 01 00 00)
     {"t":"lobby","players":[{"id":2,"name":"Thin Bot","ready":false,"vote":"","car":true},{"id":234289745,"name":"Full Bot","ready":false,"vote":"","car":false}],"maps":[{"id":"pinecrest","name":"PINECREST"},{"id":"harbor","name":"HARBOR POINT"},{"id":"maple_hollow","name":"MAPLE HOLLOW"}],"countdown":-1,"chat":[],"vote_counts":{}}
+  3.757s C→S text (raw TCP prefix 16 00 00 00)
     {"t":"ping","ms":4242}
+  3.757s C→S text (raw TCP prefix 31 00 00 00)
     {"t":"lobby","a":"chat","text":"thin bot online"}
+  3.757s C→S text (raw TCP prefix 2a 00 00 00)
     {"t":"lobby","a":"vote","map":"pinecrest"}
```
> Echo of the client's `ping.ms` (spec-common §6).

```text
+  3.773s S→C text (raw TCP prefix 18 00 00 00)
     {"t":"pong","ms":4242.0}
+  3.774s S→C text (raw TCP prefix 75 01 00 00)
     {"t":"lobby","players":[{"id":2,"name":"Thin Bot","ready":false,"vote":"","car":true},{"id":234289745,"name":"Full Bot","ready":false,"vote":"","car":false}],"maps":[{"id":"pinecrest","name":"PINECREST"},{"id":"harbor","name":"HARBOR POINT"},{"id":"maple_hollow","name":"MAPLE HOLLOW"}],"countdown":-1,"chat":[{"from":"Thin Bot","text":"thin bot online"}],"vote_counts":{}}
+  3.775s S→C text (raw TCP prefix 8b 01 00 00)
     {"t":"lobby","players":[{"id":2,"name":"Thin Bot","ready":false,"vote":"pinecrest","car":true},{"id":234289745,"name":"Full Bot","ready":false,"vote":"","car":false}],"maps":[{"id":"pinecrest","name":"PINECREST"},{"id":"harbor","name":"HARBOR POINT"},{"id":"maple_hollow","name":"MAPLE HOLLOW"}],"countdown":-1,"chat":[{"from":"Thin Bot","text":"thin bot online"}],"vote_counts":{"pinecrest":1}}
+  4.178s S→C text (raw TCP prefix b8 01 00 00)
     {"t":"lobby","players":[{"id":2,"name":"Thin Bot","ready":false,"vote":"pinecrest","car":true},{"id":234289745,"name":"Full Bot","ready":false,"vote":"","car":false}],"maps":[{"id":"pinecrest","name":"PINECREST"},{"id":"harbor","name":"HARBOR POINT"},{"id":"maple_hollow","name":"MAPLE HOLLOW"}],"countdown":-1,"chat":[{"from":"Thin Bot","text":"thin bot online"},{"from":"Full Bot","text":"full bot online"}],"vote_counts":{"pinecrest":1}}
+  4.179s S→C text (raw TCP prefix c1 01 00 00)
     {"t":"lobby","players":[{"id":2,"name":"Thin Bot","ready":false,"vote":"pinecrest","car":true},{"id":234289745,"name":"Full Bot","ready":false,"vote":"pinecrest","car":false}],"maps":[{"id":"pinecrest","name":"PINECREST"},{"id":"harbor","name":"HARBOR POINT"},{"id":"maple_hollow","name":"MAPLE HOLLOW"}],"countdown":-1,"chat":[{"from":"Thin Bot","text":"thin bot online"},{"from":"Full Bot","text":"full bot online"}],"vote_counts":{"pinecrest":2}}
+  4.565s C→S text (raw TCP prefix 22 00 00 00)
     {"t":"lobby","a":"ready","v":true}
+  4.581s S→C text (raw TCP prefix c0 01 00 00)
     {"t":"lobby","players":[{"id":2,"name":"Thin Bot","ready":true,"vote":"pinecrest","car":true},{"id":234289745,"name":"Full Bot","ready":false,"vote":"pinecrest","car":false}],"maps":[{"id":"pinecrest","name":"PINECREST"},{"id":"harbor","name":"HARBOR POINT"},{"id":"maple_hollow","name":"MAPLE HOLLOW"}],"countdown":-1,"chat":[{"from":"Thin Bot","text":"thin bot online"},{"from":"Full Bot","text":"full bot online"}],"vote_counts":{"pinecrest":2}}
+  5.688s S→C text (raw TCP prefix bf 01 00 00)
     {"t":"lobby","players":[{"id":2,"name":"Thin Bot","ready":true,"vote":"pinecrest","car":true},{"id":234289745,"name":"Full Bot","ready":true,"vote":"pinecrest","car":false}],"maps":[{"id":"pinecrest","name":"PINECREST"},{"id":"harbor","name":"HARBOR POINT"},{"id":"maple_hollow","name":"MAPLE HOLLOW"}],"countdown":-1,"chat":[{"from":"Thin Bot","text":"thin bot online"},{"from":"Full Bot","text":"full bot online"}],"vote_counts":{"pinecrest":2}}
```

## Loading

```text
+  5.688s S→C text (raw TCP prefix 29 00 00 00)
     {"t":"status","state":"loading","msg":""}
```
> Load this level now; snapshots start after the following `status run` (spec-thin §3).

```text
+  5.688s S→C text (raw TCP prefix 1e 00 00 00)
     {"t":"load","map":"pinecrest"}
+  9.070s S→C text (raw TCP prefix 25 00 00 00)
     {"t":"status","state":"run","msg":""}
```

## Run: wave 1 calm

> Complete authoritative state; `ack` = last applied input seq (spec-thin §6/§7).

```text
+  9.070s S→C binary 278 bytes
len 16 01 00 00   (raw TCP prefix: 278 bytes)
0000 02 01 00 00 00 45 23 00 00 00 00 00 00 ff ff ff
0010 ff 02 00 00 00 38 ff ff ff 06 00 00 00 32 00 00
0020 00 00 00 00 00 00 00 00 00 00 00 00 10 27 10 27
0030 10 27 10 27 01 01 01 0c 00 70 75 6d 70 5f 73 68
0040 6f 74 67 75 6e 0c 00 50 75 6d 70 20 53 68 6f 74
0050 67 75 6e 06 00 06 00 12 00 01 00 00 00 00 00 00
0060 00 00 00 00 00 00 00 00 00 00 00 02 00 01 00 01
0070 00 51 fa f6 0d c8 00 00 00 00 00 00 00 32 00 00
0080 00 00 00 00 00 00 02 08 00 46 75 6c 6c 20 42 6f
0090 74 00 00 ff 4a e0 9b 08 00 47 41 53 20 4d 41 53
00a0 4b 00 00 03 00 bb e7 ff 7c b9 ff ff ff 07 e8 fe
00b0 ff ff 05 00 00 00 84 03 00 00 07 00 73 74 61 74
00c0 69 6f 6e a9 e7 ff 6a b9 ff ff ff 07 24 13 00 00
00d0 08 00 00 00 5a 0a 00 00 07 00 73 74 61 74 69 6f
00e0 6e 97 e7 ff 58 b9 ff ff ff 07 4c eb ff ff 08 00
00f0 00 00 0d 0c 00 00 07 00 73 74 61 74 69 6f 6e 00
0100 00 00 00 00 01 00 00 00 b0 04 00 00 00 00 00 00
0110 05 00 00 00 00 00
     = {"t":"snap","tick":1,"t_ms":9029,"ack":-1,"you":{"id":2,"pos":[-2.0,0.06,0.5],"vel":[0.0,0.0,0.0],"yaw":0.0,"pitch":0.0,"state":"ok","hp":100.0,"hp_max":100.0,"suit":100.0,"suit_max":100.0,"slot":1,"exposed":true,"sheltered":false,"in_puddle":false,"crouch":false,"aiming":false,"reloading":false,"slots":[{"item":"pump_shotgun","name":"Pump Shotgun","ammo":6,"mag":6,"reserve":18,"count":1},null,null,null,null],"scrap":0,"revive":0.0,"interact_progress":0.0,"prompt":"","pouch":"","grenades":2,"domes":1},"players":[{"id":234289745,"pos":[2.0,0.0,0.5],"yaw":0.0,"pitch":0.0,"state":"ok","crouch":null,"name":"Full Bot","item":"","suit_color":"#9be04a","skin":"GAS MASK"}],"enemies":[],"pickups":[{"id":-302845532229,"kind":"station","pos":[-2.8,0.05,9.0],"item":"station"},{"id":-303147522135,"kind":"station","pos":[49.0,0.08,26.5],"item":"station"},{"id":-303449512041,"kind":"station","pos":[-53.0,0.08,30.85],"item":"station"}],"projectiles":[],"weather":{"phase":"calm","intensity":0.0,"wave":1,"phase_time_left":12.0,"lightning":false},"run":{"alive_enemies":0,"wave":1,"endless":false,"shared_decon":5,"score":0}}
```
> Ask for the current level outline.

```text
+  9.119s C→S text (raw TCP prefix 0f 00 00 00)
     {"t":"map_req"}
```
> Coarse collision outline for renderers without assets (spec-thin §8).

```text
+  9.127s S→C text (raw TCP prefix 6c 1b 00 00)
     {"t":"map","id":"pinecrest","boxes":[[0.0,0.03,0.0,134.0,0.06,9.0,0.0],[0.0,0.03,-6.25,134.0,0.06,3.5,0.0],[0.0,0.03,6.25,134.0,0.06,3.5,0.0],[0.0,0.04,-17.5,9.0,0.06,26.0,0.0],[0.0,0.05,-40.0,23.0,0.06,23.0,0.0],[0.0,0.08,-6.25,9.0,0.06,3.5,0.0],[-10.0,0.04,38.0,70.0,0.06,26.0,0.0],[-9.5,0.03,17.5,7.0,0.06,16.0,0.0],[49.0,0.05,25.0,28.0,0.06,30.0,0.0],[-53.0,0.07,25.0,22.0,0.06,32.0,0.0],[0.0,1.0,-65.0,130.0,2.0,0.4,0.0],[0.0,1.0,65.0,130.0,2.0,0.4,0.0],[-65.0,1.0,0.0,0.4,2.0,130.0,0.0],[65.0,1.0,0.0,0.4,2.0,130.0,0.0],[-68.0,3.0,0.0,0.4,6.0,16.0,0.0],[68.0,3.0,0.0,0.4,6.0,16.0,0.0],[-28.0,3…
```
> Control frame at 30 Hz; `seq` strictly increases, `b` is the button bitmask (spec-thin §5).

```text
+  9.134s C→S binary 17 bytes
len 11 00 00 00   (raw TCP prefix: 17 bytes)
0000 01 01 00 00 00 00 00 00 00 00 00 00 00 00 00 00
0010 00
     = {"t":"in","seq":1,"mv":[0.0,0.0],"yaw":0.0,"pitch":0.0,"b":0,"slot":0,"wheel":0}
+  9.166s C→S binary 17 bytes
len 11 00 00 00   (raw TCP prefix: 17 bytes)
0000 01 02 00 00 00 00 00 00 00 00 00 00 00 00 04 00
0010 00
     = {"t":"in","seq":2,"mv":[0.0,0.0],"yaw":0.0,"pitch":0.0,"b":1024,"slot":0,"wheel":0}
```
> One-shot events batched after a snapshot (spec-thin §9).

```text
+  9.230s S→C text (raw TCP prefix 44 00 00 00)
     {"t":"ev","list":[{"e":"sound","name":"storm_countdown","at":null}]}
```

Repeats not shown in this section: 90× `C→S in`, 61× `S→C snap`, 2× `S→C ev`.

## Run: wave 1 drizzle

```text
+ 12.184s S→C binary 289 bytes
len 21 01 00 00   (raw TCP prefix: 289 bytes)
0000 02 3f 00 00 00 6e 2f 00 00 00 00 00 00 5c 00 00
0010 00 02 00 00 00 38 ff ff ff 06 00 00 00 32 00 00
0020 00 00 00 00 00 00 00 00 00 00 00 00 10 27 10 27
0030 10 27 10 27 01 01 01 0c 00 70 75 6d 70 5f 73 68
0040 6f 74 67 75 6e 0c 00 50 75 6d 70 20 53 68 6f 74
0050 67 75 6e 06 00 06 00 12 00 01 00 00 00 00 00 00
0060 00 00 00 00 00 00 00 00 00 00 00 02 00 01 00 01
0070 00 51 fa f6 0d 5b 01 00 00 00 00 00 00 50 00 00
0080 00 b7 0b 00 00 00 02 08 00 46 75 6c 6c 20 42 6f
0090 74 0b 00 6e 61 69 6c 5f 64 72 69 76 65 72 ff 4a
00a0 e0 9b 08 00 47 41 53 20 4d 41 53 4b 00 00 03 00
00b0 bb e7 ff 7c b9 ff ff ff 07 e8 fe ff ff 05 00 00
00c0 00 84 03 00 00 07 00 73 74 61 74 69 6f 6e a9 e7
00d0 ff 6a b9 ff ff ff 07 24 13 00 00 08 00 00 00 5a
00e0 0a 00 00 07 00 73 74 61 74 69 6f 6e 97 e7 ff 58
00f0 b9 ff ff ff 07 4c eb ff ff 08 00 00 00 0d 0c 00
0100 00 07 00 73 74 61 74 69 6f 6e 00 00 01 02 00 01
0110 00 00 00 20 03 00 00 00 00 00 00 05 00 00 00 00
0120 00
     = {"t":"snap","tick":63,"t_ms":12142,"ack":92,"you":{"id":2,"pos":[-2.0,0.06,0.5],"vel":[0.0,0.0,0.0],"yaw":0.0,"pitch":0.0,"state":"ok","hp":100.0,"hp_max":100.0,"suit":100.0,"suit_max":100.0,"slot":1,"exposed":true,"sheltered":false,"in_puddle":false,"crouch":false,"aiming":false,"reloading":false,"slots":[{"item":"pump_shotgun","name":"Pump Shotgun","ammo":6,"mag":6,"reserve":18,"count":1},null,null,null,null],"scrap":0,"revive":0.0,"interact_progress":0.0,"prompt":"","pouch":"","grenades":2,"domes":1},"players":[{"id":234289745,"pos":[3.47,0.0,0.8],"yaw":2.999,"pitch":0.0,"state":"ok","crouch":null,"name":"Full Bot","item":"nail_driver","suit_color":"#9be04a","skin":"GAS MASK"}],"enemies":[],"pickups":[{"id":-302845532229,"kind":"station","pos":[-2.8,0.05,9.0],"item":"station"},{"id":-303147522135,"kind":"station","pos":[49.0,0.08,26.5],"item":"station"},{"id":-303449512041,"kind":"station","pos":[-53.0,0.08,30.85],"item":"station"}],"projectiles":[],"weather":{"phase":"drizzle","intensity":0.002,"wave":1,"phase_time_left":8.0,"lightning":false},"run":{"alive_enemies":0,"wave":1,"endless":false,"shared_decon":5,"score":0}}
+ 12.197s C→S binary 17 bytes
len 11 00 00 00   (raw TCP prefix: 17 bytes)
0000 01 5d 00 00 00 00 00 00 00 00 00 00 00 00 00 00
0010 00
     = {"t":"in","seq":93,"mv":[0.0,0.0],"yaw":0.0,"pitch":0.0,"b":0,"slot":0,"wheel":0}
+ 12.228s C→S binary 17 bytes
len 11 00 00 00   (raw TCP prefix: 17 bytes)
0000 01 5e 00 00 00 00 00 00 00 00 00 00 00 00 00 00
0010 00
     = {"t":"in","seq":94,"mv":[0.0,0.0],"yaw":0.0,"pitch":0.0,"b":0,"slot":0,"wheel":0}
```

Repeats not shown in this section: 240× `C→S in`, 160× `S→C snap`.

## Run: wave 1 downpour

```text
+ 20.224s S→C binary 355 bytes
len 63 01 00 00   (raw TCP prefix: 355 bytes)
0000 02 e0 00 00 00 d7 4e 00 00 00 00 00 00 4d 01 00
0010 00 02 00 00 00 38 ff ff ff 06 00 00 00 32 00 00
0020 00 00 00 00 00 00 00 87 00 ef ff 00 10 27 10 27
0030 90 24 10 27 01 01 01 0c 00 70 75 6d 70 5f 73 68
0040 6f 74 67 75 6e 0c 00 50 75 6d 70 20 53 68 6f 74
0050 67 75 6e 06 00 06 00 12 00 01 00 00 00 00 00 00
0060 00 00 00 00 00 00 00 00 00 00 00 02 00 01 00 01
0070 00 51 fa f6 0d 90 00 00 00 00 00 00 00 bd 00 00
0080 00 a4 06 00 00 00 02 08 00 46 75 6c 6c 20 42 6f
0090 74 0b 00 6e 61 69 6c 5f 64 72 69 76 65 72 ff 4a
00a0 e0 9b 08 00 47 41 53 20 4d 41 53 4b 03 00 01 00
00b0 00 00 00 87 fc ff ff 08 00 00 00 b5 ed ff ff 4b
00c0 f4 e8 03 02 02 00 00 00 01 fe fc ff ff 08 00 00
00d0 00 bb ef ff ff 41 f4 e8 03 02 03 00 00 00 00 9f
00e0 fc ff ff 00 00 00 00 44 ec ff ff 3c f4 e8 03 02
00f0 03 00 bb e7 ff 7c b9 ff ff ff 07 e8 fe ff ff 05
0100 00 00 00 84 03 00 00 07 00 73 74 61 74 69 6f 6e
0110 a9 e7 ff 6a b9 ff ff ff 07 24 13 00 00 08 00 00
0120 00 5a 0a 00 00 07 00 73 74 61 74 69 6f 6e 97 e7
0130 ff 58 b9 ff ff ff 07 4c eb ff ff 08 00 00 00 0d
0140 0c 00 00 07 00 73 74 61 74 69 6f 6e 00 00 02 2f
0150 01 01 00 00 00 33 11 00 00 00 03 00 00 05 00 00
0160 00 00 00
     = {"t":"snap","tick":224,"t_ms":20183,"ack":333,"you":{"id":2,"pos":[-2.0,0.06,0.5],"vel":[0.0,0.0,0.0],"yaw":0.135,"pitch":-0.017,"state":"ok","hp":100.0,"hp_max":100.0,"suit":93.6,"suit_max":100.0,"slot":1,"exposed":true,"sheltered":false,"in_puddle":false,"crouch":false,"aiming":false,"reloading":false,"slots":[{"item":"pump_shotgun","name":"Pump Shotgun","ammo":6,"mag":6,"reserve":18,"count":1},null,null,null,null],"scrap":0,"revive":0.0,"interact_progress":0.0,"prompt":"","pouch":"","grenades":2,"domes":1},"players":[{"id":234289745,"pos":[1.44,0.0,1.89],"yaw":1.7,"pitch":0.0,"state":"ok","crouch":null,"name":"Full Bot","item":"nail_driver","suit_color":"#9be04a","skin":"GAS MASK"}],"enemies":[{"id":1,"type":"drip","pos":[-8.89,0.08,-46.83],"yaw":-2.997,"hp":1.0,"anim":"walk"},{"id":2,"type":"gutter","pos":[-7.7,0.08,-41.65],"yaw":-3.007,"hp":1.0,"anim":"walk"},{"id":3,"type":"drip","pos":[-8.65,0.0,-50.52],"yaw":-3.012,"hp":1.0,"anim":"walk"}],"pickups":[{"id":-302845532229,"kind":"station","pos":[-2.8,0.05,9.0],"item":"station"},{"id":-303147522135,"kind":"station","pos":[49.0,0.08,26.5],"item":"station"},{"id":-303449512041,"kind":"station","pos":[-53.0,0.08,30.85],"item":"station"}],"projectiles":[],"weather":{"phase":"downpour","intensity":0.303,"wave":1,"phase_time_left":44.03,"lightning":false},"run":{"alive_enemies":3,"wave":1,"endless":false,"shared_decon":5,"score":0}}
+ 20.254s C→S binary 17 bytes
len 11 00 00 00   (raw TCP prefix: 17 bytes)
0000 01 4f 01 00 00 00 00 00 00 86 00 ef ff 00 00 00
0010 00
     = {"t":"in","seq":335,"mv":[0.0,0.0],"yaw":0.134,"pitch":-0.017,"b":0,"slot":0,"wheel":0}
+ 20.286s C→S binary 17 bytes
len 11 00 00 00   (raw TCP prefix: 17 bytes)
0000 01 50 01 00 00 00 00 00 00 86 00 ef ff 00 00 00
0010 00
     = {"t":"in","seq":336,"mv":[0.0,0.0],"yaw":0.134,"pitch":-0.017,"b":0,"slot":0,"wheel":0}
+ 24.026s S→C text (raw TCP prefix 63 00 00 00)
     {"t":"ev","list":[{"e":"puddle","id":254443262043,"pos":[-32.0,0.0,38.0],"radius":0.26,"on":true}]}
+ 25.690s S→C text (raw TCP prefix b2 00 00 00)
     {"t":"ev","list":[{"e":"shot","by":234289745,"weapon":"nail_driver","from":[2.32,1.64,1.4],"to":[-8.91,1.08,-24.74]},{"e":"sound","name":"gun_nail_driver","at":[2.32,1.64,1.4]}]}
+ 27.321s S→C text (raw TCP prefix 8b 01 00 00)
     {"t":"ev","list":[{"e":"sound","name":"turned","at":[-10.43,1.0,-21.46]},{"e":"shot","by":234289745,"weapon":"nail_driver","from":[0.35,1.63,0.51],"to":[-10.31,0.75,-21.2]},{"e":"sound","name":"gun_nail_driver","at":[0.35,1.63,0.51]},{"e":"puddle","id":254527148128,"pos":[-4.0,0.0,39.0],"radius":0.35,"on":true},{"e":"puddle","id":254862692468,"pos":[-40.0,0.0,-36.0],"radius":0.35,"on":true}]}
+ 28.779s S→C text (raw TCP prefix 1a 01 00 00)
     {"t":"ev","list":[{"e":"sound","name":"enemy_death","at":[-10.49,0.0,-21.57]},{"e":"kill","enemy":2,"type":"gutter"},{"e":"shot","by":234289745,"weapon":"nail_driver","from":[1.06,1.63,-1.32],"to":[-10.59,0.86,-21.24]},{"e":"sound","name":"gun_nail_driver","at":[1.06,1.63,-1.32]}]}
+ 31.284s S→C text (raw TCP prefix 74 00 00 00)
     {"t":"ev","list":[{"e":"sound","name":"enemy_death","at":[-27.91,0.0,-35.94]},{"e":"kill","enemy":4,"type":"drip"}]}
+ 37.526s S→C text (raw TCP prefix 5e 01 00 00)
     {"t":"ev","list":[{"e":"lightning","at":[6.8,0.0,43.36]},{"e":"sound","name":"thunder","at":[6.8,0.0,43.36]},{"e":"puddle","id":254443262043,"pos":[-32.0,0.0,38.0],"radius":0.89,"on":true},{"e":"puddle","id":254527148128,"pos":[-4.0,0.0,39.0],"radius":0.77,"on":true},{"e":"puddle","id":254862692468,"pos":[-40.0,0.0,-36.0],"radius":0.77,"on":true}]}
+ 38.585s S→C text (raw TCP prefix 12 01 00 00)
     {"t":"ev","list":[{"e":"sound","name":"enemy_death","at":[41.38,0.08,24.55]},{"e":"kill","enemy":13,"type":"drip"},{"e":"puddle","id":254191603788,"pos":[2.0,0.0,-20.0],"radius":0.56,"on":true},{"e":"puddle","id":255030464638,"pos":[-9.5,0.0,16.0],"radius":0.56,"on":true}]}
+ 62.482s S→C text (raw TCP prefix 76 00 00 00)
     {"t":"ev","list":[{"e":"lightning","at":[-40.28,0.0,-13.27]},{"e":"sound","name":"thunder","at":[-40.28,0.0,-13.27]}]}
+ 64.430s S→C text (raw TCP prefix ee 03 00 00)
     {"t":"ev","list":[{"e":"hit","at":[-20.32,0.26,-1.53],"head":false,"dmg":17},{"e":"hit","at":[-22.36,0.84,-1.88],"head":false,"dmg":21},{"e":"hit","at":[-23.08,0.85,-1.43],"head":false,"dmg":14},{"e":"shot","by":2,"weapon":"pump_shotgun","from":[-2.55,1.69,0.44],"to":[-26.86,1.94,-2.15]},{"e":"shot","by":2,"weapon":"pump_shotgun","from":[-2.55,1.69,0.44],"to":[-26.85,2.04,-2.19]},{"e":"shot","by":2,"weapon":"pump_shotgun","from":[-2.55,1.69,0.44],"to":[-20.32,0.26,-1.53]},{"e":"shot","by":2,"weapon":"pump_shotgun","from":[-2.55,1.69,0.44],"to":[-20.27,0.93,-1.63]},{"e":"shot","by":2,"weapon":"pump_shotgun","from":[-2.55,1.69,0.44],"to":[-22.37,0.87,-1.36]},{"e":"shot","by":2,"weapon":"pump_shotgun","from":[-2.55,1.69,0.44],"to":[-21.63,1.06,-0.69]},{"e":"shot","by":2,"weapon":"pump_shotgun","from":[-2.55,1.69,0.44],"to":[-22.46,0.29,-1.34]},{"e":"shot","by":2,"weapon":"pump_shotgun","from":[-2.55,1.69,0.44],"to":[-24.34,0.06,-3.03]},{"e":"sound","name":"gun_shotgun","at":[-2.55,1.69,0.44]}]}
+ 66.128s S→C text (raw TCP prefix eb 04 00 00)
     {"t":"ev","list":[{"e":"sound","name":"enemy_death","at":[-19.19,0.06,-1.45]},{"e":"kill","enemy":35,"type":"gutter"},{"e":"hit","at":[-21.89,0.61,-1.32],"head":false,"dmg":7},{"e":"hit","at":[-22.39,0.59,-1.36],"head":false,"dmg":7},{"e":"hit","at":[-18.94,1.32,-1.69],"head":true,"dmg":18},{"e":"hit","at":[-19.67,1.3,-1.78],"head":false,"dmg":27},{"e":"hit","at":[-20.68,1.21,-1.74],"head":false,"dmg":16},{"e":"sound","name":"headshot","at":null},{"e":"shot","by":2,"weapon":"pump_shotgun","from":[-2.55,1.69,0.44],"to":[-21.89,0.61,-1.32]},{"e":"shot","by":2,"weapon":"pump_shotgun","from":[-2.55,1.69,0.44],"to":[-21.83,0.92,-1.07]},{"e":"shot","by":2,"weapon":"pump_shotgun","from":[-2.55,1.69,0.44],"to":[-26.74,0.94,-3.05]},{"e":"shot","by":2,"weapon":"pump_shotgun","from":[-2.55,1.69,0.44],"to":[-21.8,0.14,-1.01]},{"e":"shot","by":2,"weapon":"pump_shotgun","from":[-2.55,1.69,0.44],"to":[-18.94,1.32,-1.69]},{"e":"shot","by":2,"weapon":"pump_shotgun","from":[-2.55,1.69,0.44],"to":[-19.6,1.24,-1.61]},{"e":"shot","by":2,"weapon":"pump_shotgun","from":[-2.55,1.69,0.44],"to":[-19.72,0.21,-1.4]},{"e":"shot","by":2,"weapon":"pump_shotgun","from":[-2.55,1.69,0.44],"to":[-26.72,0.46,-3.04]},{"e":"sound","name":"gun_shotgun","at":[-2.55,1.69,0.44]}]}
+ 67.187s S→C text (raw TCP prefix b6 01 00 00)
     {"t":"ev","list":[{"e":"sound","name":"enemy_death","at":[-20.61,0.06,-1.61]},{"e":"kill","enemy":37,"type":"drip"},{"e":"shot","by":234289745,"weapon":"nail_driver","from":[1.88,1.63,-0.95],"to":[-20.25,1.17,-1.78]},{"e":"sound","name":"gun_nail_driver","at":[1.88,1.63,-0.95]},{"e":"puddle","id":254191603788,"pos":[2.0,0.0,-20.0],"radius":1.36,"on":true},{"e":"puddle","id":255030464638,"pos":[-9.5,0.0,16.0],"radius":1.36,"on":true}]}
+ 67.933s S→C text (raw TCP prefix 3e 00 00 00)
     {"t":"ev","list":[{"e":"sound","name":"reel_tick","at":null}]}
```

Repeats not shown in this section: 1606× `C→S in`, 1071× `S→C snap`, 187× `S→C ev`.

## Run: wave 1 clearing

```text
+ 73.823s S→C binary 1494 bytes
len d6 05 00 00   (raw TCP prefix: 1494 bytes)
0000 02 10 05 00 00 36 20 01 00 00 00 00 00 95 07 00
0010 00 02 00 00 00 38 ff ff ff 06 00 00 00 32 00 00
0020 00 00 00 00 00 00 00 b2 05 00 00 00 10 27 10 27
0030 94 11 10 27 01 01 01 0c 00 70 75 6d 70 5f 73 68
0040 6f 74 67 75 6e 0c 00 50 75 6d 70 20 53 68 6f 74
0050 67 75 6e 00 00 06 00 0b 00 01 00 00 00 00 00 00
0060 00 00 00 00 00 00 00 00 00 00 00 02 00 01 00 01
0070 00 51 fa f6 0d 1b 01 00 00 00 00 00 00 b6 ff ff
0080 ff 02 06 00 00 00 02 08 00 46 75 6c 6c 20 42 6f
0090 74 0b 00 6e 61 69 6c 5f 64 72 69 76 65 72 ff 4a
00a0 e0 9b 08 00 47 41 53 20 4d 41 53 4b 00 00 2e 00
00b0 01 00 00 00 00 00 00 00 04 e7 fb ff ff 00 00 00
00c0 00 93 f7 ff ff 05 00 73 63 72 61 70 02 00 00 00
00d0 00 00 00 00 04 e8 fb ff ff 00 00 00 00 85 f7 ff
00e0 ff 05 00 73 63 72 61 70 03 00 00 00 00 00 00 00
00f0 04 fa fb ff ff 00 00 00 00 76 f6 ff ff 05 00 73
0100 63 72 61 70 04 00 00 00 00 00 00 00 04 19 f5 ff
0110 ff 00 00 00 00 f6 f1 ff ff 05 00 73 63 72 61 70
0120 05 00 00 00 00 00 00 00 04 f1 f5 ff ff 00 00 00
0130 00 d0 f2 ff ff 05 00 73 63 72 61 70 06 00 00 00
0140 00 00 00 00 04 1e f5 ff ff 00 00 00 00 fb f1 ff
0150 ff 05 00 73 63 72 61 70 07 00 00 00 00 00 00 00
0160 04 33 0f 00 00 08 00 00 00 ba 08 00 00 05 00 73
0170 63 72 61 70 08 00 00 00 00 00 00 00 04 4c 10 00
0180 00 08 00 00 00 b7 09 00 00 05 00 73 63 72 61 70
0190 09 00 00 00 00 00 00 00 04 4a 10 00 00 08 00 00
01a0 00 b4 09 00 00 05 00 73 63 72 61 70 0a 00 00 00
01b0 00 00 00 00 04 35 0f 00 00 08 00 00 00 bc 08 00
01c0 00 05 00 73 63 72 61 70 0b 00 00 00 00 00 00 00
01d0 04 39 0f 00 00 08 00 00 00 bf 08 00 00 05 00 73
01e0 63 72 61 70 0c 00 00 00 00 00 00 00 04 a0 0f 00
01f0 00 08 00 00 00 1b 09 00 00 05 00 73 63 72 61 70
0200 0d 00 00 00 00 00 00 00 04 2a 10 00 00 08 00 00
0210 00 97 09 00 00 05 00 73 63 72 61 70 0e 00 00 00
0220 00 00 00 00 04 29 10 00 00 08 00 00 00 96 09 00
0230 00 05 00 73 63 72 61 70 0f 00 00 00 00 00 00 00
0240 04 1f 0f 00 00 08 00 00 00 a8 08 00 00 05 00 73
0250 63 72 61 70 10 00 00 00 00 00 00 00 04 59 0f 00
0260 00 08 00 00 00 dd 08 00 00 05 00 73 63 72 61 70
0270 11 00 00 00 00 00 00 00 04 f8 0f 00 00 08 00 00
0280 00 69 09 00 00 05 00 73 63 72 61 70 12 00 00 00
0290 00 00 00 00 04 5c 0f 00 00 08 00 00 00 df 08 00
02a0 00 05 00 73 63 72 61 70 13 00 00 00 00 00 00 00
02b0 04 fe 0f 00 00 08 00 00 00 6e 09 00 00 05 00 73
02c0 63 72 61 70 14 00 00 00 00 00 00 00 04 70 0f 00
02d0 00 08 00 00 00 f2 08 00 00 05 00 73 63 72 61 70
02e0 15 00 00 00 00 00 00 00 04 c7 f4 ff ff 06 00 00
02f0 00 11 00 00 00 05 00 73 63 72 61 70 16 00 00 00
0300 00 00 00 00 04 78 f4 ff ff 06 00 00 00 c4 ff ff
0310 ff 05 00 73 63 72 61 70 17 00 00 00 00 00 00 00
0320 04 75 f4 ff ff 06 00 00 00 78 ff ff ff 05 00 73
0330 63 72 61 70 18 00 00 00 00 00 00 00 04 7d f4 ff
0340 ff 06 00 00 00 84 ff ff ff 05 00 73 63 72 61 70
0350 19 00 00 00 00 00 00 00 04 cd f3 ff ff 06 00 00
0360 00 22 00 00 00 05 00 73 63 72 61 70 1a 00 00 00
0370 00 00 00 00 04 cd f3 ff ff 06 00 00 00 21 00 00
0380 00 05 00 73 63 72 61 70 1b 00 00 00 00 00 00 00
0390 04 9c f3 ff ff 06 00 00 00 9c 00 00 00 05 00 73
03a0 63 72 61 70 1c 00 00 00 00 00 00 00 02 bb f3 ff
03b0 ff 06 00 00 00 ca 00 00 00 06 00 68 65 61 6c 74
03c0 68 1d 00 00 00 00 00 00 00 04 2d fa ff ff 07 00
03d0 00 00 55 0c 00 00 05 00 73 63 72 61 70 1e 00 00
03e0 00 00 00 00 00 04 ae f9 ff ff 07 00 00 00 87 0c
03f0 00 00 05 00 73 63 72 61 70 1f 00 00 00 00 00 00
0400 00 04 c7 f9 ff ff 07 00 00 00 fa 0c 00 00 05 00
0410 73 63 72 61 70 20 00 00 00 00 00 00 00 04 a9 f9
0420 ff ff 07 00 00 00 dd 0c 00 00 05 00 73 63 72 61
0430 70 21 00 00 00 00 00 00 00 04 33 fa ff ff 07 00
0440 00 00 c4 0c 00 00 05 00 73 63 72 61 70 22 00 00
0450 00 00 00 00 00 04 7b fa ff ff 07 00 00 00 a3 0b
0460 00 00 05 00 73 63 72 61 70 23 00 00 00 00 00 00
0470 00 04 c7 f9 ff ff 07 00 00 00 0f 0d 00 00 05 00
0480 73 63 72 61 70 24 00 00 00 00 00 00 00 04 81 f8
0490 ff ff 06 00 00 00 6f ff ff ff 05 00 73 63 72 61
04a0 70 25 00 00 00 00 00 00 00 04 22 f8 ff ff 06 00
04b0 00 00 64 ff ff ff 05 00 73 63 72 61 70 26 00 00
04c0 00 00 00 00 00 04 f3 f7 ff ff 06 00 00 00 5f ff
04d0 ff ff 05 00 73 63 72 61 70 27 00 00 00 00 00 00
04e0 00 04 e6 f7 ff ff 06 00 00 00 5d ff ff ff 05 00
04f0 73 63 72 61 70 28 00 00 00 00 00 00 00 04 bf f7
0500 ff ff 06 00 00 00 59 ff ff ff 05 00 73 63 72 61
0510 70 29 00 00 00 00 00 00 00 04 b9 f7 ff ff 06 00
0520 00 00 58 ff ff ff 05 00 73 63 72 61 70 2a 00 00
0530 00 00 00 00 00 04 ca f7 ff ff 06 00 00 00 5a ff
0540 ff ff 05 00 73 63 72 61 70 2b 00 00 00 00 00 00
0550 00 04 d5 f7 ff ff 06 00 00 00 5c ff ff ff 05 00
0560 73 63 72 61 70 bb e7 ff 7c b9 ff ff ff 07 e8 fe
0570 ff ff 05 00 00 00 84 03 00 00 07 00 73 74 61 74
0580 69 6f 6e a9 e7 ff 6a b9 ff ff ff 07 24 13 00 00
0590 08 00 00 00 5a 0a 00 00 07 00 73 74 61 74 69 6f
05a0 6e 97 e7 ff 58 b9 ff ff ff 07 4c eb ff ff 08 00
05b0 00 00 0d 0c 00 00 07 00 73 74 61 74 69 6f 6e 00
05c0 00 04 b7 02 01 00 00 00 8d 01 00 00 00 00 00 00
05d0 05 00 00 00 00 00
     = {"t":"snap","tick":1296,"t_ms":73782,"ack":1941,"you":{"id":2,"pos":[-2.0,0.06,0.5],"vel":[0.0,0.0,0.0],"yaw":1.458,"pitch":0.0,"state":"ok","hp":100.0,"hp_max":100.0,"suit":45.0,"suit_max":100.0,"slot":1,"exposed":true,"sheltered":false,"in_puddle":false,"crouch":false,"aiming":false,"reloading":false,"slots":[{"item":"pump_shotgun","name":"Pump Shotgun","ammo":0,"mag":6,"reserve":11,"count":1},null,null,null,null],"scrap":0,"revive":0.0,"interact_progress":0.0,"prompt":"","pouch":"","grenades":2,"domes":1},"players":[{"id":234289745,"pos":[2.83,0.0,-0.74],"yaw":1.538,"pitch":0.0,"state":"ok","crouch":null,"name":"Full Bot","item":"nail_driver","suit_color":"#9be04a","skin":"GAS MASK"}],"enemies":[],"pickups":[{"id":1,"kind":"scrap","pos":[-10.49,0.0,-21.57],"item":"scrap"},{"id":2,"kind":"scrap","pos":[-10.48,0.0,-21.71],"item":"scrap"},{"id":3,"kind":"scrap","pos":[-10.3,0.0,-24.42],"item":"scrap"},{"id":4,"kind":"scrap","pos":[-27.91,0.0,-35.94],"item":"scrap"},{"id":5,"kind":"scrap","pos":[-25.75,0.0,-33.76],"item":"scrap"},{"id":6,"kind":"scrap","pos":[-27.86,0.0,-35.89],"item":"scrap"},{"id":7,"kind":"scrap","pos":[38.91,0.08,22.34],"item":"scrap"},{"id":8,"kind":"scrap","pos":[41.72,0.08,24.87],"item":"scrap"},{"id":9,"kind":"scrap","pos":[41.7,0.08,24.84],"item":"scrap"},{"id":10,"kind":"scrap","pos":[38.93,0.08,22.36],"item":"scrap"},{"id":11,"kind":"scrap","pos":[38.97,0.08,22.39],"item":"scrap"},{"id":12,"kind":"scrap","pos":[40.0,0.08,23.31],"item":"scrap"},{"id":13,"kind":"scrap","pos":[41.38,0.08,24.55],"item":"scrap"},{"id":14,"kind":"scrap","pos":[41.37,0.08,24.54],"item":"scrap"},{"id":15,"kind":"scrap","pos":[38.71,0.08,22.16],"item":"scrap"},{"id":16,"kind":"scrap","pos":[39.29,0.08,22.69],"item":"scrap"},{"id":17,"kind":"scrap","pos":[40.88,0.08,24.09],"item":"scrap"},{"id":18,"kind":"scrap","pos":[39.32,0.08,22.71],"item":"scrap"},{"id":19,"kind":"scrap","pos":[40.94,0.08,24.14],"item":"scrap"},{"id":20,"kind":"scrap","pos":[39.52,0.08,22.9],"item":"scrap"},{"id":21,"kind":"scrap","pos":[-28.73,0.06,0.17],"item":"scrap"},{"id":22,"kind":"scrap","pos":[-29.52,0.06,-0.6],"item":"scrap"},{"id":23,"kind":"scrap","pos":[-29.55,0.06,-1.36],"item":"scrap"},{"id":24,"kind":"scrap","pos":[-29.47,0.06,-1.24],"item":"scrap"},{"id":25,"kind":"scrap","pos":[-31.23,0.06,0.34],"item":"scrap"},{"id":26,"kind":"scrap","pos":[-31.23,0.06,0.33],"item":"scrap"},{"id":27,"kind":"scrap","pos":[-31.72,0.06,1.56],"item":"scrap"},{"id":28,"kind":"health","pos":[-31.41,0.06,2.02],"item":"health"},{"id":29,"kind":"scrap","pos":[-14.91,0.07,31.57],"item":"scrap"},{"id":30,"kind":"scrap","pos":[-16.18,0.07,32.07],"item":"scrap"},{"id":31,"kind":"scrap","pos":[-15.93,0.07,33.22],"item":"scrap"},{"id":32,"kind":"scrap","pos":[-16.23,0.07,32.93],"item":"scrap"},{"id":33,"kind":"scrap","pos":[-14.85,0.07,32.68],"item":"scrap"},{"id":34,"kind":"scrap","pos":[-14.13,0.07,29.79],"item":"scrap"},{"id":35,"kind":"scrap","pos":[-15.93,0.07,33.43],"item":"scrap"},{"id":36,"kind":"scrap","pos":[-19.19,0.06,-1.45],"item":"scrap"},{"id":37,"kind":"scrap","pos":[-20.14,0.06,-1.56],"item":"scrap"},{"id":38,"kind":"scrap","pos":[-20.61,0.06,-1.61],"item":"scrap"},{"id":39,"kind":"scrap","pos":[-20.74,0.06,-1.63],"item":"scrap"},{"id":40,"kind":"scrap","pos":[-21.13,0.06,-1.67],"item":"scrap"},{"id":41,"kind":"scrap","pos":[-21.19,0.06,-1.68],"item":"scrap"},{"id":42,"kind":"scrap","pos":[-21.02,0.06,-1.66],"item":"scrap"},{"id":43,"kind":"scrap","pos":[-20.91,0.06,-1.64],"item":"scrap"},{"id":-302845532229,"kind":"station","pos":[-2.8,0.05,9.0],"item":"station"},{"id":-303147522135,"kind":"station","pos":[49.0,0.08,26.5],"item":"station"},{"id":-303449512041,"kind":"station","pos":[-53.0,0.08,30.85],"item":"station"}],"projectiles":[],"weather":{"phase":"clearing","intensity":0.695,"wave":1,"phase_time_left":3.97,"lightning":false},"run":{"alive_enemies":0,"wave":1,"endless":false,"shared_decon":5,"score":0}}
+ 73.824s S→C text (raw TCP prefix 38 00 00 00)
     {"t":"ev","list":[{"e":"banner","text":"WAVE 1 CLEAR"}]}
+ 73.853s C→S binary 17 bytes
len 11 00 00 00   (raw TCP prefix: 17 bytes)
0000 01 97 07 00 00 00 00 00 00 b2 05 00 00 00 00 00
0010 00
     = {"t":"in","seq":1943,"mv":[0.0,0.0],"yaw":1.458,"pitch":0.0,"b":0,"slot":0,"wheel":0}
+ 73.899s C→S binary 17 bytes
len 11 00 00 00   (raw TCP prefix: 17 bytes)
0000 01 98 07 00 00 00 00 00 00 b2 05 00 00 00 04 00
0010 00
     = {"t":"in","seq":1944,"mv":[0.0,0.0],"yaw":1.458,"pitch":0.0,"b":1024,"slot":0,"wheel":0}
+ 74.835s S→C text (raw TCP prefix 63 00 00 00)
     {"t":"ev","list":[{"e":"puddle","id":254443262043,"pos":[-32.0,0.0,38.0],"radius":2.45,"on":true}]}
```

Repeats not shown in this section: 91× `C→S in`, 61× `S→C snap`, 8× `S→C ev`.

## Mutation draft

> Mutation draft opened (wave 2+ Calm); answer with `choice` (spec-thin §10).

```text
+ 76.923s S→C text (raw TCP prefix a5 01 00 00)
     {"t":"draft","kind":"mutation","cards":[{"id":"reflex_tendons","title":"REFLEX TENDONS","desc":"Reload 35% faster and fire 20% faster","icon":"reflex_tendons"},{"id":"chitin_suit","title":"CHITIN SUIT","desc":"+25 max health and suit drains 35% slower in rain","icon":"chitin_suit"},{"id":"adrenaline_glands","title":"ADRENALINE","desc":"Move 18% faster and jump 20% higher","icon":"adrenaline_glands"}],"time_left":14.0}
```
> Vote for card index `i` (zero-based).

```text
+ 76.923s C→S text (raw TCP prefix 26 00 00 00)
     {"t":"choice","kind":"mutation","i":0}
```

## Run: wave 2 calm

```text
+ 76.926s S→C binary 1356 bytes
len 4c 05 00 00   (raw TCP prefix: 1356 bytes)
0000 02 4e 05 00 00 55 2c 01 00 00 00 00 00 f2 07 00
0010 00 02 00 00 00 38 ff ff ff 06 00 00 00 32 00 00
0020 00 00 00 00 00 00 00 b2 05 00 00 00 10 27 10 27
0030 94 11 10 27 01 01 01 0c 00 70 75 6d 70 5f 73 68
0040 6f 74 67 75 6e 0c 00 50 75 6d 70 20 53 68 6f 74
0050 67 75 6e 00 00 06 00 0b 00 01 00 00 00 00 00 00
0060 00 00 00 00 00 00 00 00 00 00 00 02 00 01 00 01
0070 00 51 fa f6 0d 7a 00 00 00 00 00 00 00 b2 00 00
0080 00 39 04 00 00 00 02 08 00 46 75 6c 6c 20 42 6f
0090 74 0b 00 6e 61 69 6c 5f 64 72 69 76 65 72 ff 4a
00a0 e0 9b 08 00 47 41 53 20 4d 41 53 4b 00 00 29 00
00b0 07 00 00 00 00 00 00 00 04 33 0f 00 00 08 00 00
00c0 00 ba 08 00 00 05 00 73 63 72 61 70 08 00 00 00
00d0 00 00 00 00 04 4c 10 00 00 08 00 00 00 b7 09 00
00e0 00 05 00 73 63 72 61 70 09 00 00 00 00 00 00 00
00f0 04 4a 10 00 00 08 00 00 00 b4 09 00 00 05 00 73
0100 63 72 61 70 0a 00 00 00 00 00 00 00 04 35 0f 00
0110 00 08 00 00 00 bc 08 00 00 05 00 73 63 72 61 70
0120 0b 00 00 00 00 00 00 00 04 39 0f 00 00 08 00 00
0130 00 bf 08 00 00 05 00 73 63 72 61 70 0c 00 00 00
0140 00 00 00 00 04 a0 0f 00 00 08 00 00 00 1b 09 00
0150 00 05 00 73 63 72 61 70 0d 00 00 00 00 00 00 00
0160 04 2a 10 00 00 08 00 00 00 97 09 00 00 05 00 73
0170 63 72 61 70 0e 00 00 00 00 00 00 00 04 29 10 00
0180 00 08 00 00 00 96 09 00 00 05 00 73 63 72 61 70
0190 0f 00 00 00 00 00 00 00 04 1f 0f 00 00 08 00 00
01a0 00 a8 08 00 00 05 00 73 63 72 61 70 10 00 00 00
01b0 00 00 00 00 04 59 0f 00 00 08 00 00 00 dd 08 00
01c0 00 05 00 73 63 72 61 70 11 00 00 00 00 00 00 00
01d0 04 f8 0f 00 00 08 00 00 00 69 09 00 00 05 00 73
01e0 63 72 61 70 12 00 00 00 00 00 00 00 04 5c 0f 00
01f0 00 08 00 00 00 df 08 00 00 05 00 73 63 72 61 70
0200 13 00 00 00 00 00 00 00 04 fe 0f 00 00 08 00 00
0210 00 6e 09 00 00 05 00 73 63 72 61 70 14 00 00 00
0220 00 00 00 00 04 70 0f 00 00 08 00 00 00 f2 08 00
0230 00 05 00 73 63 72 61 70 15 00 00 00 00 00 00 00
0240 04 c7 f4 ff ff 06 00 00 00 11 00 00 00 05 00 73
0250 63 72 61 70 16 00 00 00 00 00 00 00 04 78 f4 ff
0260 ff 06 00 00 00 c4 ff ff ff 05 00 73 63 72 61 70
0270 17 00 00 00 00 00 00 00 04 75 f4 ff ff 06 00 00
0280 00 78 ff ff ff 05 00 73 63 72 61 70 18 00 00 00
0290 00 00 00 00 04 7d f4 ff ff 06 00 00 00 84 ff ff
02a0 ff 05 00 73 63 72 61 70 19 00 00 00 00 00 00 00
02b0 04 cd f3 ff ff 06 00 00 00 22 00 00 00 05 00 73
02c0 63 72 61 70 1a 00 00 00 00 00 00 00 04 cd f3 ff
02d0 ff 06 00 00 00 21 00 00 00 05 00 73 63 72 61 70
02e0 1b 00 00 00 00 00 00 00 04 9c f3 ff ff 06 00 00
02f0 00 9c 00 00 00 05 00 73 63 72 61 70 1c 00 00 00
0300 00 00 00 00 02 bb f3 ff ff 06 00 00 00 ca 00 00
0310 00 06 00 68 65 61 6c 74 68 1d 00 00 00 00 00 00
0320 00 04 2d fa ff ff 07 00 00 00 55 0c 00 00 05 00
0330 73 63 72 61 70 1e 00 00 00 00 00 00 00 04 ae f9
0340 ff ff 07 00 00 00 87 0c 00 00 05 00 73 63 72 61
0350 70 1f 00 00 00 00 00 00 00 04 c7 f9 ff ff 07 00
0360 00 00 fa 0c 00 00 05 00 73 63 72 61 70 20 00 00
0370 00 00 00 00 00 04 a9 f9 ff ff 07 00 00 00 dd 0c
0380 00 00 05 00 73 63 72 61 70 21 00 00 00 00 00 00
0390 00 04 33 fa ff ff 07 00 00 00 c4 0c 00 00 05 00
03a0 73 63 72 61 70 22 00 00 00 00 00 00 00 04 7b fa
03b0 ff ff 07 00 00 00 a3 0b 00 00 05 00 73 63 72 61
03c0 70 23 00 00 00 00 00 00 00 04 c7 f9 ff ff 07 00
03d0 00 00 0f 0d 00 00 05 00 73 63 72 61 70 24 00 00
03e0 00 00 00 00 00 04 81 f8 ff ff 06 00 00 00 6f ff
03f0 ff ff 05 00 73 63 72 61 70 25 00 00 00 00 00 00
0400 00 04 22 f8 ff ff 06 00 00 00 64 ff ff ff 05 00
0410 73 63 72 61 70 26 00 00 00 00 00 00 00 04 f3 f7
0420 ff ff 06 00 00 00 5f ff ff ff 05 00 73 63 72 61
0430 70 27 00 00 00 00 00 00 00 04 e6 f7 ff ff 06 00
0440 00 00 5d ff ff ff 05 00 73 63 72 61 70 28 00 00
0450 00 00 00 00 00 04 bf f7 ff ff 06 00 00 00 59 ff
0460 ff ff 05 00 73 63 72 61 70 29 00 00 00 00 00 00
0470 00 04 b9 f7 ff ff 06 00 00 00 58 ff ff ff 05 00
0480 73 63 72 61 70 2a 00 00 00 00 00 00 00 04 ca f7
0490 ff ff 06 00 00 00 5a ff ff ff 05 00 73 63 72 61
04a0 70 2b 00 00 00 00 00 00 00 04 d5 f7 ff ff 06 00
04b0 00 00 5c ff ff ff 05 00 73 63 72 61 70 bb e7 ff
04c0 7c b9 ff ff ff 07 e8 fe ff ff 05 00 00 00 84 03
04d0 00 00 07 00 73 74 61 74 69 6f 6e a9 e7 ff 6a b9
04e0 ff ff ff 07 24 13 00 00 08 00 00 00 5a 0a 00 00
04f0 07 00 73 74 61 74 69 6f 6e 97 e7 ff 58 b9 ff ff
0500 ff 07 4c eb ff ff 08 00 00 00 0d 0c 00 00 07 00
0510 73 74 61 74 69 6f 6e 29 e7 ff fe ab ff ff ff 06
0520 00 00 00 00 07 00 00 00 50 fb ff ff 07 00 61 69
0530 72 64 72 6f 70 00 00 00 81 01 02 00 00 00 b8 0b
0540 00 00 00 00 00 00 05 00 00 00 00 00
     = {"t":"snap","tick":1358,"t_ms":76885,"ack":2034,"you":{"id":2,"pos":[-2.0,0.06,0.5],"vel":[0.0,0.0,0.0],"yaw":1.458,"pitch":0.0,"state":"ok","hp":100.0,"hp_max":100.0,"suit":45.0,"suit_max":100.0,"slot":1,"exposed":true,"sheltered":false,"in_puddle":false,"crouch":false,"aiming":false,"reloading":false,"slots":[{"item":"pump_shotgun","name":"Pump Shotgun","ammo":0,"mag":6,"reserve":11,"count":1},null,null,null,null],"scrap":0,"revive":0.0,"interact_progress":0.0,"prompt":"","pouch":"","grenades":2,"domes":1},"players":[{"id":234289745,"pos":[1.22,0.0,1.78],"yaw":1.081,"pitch":0.0,"state":"ok","crouch":null,"name":"Full Bot","item":"nail_driver","suit_color":"#9be04a","skin":"GAS MASK"}],"enemies":[],"pickups":[{"id":7,"kind":"scrap","pos":[38.91,0.08,22.34],"item":"scrap"},{"id":8,"kind":"scrap","pos":[41.72,0.08,24.87],"item":"scrap"},{"id":9,"kind":"scrap","pos":[41.7,0.08,24.84],"item":"scrap"},{"id":10,"kind":"scrap","pos":[38.93,0.08,22.36],"item":"scrap"},{"id":11,"kind":"scrap","pos":[38.97,0.08,22.39],"item":"scrap"},{"id":12,"kind":"scrap","pos":[40.0,0.08,23.31],"item":"scrap"},{"id":13,"kind":"scrap","pos":[41.38,0.08,24.55],"item":"scrap"},{"id":14,"kind":"scrap","pos":[41.37,0.08,24.54],"item":"scrap"},{"id":15,"kind":"scrap","pos":[38.71,0.08,22.16],"item":"scrap"},{"id":16,"kind":"scrap","pos":[39.29,0.08,22.69],"item":"scrap"},{"id":17,"kind":"scrap","pos":[40.88,0.08,24.09],"item":"scrap"},{"id":18,"kind":"scrap","pos":[39.32,0.08,22.71],"item":"scrap"},{"id":19,"kind":"scrap","pos":[40.94,0.08,24.14],"item":"scrap"},{"id":20,"kind":"scrap","pos":[39.52,0.08,22.9],"item":"scrap"},{"id":21,"kind":"scrap","pos":[-28.73,0.06,0.17],"item":"scrap"},{"id":22,"kind":"scrap","pos":[-29.52,0.06,-0.6],"item":"scrap"},{"id":23,"kind":"scrap","pos":[-29.55,0.06,-1.36],"item":"scrap"},{"id":24,"kind":"scrap","pos":[-29.47,0.06,-1.24],"item":"scrap"},{"id":25,"kind":"scrap","pos":[-31.23,0.06,0.34],"item":"scrap"},{"id":26,"kind":"scrap","pos":[-31.23,0.06,0.33],"item":"scrap"},{"id":27,"kind":"scrap","pos":[-31.72,0.06,1.56],"item":"scrap"},{"id":28,"kind":"health","pos":[-31.41,0.06,2.02],"item":"health"},{"id":29,"kind":"scrap","pos":[-14.91,0.07,31.57],"item":"scrap"},{"id":30,"kind":"scrap","pos":[-16.18,0.07,32.07],"item":"scrap"},{"id":31,"kind":"scrap","pos":[-15.93,0.07,33.22],"item":"scrap"},{"id":32,"kind":"scrap","pos":[-16.23,0.07,32.93],"item":"scrap"},{"id":33,"kind":"scrap","pos":[-14.85,0.07,32.68],"item":"scrap"},{"id":34,"kind":"scrap","pos":[-14.13,0.07,29.79],"item":"scrap"},{"id":35,"kind":"scrap","pos":[-15.93,0.07,33.43],"item":"scrap"},{"id":36,"kind":"scrap","pos":[-19.19,0.06,-1.45],"item":"scrap"},{"id":37,"kind":"scrap","pos":[-20.14,0.06,-1.56],"item":"scrap"},{"id":38,"kind":"scrap","pos":[-20.61,0.06,-1.61],"item":"scrap"},{"id":39,"kind":"scrap","pos":[-20.74,0.06,-1.63],"item":"scrap"},{"id":40,"kind":"scrap","pos":[-21.13,0.06,-1.67],"item":"scrap"},{"id":41,"kind":"scrap","pos":[-21.19,0.06,-1.68],"item":"scrap"},{"id":42,"kind":"scrap","pos":[-21.02,0.06,-1.66],"item":"scrap"},{"id":43,"kind":"scrap","pos":[-20.91,0.06,-1.64],"item":"scrap"},{"id":-302845532229,"kind":"station","pos":[-2.8,0.05,9.0],"item":"station"},{"id":-303147522135,"kind":"station","pos":[49.0,0.08,26.5],"item":"station"},{"id":-303449512041,"kind":"station","pos":[-53.0,0.08,30.85],"item":"station"},{"id":-360794036439,"kind":"airdrop","pos":[0.0,0.07,-12.0],"item":"airdrop"}],"projectiles":[],"weather":{"phase":"calm","intensity":0.385,"wave":2,"phase_time_left":30.0,"lightning":false},"run":{"alive_enemies":0,"wave":2,"endless":false,"shared_decon":5,"score":0}}
+ 76.926s S→C text (raw TCP prefix 47 00 00 00)
     {"t":"ev","list":[{"e":"banner","text":"SURPLUS SUPPLY DROP INBOUND"}]}
+ 76.954s C→S binary 17 bytes
len 11 00 00 00   (raw TCP prefix: 17 bytes)
0000 01 f4 07 00 00 00 00 00 00 b2 05 00 00 00 04 00
0010 00
     = {"t":"in","seq":2036,"mv":[0.0,0.0],"yaw":1.458,"pitch":0.0,"b":1024,"slot":0,"wheel":0}
+ 76.972s S→C text (raw TCP prefix 3c 02 00 00)
     {"t":"ev","list":[{"e":"puddle","id":253939945533,"pos":[-6.0,0.0,-2.0],"radius":1.47,"on":true},{"e":"puddle","id":254023831618,"pos":[26.0,0.0,2.0],"radius":1.76,"on":true},{"e":"puddle","id":254107717703,"pos":[56.0,0.0,-1.0],"radius":1.47,"on":true},{"e":"puddle","id":254359375958,"pos":[7.0,0.0,-35.0],"radius":1.47,"on":true},{"e":"puddle","id":254611034213,"pos":[16.0,0.0,40.0],"radius":1.76,"on":true},{"e":"puddle","id":254694920298,"pos":[-48.0,0.0,18.0],"radius":1.47,"on":true},{"e":"puddle","id":254778806383,"pos":[42.0,0.0,30.0],"radius":1.76,"on":true}]}
+ 77.000s C→S binary 17 bytes
len 11 00 00 00   (raw TCP prefix: 17 bytes)
0000 01 f5 07 00 00 00 00 00 00 b2 05 00 00 00 00 00
0010 00
     = {"t":"in","seq":2037,"mv":[0.0,0.0],"yaw":1.458,"pitch":0.0,"b":0,"slot":0,"wheel":0}
```
> Draft resolved; close the card UI.

```text
+ 77.533s S→C text (raw TCP prefix 12 00 00 00)
     {"t":"draft_done"}
+104.783s S→C text (raw TCP prefix 44 00 00 00)
     {"t":"ev","list":[{"e":"sound","name":"storm_countdown","at":null}]}
```

Repeats not shown in this section: 983× `C→S in`, 656× `S→C snap`, 57× `S→C ev`.

## Run: wave 2 drizzle

```text
+109.775s S→C binary 543 bytes
len 1f 02 00 00   (raw TCP prefix: 543 bytes)
0000 02 df 07 00 00 a5 ac 01 00 00 00 00 00 cc 0b 00
0010 00 02 00 00 00 38 ff ff ff 06 00 00 00 32 00 00
0020 00 00 00 00 00 00 00 b2 05 00 00 00 10 27 10 27
0030 94 11 10 27 01 01 01 0c 00 70 75 6d 70 5f 73 68
0040 6f 74 67 75 6e 0c 00 50 75 6d 70 20 53 68 6f 74
0050 67 75 6e 00 00 06 00 0b 00 01 00 00 00 00 00 00
0060 00 00 00 00 00 00 00 00 00 00 00 02 00 01 00 01
0070 00 51 fa f6 0d 3f 00 00 00 00 00 00 00 f6 ff ff
0080 ff a0 fe 00 00 00 02 08 00 46 75 6c 6c 20 42 6f
0090 74 0b 00 6e 61 69 6c 5f 64 72 69 76 65 72 ff 4a
00a0 e0 9b 08 00 47 41 53 20 4d 41 53 4b 00 00 0c 00
00b0 24 00 00 00 00 00 00 00 04 81 f8 ff ff 06 00 00
00c0 00 6f ff ff ff 05 00 73 63 72 61 70 25 00 00 00
00d0 00 00 00 00 04 22 f8 ff ff 06 00 00 00 64 ff ff
00e0 ff 05 00 73 63 72 61 70 26 00 00 00 00 00 00 00
00f0 04 f3 f7 ff ff 06 00 00 00 5f ff ff ff 05 00 73
0100 63 72 61 70 27 00 00 00 00 00 00 00 04 e6 f7 ff
0110 ff 06 00 00 00 5d ff ff ff 05 00 73 63 72 61 70
0120 28 00 00 00 00 00 00 00 04 bf f7 ff ff 06 00 00
0130 00 59 ff ff ff 05 00 73 63 72 61 70 29 00 00 00
0140 00 00 00 00 04 b9 f7 ff ff 06 00 00 00 58 ff ff
0150 ff 05 00 73 63 72 61 70 2a 00 00 00 00 00 00 00
0160 04 ca f7 ff ff 06 00 00 00 5a ff ff ff 05 00 73
0170 63 72 61 70 2b 00 00 00 00 00 00 00 04 d5 f7 ff
0180 ff 06 00 00 00 5c ff ff ff 05 00 73 63 72 61 70
0190 bb e7 ff 7c b9 ff ff ff 07 e8 fe ff ff 05 00 00
01a0 00 84 03 00 00 07 00 73 74 61 74 69 6f 6e a9 e7
01b0 ff 6a b9 ff ff ff 07 24 13 00 00 08 00 00 00 5a
01c0 0a 00 00 07 00 73 74 61 74 69 6f 6e 97 e7 ff 58
01d0 b9 ff ff ff 07 4c eb ff ff 08 00 00 00 0d 0c 00
01e0 00 07 00 73 74 61 74 69 6f 6e 29 e7 ff fe ab ff
01f0 ff ff 06 00 00 00 00 07 00 00 00 50 fb ff ff 07
0200 00 61 69 72 64 72 6f 70 00 00 01 02 00 02 00 00
0210 00 20 03 00 00 00 00 00 00 05 00 00 00 00 00
     = {"t":"snap","tick":2015,"t_ms":109733,"ack":3020,"you":{"id":2,"pos":[-2.0,0.06,0.5],"vel":[0.0,0.0,0.0],"yaw":1.458,"pitch":0.0,"state":"ok","hp":100.0,"hp_max":100.0,"suit":45.0,"suit_max":100.0,"slot":1,"exposed":true,"sheltered":false,"in_puddle":false,"crouch":false,"aiming":false,"reloading":false,"slots":[{"item":"pump_shotgun","name":"Pump Shotgun","ammo":0,"mag":6,"reserve":11,"count":1},null,null,null,null],"scrap":0,"revive":0.0,"interact_progress":0.0,"prompt":"","pouch":"","grenades":2,"domes":1},"players":[{"id":234289745,"pos":[0.63,0.0,-0.1],"yaw":-0.352,"pitch":0.0,"state":"ok","crouch":null,"name":"Full Bot","item":"nail_driver","suit_color":"#9be04a","skin":"GAS MASK"}],"enemies":[],"pickups":[{"id":36,"kind":"scrap","pos":[-19.19,0.06,-1.45],"item":"scrap"},{"id":37,"kind":"scrap","pos":[-20.14,0.06,-1.56],"item":"scrap"},{"id":38,"kind":"scrap","pos":[-20.61,0.06,-1.61],"item":"scrap"},{"id":39,"kind":"scrap","pos":[-20.74,0.06,-1.63],"item":"scrap"},{"id":40,"kind":"scrap","pos":[-21.13,0.06,-1.67],"item":"scrap"},{"id":41,"kind":"scrap","pos":[-21.19,0.06,-1.68],"item":"scrap"},{"id":42,"kind":"scrap","pos":[-21.02,0.06,-1.66],"item":"scrap"},{"id":43,"kind":"scrap","pos":[-20.91,0.06,-1.64],"item":"scrap"},{"id":-302845532229,"kind":"station","pos":[-2.8,0.05,9.0],"item":"station"},{"id":-303147522135,"kind":"station","pos":[49.0,0.08,26.5],"item":"station"},{"id":-303449512041,"kind":"station","pos":[-53.0,0.08,30.85],"item":"station"},{"id":-360794036439,"kind":"airdrop","pos":[0.0,0.07,-12.0],"item":"airdrop"}],"projectiles":[],"weather":{"phase":"drizzle","intensity":0.002,"wave":2,"phase_time_left":8.0,"lightning":false},"run":{"alive_enemies":0,"wave":2,"endless":false,"shared_decon":5,"score":0}}
+109.788s C→S binary 17 bytes
len 11 00 00 00   (raw TCP prefix: 17 bytes)
0000 01 cd 0b 00 00 00 00 00 00 b2 05 00 00 00 00 00
0010 00
     = {"t":"in","seq":3021,"mv":[0.0,0.0],"yaw":1.458,"pitch":0.0,"b":0,"slot":0,"wheel":0}
+109.819s C→S binary 17 bytes
len 11 00 00 00   (raw TCP prefix: 17 bytes)
0000 01 ce 0b 00 00 00 00 00 00 b2 05 00 00 00 00 00
0010 00
     = {"t":"in","seq":3022,"mv":[0.0,0.0],"yaw":1.458,"pitch":0.0,"b":0,"slot":0,"wheel":0}
+111.322s S→C text (raw TCP prefix 0c 01 00 00)
     {"t":"ev","list":[{"e":"banner","text":"GUTTER AMBUSH"},{"e":"sound","name":"turned","at":[12.48,1.65,4.9]},{"e":"shot","by":234289745,"weapon":"nail_driver","from":[3.07,1.65,-0.6],"to":[12.35,1.42,4.61]},{"e":"sound","name":"gun_nail_driver","at":[3.07,1.65,-0.6]}]}
+111.378s S→C text (raw TCP prefix 3e 00 00 00)
     {"t":"ev","list":[{"e":"sound","name":"reel_tick","at":null}]}
+111.522s S→C text (raw TCP prefix b4 00 00 00)
     {"t":"ev","list":[{"e":"shot","by":234289745,"weapon":"nail_driver","from":[3.33,1.64,-0.45],"to":[12.23,1.44,4.76]},{"e":"sound","name":"gun_nail_driver","at":[3.33,1.64,-0.45]}]}
+111.724s S→C text (raw TCP prefix 12 05 00 00)
     {"t":"ev","list":[{"e":"sound","name":"turned","at":[14.87,1.06,3.91]},{"e":"sound","name":"turned","at":[12.41,1.06,4.18]},{"e":"hit","at":[14.72,1.0,3.64],"head":false,"dmg":9},{"e":"hit","at":[12.11,1.13,4.18],"head":false,"dmg":11},{"e":"hit","at":[12.33,1.13,4.73],"head":false,"dmg":11},{"e":"shot","by":2,"weapon":"pump_shotgun","from":[-1.47,1.68,0.64],"to":[14.72,1.0,3.64]},{"e":"shot","by":2,"weapon":"pump_shotgun","from":[-1.47,1.68,0.64],"to":[12.11,1.13,4.18]},{"e":"shot","by":2,"weapon":"pump_shotgun","from":[-1.47,1.68,0.64],"to":[22.56,1.84,5.18]},{"e":"shot","by":2,"weapon":"pump_shotgun","from":[-1.47,1.68,0.64],"to":[12.33,1.13,4.73]},{"e":"shot","by":2,"weapon":"pump_shotgun","from":[-1.47,1.68,0.64],"to":[11.44,0.06,3.83]},{"e":"shot","by":2,"weapon":"pump_shotgun","from":[-1.47,1.68,0.64],"to":[7.27,0.06,3.11]},{"e":"shot","by":2,"weapon":"pump_shotgun","from":[-1.47,1.68,0.64],"to":[19.0,0.0,8.27]},{"e":"shot","by":2,"weapon":"pump_shotgun","from":[-1.47,1.68,0.64],"to":[17.91,0.05,7.99]},{"e":"sound","name":"gun_shotgun","at":[-1.47,1.68,0.64]},{"e":"sound","name":"turned","at":[12.86,1.06,2.37]},{"e":"shot","by":234289745,"weapon":"nail_driver","from":[3.61,1.61,-0.38],"to":[12.65,1.06,2.28]},{"e":"sound","name":"gun_nail_driver","at":[3.61,1.61,-0.38]}]}
+113.079s S→C text (raw TCP prefix ba 04 00 00)
     {"t":"ev","list":[{"e":"sound","name":"turned","at":[14.22,1.06,3.74]},{"e":"sound","name":"enemy_death","at":[12.19,0.06,4.08]},{"e":"kill","enemy":45,"type":"gutter"},{"e":"sound","name":"enemy_death","at":[14.22,0.06,3.74]},{"e":"kill","enemy":49,"type":"gutter"},{"e":"hit","at":[13.91,0.42,3.78],"head":true,"dmg":39},{"e":"hit","at":[11.94,0.2,4.21],"head":true,"dmg":33},{"e":"sound","name":"headshot","at":null},{"e":"shot","by":2,"weapon":"pump_shotgun","from":[-1.47,1.68,0.63],"to":[13.91,0.42,3.78]},{"e":"shot","by":2,"weapon":"pump_shotgun","from":[-1.47,1.68,0.63],"to":[14.01,0.44,3.99]},{"e":"shot","by":2,"weapon":"pump_shotgun","from":[-1.47,1.68,0.63],"to":[11.94,0.2,4.21]},{"e":"shot","by":2,"weapon":"pump_shotgun","from":[-1.47,1.68,0.63],"to":[22.36,0.64,6.03]},{"e":"shot","by":2,"weapon":"pump_shotgun","from":[-1.47,1.68,0.63],"to":[11.94,1.4,3.89]},{"e":"shot","by":2,"weapon":"pump_shotgun","from":[-1.47,1.68,0.63],"to":[14.01,1.48,3.86]},{"e":"shot","by":2,"weapon":"pump_shotgun","from":[-1.47,1.68,0.63],"to":[21.2,0.05,6.3]},{"e":"shot","by":2,"weapon":"pump_shotgun","from":[-1.47,1.68,0.63],"to":[22.3,1.11,6.35]},{"e":"sound","name":"gun_shotgun","at":[-1.47,1.68,0.63]}]}
+113.377s S→C text (raw TCP prefix 14 01 00 00)
     {"t":"ev","list":[{"e":"sound","name":"enemy_death","at":[11.93,0.06,4.68]},{"e":"kill","enemy":46,"type":"gutter"},{"e":"shot","by":234289745,"weapon":"nail_driver","from":[3.47,1.61,1.84],"to":[11.64,1.16,4.49]},{"e":"sound","name":"gun_nail_driver","at":[3.47,1.61,1.84]}]}
```

Repeats not shown in this section: 178× `C→S in`, 119× `S→C snap`, 15× `S→C ev`.

## Results

```text
+115.779s S→C text (raw TCP prefix 29 00 00 00)
     {"t":"status","state":"results","msg":""}
```
> End-of-run summary, after `status results`; the lobby follows ~5 s later (spec-thin §11).

```text
+115.779s S→C text (raw TCP prefix bb 00 00 00)
     {"t":"results","won":false,"time_s":106,"waves":1,"kills":15,"players":[{"name":"Thin Bot","kills":7,"downs":0,"revives":0},{"name":"Full Bot","kills":8,"downs":0,"revives":0}],"score":0}
```

## Back in the lobby

```text
+120.795s S→C text (raw TCP prefix 27 00 00 00)
     {"t":"status","state":"lobby","msg":""}
+120.795s S→C text (raw TCP prefix a2 01 00 00)
     {"t":"lobby","players":[{"id":2,"name":"Thin Bot","ready":false,"vote":"","car":true},{"id":234289745,"name":"Full Bot","ready":false,"vote":"","car":false}],"maps":[{"id":"pinecrest","name":"PINECREST"},{"id":"harbor","name":"HARBOR POINT"},{"id":"maple_hollow","name":"MAPLE HOLLOW"}],"countdown":-1,"chat":[{"from":"Thin Bot","text":"thin bot online"},{"from":"Full Bot","text":"full bot online"}],"vote_counts":{}}
```

## Leave

> Clean exit: server answers `status disconnected` and closes (spec-common §7).

```text
+121.822s C→S text (raw TCP prefix 0d 00 00 00)
     {"t":"leave"}
+121.838s S→C text (raw TCP prefix 3a 00 00 00)
     {"t":"status","state":"disconnected","msg":"Left session"}
# transport closed by server after leave (EOFError)
```

## Frame totals

| Kind | Frames |
| --- | ---: |
| `in` | 3200 |
| `snap` | 2134 |
| `ev` | 293 |
| `lobby` | 12 |
| `status` | 6 |
| `hello` | 1 |
| `welcome` | 1 |
| `ping` | 1 |
| `pong` | 1 |
| `load` | 1 |
| `map_req` | 1 |
| `map` | 1 |
| `draft` | 1 |
| `choice` | 1 |
| `draft_done` | 1 |
| `results` | 1 |
| `leave` | 1 |
