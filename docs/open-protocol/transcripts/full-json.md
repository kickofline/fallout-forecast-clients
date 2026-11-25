# Full tier session — ws/json

Captured from a local Godot 4.7.2 dedicated server using **ws** and **json**.
The capture harness shortens Drizzle and Clearing, removes wave-one
stragglers, keeps players above a health and suit floor, and ends the
run six seconds into wave-two Drizzle. A bot of the other tier shares
the lobby, so its traffic appears here too.

`C→S` is client to server, `S→C` is server to client, and `+t` is
seconds since capture start. Long previews can be truncated. Repeats
are counted at the end of the section. The sampled, ordered capture
is [`full-json.jsonl`](full-json.jsonl).

> Open Protocol hello selecting the Full tier; JSON text even for `enc:"bin"` (spec-common §4).

```text
+  2.354s C→S {"t":"hello","v":1,"tier":"full","enc":"json","client":"capture-full/1"}
```

## Handshake

> Transport-level acceptance. `you` is the real Godot peer id; `game_protocol` must equal the client's (spec-full §2).

```text
+  2.373s S→C {"t":"welcome","v":1,"tier":"full","enc":"json","you":453073507,"game_protocol":19,"maps":[{"id":"pinecrest","name":"PINECREST"},{"id":"harbor","name":"HARBOR POINT"},{"id":"maple_hollow","name":"MAPLE HOLLOW"}]}
```
> 1 Hz latency probe; answer `Net._rtt_pong(seq)` unreliably (client-responsibilities §RTT).

```text
+  2.520s S→C {"t":"rpc","node":"Net","method":"_rtt_ping","args":[2,0.0],"ch":0,"rel":false}
```
> Echo of `_rtt_ping.seq`.

```text
+  2.520s C→S {"t":"rpc","node":"Net","method":"_rtt_pong","args":[2],"ch":0,"rel":false}
```
> Game-level handshake RPC: arg0 is a JSON *string*, arg1 the game protocol (spec-full §3).

```text
+  3.360s C→S {"t":"rpc","node":"Net","method":"_hello","args":["{\"name\":\"Full Bot\",\"color\":3,\"skin\":1,\"colors\":[]}",19],"ch":0,"rel":true}
```

## Lobby

> Roster broadcast: `Dictionary[int peer_id -> {name,ready,color,skin}]` + lobby voting state (spec-full §4).

```text
+  3.376s S→C {"t":"rpc","node":"Net","method":"_push_roster","args":[{"_t":"dict","v":[[2,{"name":"Thin Bot","ready":false,"color":0,"skin":0}],[453073507,{"name":"Full Bot","ready":false,"color":3,"skin":1}]]},"pinecrest",true,{},""],"ch":0,"rel":true}
+  3.532s S→C {"t":"rpc","node":"Net","method":"_rtt_ping","args":[3,17.0],"ch":0,"rel":false}
+  3.532s C→S {"t":"rpc","node":"Net","method":"_rtt_pong","args":[3],"ch":0,"rel":false}
```
> Chat relay; sent to every peer, including the sender.

```text
+  3.808s S→C {"t":"rpc","node":"Net","method":"_chat_rpc","args":["Thin Bot","thin bot online"],"ch":0,"rel":true}
+  3.808s S→C {"t":"rpc","node":"Net","method":"_push_roster","args":[{"_t":"dict","v":[[2,{"name":"Thin Bot","ready":false,"color":0,"skin":0}],[453073507,{"name":"Full Bot","ready":false,"color":3,"skin":1}]]},"pinecrest",true,{"pinecrest":1},""],"ch":0,"rel":true}
+  4.171s C→S {"t":"rpc","node":"Net","method":"_request_chat","args":["full bot online"],"ch":0,"rel":true}
+  4.171s C→S {"t":"rpc","node":"Net","method":"_request_map_vote","args":["pinecrest"],"ch":0,"rel":true}
+  4.189s S→C {"t":"rpc","node":"Net","method":"_chat_rpc","args":["Full Bot","full bot online"],"ch":0,"rel":true}
+  4.190s S→C {"t":"rpc","node":"Net","method":"_push_roster","args":[{"_t":"dict","v":[[2,{"name":"Thin Bot","ready":false,"color":0,"skin":0}],[453073507,{"name":"Full Bot","ready":false,"color":3,"skin":1}]]},"pinecrest",true,{"pinecrest":2},"pinecrest"],"ch":0,"rel":true}
+  4.548s S→C {"t":"rpc","node":"Net","method":"_rtt_ping","args":[4,16.7],"ch":0,"rel":false}
+  4.548s C→S {"t":"rpc","node":"Net","method":"_rtt_pong","args":[4],"ch":0,"rel":false}
+  4.611s S→C {"t":"rpc","node":"Net","method":"_push_roster","args":[{"_t":"dict","v":[[2,{"name":"Thin Bot","ready":true,"color":0,"skin":0}],[453073507,{"name":"Full Bot","ready":false,"color":3,"skin":1}]]},"pinecrest",true,{"pinecrest":2},"pinecrest"],"ch":0,"rel":true}
+  5.674s C→S {"t":"rpc","node":"Net","method":"_request_ready","args":[true],"ch":0,"rel":true}
+  5.695s S→C {"t":"rpc","node":"Net","method":"_push_roster","args":[{"_t":"dict","v":[[2,{"name":"Thin Bot","ready":true,"color":0,"skin":0}],[453073507,{"name":"Full Bot","ready":true,"color":3,"skin":1}]]},"pinecrest",true,{"pinecrest":2},"pinecrest"],"ch":0,"rel":true}
+  5.695s S→C {"t":"rpc","node":"Net","method":"_push_roster","args":[{"_t":"dict","v":[[2,{"name":"Thin Bot","ready":false,"color":0,"skin":0}],[453073507,{"name":"Full Bot","ready":false,"color":3,"skin":1}]]},"pinecrest",true,{"pinecrest":2},"pinecrest"],"ch":0,"rel":true}
```

Repeats not shown in this section: 1× `S→C _rtt_ping`, 1× `C→S _rtt_pong`.

## Run start and catch-up burst

> Run starts on this concrete map id: load the level, build `Main/Players/P_<id>` for every roster peer, then `_report_in_run(true)` (spec-full §5).

```text
+  5.695s S→C {"t":"rpc","node":"Net","method":"_start_run","args":["pinecrest"],"ch":0,"rel":true}
```
> Client finished loading (`true`) or unloaded the run scene (`false`).

```text
+  5.695s C→S {"t":"rpc","node":"Net","method":"_report_in_run","args":[true],"ch":0,"rel":true}
+  6.569s S→C {"t":"rpc","node":"Net","method":"_rtt_ping","args":[6,16.553],"ch":0,"rel":false}
+  6.570s C→S {"t":"rpc","node":"Net","method":"_rtt_pong","args":[6],"ch":0,"rel":false}
```
> Catch-up #1: endless-tape state (choice pending, endless, victory locked).

```text
+  8.919s S→C {"t":"rpc","node":"GameManager","method":"_sync_tape_state","args":[false,false,false],"ch":0,"rel":true}
+  8.920s S→C {"t":"rpc","node":"GameManager/MutationRoll","method":"_reset_run_rpc","args":[],"ch":0,"rel":true}
```
> Shared decon charge pool.

```text
+  8.921s S→C {"t":"rpc","node":"GameManager","method":"_sync_decon","args":[5],"ch":0,"rel":true}
```
> Storm intensity override (-1 = none).

```text
+  8.922s S→C {"t":"rpc","node":"WeatherManager","method":"_override","args":[-1.0],"ch":0,"rel":true}
```
> Phase change: `[phase enum, wave, seconds_left]`. Count down locally (client-responsibilities §Weather).

