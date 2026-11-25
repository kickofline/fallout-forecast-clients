# Thin tier session — ws/json

Captured from a local Godot 4.7.2 dedicated server using **ws** and **json**.
The capture harness shortens Drizzle and Clearing, removes wave-one
stragglers, keeps players above a health and suit floor, and ends the
run six seconds into wave-two Drizzle. A bot of the other tier shares
the lobby, so its traffic appears here too.

`C→S` is client to server, `S→C` is server to client, and `+t` is
seconds since capture start. Long previews can be truncated. Repeats
are counted at the end of the section. The sampled, ordered capture
is [`thin-json.jsonl`](thin-json.jsonl).

> First frame on the socket, always JSON text even for `enc:"bin"` (spec-common §4, spec-thin §2).

```text
+  2.769s C→S {"t":"hello","v":1,"tier":"thin","enc":"json","name":"Thin Bot","client":"capture-thin/1","rate":10}
```

## Handshake and lobby

> Server accepted the hello: `you` is the roster id, `rate/radius/max_enemies` echo the negotiated values (spec-thin §2).

```text
+  2.787s S→C {"t":"welcome","v":1,"game_protocol":19,"you":2,"maps":[{"id":"pinecrest","name":"PINECREST"},{"id":"harbor","name":"HARBOR POINT"},{"id":"maple_hollow","name":"MAPLE HOLLOW"}],"tier":"thin","enc":"json","rate":10,"radius":0.0,"max_enemies":-1}
```
> Connection state machine update (spec-thin §3). `run` is the only state where `in`/`choice` are applied.

```text
+  2.787s S→C {"t":"status","state":"lobby","msg":""}
```
> Full lobby state; sent on every change, never as a delta (spec-thin §4).

```text
+  2.787s S→C {"t":"lobby","players":[{"id":2,"name":"Thin Bot","ready":false,"vote":"","car":true}],"maps":[{"id":"pinecrest","name":"PINECREST"},{"id":"harbor","name":"HARBOR POINT"},{"id":"maple_hollow","name":"MAPLE HOLLOW"}],"countdown":-1,"chat":[],"vote_counts":{}}
+  3.376s S→C {"t":"lobby","players":[{"id":2,"name":"Thin Bot","ready":false,"vote":"","car":true},{"id":453073507,"name":"Full Bot","ready":false,"vote":"","car":false}],"maps":[{"id":"pinecrest","name":"PINECREST"},{"id":"harbor","name":"HARBOR POINT"},{"id":"maple_hollow","name":"MAPLE HOLLOW"}],"countdown":-1,"chat":[],"vote_counts":{}}
+  3.783s C→S {"t":"ping","ms":4242}
+  3.783s C→S {"t":"lobby","a":"chat","text":"thin bot online"}
+  3.783s C→S {"t":"lobby","a":"vote","map":"pinecrest"}
```
> Echo of the client's `ping.ms` (spec-common §6).

```text
+  3.798s S→C {"t":"pong","ms":4242.0}
+  3.808s S→C {"t":"lobby","players":[{"id":2,"name":"Thin Bot","ready":false,"vote":"","car":true},{"id":453073507,"name":"Full Bot","ready":false,"vote":"","car":false}],"maps":[{"id":"pinecrest","name":"PINECREST"},{"id":"harbor","name":"HARBOR POINT"},{"id":"maple_hollow","name":"MAPLE HOLLOW"}],"countdown":-1,"chat":[{"from":"Thin Bot","text":"thin bot online"}],"vote_counts":{}}
+  3.808s S→C {"t":"lobby","players":[{"id":2,"name":"Thin Bot","ready":false,"vote":"pinecrest","car":true},{"id":453073507,"name":"Full Bot","ready":false,"vote":"","car":false}],"maps":[{"id":"pinecrest","name":"PINECREST"},{"id":"harbor","name":"HARBOR POINT"},{"id":"maple_hollow","name":"MAPLE HOLLOW"}],"countdown":-1,"chat":[{"from":"Thin Bot","text":"thin bot online"}],"vote_counts":{"pinecrest":1}}
+  4.189s S→C {"t":"lobby","players":[{"id":2,"name":"Thin Bot","ready":false,"vote":"pinecrest","car":true},{"id":453073507,"name":"Full Bot","ready":false,"vote":"","car":false}],"maps":[{"id":"pinecrest","name":"PINECREST"},{"id":"harbor","name":"HARBOR POINT"},{"id":"maple_hollow","name":"MAPLE HOLLOW"}],"countdown":-1,"chat":[{"from":"Thin Bot","text":"thin bot online"},{"from":"Full Bot","text":"full bot online"}],"vote_counts":{"pinecrest":1}}
+  4.190s S→C {"t":"lobby","players":[{"id":2,"name":"Thin Bot","ready":false,"vote":"pinecrest","car":true},{"id":453073507,"name":"Full Bot","ready":false,"vote":"pinecrest","car":false}],"maps":[{"id":"pinecrest","name":"PINECREST"},{"id":"harbor","name":"HARBOR POINT"},{"id":"maple_hollow","name":"MAPLE HOLLOW"}],"countdown":-1,"chat":[{"from":"Thin Bot","text":"thin bot online"},{"from":"Full Bot","text":"full bot online"}],"vote_counts":{"pinecrest":2}}
+  4.595s C→S {"t":"lobby","a":"ready","v":true}
+  4.611s S→C {"t":"lobby","players":[{"id":2,"name":"Thin Bot","ready":true,"vote":"pinecrest","car":true},{"id":453073507,"name":"Full Bot","ready":false,"vote":"pinecrest","car":false}],"maps":[{"id":"pinecrest","name":"PINECREST"},{"id":"harbor","name":"HARBOR POINT"},{"id":"maple_hollow","name":"MAPLE HOLLOW"}],"countdown":-1,"chat":[{"from":"Thin Bot","text":"thin bot online"},{"from":"Full Bot","text":"full bot online"}],"vote_counts":{"pinecrest":2}}
+  5.691s S→C {"t":"lobby","players":[{"id":2,"name":"Thin Bot","ready":true,"vote":"pinecrest","car":true},{"id":453073507,"name":"Full Bot","ready":true,"vote":"pinecrest","car":false}],"maps":[{"id":"pinecrest","name":"PINECREST"},{"id":"harbor","name":"HARBOR POINT"},{"id":"maple_hollow","name":"MAPLE HOLLOW"}],"countdown":-1,"chat":[{"from":"Thin Bot","text":"thin bot online"},{"from":"Full Bot","text":"full bot online"}],"vote_counts":{"pinecrest":2}}
```

## Loading

```text
+  5.692s S→C {"t":"status","state":"loading","msg":""}
```
> Load this level now; snapshots start after the following `status run` (spec-thin §3).

```text
+  5.692s S→C {"t":"load","map":"pinecrest"}
+  8.929s S→C {"t":"status","state":"run","msg":""}
```

## Run: wave 1 calm

> Complete authoritative state; `ack` = last applied input seq (spec-thin §6/§7).

```text
+  8.929s S→C {"t":"snap","tick":1,"t_ms":8891,"ack":-1,"you":{"id":2,"pos":[-2.0,0.06,0.5],"vel":[0.0,0.0,0.0],"yaw":0.0,"pitch":0.0,"state":"ok","hp":100.0,"hp_max":100.0,"suit":100.0,"suit_max":100,"exposed":true,"sheltered":false,"in_puddle":false,"crouch":false,"aiming":false,"reloading":false,"slot":1,"slots":[{"item":"pump_shotgun","name":"Pump Shotgun","ammo":6,"mag":6,"reserve":18,"count":1},null,null,null,null],"scrap":0,"revive":0.0,"interact_progress":0.0,"prompt":"","pouch":"","grenades":2,"domes":1},"players":[{"id":453073507,"name":"Full Bot","pos":[2.0,0.0,0.5],"yaw":0.0,"pitch":0.0,"state":"ok","item":"","crouch":null,"suit_color":"#9be04a","skin":"GAS MASK"}],"enemies":[],"pickups":[{"id":-303080413257,"item":"station","pos":[-2.8,0.05,9.0],"kind":"station"},{"id":-303382403163,"item":"station","pos":[49.0,0.08,26.5],"kind":"station"},{"id":-303684393069,"item":"station","pos":[-53.0,0.08,30.85],"kind":"station"}],"projectiles":[],"weather":{"phase":"calm","intensity":0.0,"wave":1,"phase_time_left":12.0,"lightning":false},"run":{"alive_enemies":0,"wave":1,"endless":false,"shared_decon":5,"score":0}}
```
> Ask for the current level outline.

```text
+  8.969s C→S {"t":"map_req"}
```
> Control frame at 30 Hz; `seq` strictly increases, `b` is the button bitmask (spec-thin §5).

```text
+  8.977s C→S {"t":"in","seq":1,"mv":[0.0,0.0],"yaw":0.0,"pitch":0.0,"b":0,"slot":0,"wheel":0}
```
> Coarse collision outline for renderers without assets (spec-thin §8).

```text
+  8.978s S→C {"t":"map","id":"pinecrest","boxes":[[0.0,0.03,0.0,134.0,0.06,9.0,0.0],[0.0,0.03,-6.25,134.0,0.06,3.5,0.0],[0.0,0.03,6.25,134.0,0.06,3.5,0.0],[0.0,0.04,-17.5,9.0,0.06,26.0,0.0],[0.0,0.05,-40.0,23.0,0.06,23.0,0.0],[0.0,0.08,-6.25,9.0,0.06,3.5,0.0],[-10.0,0.04,38.0,70.0,0.06,26.0,0.0],[-9.5,0.03,17.5,7.0,0.06,16.0,0.0],[49.0,0.05,25.0,28.0,0.06,30.0,0.0],[-53.0,0.07,25.0,22.0,0.06,32.0,0.0],[0.0,1.0,-65.0,130.0,2.0,0.4,0.0],[0.0,1.0,65.0,130.0,2.0,0.4,0.0],[-65.0,1.0,0.0,0.4,2.0,130.0,0.0],[65.0,1.0,0.0,0.4,2.0,130.0,0.0],[-68.0,3.0,0.0,0.4,6.0,16.0,0.0],[68.0,3.0,0.0,0.4,6.0,16.0,0.0],[-28.0,3…
+  9.015s C→S {"t":"in","seq":2,"mv":[0.0,0.0],"yaw":0.0,"pitch":0.0,"b":1024,"slot":0,"wheel":0}
```
> One-shot events batched after a snapshot (spec-thin §9).

```text
+  9.141s S→C {"t":"ev","list":[{"e":"sound","name":"storm_countdown","at":null}]}
```