```text
+  8.922s S→C {"t":"rpc","node":"WeatherManager","method":"_receive_phase","args":[0,1,12.0],"ch":0,"rel":true}
+  8.922s S→C {"t":"rpc","node":"GameManager","method":"_sync_tape_state","args":[false,false,false],"ch":0,"rel":true}
+  8.922s S→C {"t":"rpc","node":"WeatherManager","method":"_receive_phase","args":[0,1,12.0],"ch":0,"rel":true}
```
> Catch-up only: current smoothed storm intensity.

```text
+  8.923s S→C {"t":"rpc","node":"WeatherManager","method":"_receive_intensity","args":[0.0],"ch":0,"rel":true}
+  8.923s S→C {"t":"rpc","node":"WeatherManager","method":"_override","args":[-1.0],"ch":0,"rel":true}
+  8.923s S→C {"t":"rpc","node":"GameManager","method":"_sync_decon","args":[5],"ch":0,"rel":true}
```
> Active enemy/player mutation id lists (typed `Array[String]` in binary!).

```text
+  8.923s S→C {"t":"rpc","node":"GameManager/MutationRoll","method":"_sync_active","args":[[],[]],"ch":0,"rel":true}
```
> Vending cabinets `{key: [[item,tier,price,offer_serial],...]}` and airdrop.

```text
+  8.923s S→C {"t":"rpc","node":"GameManager/CrateManager","method":"_snapshot","args":[1,{"HardwareStation":[["med_tin",0,6,1],["hunting_rifle",0,11,2],["flare_launcher",1,18,3]],"GasStationSurplus":[["shield_dome",0,6,4],["pressure_washer",0,11,5],["harpoon",1,18,6]],"TownSquareStation":[["suit_patch",0,6,7],["spray_rifle",0,11,8],["leaf_blower",1,18,9]]},[]],"ch":0,"rel":true}
```
> Wave progress for the HUD at ~3.6 Hz: wave, remaining, total, recovery, endless score.

```text
+  8.924s S→C {"t":"rpc","node":"Main/Enemies","method":"_sync_progress","args":[1,42,42,2.1,0],"ch":0,"rel":false}
```
> Puddle growth keyed by *absolute* NodePath (`{"_t":"dict"}` form).

```text
+  8.925s S→C {"t":"rpc","node":"WeatherManager","method":"_sync_puddles","args":[{"_t":"dict","v":[[{"_t":"np","v":"/root/Main/Level/Puddles/MainW"},0.0],[{"_t":"np","v":"/root/Main/Level/Puddles/MainC"},0.0],[{"_t":"np","v":"/root/Main/Level/Puddles/MainE"},0.0],[{"_t":"np","v":"/root/Main/Level/Puddles/MainFarE"},0.0],[{"_t":"np","v":"/root/Main/Level/Puddles/Lane"},0.0],[{"_t":"np","v":"/root/Main/Level/Puddles/CircleW"},0.0],[{"_t":"np","v":"/root/Main/Level/Puddles/CircleE"},0.0],[{"_t":"np","v":"/root/Main/Level/Puddles/LotW"},0.0],[{"_t":"np","v":"/root/Main/Level/Puddles/LotC"},0.0],[{"_t":"np","v":"/root/Main/Level/Puddles/LotE"},0.0],[{"_t":"np","v":"/root/Main/Level/Puddles/Square"},0.0],[{"_t":"np","v":"/root/Main/Level/Puddles/Gas"},0.0],[{"_t":"np","v":"/root/Main/Level/Puddles/Park"},0.0],[{"_t":"np","v":"/root/Main/Level/Puddles/Backyards"},0.0],[{"_t":"np","v":"/root/Main/Level/Puddles/Alley"},0.0]]}],"ch":0,"rel":true}
```
> World pickups/effects snapshot; arg0 is the `run_id` for RPCs with a `run` argument.

```text
+  8.926s S→C {"t":"rpc","node":"Main/RunLoot","method":"_snapshot","args":[1,[],[],[],false],"ch":0,"rel":true}
```
> Public held item per player (relayed to everyone including the owner).

```text
+  8.927s S→C {"t":"rpc","node":"Main/Players/P_2/Head/Camera3D/WeaponHolder","method":"_equip_state","args":[1,1,"",0,0.0,1.0],"ch":0,"rel":true}
+  8.928s S→C {"t":"rpc","node":"Main/Players/P_453073507/Head/Camera3D/WeaponHolder","method":"_equip_state","args":[1,1,"",0,0.0,1.0],"ch":0,"rel":true}
```
> Owner-only authoritative inventory; drop updates with `rev <= last` (client-responsibilities §Inventory).

```text
+  8.928s S→C {"t":"rpc","node":"Main/Players/P_453073507/Head/Camera3D/WeaponHolder","method":"_private_state","args":[1,1,[[],[],[],[],[]],{},0,"",0,0,0,0.0,1.0,0.0,0.0],"ch":0,"rel":true}
```
> Last frame of the catch-up burst. Only now may run-scoped RPCs be sent (spec-full §5).

```text
+  8.928s S→C {"t":"rpc","node":"Net","method":"_confirm_run_ready","args":[],"ch":0,"rel":true}
```
> Owner-reported shelter/puddle state; the host trusts it for acid drain (client-responsibilities §Exposure).

```text
+  8.928s C→S {"t":"rpc","node":"Main/Players/P_453073507","method":"_report_exposure","args":[false,false],"ch":0,"rel":true}
```
> Pick a starter kit (0 pump_shotgun, 1 nail_driver, 2 service_revolver).

```text
+  8.928s C→S {"t":"rpc","node":"Main/RunLoot","method":"_request_starter","args":[1,1],"ch":0,"rel":true}
```
> Host relay of a player's transform to every run peer, *including the owner* (ignore your own).

```text
+  8.931s S→C {"t":"rpc","node":"Main/Players/P_2","method":"_relay_transform","args":[{"_t":"v3","v":[-2.0,0.0599821582436562,0.5]},0.0,0.0,{"_t":"v3","v":[0.0,0.0,0.0]}],"ch":0,"rel":false}
```
> Host-owned vitals at 5 Hz: hp, suit, state, bleed, tarp, max_hp, static charge, invulnerable.

```text
+  8.931s S→C {"t":"rpc","node":"Main/Players/P_2","method":"_apply_vitals","args":[100.0,100.0,"ok",0.0,false,100.0,0.0,false],"ch":0,"rel":false}
+  8.931s S→C {"t":"rpc","node":"Main/Players/P_453073507","method":"_apply_vitals","args":[100.0,100.0,"ok",0.0,false,100.0,0.0,false],"ch":0,"rel":false}
+  8.934s S→C {"t":"rpc","node":"Main/Enemies","method":"_sync_progress","args":[1,42,42,2.1,0],"ch":0,"rel":false}
+  8.935s S→C {"t":"rpc","node":"Main/Players/P_453073507/Head/Camera3D/WeaponHolder","method":"_private_state","args":[1,2,[[2,"nail_driver",0,24],[],[],[],[]],{"nail":60},0,"",0,2,1,0.0,1.0,0.0,0.0],"ch":0,"rel":true}
```
> Starter kit granted.

```text
+  8.935s S→C {"t":"rpc","node":"Main/RunLoot","method":"_starter_accepted","args":[1],"ch":0,"rel":true}
```
> Skip the rest of Calm/Clearing (counts toward the all-ready threshold).

```text
+  8.953s C→S {"t":"rpc","node":"GameManager","method":"_request_ready","args":[],"ch":0,"rel":true}
```
> Owner transform at 20 Hz, unreliable-ordered (client-responsibilities §Movement).

```text
+  8.953s C→S {"t":"rpc","node":"Main/Players/P_453073507","method":"_push_transform","args":[{"_t":"v3","v":[3.4981253905924494,0.0,0.5749687539060175]},-1.6207963267948966,0.0,{"_t":"v3","v":[29.962507811848987,0.0,1.4993750781203508]}],"ch":0,"rel":false}
```
> Ready-up tally `[count, needed]` (broadcast).

```text
+  8.955s S→C {"t":"rpc","node":"GameManager","method":"_ready_changed","args":[1,2],"ch":0,"rel":true}
+  8.955s S→C {"t":"rpc","node":"Main/Players/P_453073507","method":"_relay_transform","args":[{"_t":"v3","v":[3.49812531471252,0.0,0.574968755245209]},-1.6207963267949,0.0,{"_t":"v3","v":[29.9625072479248,0.0,1.49937510490417]}],"ch":0,"rel":false}
+  8.969s C→S {"t":"rpc","node":"Main/Players/P_453073507","method":"_push_transform","args":[{"_t":"v3","v":[3.4925062479170386,0.0,0.6497501249702422]},3.066592653589791,0.0,{"_t":"v3","v":[-0.1123828535082172,0.0,1.4956274212844933]}],"ch":0,"rel":false}
+  9.034s S→C {"t":"rpc","node":"GameManager","method":"_ready_changed","args":[2,2],"ch":0,"rel":true}
```

Repeats not shown in this section: 6× `S→C _relay_transform`, 4× `C→S _push_transform`, 2× `S→C _equip_state`.

## Run: wave 1 calm

```text
+  9.034s S→C {"t":"rpc","node":"WeatherManager","method":"_receive_phase","args":[0,1,3.0],"ch":0,"rel":true}
+  9.035s S→C {"t":"rpc","node":"Main/Players/P_2","method":"_relay_transform","args":[{"_t":"v3","v":[-2.0,0.0599821582436562,0.5]},0.0,0.0,{"_t":"v3","v":[0.0,0.0,0.0]}],"ch":0,"rel":false}
+  9.046s C→S {"t":"rpc","node":"Main/Players/P_453073507","method":"_push_transform","args":[{"_t":"v3","v":[3.409059069271068,0.0,1.014346711183177]},2.816592653589788,0.0,{"_t":"v3","v":[-0.47891328834682056,0.0,1.4213280238233517]}],"ch":0,"rel":false}
+  9.061s C→S {"t":"rpc","node":"Main/Players/P_453073507","method":"_push_transform","args":[{"_t":"v3","v":[3.3815914910043277,0.0,1.0841275134629758]},2.766592653589798,0.0,{"_t":"v3","v":[-0.549351565334808,0.0,1.3956160455959754]}],"ch":0,"rel":false}
+  9.063s S→C {"t":"rpc","node":"Main/Players/P_453073507","method":"_relay_transform","args":[{"_t":"v3","v":[3.40905904769897,0.0,1.01434671878815]},2.81659265358979,0.0,{"_t":"v3","v":[-0.478913277387619,0.0,1.42132806777954]}],"ch":0,"rel":false}
+  9.126s S→C {"t":"rpc","node":"Main/Players/P_2","method":"_apply_vitals","args":[100.0,100.0,"ok",0.0,false,100.0,0.0,false],"ch":0,"rel":false}
+  9.126s S→C {"t":"rpc","node":"Main/Players/P_453073507","method":"_apply_vitals","args":[100.0,100.0,"ok",0.0,false,100.0,0.0,false],"ch":0,"rel":false}
+  9.188s S→C {"t":"rpc","node":"Net","method":"_rtt_ping","args":[7,16.3871],"ch":0,"rel":false}
+  9.188s C→S {"t":"rpc","node":"Net","method":"_rtt_pong","args":[7],"ch":0,"rel":false}
+  9.204s S→C {"t":"rpc","node":"Main/Enemies","method":"_sync_progress","args":[1,42,42,2.1,0],"ch":0,"rel":false}
+  9.486s S→C {"t":"rpc","node":"Main/Enemies","method":"_sync_progress","args":[1,42,42,2.1,0],"ch":0,"rel":false}
+ 10.186s S→C {"t":"rpc","node":"Net","method":"_rtt_ping","args":[8,16.27097],"ch":0,"rel":false}
+ 10.187s C→S {"t":"rpc","node":"Net","method":"_rtt_pong","args":[8],"ch":0,"rel":false}
```

Repeats not shown in this section: 166× `S→C _relay_transform`, 119× `C→S _push_transform`, 26× `S→C _apply_vitals`, 8× `S→C _sync_progress`, 1× `S→C _rtt_ping`, 1× `C→S _rtt_pong`.

## Run: wave 1 drizzle

```text
+ 12.021s S→C {"t":"rpc","node":"WeatherManager","method":"_receive_phase","args":[2,1,30.0],"ch":0,"rel":true}
+ 12.033s C→S {"t":"rpc","node":"Main/Players/P_453073507","method":"_push_transform","args":[{"_t":"v3","v":[3.4897773781372887,0.0,0.6748238072757404]},3.04977796076938,0.0,{"_t":"v3","v":[-0.13751429728474207,0.0,1.4935263998681192]}],"ch":0,"rel":false}
+ 12.036s S→C {"t":"rpc","node":"Main/Enemies","method":"_sync_progress","args":[1,42,42,1.25,0],"ch":0,"rel":false}
+ 12.036s S→C {"t":"rpc","node":"Main/Players/P_453073507","method":"_relay_transform","args":[{"_t":"v3","v":[3.48977732658386,0.0,0.674823820590973]},3.04977796076938,0.0,{"_t":"v3","v":[-0.137514293193817,0.0,1.49352645874023]}],"ch":0,"rel":false}
+ 12.068s S→C {"t":"rpc","node":"Main/Players/P_2","method":"_relay_transform","args":[{"_t":"v3","v":[-2.0,0.0599821582436562,0.5]},0.0,0.0,{"_t":"v3","v":[0.0,0.0,0.0]}],"ch":0,"rel":false}
+ 12.081s C→S {"t":"rpc","node":"Main/Players/P_453073507","method":"_push_transform","args":[{"_t":"v3","v":[3.4791779956887687,0.0,0.7490631587974358]},2.9997779607693817,0.0,{"_t":"v3","v":[-0.2119876489703998,0.0,1.4847870304339073]}],"ch":0,"rel":false}
+ 12.101s S→C {"t":"rpc","node":"Main/Players/P_2","method":"_apply_vitals","args":[100.0,100.0,"ok",0.0,false,100.0,0.0,false],"ch":0,"rel":false}
+ 12.101s S→C {"t":"rpc","node":"Main/Players/P_453073507","method":"_apply_vitals","args":[100.0,100.0,"ok",0.0,false,100.0,0.0,false],"ch":0,"rel":false}
+ 12.208s S→C {"t":"rpc","node":"Net","method":"_rtt_ping","args":[10,16.3427753],"ch":0,"rel":false}
+ 12.208s C→S {"t":"rpc","node":"Net","method":"_rtt_pong","args":[10],"ch":0,"rel":false}
+ 12.317s S→C {"t":"rpc","node":"Main/Enemies","method":"_sync_progress","args":[1,42,42,0.966666666666667,0],"ch":0,"rel":false}
+ 13.220s S→C {"t":"rpc","node":"Net","method":"_rtt_ping","args":[11,16.23994271],"ch":0,"rel":false}
+ 13.220s C→S {"t":"rpc","node":"Net","method":"_rtt_pong","args":[11],"ch":0,"rel":false}
```
> Spawn `[net_id, kind enum, pos, small, elite, miniboss_wave]`.

```text
+ 13.283s S→C {"t":"rpc","node":"Main/Enemies","method":"_spawn_enemy","args":[1,0,{"_t":"v3","v":[57.4338874816895,0.649999976158142,1.28232681751251]},false,false],"ch":0,"rel":true}
+ 13.283s S→C {"t":"rpc","node":"Main/Enemies","method":"_receive_group_warning","args":[{"_t":"v3","v":[57.4338874816895,0.649999976158142,1.28232681751251]}],"ch":0,"rel":true}
```
> 20 Hz batch: PackedInt32Array ids, PackedVector3Array positions, PackedFloat32Array yaws.