Repeats not shown in this section: 90× `C→S in`, 30× `S→C snap`, 2× `S→C ev`.

## Run: wave 1 drizzle

```text
+ 12.036s S→C {"t":"snap","tick":32,"t_ms":11998,"ack":92,"you":{"id":2,"pos":[-2.0,0.06,0.5],"vel":[0.0,0.0,0.0],"yaw":0.0,"pitch":0.0,"state":"ok","hp":100.0,"hp_max":100.0,"suit":100.0,"suit_max":100,"exposed":true,"sheltered":false,"in_puddle":false,"crouch":false,"aiming":false,"reloading":false,"slot":1,"slots":[{"item":"pump_shotgun","name":"Pump Shotgun","ammo":6,"mag":6,"reserve":18,"count":1},null,null,null,null],"scrap":0,"revive":0.0,"interact_progress":0.0,"prompt":"","pouch":"","grenades":2,"domes":1},"players":[{"id":453073507,"name":"Full Bot","pos":[3.5,0.0,0.59],"yaw":-3.138,"pitch":0.0,"state":"ok","item":"nail_driver","crouch":null,"suit_color":"#9be04a","skin":"GAS MASK"}],"enemies":[],"pickups":[{"id":-303080413257,"item":"station","pos":[-2.8,0.05,9.0],"kind":"station"},{"id":-303382403163,"item":"station","pos":[49.0,0.08,26.5],"kind":"station"},{"id":-303684393069,"item":"station","pos":[-53.0,0.08,30.85],"kind":"station"}],"projectiles":[],"weather":{"phase":"drizzle","intensity":0.002,"wave":1,"phase_time_left":8.0,"lightning":false},"run":{"alive_enemies":0,"wave":1,"endless":false,"shared_decon":5,"score":0}}
+ 12.049s C→S {"t":"in","seq":93,"mv":[0.0,0.0],"yaw":0.0,"pitch":0.0,"b":0,"slot":0,"wheel":0}
+ 12.081s C→S {"t":"in","seq":94,"mv":[0.0,0.0],"yaw":0.0,"pitch":0.0,"b":0,"slot":0,"wheel":0}
```

Repeats not shown in this section: 242× `C→S in`, 80× `S→C snap`.

## Run: wave 1 downpour