```text
+ 13.331s S→C {"t":"rpc","node":"Main/Enemies","method":"_sync_enemies","args":[{"_t":"pi32","v":[1]},{"_t":"pv3","v":[[57.3523902893066,0.641833305358887,1.2649177312851]]},{"_t":"pf32","v":[1.58315575122833]}],"ch":0,"rel":false}
+ 13.394s S→C {"t":"rpc","node":"Main/Enemies","method":"_sync_enemies","args":[{"_t":"pi32","v":[1]},{"_t":"pv3","v":[[57.189395904541,0.592833280563354,1.23009955883026]]},{"_t":"pf32","v":[1.58421015739441]}],"ch":0,"rel":false}
+ 13.564s S→C {"t":"rpc","node":"Main/Enemies","method":"_spawn_enemy","args":[2,1,{"_t":"v3","v":[58.0,0.649999976158142,2.0]},false,false],"ch":0,"rel":true}
```

Repeats not shown in this section: 279× `S→C _relay_transform`, 159× `C→S _push_transform`, 99× `S→C _sync_enemies`, 72× `S→C _apply_vitals`, 27× `S→C _sync_progress`, 6× `S→C _rtt_ping`, 6× `C→S _rtt_pong`, 1× `S→C _spawn_enemy`.

## Run: wave 1 downpour

```text
+ 20.034s S→C {"t":"rpc","node":"WeatherManager","method":"_receive_phase","args":[3,1,40.1146148393847],"ch":0,"rel":true}
+ 20.064s S→C {"t":"rpc","node":"Main/Enemies","method":"_sync_enemies","args":[{"_t":"pi32","v":[1,2,3]},{"_t":"pv3","v":[[40.7998352050781,0.0609114021062851,-1.71832871437073],[41.5874557495117,0.0600066967308521,-1.61927926540375],[42.3781127929688,0.0600234679877758,-1.64454889297485]]},{"_t":"pf32","v":[1.66452193260193,1.66022431850433,1.65911638736725]}],"ch":0,"rel":false}
+ 20.064s S→C {"t":"rpc","node":"Main/Enemies","method":"_sync_progress","args":[1,42,42,2.1,0],"ch":0,"rel":false}
+ 20.078s C→S {"t":"rpc","node":"Main/Players/P_453073507","method":"_push_transform","args":[{"_t":"v3","v":[1.5383668615320136,0.0,1.9271982502330212]},1.7997779607693793,0.0,{"_t":"v3","v":[-1.4381420829470493,0.0,-0.42576829181789844]}],"ch":0,"rel":false}
+ 20.080s S→C {"t":"rpc","node":"Main/Players/P_453073507","method":"_relay_transform","args":[{"_t":"v3","v":[1.53836691379547,0.0,1.92719829082489]},1.79977796076938,0.0,{"_t":"v3","v":[-1.43814206123352,0.0,-0.425768285989761]}],"ch":0,"rel":false}
+ 20.080s S→C {"t":"rpc","node":"Main/Players/P_2","method":"_relay_transform","args":[{"_t":"v3","v":[-2.0,0.0599821582436562,0.5]},-1.51900005340576,-0.017000000923872,{"_t":"v3","v":[0.0,0.0,0.0]}],"ch":0,"rel":false}
+ 20.126s S→C {"t":"rpc","node":"Main/Enemies","method":"_sync_enemies","args":[{"_t":"pi32","v":[1,2,3]},{"_t":"pv3","v":[[40.6343841552734,0.0609114021062851,-1.73840117454529],[41.4202461242676,0.0600066967308521,-1.63958632946014],[42.2127456665039,0.0600234679877758,-1.66393148899078]]},{"_t":"pf32","v":[1.66449916362762,1.66020536422729,1.65906965732574]}],"ch":0,"rel":false}
+ 20.126s S→C {"t":"rpc","node":"Main/Players/P_2","method":"_apply_vitals","args":[100.0,93.5582974700748,"ok",0.0,false,100.0,0.0,false],"ch":0,"rel":false}
+ 20.126s S→C {"t":"rpc","node":"Main/Players/P_453073507","method":"_apply_vitals","args":[100.0,93.5582974700748,"ok",0.0,false,100.0,0.0,false],"ch":0,"rel":false}
+ 20.140s C→S {"t":"rpc","node":"Main/Players/P_453073507","method":"_push_transform","args":[{"_t":"v3","v":[1.4676135998169424,0.0,1.9023425832870244]},1.7997779607693793,0.0,{"_t":"v3","v":[-1.4150652343014247,0.0,-0.4971133389199345]}],"ch":0,"rel":false}
+ 20.345s S→C {"t":"rpc","node":"Main/Enemies","method":"_sync_progress","args":[1,42,42,1.81666666666667,0],"ch":0,"rel":false}
+ 20.345s S→C {"t":"rpc","node":"Net","method":"_rtt_ping","args":[18,10.5677613139222],"ch":0,"rel":false}
+ 20.346s C→S {"t":"rpc","node":"Net","method":"_rtt_pong","args":[18],"ch":0,"rel":false}
+ 21.358s S→C {"t":"rpc","node":"Net","method":"_rtt_ping","args":[19,12.1974329197455],"ch":0,"rel":false}
+ 21.358s C→S {"t":"rpc","node":"Net","method":"_rtt_pong","args":[19],"ch":0,"rel":false}
+ 22.154s S→C {"t":"rpc","node":"Main/Enemies","method":"_spawn_enemy","args":[4,0,{"_t":"v3","v":[-38.932430267334,0.649999976158142,-60.0322799682617]},false,false],"ch":0,"rel":true}
+ 22.154s S→C {"t":"rpc","node":"Main/Enemies","method":"_receive_group_warning","args":[{"_t":"v3","v":[-38.932430267334,0.649999976158142,-60.0322799682617]}],"ch":0,"rel":true}
+ 22.448s S→C {"t":"rpc","node":"Main/Enemies","method":"_spawn_enemy","args":[5,1,{"_t":"v3","v":[-40.6086921691895,0.649999976158142,-61.1213798522949]},false,false],"ch":0,"rel":true}
```
> Hitscan request: `[run_id, serial, origin(eye), dir, aiming, predicted]`; host resolves hits (client-responsibilities §Weapons).

```text
+ 23.398s C→S {"t":"rpc","node":"Main/Players/P_453073507/Head/Camera3D/WeaponHolder","method":"_request_shot","args":[1,2,{"_t":"v3","v":[2.68098776401971,1.65,-0.83650875988728]},{"_t":"v3","v":[0.9977457542315453,-0.02303586505362331,-0.0630298249573663]},false,true],"ch":0,"rel":true}
```
> Authoritative shot effect with `traces[[end, impact]]`, relayed to everyone; skip local re-play when `predicted` and it is yours.

```text
+ 23.401s S→C {"t":"rpc","node":"Main/Players/P_453073507/Head/Camera3D/WeaponHolder","method":"_shot_fx","args":[1,"nail_driver",{"_t":"v3","v":[2.68098783493042,1.64999997615814,-0.836508750915527]},{"_t":"v3","v":[0.997745752334595,-0.0230358652770519,-0.0630298256874084]},[[{"_t":"v3","v":[12.7014446258545,1.2842857837677,-1.53460621833801]},1]],false,true],"ch":0,"rel":false}
+ 23.401s S→C {"t":"rpc","node":"Main/Players/P_453073507/Head/Camera3D/WeaponHolder","method":"_private_state","args":[1,3,[[2,"nail_driver",0,23],[],[],[],[]],{"nail":60},0,"",0,2,1,0.0,1.0,0.0,0.085],"ch":0,"rel":true}
+ 23.602s C→S {"t":"rpc","node":"Main/Players/P_453073507/Head/Camera3D/WeaponHolder","method":"_request_shot","args":[1,2,{"_t":"v3","v":[2.932936648363099,1.65,-0.674576183200148]},{"_t":"v3","v":[0.9971090219652256,-0.0236131907740686,-0.07222198790547646]},false,true],"ch":0,"rel":true}
+ 23.606s S→C {"t":"rpc","node":"Main/Players/P_453073507/Head/Camera3D/WeaponHolder","method":"_shot_fx","args":[1,"nail_driver",{"_t":"v3","v":[2.932936668396,1.64999997615814,-0.674576163291931]},{"_t":"v3","v":[0.997109055519104,-0.0236131921410561,-0.0722219944000244]},[[{"_t":"v3","v":[12.7144184112549,1.41662192344666,-1.59564220905304]},1]],false,true],"ch":0,"rel":false}
+ 23.606s S→C {"t":"rpc","node":"Main/Players/P_453073507/Head/Camera3D/WeaponHolder","method":"_private_state","args":[1,4,[[2,"nail_driver",0,22],[],[],[],[]],{"nail":60},0,"",0,2,1,0.0,1.0,0.0,0.085],"ch":0,"rel":true}
+ 27.739s S→C {"t":"rpc","node":"Main/Enemies","method":"_receive_group_warning","args":[{"_t":"v3","v":[60.4049034118652,0.649999976158142,41.6753959655762]}],"ch":0,"rel":true}
+ 28.248s C→S {"t":"rpc","node":"Main/Players/P_453073507/Head/Camera3D/WeaponHolder","method":"_action","args":[1,"reload",2,-1],"ch":0,"rel":true}
+ 28.251s S→C {"t":"rpc","node":"Main/Players/P_453073507/Head/Camera3D/WeaponHolder","method":"_equip_state","args":[1,27,"nail_driver",0,1.65,1.65],"ch":0,"rel":true}
+ 28.562s S→C {"t":"rpc","node":"Main/Enemies","method":"_enemy_impacts","args":[[[1,{"_t":"v3","v":[0.998372852802277,-0.0564277768135071,0.008229642175138]},false]]],"ch":0,"rel":false}
```
> World pickup appeared: `[run_id, pickup_id, [pos, item[], flavor, claim_peer]]`.

```text
+ 29.062s S→C {"t":"rpc","node":"Main/RunLoot","method":"_spawn","args":[1,1,[{"_t":"v3","v":[16.2863292694092,0.0609114021062851,0.815105199813843]},[],"scrap",0]],"ch":0,"rel":true}
```
> Enemy died: `[net_id, drops, at, throw_vec, critical]`.

```text
+ 29.062s S→C {"t":"rpc","node":"Main/Enemies","method":"_despawn_enemy","args":[1,[[{"_t":"v3","v":[16.2863292694092,0.0609114021062851,0.815105199813843]},"scrap"]],{"_t":"v3","v":[16.2863292694092,0.0609114021062851,0.815105199813843]},{"_t":"v3","v":[0.693669259548187,0.0,0.00571795366704464]},false],"ch":0,"rel":true}
+ 29.062s S→C {"t":"rpc","node":"Main/RunLoot","method":"_spawn","args":[1,2,[{"_t":"v3","v":[16.9959487915039,0.0600069686770439,0.49434694647789]},[],"scrap",0]],"ch":0,"rel":true}
+ 29.062s S→C {"t":"rpc","node":"Main/Enemies","method":"_despawn_enemy","args":[2,[[{"_t":"v3","v":[16.9959487915039,0.0600069686770439,0.49434694647789]},"scrap"]],{"_t":"v3","v":[16.9959487915039,0.0600069686770439,0.49434694647789]},{"_t":"v3","v":[0.0,0.0,0.0]},false],"ch":0,"rel":true}
+ 29.890s S→C {"t":"rpc","node":"Main/Players/P_453073507/Head/Camera3D/WeaponHolder","method":"_equip_state","args":[1,28,"nail_driver",0,0.0,1.65],"ch":0,"rel":true}
```
> Lightning: negative seed = ambient, positive = tactical (item) strike.

```text
+ 34.185s S→C {"t":"rpc","node":"WeatherManager","method":"_strike","args":[{"_t":"v3","v":[54.7950859069824,0.0,-53.0685577392578]},-798603761],"ch":0,"rel":true}
+ 56.737s S→C {"t":"rpc","node":"WeatherManager","method":"_strike","args":[{"_t":"v3","v":[76.5875244140625,0.0,-15.550817489624]},-543238854],"ch":0,"rel":true}
+ 59.105s S→C {"t":"rpc","node":"Main/Enemies","method":"_enemy_impacts","args":[[[30,{"_t":"v3","v":[-0.399812132120132,-0.0626508295536041,0.914453446865082]},false],[28,{"_t":"v3","v":[-0.392677992582321,-0.0766400620341301,0.916477084159851]},false]]],"ch":0,"rel":false}
+ 61.282s C→S {"t":"rpc","node":"Main/Players/P_453073507/Head/Camera3D/WeaponHolder","method":"_action","args":[1,"reload",2,-1],"ch":0,"rel":true}
```
> World pickup collected/expired: `[run_id, pickup_id, collector]`.

```text
+ 66.258s S→C {"t":"rpc","node":"Main/RunLoot","method":"_remove","args":[1,5,0],"ch":0,"rel":true}
+ 72.664s S→C {"t":"rpc","node":"Main/RunLoot","method":"_remove","args":[1,12,0],"ch":0,"rel":true}
```

Repeats not shown in this section: 1962× `S→C _relay_transform`, 1120× `C→S _push_transform`, 840× `S→C _sync_enemies`, 516× `S→C _apply_vitals`, 197× `S→C _sync_progress`, 56× `S→C _shot_fx`, 53× `S→C _rtt_ping`, 53× `C→S _rtt_pong`, 51× `S→C _private_state`, 47× `C→S _request_shot`, 41× `S→C _spawn`, 39× `S→C _despawn_enemy`, 37× `S→C _spawn_enemy`, 11× `S→C _equip_state`, 5× `S→C _receive_group_warning`, 4× `S→C _enemy_impacts`, 3× `S→C _remove`.

## Run: wave 1 clearing

```text
+ 76.158s S→C {"t":"rpc","node":"WeatherManager","method":"_receive_phase","args":[4,1,15.0],"ch":0,"rel":true}
+ 76.158s S→C {"t":"rpc","node":"GameManager/Feats","method":"_feat_event","args":["no_roof",1],"ch":0,"rel":true}
+ 76.158s S→C {"t":"rpc","node":"GameManager/Feats","method":"_feat_event","args":["conscientious_objector",1],"ch":0,"rel":true}
```
> Centre-screen banner text, colour, seconds.