```text
+ 20.141s S→C {"t":"snap","tick":113,"t_ms":20104,"ack":335,"you":{"id":2,"pos":[-2.0,0.06,0.5],"vel":[0.0,0.0,0.0],"yaw":-1.519,"pitch":-0.017,"state":"ok","hp":100.0,"hp_max":100.0,"suit":93.54,"suit_max":100,"exposed":true,"sheltered":false,"in_puddle":false,"crouch":false,"aiming":false,"reloading":false,"slot":1,"slots":[{"item":"pump_shotgun","name":"Pump Shotgun","ammo":6,"mag":6,"reserve":18,"count":1},null,null,null,null],"scrap":0,"revive":0.0,"interact_progress":0.0,"prompt":"","pouch":"","grenades":2,"domes":1},"players":[{"id":453073507,"name":"Full Bot","pos":[1.54,0.0,1.93],"yaw":1.8,"pitch":0.0,"state":"ok","item":"nail_driver","crouch":null,"suit_color":"#9be04a","skin":"GAS MASK"}],"enemies":[{"id":1,"type":"drip","pos":[40.55,0.06,-1.75],"yaw":1.664,"hp":1.0,"anim":"walk"},{"id":2,"type":"gutter","pos":[41.34,0.06,-1.65],"yaw":1.66,"hp":1.0,"anim":"idle"},{"id":3,"type":"drip","pos":[42.13,0.06,-1.67],"yaw":1.659,"hp":1.0,"anim":"walk"}],"pickups":[{"id":-303080413257,"item":"station","pos":[-2.8,0.05,9.0],"kind":"station"},{"id":-303382403163,"item":"station","pos":[49.0,0.08,26.5],"kind":"station"},{"id":-303684393069,"item":"station","pos":[-53.0,0.08,30.85],"kind":"station"}],"projectiles":[],"weather":{"phase":"downpour","intensity":0.31,"wave":1,"phase_time_left":40.03,"lightning":false},"run":{"alive_enemies":3,"wave":1,"endless":false,"shared_decon":5,"score":0}}
+ 20.171s C→S {"t":"in","seq":337,"mv":[0.0,0.0],"yaw":-1.518,"pitch":-0.018,"b":0,"slot":0,"wheel":0}
+ 20.218s C→S {"t":"in","seq":338,"mv":[0.0,0.0],"yaw":-1.518,"pitch":-0.018,"b":0,"slot":0,"wheel":0}
+ 23.433s S→C {"t":"ev","list":[{"e":"shot","by":453073507,"weapon":"nail_driver","from":[3.23,1.64,-0.87],"to":[12.7,1.28,-1.53]},{"e":"sound","name":"gun_nail_driver","at":[3.23,1.64,-0.87]}]}
+ 23.942s S→C {"t":"ev","list":[{"e":"puddle","id":254678143071,"pos":[-32.0,0.0,38.0],"radius":0.26,"on":true}]}
+ 24.642s S→C {"t":"ev","list":[{"e":"shot","by":453073507,"weapon":"nail_driver","from":[4.04,1.64,0.57],"to":[12.53,1.35,-0.75]},{"e":"sound","name":"gun_nail_driver","at":[4.04,1.64,0.57]},{"e":"puddle","id":254762029156,"pos":[-4.0,0.0,39.0],"radius":0.26,"on":true},{"e":"puddle","id":255097573496,"pos":[-40.0,0.0,-36.0],"radius":0.26,"on":true}]}
+ 28.640s S→C {"t":"ev","list":[{"e":"hit","at":[16.71,0.65,0.65],"head":false,"dmg":8},{"e":"shot","by":2,"weapon":"pump_shotgun","from":[-1.45,1.69,0.5],"to":[12.67,1.39,0.15]},{"e":"shot","by":2,"weapon":"pump_shotgun","from":[-1.45,1.69,0.5],"to":[12.41,0.96,-0.16]},{"e":"shot","by":2,"weapon":"pump_shotgun","from":[-1.45,1.69,0.5],"to":[12.69,0.99,0.15]},{"e":"shot","by":2,"weapon":"pump_shotgun","from":[-1.45,1.69,0.5],"to":[13.77,1.42,0.38]},{"e":"shot","by":2,"weapon":"pump_shotgun","from":[-1.45,1.69,0.5],"to":[16.71,0.65,0.65]},{"e":"shot","by":2,"weapon":"pump_shotgun","from":[-1.45,1.69,0.5],"to":[13.26,1.49,0.27]},{"e":"shot","by":2,"weapon":"pump_shotgun","from":[-1.45,1.69,0.5],"to":[13.95,1.23,0.42]},{"e":"shot","by":2,"weapon":"pump_shotgun","from":[-1.45,1.69,0.5],"to":[12.69,1.09,0.15]},{"e":"sound","name":"gun_shotgun","at":[-1.45,1.69,0.5]}]}
+ 29.142s S→C {"t":"ev","list":[{"e":"sound","name":"enemy_death","at":[16.29,0.06,0.82]},{"e":"kill","enemy":1,"type":"drip"},{"e":"sound","name":"enemy_death","at":[17.0,0.06,0.49]},{"e":"kill","enemy":2,"type":"gutter"},{"e":"sound","name":"enemy_death","at":[16.3,0.06,-4.7]},{"e":"kill","enemy":3,"type":"drip"},{"e":"puddle","id":254510370901,"pos":[-6.0,0.0,-45.0],"radius":0.37,"on":true},{"e":"puddle","id":255181459581,"pos":[45.0,0.0,-32.0],"radius":0.37,"on":true}]}
+ 31.238s S→C {"t":"ev","list":[{"e":"sound","name":"enemy_death","at":[-27.32,0.0,-35.34]},{"e":"kill","enemy":4,"type":"drip"}]}
+ 34.231s S→C {"t":"ev","list":[{"e":"lightning","at":[54.8,0.0,-53.07]},{"e":"sound","name":"thunder","at":[54.8,0.0,-53.07]}]}
+ 56.848s S→C {"t":"ev","list":[{"e":"lightning","at":[76.59,0.0,-15.55]},{"e":"sound","name":"thunder","at":[76.59,0.0,-15.55]},{"e":"shot","by":453073507,"weapon":"nail_driver","from":[2.68,1.64,2.14],"to":[0.22,1.63,6.48]},{"e":"sound","name":"gun_nail_driver","at":[2.68,1.64,2.14]},{"e":"puddle","id":254510370901,"pos":[-6.0,0.0,-45.0],"radius":1.32,"on":true},{"e":"puddle","id":255181459581,"pos":[45.0,0.0,-32.0],"radius":1.32,"on":true}]}
+ 60.836s S→C {"t":"ev","list":[{"e":"sound","name":"turned","at":[-8.31,1.06,14.55]},{"e":"sound","name":"turned","at":[-8.53,1.06,15.24]},{"e":"sound","name":"enemy_death","at":[-8.31,0.06,14.55]},{"e":"kill","enemy":28,"type":"gutter"},{"e":"sound","name":"enemy_death","at":[-8.53,0.06,15.24]},{"e":"kill","enemy":31,"type":"gutter"},{"e":"sound","name":"turned","at":[-8.6,1.06,15.97]},{"e":"hit","at":[-8.04,1.34,14.38],"head":true,"dmg":42},{"e":"hit","at":[-8.32,1.33,15.01],"head":true,"dmg":50},{"e":"hit","at":[-8.49,0.83,15.67],"head":false,"dmg":10},{"e":"sound","name":"headshot","at":null},{"e":"shot","by":2,"weapon":"pump_shotgun","from":[-2.22,1.68,1.0],"to":[-8.04,1.34,14.38]},{"e":"shot","by":2,"weapon":"pump_shotgun","from":[-2.22,1.68,1.0],"to":[-5.73,1.43,10.0]},{"e":"shot","by":2,"weapon":"pump_shotgun","from":[-2.22,1.68,1.0],"to":[-13.33,0.54,22.75]},{"e":"shot","by":2,"weapon":"pump_shotgun","from":[-2.22,1.68,1.0],"to":[-8.13,1.27,14.28]},{"e":"shot","by":2,"weapon":"pump_shotgun","from":[-2.22,1.68,1.0],"to":[-5.84,1.06,10.0]},{"e":"shot","by":2,"weapon":"pump_shotgun","from":[-2.22,1.68,1.0],"to":[-12.84,0.87,23.01]},{"e":"shot","by":2,"weapon":"pump_shotgun","from":[-2.22,1.68,1.0],"to":[-5.86,1.32,10.0]},{"e":"shot","by":2,"weapon":"pump_shotgun","from":[-2.22,1.68,1.0],"to":[-8.24,0.87,15.09]},{"e":"sound","name":"gun_shotgun","at":[-2.22,1.68,1.0]}]}
+ 61.440s S→C {"t":"ev","list":[{"e":"sound","name":"reel_tick","at":null}]}
+ 63.436s S→C {"t":"ev","list":[{"e":"sound","name":"enemy_death","at":[-8.96,0.06,14.97]},{"e":"kill","enemy":34,"type":"drip"},{"e":"shot","by":2,"weapon":"pump_shotgun","from":[-2.24,1.68,1.0],"to":[-11.79,1.4,23.5]},{"e":"shot","by":2,"weapon":"pump_shotgun","from":[-2.24,1.68,1.0],"to":[-12.84,1.04,23.02]},{"e":"shot","by":2,"weapon":"pump_shotgun","from":[-2.24,1.68,1.0],"to":[-6.0,2.31,10.0]},{"e":"shot","by":2,"weapon":"pump_shotgun","from":[-2.24,1.68,1.0],"to":[-5.61,1.04,10.0]},{"e":"shot","by":2,"weapon":"pump_shotgun","from":[-2.24,1.68,1.0],"to":[-5.61,1.45,10.0]},{"e":"shot","by":2,"weapon":"pump_shotgun","from":[-2.24,1.68,1.0],"to":[-11.86,2.42,23.46]},{"e":"shot","by":2,"weapon":"pump_shotgun","from":[-2.24,1.68,1.0],"to":[-13.33,2.14,22.78]},{"e":"shot","by":2,"weapon":"pump_shotgun","from":[-2.24,1.68,1.0],"to":[-12.72,1.9,23.08]},{"e":"sound","name":"gun_shotgun","at":[-2.24,1.68,1.0]}]}
```