```text
+ 76.158s S→C {"t":"rpc","node":"GameManager","method":"_banner","args":["WAVE 1 CLEAR",{"_t":"color","v":[0.400000005960464,0.874509811401367,0.854901969432831,1.0]},2.2],"ch":0,"rel":true}
+ 76.158s S→C {"t":"rpc","node":"GameManager/MutationRoll","method":"_clear_rpc","args":[],"ch":0,"rel":true}
+ 76.158s S→C {"t":"rpc","node":"Main/Enemies","method":"_retire_enemies","args":[{"_t":"pi32","v":[42]}],"ch":0,"rel":true}
+ 76.171s C→S {"t":"rpc","node":"GameManager","method":"_request_ready","args":[],"ch":0,"rel":true}
+ 76.173s S→C {"t":"rpc","node":"Main/Enemies","method":"_sync_progress","args":[1,0,42,0.0,0],"ch":0,"rel":false}
+ 76.173s S→C {"t":"rpc","node":"GameManager","method":"_ready_changed","args":[1,2],"ch":0,"rel":true}
+ 76.187s C→S {"t":"rpc","node":"Main/Players/P_453073507","method":"_push_transform","args":[{"_t":"v3","v":[2.203126062625258,0.0,1.9861829640667934]},1.7316310325652469,0.0,{"_t":"v3","v":[-1.4804867048602244,0.0,0.24018827155508404]}],"ch":0,"rel":false}
+ 76.189s S→C {"t":"rpc","node":"Main/Players/P_453073507","method":"_relay_transform","args":[{"_t":"v3","v":[2.20312595367432,0.0,1.98618292808533]},1.73163103256525,0.0,{"_t":"v3","v":[-1.48048675060272,0.0,0.240188270807266]}],"ch":0,"rel":false}
+ 76.205s S→C {"t":"rpc","node":"Main/Players/P_2","method":"_relay_transform","args":[{"_t":"v3","v":[-2.0,0.0599821582436562,0.5]},0.617999970912933,-0.0160000007599592,{"_t":"v3","v":[0.0,0.0,0.0]}],"ch":0,"rel":false}
+ 76.233s C→S {"t":"rpc","node":"Main/Players/P_453073507","method":"_push_transform","args":[{"_t":"v3","v":[2.128594018011671,0.0,1.9944776942235083]},1.6816310325652413,0.0,{"_t":"v3","v":[-1.4906408922717418,0.0,0.16589460313429782]}],"ch":0,"rel":false}
+ 76.236s S→C {"t":"rpc","node":"Main/Players/P_2","method":"_apply_vitals","args":[100.0,45.0,"ok",0.0,false,100.0,0.0,false],"ch":0,"rel":false}
+ 76.236s S→C {"t":"rpc","node":"Main/Players/P_453073507","method":"_apply_vitals","args":[100.0,45.0,"ok",0.0,false,100.0,0.0,false],"ch":0,"rel":false}
+ 76.251s S→C {"t":"rpc","node":"Main/RunLoot","method":"_remove","args":[1,4,0],"ch":0,"rel":true}
+ 76.251s S→C {"t":"rpc","node":"Net","method":"_rtt_ping","args":[73,15.9263336910491],"ch":0,"rel":false}
+ 76.251s C→S {"t":"rpc","node":"Net","method":"_rtt_pong","args":[73],"ch":0,"rel":false}
+ 76.315s S→C {"t":"rpc","node":"GameManager","method":"_ready_changed","args":[2,2],"ch":0,"rel":true}
+ 76.315s S→C {"t":"rpc","node":"WeatherManager","method":"_receive_phase","args":[4,1,3.0],"ch":0,"rel":true}
+ 76.454s S→C {"t":"rpc","node":"Main/Enemies","method":"_sync_progress","args":[1,0,42,0.0,0],"ch":0,"rel":false}
+ 76.516s S→C {"t":"rpc","node":"Main/RunLoot","method":"_remove","args":[1,6,0],"ch":0,"rel":true}
+ 77.267s S→C {"t":"rpc","node":"Net","method":"_rtt_ping","args":[74,15.6484335837344],"ch":0,"rel":false}
+ 77.267s C→S {"t":"rpc","node":"Net","method":"_rtt_pong","args":[74],"ch":0,"rel":false}
```

Repeats not shown in this section: 108× `S→C _relay_transform`, 61× `C→S _push_transform`, 28× `S→C _apply_vitals`, 10× `S→C _sync_progress`, 2× `S→C _rtt_ping`, 2× `C→S _rtt_pong`, 1× `S→C _remove`.

## Run: wave 2 calm

```text
+ 79.310s S→C {"t":"rpc","node":"WeatherManager","method":"_receive_phase","args":[0,2,30.0],"ch":0,"rel":true}
+ 79.310s S→C {"t":"rpc","node":"GameManager/CrateManager","method":"_stock","args":[1,"HardwareStation",[["suit_patch",0,6,10],["rock_salt",1,10,11],["lightning_rod",2,18,12]]],"ch":0,"rel":true}
+ 79.310s S→C {"t":"rpc","node":"GameManager/CrateManager","method":"_stock","args":[1,"GasStationSurplus",[["umbrella",0,6,13],["rock_salt",1,10,14],["leaf_blower",2,18,15]]],"ch":0,"rel":true}
+ 79.310s S→C {"t":"rpc","node":"GameManager","method":"_banner","args":["SURPLUS SUPPLY DROP INBOUND",{"_t":"color","v":[0.941372573375702,0.861568629741669,0.681568622589111,1.0]},3.2],"ch":0,"rel":true}
+ 79.310s S→C {"t":"rpc","node":"GameManager/CrateManager","method":"_announce_drop","args":[1],"ch":0,"rel":true}
+ 79.324s C→S {"t":"rpc","node":"GameManager","method":"_request_ready","args":[],"ch":0,"rel":true}
+ 79.326s S→C {"t":"rpc","node":"GameManager/CrateManager","method":"_airdrop_spawn","args":[1,{"_t":"v3","v":[0.0,0.0700000524520874,-12.0]},2.4],"ch":0,"rel":true}
```

Repeats not shown in this section: 1× `S→C _stock`.

## Mutation draft

> Mutation draft: enemy mutation id + 3 player mutation card ids. Vote with `_request_vote(i)`.

```text
+ 79.326s S→C {"t":"rpc","node":"GameManager/MutationRoll","method":"_deal_rpc","args":["",["reflex_tendons","chitin_suit","adrenaline_glands"]],"ch":0,"rel":true}
```
> Vote for card index.

```text
+ 79.326s C→S {"t":"rpc","node":"GameManager/MutationRoll","method":"_request_vote","args":[0],"ch":0,"rel":true}
+ 79.326s S→C {"t":"rpc","node":"Main/Enemies","method":"_sync_progress","args":[2,54,54,2.1,0],"ch":0,"rel":false}
```
> Vote tally `[n0, n1, n2]`.

```text
+ 79.327s S→C {"t":"rpc","node":"GameManager/MutationRoll","method":"_votes_rpc","args":[[1,0,0]],"ch":0,"rel":true}
+ 79.327s S→C {"t":"rpc","node":"GameManager/MutationRoll","method":"_votes_rpc","args":[[2,0,0]],"ch":0,"rel":true}
+ 79.338s C→S {"t":"rpc","node":"Main/Players/P_453073507","method":"_push_transform","args":[{"_t":"v3","v":[1.8093758239720656,0.0,-0.9878381711441844]},-1.4183689674347588,0.0,{"_t":"v3","v":[1.4824537044105712,0.0,-0.22773296498285855]}],"ch":0,"rel":false}
+ 79.341s S→C {"t":"rpc","node":"Main/Players/P_453073507","method":"_relay_transform","args":[{"_t":"v3","v":[1.80937588214874,0.0,-0.98783814907074]},-1.41836896743476,0.0,{"_t":"v3","v":[1.48245370388031,0.0,-0.227732971310616]}],"ch":0,"rel":false}
+ 79.341s S→C {"t":"rpc","node":"Main/Players/P_2","method":"_relay_transform","args":[{"_t":"v3","v":[-2.0,0.0599821582436562,0.5]},0.617999970912933,0.0,{"_t":"v3","v":[0.0,0.0,0.0]}],"ch":0,"rel":false}
+ 79.385s C→S {"t":"rpc","node":"Main/Players/P_453073507","method":"_push_transform","args":[{"_t":"v3","v":[1.8839749703575122,0.0,-0.9955059988166077]},-1.468368967434759,0.0,{"_t":"v3","v":[1.4919829277089303,0.0,-0.1533565534484671]}],"ch":0,"rel":false}
+ 79.481s S→C {"t":"rpc","node":"Main/Players/P_2","method":"_apply_vitals","args":[100.0,45.0,"ok",0.0,false,100.0,0.0,false],"ch":0,"rel":false}
+ 79.481s S→C {"t":"rpc","node":"Main/Players/P_453073507","method":"_apply_vitals","args":[100.0,45.0,"ok",0.0,false,100.0,0.0,false],"ch":0,"rel":false}
+ 79.605s S→C {"t":"rpc","node":"Main/Enemies","method":"_sync_progress","args":[2,54,54,2.1,0],"ch":0,"rel":false}
```
> Draft result: `[pick, enemy_list, player_list, granted]`; resume the Calm countdown after 2.2 s.