Repeats not shown in this section: 1680× `C→S in`, 560× `S→C snap`, 164× `S→C ev`.

## Run: wave 1 clearing

```text
+ 76.235s S→C {"t":"snap","tick":674,"t_ms":76197,"ack":2018,"you":{"id":2,"pos":[-2.0,0.06,0.5],"vel":[0.0,0.0,0.0],"yaw":0.618,"pitch":-0.016,"state":"ok","hp":100.0,"hp_max":100.0,"suit":45.0,"suit_max":100,"exposed":true,"sheltered":false,"in_puddle":false,"crouch":false,"aiming":false,"reloading":false,"slot":1,"slots":[{"item":"pump_shotgun","name":"Pump Shotgun","ammo":0,"mag":6,"reserve":15,"count":1},null,null,null,null],"scrap":0,"revive":0.0,"interact_progress":0.0,"prompt":"","pouch":"","grenades":2,"domes":1},"players":[{"id":453073507,"name":"Full Bot","pos":[2.22,0.0,1.98],"yaw":2.075,"pitch":0.0,"state":"ok","item":"nail_driver","crouch":null,"suit_color":"#9be04a","skin":"GAS MASK"}],"enemies":[],"pickups":[{"id":4,"item":"scrap","pos":[-27.32,0.0,-35.34],"kind":"scrap"},{"id":6,"item":"scrap","pos":[-27.15,0.0,-35.18],"kind":"scrap"},{"id":7,"item":"scrap","pos":[-27.34,0.0,-35.36],"kind":"scrap"},{"id":8,"item":"scrap","pos":[39.4,0.08,22.79],"kind":"scrap"},{"id":9,"item":"scrap","pos":[41.18,0.08,24.36],"kind":"scrap"},{"id":10,"item":"scrap","pos":[39.76,0.08,23.13],"kind":"scrap"},{"id":11,"item":"scrap","pos":[42.09,0.08,25.18],"kind":"scrap"},{"id":13,"item":"scrap","pos":[39.94,0.08,23.26],"kind":"scrap"},{"id":14,"item":"scrap","pos":[39.76,0.08,23.13],"kind":"scrap"},{"id":15,"item":"scrap","pos":[40.75,0.08,23.98],"kind":"scrap"},{"id":16,"item":"scrap","pos":[-16.53,0.07,34.96],"kind":"scrap"},{"id":17,"item":"scrap","pos":[-16.55,0.07,33.33],"kind":"scrap"},{"id":18,"item":"scrap","pos":[-14.74,0.07,28.66],"kind":"scrap"},{"id":19,"item":"scrap","pos":[-14.17,0.07,29.86],"kind":"scrap"},{"id":20,"item":"scrap","pos":[-15.1,0.07,33.08],"kind":"scrap"},{"id":21,"item":"scrap","pos":[-16.26,0.07,32.64],"kind":"scrap"},{"id":22,"item":"scrap","pos":[-15.74,0.07,33.71],"kind":"scrap"},{"id":23,"item":"scrap","pos":[-6.82,0.08,-31.93],"kind":"scrap"},{"id":24,"item":"scrap","pos":[-6.46,0.08,-34.37],"kind":"scrap"},{"id":25,"item":"scrap","pos":[-9.63,0.08,-34.94],"kind":"scrap"},{"id":26,"item":"scrap","pos":[-7.74,0.0,-29.93],"kind":"scrap"},{"id":27,"item":"scrap","pos":[-9.69,0.08,-33.97],"kind":"scrap"},{"id":28,"item":"scrap","pos":[-7.58,0.08,-33.55],"kind":"scrap"},{"id":29,"item":"scrap","pos":[-9.77,0.0,-32.72],"kind":"scrap"},{"id":30,"item":"scrap","pos":[-8.31,0.06,14.55],"kind":"scrap"},{"id":31,"item":"scrap","pos":[-8.53,0.06,15.24],"kind":"scrap"},{"id":32,"item":"scrap","pos":[-9.31,0.06,16.24],"kind":"scrap"},{"id":33,"item":"scrap","pos":[-8.68,0.06,13.98],"kind":"scrap"},{"id":34,"item":"scrap","pos":[-8.61,0.06,15.97],"kind":"scrap"},{"id":35,"item":"scrap","pos":[-8.44,0.06,15.78],"kind":"scrap"},{"id":36,"item":"scrap","pos":[-8.96,0.06,14.97],"kind":"scrap"},{"id":37,"item":"scrap","pos":[-9.76,0.0,-32.87],"kind":"scrap"},{"id":38,"item":"scrap","pos":[-10.06,0.0,-27.75],"kind":"scrap"},{"id":39,"item":"scrap","pos":[-7.03,0.08,-32.06],"kind":"scrap"},{"id":40,"item":"scrap","pos":[-6.46,0.08,-34.33],"kind":"scrap"},{"id":41,"item":"scrap","pos":[-7.15,0.08,-32.23],"kind":"scrap"},{"id":42,"item":"scrap","pos":[-6.28,0.08,-33.09],"kind":"scrap"},{"id":43,"item":"scrap","pos":[-6.24,0.08,-33.19],"kind":"scrap"},{"id":-303080413257,"item":"station","pos":[-2.8,0.05,9.0],"kind":"station"},{"id":-303382403163,"item":"station","pos":[49.0,0.08,26.5],"kind":"station"},{"id":-303684393069,"item":"station","pos":[-53.0,0.08,30.85],"kind":"station"}],"projectiles":[],"weather":{"phase":"clearing","intensity":0.692,"wave":1,"phase_time_left":3.93,"lightning":false},"run":{"alive_enemies":0,"wave":1,"endless":false,"shared_decon":5,"score":0}}
+ 76.236s S→C {"t":"ev","list":[{"e":"banner","text":"WAVE 1 CLEAR"}]}
+ 76.249s C→S {"t":"in","seq":2019,"mv":[0.0,0.0],"yaw":0.618,"pitch":0.0,"b":0,"slot":0,"wheel":0}
+ 76.281s C→S {"t":"in","seq":2020,"mv":[0.0,0.0],"yaw":0.618,"pitch":0.0,"b":1024,"slot":0,"wheel":0}
+ 77.347s S→C {"t":"ev","list":[{"e":"puddle","id":254090940476,"pos":[-32.0,0.0,2.0],"radius":2.13,"on":true}]}
```

Repeats not shown in this section: 91× `C→S in`, 30× `S→C snap`, 5× `S→C ev`.

## Mutation draft

> Mutation draft opened (wave 2+ Calm); answer with `choice` (spec-thin §10).

```text
+ 79.326s S→C {"t":"draft","kind":"mutation","cards":[{"id":"reflex_tendons","title":"REFLEX TENDONS","desc":"Reload 35% faster and fire 20% faster","icon":"reflex_tendons"},{"id":"chitin_suit","title":"CHITIN SUIT","desc":"+25 max health and suit drains 35% slower in rain","icon":"chitin_suit"},{"id":"adrenaline_glands","title":"ADRENALINE","desc":"Move 18% faster and jump 20% higher","icon":"adrenaline_glands"}],"time_left":14.0}
```
> Vote for card index `i` (zero-based).

```text
+ 79.326s C→S {"t":"choice","kind":"mutation","i":0}
+ 79.338s C→S {"t":"in","seq":2112,"mv":[0.0,0.0],"yaw":0.618,"pitch":0.0,"b":0,"slot":0,"wheel":0}
```

## Run: wave 2 calm

```text
+ 79.340s S→C {"t":"snap","tick":705,"t_ms":79302,"ack":2111,"you":{"id":2,"pos":[-2.0,0.06,0.5],"vel":[0.0,0.0,0.0],"yaw":0.618,"pitch":0.0,"state":"ok","hp":100.0,"hp_max":100.0,"suit":45.0,"suit_max":100,"exposed":true,"sheltered":false,"in_puddle":false,"crouch":false,"aiming":false,"reloading":false,"slot":1,"slots":[{"item":"pump_shotgun","name":"Pump Shotgun","ammo":0,"mag":6,"reserve":15,"count":1},null,null,null,null],"scrap":0,"revive":0.0,"interact_progress":0.0,"prompt":"","pouch":"","grenades":2,"domes":1},"players":[{"id":453073507,"name":"Full Bot","pos":[1.73,0.0,-0.97],"yaw":-1.325,"pitch":0.0,"state":"ok","item":"nail_driver","crouch":null,"suit_color":"#9be04a","skin":"GAS MASK"}],"enemies":[],"pickups":[{"id":8,"item":"scrap","pos":[39.4,0.08,22.79],"kind":"scrap"},{"id":9,"item":"scrap","pos":[41.18,0.08,24.36],"kind":"scrap"},{"id":10,"item":"scrap","pos":[39.76,0.08,23.13],"kind":"scrap"},{"id":11,"item":"scrap","pos":[42.09,0.08,25.18],"kind":"scrap"},{"id":13,"item":"scrap","pos":[39.94,0.08,23.26],"kind":"scrap"},{"id":14,"item":"scrap","pos":[39.76,0.08,23.13],"kind":"scrap"},{"id":15,"item":"scrap","pos":[40.75,0.08,23.98],"kind":"scrap"},{"id":16,"item":"scrap","pos":[-16.53,0.07,34.96],"kind":"scrap"},{"id":17,"item":"scrap","pos":[-16.55,0.07,33.33],"kind":"scrap"},{"id":18,"item":"scrap","pos":[-14.74,0.07,28.66],"kind":"scrap"},{"id":19,"item":"scrap","pos":[-14.17,0.07,29.86],"kind":"scrap"},{"id":20,"item":"scrap","pos":[-15.1,0.07,33.08],"kind":"scrap"},{"id":21,"item":"scrap","pos":[-16.26,0.07,32.64],"kind":"scrap"},{"id":22,"item":"scrap","pos":[-15.74,0.07,33.71],"kind":"scrap"},{"id":23,"item":"scrap","pos":[-6.82,0.08,-31.93],"kind":"scrap"},{"id":24,"item":"scrap","pos":[-6.46,0.08,-34.37],"kind":"scrap"},{"id":25,"item":"scrap","pos":[-9.63,0.08,-34.94],"kind":"scrap"},{"id":26,"item":"scrap","pos":[-7.74,0.0,-29.93],"kind":"scrap"},{"id":27,"item":"scrap","pos":[-9.69,0.08,-33.97],"kind":"scrap"},{"id":28,"item":"scrap","pos":[-7.58,0.08,-33.55],"kind":"scrap"},{"id":29,"item":"scrap","pos":[-9.77,0.0,-32.72],"kind":"scrap"},{"id":30,"item":"scrap","pos":[-8.31,0.06,14.55],"kind":"scrap"},{"id":31,"item":"scrap","pos":[-8.53,0.06,15.24],"kind":"scrap"},{"id":32,"item":"scrap","pos":[-9.31,0.06,16.24],"kind":"scrap"},{"id":33,"item":"scrap","pos":[-8.68,0.06,13.98],"kind":"scrap"},{"id":34,"item":"scrap","pos":[-8.61,0.06,15.97],"kind":"scrap"},{"id":35,"item":"scrap","pos":[-8.44,0.06,15.78],"kind":"scrap"},{"id":36,"item":"scrap","pos":[-8.96,0.06,14.97],"kind":"scrap"},{"id":37,"item":"scrap","pos":[-9.76,0.0,-32.87],"kind":"scrap"},{"id":38,"item":"scrap","pos":[-10.06,0.0,-27.75],"kind":"scrap"},{"id":39,"item":"scrap","pos":[-7.03,0.08,-32.06],"kind":"scrap"},{"id":40,"item":"scrap","pos":[-6.46,0.08,-34.33],"kind":"scrap"},{"id":41,"item":"scrap","pos":[-7.15,0.08,-32.23],"kind":"scrap"},{"id":42,"item":"scrap","pos":[-6.28,0.08,-33.09],"kind":"scrap"},{"id":43,"item":"scrap","pos":[-6.24,0.08,-33.19],"kind":"scrap"},{"id":-303080413257,"item":"station","pos":[-2.8,0.05,9.0],"kind":"station"},{"id":-303382403163,"item":"station","pos":[49.0,0.08,26.5],"kind":"station"},{"id":-303684393069,"item":"station","pos":[-53.0,0.08,30.85],"kind":"station"},{"id":-400723810528,"item":"airdrop","pos":[0.0,0.07,-12.0],"kind":"airdrop"}],"projectiles":[],"weather":{"phase":"calm","intensity":0.382,"wave":2,"phase_time_left":30.0,"lightning":false},"run":{"alive_enemies":0,"wave":2,"endless":false,"shared_decon":5,"score":0}}
+ 79.340s S→C {"t":"ev","list":[{"e":"banner","text":"SURPLUS SUPPLY DROP INBOUND"},{"e":"puddle","id":254510370901,"pos":[-6.0,0.0,-45.0],"radius":1.7,"on":true},{"e":"puddle","id":255181459581,"pos":[45.0,0.0,-32.0],"radius":1.7,"on":true}]}
+ 79.369s C→S {"t":"in","seq":2113,"mv":[0.0,0.0],"yaw":0.618,"pitch":0.0,"b":0,"slot":0,"wheel":0}
+ 79.415s C→S {"t":"in","seq":2114,"mv":[0.0,0.0],"yaw":0.618,"pitch":0.0,"b":1024,"slot":0,"wheel":0}
+ 79.542s S→C {"t":"ev","list":[{"e":"puddle","id":254090940476,"pos":[-32.0,0.0,2.0],"radius":1.91,"on":true},{"e":"puddle","id":254258712646,"pos":[26.0,0.0,2.0],"radius":1.83,"on":true},{"e":"puddle","id":254845915241,"pos":[16.0,0.0,40.0],"radius":1.83,"on":true},{"e":"puddle","id":255013687411,"pos":[42.0,0.0,30.0],"radius":1.83,"on":true}]}
```
> Draft resolved; close the card UI.