```text
+ 79.916s S→C {"t":"rpc","node":"GameManager/MutationRoll","method":"_result_rpc","args":[0,[],["reflex_tendons"],["reflex_tendons"]],"ch":0,"rel":true}
+ 80.321s S→C {"t":"rpc","node":"Net","method":"_rtt_ping","args":[77,19.9294127192209],"ch":0,"rel":false}
+ 80.321s C→S {"t":"rpc","node":"Net","method":"_rtt_pong","args":[77],"ch":0,"rel":false}
+ 81.334s S→C {"t":"rpc","node":"Net","method":"_rtt_ping","args":[78,18.7505889034546],"ch":0,"rel":false}
+ 81.334s C→S {"t":"rpc","node":"Net","method":"_rtt_pong","args":[78],"ch":0,"rel":false}
+ 81.864s S→C {"t":"rpc","node":"Main/RunLoot","method":"_remove","args":[1,8,0],"ch":0,"rel":true}
+ 82.129s S→C {"t":"rpc","node":"Main/RunLoot","method":"_remove","args":[1,9,0],"ch":0,"rel":true}
```

Repeats not shown in this section: 1148× `S→C _relay_transform`, 655× `C→S _push_transform`, 300× `S→C _apply_vitals`, 114× `S→C _sync_progress`, 30× `S→C _rtt_ping`, 30× `C→S _rtt_pong`, 26× `S→C _remove`.

## Run: wave 2 drizzle

```text
+112.148s S→C {"t":"rpc","node":"WeatherManager","method":"_receive_phase","args":[2,2,30.0],"ch":0,"rel":true}
+112.177s C→S {"t":"rpc","node":"Main/Players/P_453073507","method":"_push_transform","args":[{"_t":"v3","v":[3.447972075675846,0.0,0.10836641096174815]},-2.8524424315368293,0.0,{"_t":"v3","v":[0.427662189771727,0.0,1.4375800292510443]}],"ch":0,"rel":false}
+112.180s S→C {"t":"rpc","node":"Main/Enemies","method":"_sync_progress","args":[2,54,54,1.25,0],"ch":0,"rel":false}
+112.180s S→C {"t":"rpc","node":"Main/Players/P_453073507","method":"_relay_transform","args":[{"_t":"v3","v":[3.44797205924988,0.0,0.108366407454014]},-2.85244243153683,0.0,{"_t":"v3","v":[0.427662193775177,0.0,1.43757998943329]}],"ch":0,"rel":false}
+112.210s S→C {"t":"rpc","node":"Main/Players/P_2","method":"_relay_transform","args":[{"_t":"v3","v":[-2.0,0.0599821582436562,0.5]},0.617999970912933,0.0,{"_t":"v3","v":[0.0,0.0,0.0]}],"ch":0,"rel":false}
+112.210s S→C {"t":"rpc","node":"Main/Players/P_2","method":"_apply_vitals","args":[100.0,45.0,"ok",0.0,false,100.0,0.0,false],"ch":0,"rel":false}
+112.210s S→C {"t":"rpc","node":"Main/Players/P_453073507","method":"_apply_vitals","args":[100.0,45.0,"ok",0.0,false,100.0,0.0,false],"ch":0,"rel":false}
+112.239s C→S {"t":"rpc","node":"Main/Players/P_453073507","method":"_push_transform","args":[{"_t":"v3","v":[3.465736009064516,0.0,0.1812242924380451]},-2.9024424315368362,0.0,{"_t":"v3","v":[0.35527866777339767,0.0,1.4571576295259392]}],"ch":0,"rel":false}
+112.458s S→C {"t":"rpc","node":"Main/Enemies","method":"_sync_progress","args":[2,54,54,0.966666666666667,0],"ch":0,"rel":false}
+112.847s S→C {"t":"rpc","node":"Net","method":"_rtt_ping","args":[109,19.3523341934873],"ch":0,"rel":false}
+112.847s C→S {"t":"rpc","node":"Net","method":"_rtt_pong","args":[109],"ch":0,"rel":false}
+113.407s S→C {"t":"rpc","node":"Main/Enemies","method":"_spawn_enemy","args":[43,0,{"_t":"v3","v":[18.3136367797852,0.649999976158142,60.4311218261719]},false,false],"ch":0,"rel":true}
+113.407s S→C {"t":"rpc","node":"Main/Enemies","method":"_receive_group_warning","args":[{"_t":"v3","v":[18.3136367797852,0.649999976158142,60.4311218261719]}],"ch":0,"rel":true}
+113.469s S→C {"t":"rpc","node":"Main/Enemies","method":"_sync_enemies","args":[{"_t":"pi32","v":[43]},{"_t":"pv3","v":[[18.1917285919189,0.633666634559631,60.4034843444824]]},{"_t":"pf32","v":[0.25581169128418]}],"ch":0,"rel":false}
+113.532s S→C {"t":"rpc","node":"Main/Enemies","method":"_sync_enemies","args":[{"_t":"pi32","v":[43]},{"_t":"pv3","v":[[18.0291843414307,0.573777735233307,60.3666343688965]]},{"_t":"pf32","v":[0.254866570234299]}],"ch":0,"rel":false}
+113.687s S→C {"t":"rpc","node":"Main/Enemies","method":"_spawn_enemy","args":[44,1,{"_t":"v3","v":[19.1606025695801,0.649999976158142,61.639232635498]},false,false],"ch":0,"rel":true}
+113.687s S→C {"t":"rpc","node":"GameManager","method":"_banner","args":["GUTTER AMBUSH",{"_t":"color","v":[1.0,0.764705896377563,0.396078437566757,1.0]},2.0],"ch":0,"rel":true}
+113.687s S→C {"t":"rpc","node":"Main/Enemies","method":"_receive_group_warning","args":[{"_t":"v3","v":[8.0,0.0,-36.0]}],"ch":0,"rel":true}
+113.873s S→C {"t":"rpc","node":"Net","method":"_rtt_ping","args":[110,22.5466339354411],"ch":0,"rel":false}
+113.873s C→S {"t":"rpc","node":"Net","method":"_rtt_pong","args":[110],"ch":0,"rel":false}
+115.073s S→C {"t":"rpc","node":"Main/RunLoot","method":"_remove","args":[1,37,0],"ch":0,"rel":true}
+115.341s S→C {"t":"rpc","node":"Main/RunLoot","method":"_remove","args":[1,38,0],"ch":0,"rel":true}
+115.775s C→S {"t":"rpc","node":"Main/Players/P_453073507/Head/Camera3D/WeaponHolder","method":"_request_shot","args":[1,2,{"_t":"v3","v":[0.528212985090498,1.65,0.21044347228256644]},{"_t":"v3","v":[0.2621701935655206,-0.025011583448969504,-0.9646974708680399]},false,true],"ch":0,"rel":true}
+115.778s S→C {"t":"rpc","node":"Main/Players/P_453073507/Head/Camera3D/WeaponHolder","method":"_shot_fx","args":[1,"nail_driver",{"_t":"v3","v":[0.52821296453476,1.64999997615814,0.210443466901779]},{"_t":"v3","v":[0.262170195579529,-0.0250115841627121,-0.964697480201721]},[[{"_t":"v3","v":[7.76237344741821,1.37931036949158,-26.8267421722412]},1]],false,true],"ch":0,"rel":false}
+115.778s S→C {"t":"rpc","node":"Main/Players/P_453073507/Head/Camera3D/WeaponHolder","method":"_private_state","args":[1,56,[[2,"nail_driver",0,22],[],[],[],[]],{"nail":12},0,"",0,2,1,0.0,1.65,0.0,0.068],"ch":0,"rel":true}
+115.977s C→S {"t":"rpc","node":"Main/Players/P_453073507/Head/Camera3D/WeaponHolder","method":"_request_shot","args":[1,2,{"_t":"v3","v":[0.6150767385754334,1.65,-0.07618361653655326]},{"_t":"v3","v":[0.2508812680996463,-0.0256515928844193,-0.9676779345935327]},false,true],"ch":0,"rel":true}
+115.994s S→C {"t":"rpc","node":"Main/Enemies","method":"_enemy_impacts","args":[[[47,{"_t":"v3","v":[0.241063565015793,-0.0289741214364767,-0.9700767993927]},false]]],"ch":0,"rel":false}
```
> Hit markers for your shots: `[[killed, critical, pos, damage, enemy_id], ...]`.