```text
+ 79.915s S→C {"t":"draft_done"}
+107.236s S→C {"t":"ev","list":[{"e":"sound","name":"storm_countdown","at":null}]}
```

Repeats not shown in this section: 985× `C→S in`, 328× `S→C snap`, 61× `S→C ev`.

## Run: wave 2 drizzle

```text
+112.240s S→C {"t":"snap","tick":1034,"t_ms":112203,"ack":3098,"you":{"id":2,"pos":[-2.0,0.06,0.5],"vel":[0.0,0.0,0.0],"yaw":0.618,"pitch":0.0,"state":"ok","hp":100.0,"hp_max":100.0,"suit":45.0,"suit_max":100,"exposed":true,"sheltered":false,"in_puddle":false,"crouch":false,"aiming":false,"reloading":false,"slot":1,"slots":[{"item":"pump_shotgun","name":"Pump Shotgun","ammo":0,"mag":6,"reserve":15,"count":1},null,null,null,null],"scrap":0,"revive":0.0,"interact_progress":0.0,"prompt":"","pouch":"","grenades":2,"domes":1},"players":[{"id":453073507,"name":"Full Bot","pos":[3.45,0.0,0.1],"yaw":-2.809,"pitch":0.0,"state":"ok","item":"nail_driver","crouch":null,"suit_color":"#9be04a","skin":"GAS MASK"}],"enemies":[],"pickups":[{"id":37,"item":"scrap","pos":[-9.76,0.0,-32.87],"kind":"scrap"},{"id":38,"item":"scrap","pos":[-10.06,0.0,-27.75],"kind":"scrap"},{"id":39,"item":"scrap","pos":[-7.03,0.08,-32.06],"kind":"scrap"},{"id":40,"item":"scrap","pos":[-6.46,0.08,-34.33],"kind":"scrap"},{"id":41,"item":"scrap","pos":[-7.15,0.08,-32.23],"kind":"scrap"},{"id":42,"item":"scrap","pos":[-6.28,0.08,-33.09],"kind":"scrap"},{"id":43,"item":"scrap","pos":[-6.24,0.08,-33.19],"kind":"scrap"},{"id":-303080413257,"item":"station","pos":[-2.8,0.05,9.0],"kind":"station"},{"id":-303382403163,"item":"station","pos":[49.0,0.08,26.5],"kind":"station"},{"id":-303684393069,"item":"station","pos":[-53.0,0.08,30.85],"kind":"station"},{"id":-400723810528,"item":"airdrop","pos":[0.0,0.07,-12.0],"kind":"airdrop"}],"projectiles":[],"weather":{"phase":"drizzle","intensity":0.008,"wave":2,"phase_time_left":7.93,"lightning":false},"run":{"alive_enemies":0,"wave":2,"endless":false,"shared_decon":5,"score":0}}
+112.271s C→S {"t":"in","seq":3100,"mv":[0.0,0.0],"yaw":0.618,"pitch":0.0,"b":0,"slot":0,"wheel":0}
+112.316s C→S {"t":"in","seq":3101,"mv":[0.0,0.0],"yaw":0.618,"pitch":0.0,"b":0,"slot":0,"wheel":0}
+113.734s S→C {"t":"ev","list":[{"e":"banner","text":"GUTTER AMBUSH"}]}
+115.841s S→C {"t":"ev","list":[{"e":"shot","by":453073507,"weapon":"nail_driver","from":[0.67,1.64,-0.32],"to":[7.76,1.38,-26.83]},{"e":"sound","name":"gun_nail_driver","at":[0.67,1.64,-0.32]}]}
```

Repeats not shown in this section: 175× `C→S in`, 59× `S→C snap`, 11× `S→C ev`.

## Results

```text
+118.169s S→C {"t":"status","state":"results","msg":""}
```
> End-of-run summary, after `status results`; the lobby follows ~5 s later (spec-thin §11).

```text
+118.169s S→C {"t":"results","won":false,"time_s":109,"waves":1,"kills":7,"players":[{"name":"Thin Bot","kills":7,"downs":0,"revives":0},{"name":"Full Bot","kills":0,"downs":0,"revives":0}],"score":0}
```

## Back in the lobby

```text
+123.201s S→C {"t":"status","state":"lobby","msg":""}
+123.201s S→C {"t":"lobby","players":[{"id":2,"name":"Thin Bot","ready":false,"vote":"","car":true},{"id":453073507,"name":"Full Bot","ready":false,"vote":"","car":false}],"maps":[{"id":"pinecrest","name":"PINECREST"},{"id":"harbor","name":"HARBOR POINT"},{"id":"maple_hollow","name":"MAPLE HOLLOW"}],"countdown":-1,"chat":[{"from":"Thin Bot","text":"thin bot online"},{"from":"Full Bot","text":"full bot online"}],"vote_counts":{}}
```

## Leave

> Clean exit: server answers `status disconnected` and closes (spec-common §7).

```text
+124.227s C→S {"t":"leave"}
+124.243s S→C {"t":"status","state":"disconnected","msg":"Left session"}
# transport closed by server after leave (EOFError)
```

## Frame totals

| Kind | Frames |
| --- | ---: |
| `in` | 3276 |
| `snap` | 1093 |
| `ev` | 262 |
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