```text
+115.994s S→C {"t":"rpc","node":"Main/Players/P_453073507","method":"_receive_hits","args":[1,[[false,false,{"_t":"v3","v":[7.57466983795166,0.813506484031677,-28.0826549530029]},3,47]]],"ch":0,"rel":true}
+115.995s S→C {"t":"rpc","node":"Main/Players/P_453073507/Head/Camera3D/WeaponHolder","method":"_shot_fx","args":[1,"nail_driver",{"_t":"v3","v":[0.615076720714569,1.64999997615814,-0.0761836171150208]},{"_t":"v3","v":[0.250881254673004,-0.0256515927612782,-0.96767795085907]},[[{"_t":"v3","v":[7.57466983795166,0.813506484031677,-28.0826549530029]},2]],false,true],"ch":0,"rel":false}
+115.995s S→C {"t":"rpc","node":"Main/Players/P_453073507/Head/Camera3D/WeaponHolder","method":"_private_state","args":[1,57,[[2,"nail_driver",0,21],[],[],[],[]],{"nail":12},0,"",0,2,1,0.0,1.65,0.0,0.068],"ch":0,"rel":true}
+116.182s S→C {"t":"rpc","node":"Main/Enemies","method":"_enemy_impacts","args":[[[47,{"_t":"v3","v":[0.247363165020943,-0.0230338629335165,-0.96864902973175]},false]]],"ch":0,"rel":false}
+116.182s S→C {"t":"rpc","node":"Main/Players/P_453073507","method":"_receive_hits","args":[1,[[false,false,{"_t":"v3","v":[7.70792102813721,1.00276112556458,-27.5583419799805]},4,47]]],"ch":0,"rel":true}
+118.168s S→C {"t":"rpc","node":"GameManager/Feats","method":"_feat_event","args":["cable_subscriber",1],"ch":0,"rel":true}
```

Repeats not shown in this section: 208× `S→C _relay_transform`, 118× `C→S _push_transform`, 69× `S→C _sync_enemies`, 54× `S→C _apply_vitals`, 20× `S→C _sync_progress`, 10× `C→S _request_shot`, 10× `S→C _shot_fx`, 10× `S→C _private_state`, 7× `S→C _spawn_enemy`, 5× `S→C _remove`, 5× `S→C _enemy_impacts`, 5× `S→C _receive_hits`, 4× `S→C _rtt_ping`, 4× `C→S _rtt_pong`.

## Results and return to the lobby

> Run over: `[won, results]`. Show results, unload, send `_report_in_run(false)`; next `_push_roster` is the lobby.

```text
+118.168s S→C {"t":"rpc","node":"GameManager","method":"_finish","args":[false,{"won":false,"map_id":"pinecrest","waves":1,"wave_reached":2,"endless":false,"endless_score":0,"seconds":109,"squad_mutations":["REFLEX TENDONS"],"players":{"_t":"dict","v":[[2,{"name":"Thin Bot","kills":7,"revives":0,"turned":0,"cursed":"","weapon":"Pump Shotgun"}],[453073507,{"name":"Full Bot","kills":0,"revives":0,"turned":0,"cursed":"","weapon":"Nail Driver"}]]}}],"ch":0,"rel":true}
+118.168s S→C {"t":"rpc","node":"Net","method":"_push_roster","args":[{"_t":"dict","v":[[2,{"name":"Thin Bot","ready":false,"color":0,"skin":0}],[453073507,{"name":"Full Bot","ready":false,"color":3,"skin":1}]]},"pinecrest",true,{},""],"ch":0,"rel":true}
+118.960s S→C {"t":"rpc","node":"Net","method":"_rtt_ping","args":[115,18.9833327655296],"ch":0,"rel":false}
+118.960s C→S {"t":"rpc","node":"Net","method":"_rtt_pong","args":[115],"ch":0,"rel":false}
+119.974s S→C {"t":"rpc","node":"Net","method":"_rtt_ping","args":[116,18.3883329358707],"ch":0,"rel":false}
+119.975s C→S {"t":"rpc","node":"Net","method":"_rtt_pong","args":[116],"ch":0,"rel":false}
+120.179s S→C {"t":"rpc","node":"WeatherManager","method":"_receive_phase","args":[3,2,46.8079096703892],"ch":0,"rel":true}
+122.683s C→S {"t":"rpc","node":"Net","method":"_report_in_run","args":[false],"ch":0,"rel":true}
+123.173s S→C {"t":"rpc","node":"GameManager/MutationRoll","method":"_reset_run_rpc","args":[],"ch":0,"rel":true}
+124.248s S→C {"t":"rpc","node":"Net","method":"_push_roster","args":[{"_t":"dict","v":[[453073507,{"name":"Full Bot","ready":false,"color":3,"skin":1}]]},"pinecrest",true,{},""],"ch":0,"rel":true}
```

Repeats not shown in this section: 5× `S→C _rtt_ping`, 5× `C→S _rtt_pong`.

## Leave

> Clean exit. The server removes the peer and closes the socket.

```text
+125.271s C→S {"t":"leave"}
# transport closed by server after leave (EOFError)
```

## Frame totals

| Kind | Frames |
| --- | ---: |
| `_relay_transform` | 3891 |
| `_push_transform` | 2250 |
| `_sync_enemies` | 1014 |
| `_apply_vitals` | 1010 |
| `_sync_progress` | 390 |
| `_rtt_ping` | 120 |
| `_rtt_pong` | 120 |
| `_shot_fx` | 70 |
| `_private_state` | 67 |
| `_request_shot` | 61 |
| `_spawn_enemy` | 51 |
| `_spawn` | 43 |
| `_remove` | 43 |
| `_despawn_enemy` | 41 |
| `_equip_state` | 17 |
| `_enemy_impacts` | 13 |
| `_receive_phase` | 10 |
| `_receive_group_warning` | 10 |
| `_push_roster` | 8 |
| `_receive_hits` | 7 |
| `_request_ready` | 4 |
| `_ready_changed` | 4 |
| `_feat_event` | 3 |
| `_banner` | 3 |
| `_stock` | 3 |
| `_chat_rpc` | 2 |
| `_report_in_run` | 2 |
| `_sync_tape_state` | 2 |
| `_reset_run_rpc` | 2 |
| `_sync_decon` | 2 |
| `_override` | 2 |
| `_snapshot` | 2 |
| `_action` | 2 |
| `_strike` | 2 |
| `_votes_rpc` | 2 |
| `hello` | 1 |
| `welcome` | 1 |
| `_hello` | 1 |
| `_request_chat` | 1 |
| `_request_map_vote` | 1 |
| `_start_run` | 1 |
| `_receive_intensity` | 1 |
| `_sync_active` | 1 |
| `_sync_puddles` | 1 |
| `_confirm_run_ready` | 1 |
| `_report_exposure` | 1 |
| `_request_starter` | 1 |
| `_starter_accepted` | 1 |
| `_clear_rpc` | 1 |
| `_retire_enemies` | 1 |
| `_announce_drop` | 1 |
| `_airdrop_spawn` | 1 |
| `_deal_rpc` | 1 |
| `_request_vote` | 1 |
| `_result_rpc` | 1 |
| `_finish` | 1 |
| `leave` | 1 |
