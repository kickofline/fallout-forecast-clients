# Full tier session — tcp/bin

Captured from a local Godot 4.7.2 dedicated server using **tcp** and **bin**.
The capture harness shortens Drizzle and Clearing, removes wave-one
stragglers, keeps players above a health and suit floor, and ends the
run six seconds into wave-two Drizzle. A bot of the other tier shares
the lobby, so its traffic appears here too.

`C→S` is client to server, `S→C` is server to client, and `+t` is
seconds since capture start. Long previews can be truncated. Repeats
are counted at the end of the section. The sampled, ordered capture
is [`full-bin.jsonl`](full-bin.jsonl).

TCP prefixes show the full payload length. The JSONL `hex` field
contains the full payload without that prefix. Use `hex` for
byte-exact tests. For outgoing client frames, `msg` can hold
values from before encoding, such as a double that was rounded
to a 32-bit float on the wire.

> Open Protocol hello selecting the Full tier; JSON text even for `enc:"bin"` (spec-common §4).

```text
+  2.352s C→S text (raw TCP prefix 47 00 00 00)
     {"t":"hello","v":1,"tier":"full","enc":"bin","client":"capture-full/1"}
```

## Handshake

> Transport-level acceptance. `you` is the real Godot peer id; `game_protocol` must equal the client's (spec-full §2).

```text
+  2.359s S→C text (raw TCP prefix d3 00 00 00)
     {"t":"welcome","v":1,"tier":"full","enc":"bin","you":234289745,"game_protocol":19,"maps":[{"id":"pinecrest","name":"PINECREST"},{"id":"harbor","name":"HARBOR POINT"},{"id":"maple_hollow","name":"MAPLE HOLLOW"}]}
```
> 1 Hz latency probe; answer `Net._rtt_pong(seq)` unreliably (client-responsibilities §RTT).

```text
+  2.455s S→C binary 35 bytes
len 23 00 00 00   (raw TCP prefix: 35 bytes)
0000 03 00 00 03 00 4e 65 74 09 5f 72 74 74 5f 70 69
0010 6e 67 02 02 00 00 00 02 00 00 00 03 00 00 00 00
0020 00 00 00
     = {"t":"rpc","node":"Net","method":"_rtt_ping","args":[2,0.0],"ch":0,"rel":false,"mode":0}
```
> Echo of `_rtt_ping.seq`.

```text
+  2.455s C→S binary 27 bytes
len 1b 00 00 00   (raw TCP prefix: 27 bytes)
0000 03 00 00 03 00 4e 65 74 09 5f 72 74 74 5f 70 6f
0010 6e 67 01 02 00 00 00 02 00 00 00
     = {"t":"rpc","node":"Net","method":"_rtt_pong","args":[2],"ch":0,"rel":false}
```
> Game-level handshake RPC: arg0 is a JSON *string*, arg1 the game protocol (spec-full §3).

```text
+  3.354s C→S binary 84 bytes
len 54 00 00 00   (raw TCP prefix: 84 bytes)
0000 03 02 00 03 00 4e 65 74 06 5f 68 65 6c 6c 6f 02
0010 04 00 00 00 32 00 00 00 7b 22 6e 61 6d 65 22 3a
0020 22 46 75 6c 6c 20 42 6f 74 22 2c 22 63 6f 6c 6f
0030 72 22 3a 33 2c 22 73 6b 69 6e 22 3a 31 2c 22 63
0040 6f 6c 6f 72 73 22 3a 5b 5d 7d 00 00 02 00 00 00
0050 13 00 00 00
     = {"t":"rpc","node":"Net","method":"_hello","args":["{\"name\":\"Full Bot\",\"color\":3,\"skin\":1,\"colors\":[]}",19],"ch":0,"rel":true}
```

## Lobby

> Roster broadcast: `Dictionary[int peer_id -> {name,ready,color,skin}]` + lobby voting state (spec-full §4).

```text
+  3.354s S→C binary 298 bytes
len 2a 01 00 00   (raw TCP prefix: 298 bytes)
0000 03 02 00 03 00 4e 65 74 0c 5f 70 75 73 68 5f 72
0010 6f 73 74 65 72 05 1b 00 00 00 02 00 00 00 02 00
0020 00 00 02 00 00 00 1b 00 00 00 04 00 00 00 04 00
0030 00 00 04 00 00 00 6e 61 6d 65 04 00 00 00 08 00
0040 00 00 54 68 69 6e 20 42 6f 74 04 00 00 00 05 00
0050 00 00 72 65 61 64 79 00 00 00 01 00 00 00 00 00
0060 00 00 04 00 00 00 05 00 00 00 63 6f 6c 6f 72 00
0070 00 00 02 00 00 00 00 00 00 00 04 00 00 00 04 00
0080 00 00 73 6b 69 6e 02 00 00 00 00 00 00 00 02 00
0090 00 00 51 fa f6 0d 1b 00 00 00 04 00 00 00 04 00
00a0 00 00 04 00 00 00 6e 61 6d 65 04 00 00 00 08 00
00b0 00 00 46 75 6c 6c 20 42 6f 74 04 00 00 00 05 00
00c0 00 00 72 65 61 64 79 00 00 00 01 00 00 00 00 00
00d0 00 00 04 00 00 00 05 00 00 00 63 6f 6c 6f 72 00
00e0 00 00 02 00 00 00 03 00 00 00 04 00 00 00 04 00
00f0 00 00 73 6b 69 6e 02 00 00 00 01 00 00 00 04 00
0100 00 00 09 00 00 00 70 69 6e 65 63 72 65 73 74 00
0110 00 00 01 00 00 00 01 00 00 00 1b 00 00 00 00 00
0120 00 00 04 00 00 00 00 00 00 00
     = {"t":"rpc","node":"Net","method":"_push_roster","args":[{"_t":"dict","v":[[2,{"name":"Thin Bot","ready":false,"color":0,"skin":0}],[234289745,{"name":"Full Bot","ready":false,"color":3,"skin":1}]]},"pinecrest",true,{},""],"ch":0,"rel":true,"mode":2}
+  3.447s S→C binary 35 bytes
len 23 00 00 00   (raw TCP prefix: 35 bytes)
0000 03 00 00 03 00 4e 65 74 09 5f 72 74 74 5f 70 69
0010 6e 67 02 02 00 00 00 03 00 00 00 03 00 00 00 00
0020 00 88 41
     = {"t":"rpc","node":"Net","method":"_rtt_ping","args":[3,17.0],"ch":0,"rel":false,"mode":0}
+  3.448s C→S binary 27 bytes
len 1b 00 00 00   (raw TCP prefix: 27 bytes)
0000 03 00 00 03 00 4e 65 74 09 5f 72 74 74 5f 70 6f
0010 6e 67 01 02 00 00 00 03 00 00 00
     = {"t":"rpc","node":"Net","method":"_rtt_pong","args":[3],"ch":0,"rel":false}
```
> Chat relay; sent to every peer, including the sender.

```text
+  3.774s S→C binary 59 bytes
len 3b 00 00 00   (raw TCP prefix: 59 bytes)
0000 03 02 00 03 00 4e 65 74 09 5f 63 68 61 74 5f 72
0010 70 63 02 04 00 00 00 08 00 00 00 54 68 69 6e 20
0020 42 6f 74 04 00 00 00 0f 00 00 00 74 68 69 6e 20
0030 62 6f 74 20 6f 6e 6c 69 6e 65 00
     = {"t":"rpc","node":"Net","method":"_chat_rpc","args":["Thin Bot","thin bot online"],"ch":0,"rel":true,"mode":2}
+  3.775s S→C binary 326 bytes
len 46 01 00 00   (raw TCP prefix: 326 bytes)
0000 03 02 00 03 00 4e 65 74 0c 5f 70 75 73 68 5f 72
0010 6f 73 74 65 72 05 1b 00 00 00 02 00 00 00 02 00
0020 00 00 02 00 00 00 1b 00 00 00 04 00 00 00 04 00
0030 00 00 04 00 00 00 6e 61 6d 65 04 00 00 00 08 00
0040 00 00 54 68 69 6e 20 42 6f 74 04 00 00 00 05 00
0050 00 00 72 65 61 64 79 00 00 00 01 00 00 00 00 00
0060 00 00 04 00 00 00 05 00 00 00 63 6f 6c 6f 72 00
0070 00 00 02 00 00 00 00 00 00 00 04 00 00 00 04 00
     … (hex truncated)
     = {"t":"rpc","node":"Net","method":"_push_roster","args":[{"_t":"dict","v":[[2,{"name":"Thin Bot","ready":false,"color":0,"skin":0}],[234289745,{"name":"Full Bot","ready":false,"color":3,"skin":1}]]},"pinecrest",true,{"pinecrest":1},""],"ch":0,"rel":true,"mode":2}
+  4.161s C→S binary 47 bytes
len 2f 00 00 00   (raw TCP prefix: 47 bytes)
0000 03 02 00 03 00 4e 65 74 0d 5f 72 65 71 75 65 73
0010 74 5f 63 68 61 74 01 04 00 00 00 0f 00 00 00 66
0020 75 6c 6c 20 62 6f 74 20 6f 6e 6c 69 6e 65 00
     = {"t":"rpc","node":"Net","method":"_request_chat","args":["full bot online"],"ch":0,"rel":true}
+  4.162s C→S binary 47 bytes
len 2f 00 00 00   (raw TCP prefix: 47 bytes)
0000 03 02 00 03 00 4e 65 74 11 5f 72 65 71 75 65 73
0010 74 5f 6d 61 70 5f 76 6f 74 65 01 04 00 00 00 09
0020 00 00 00 70 69 6e 65 63 72 65 73 74 00 00 00
     = {"t":"rpc","node":"Net","method":"_request_map_vote","args":["pinecrest"],"ch":0,"rel":true}
+  4.178s S→C binary 59 bytes
len 3b 00 00 00   (raw TCP prefix: 59 bytes)
0000 03 02 00 03 00 4e 65 74 09 5f 63 68 61 74 5f 72
0010 70 63 02 04 00 00 00 08 00 00 00 46 75 6c 6c 20
0020 42 6f 74 04 00 00 00 0f 00 00 00 66 75 6c 6c 20
0030 62 6f 74 20 6f 6e 6c 69 6e 65 00
     = {"t":"rpc","node":"Net","method":"_chat_rpc","args":["Full Bot","full bot online"],"ch":0,"rel":true,"mode":2}
+  4.179s S→C binary 338 bytes
len 52 01 00 00   (raw TCP prefix: 338 bytes)
0000 03 02 00 03 00 4e 65 74 0c 5f 70 75 73 68 5f 72
0010 6f 73 74 65 72 05 1b 00 00 00 02 00 00 00 02 00
0020 00 00 02 00 00 00 1b 00 00 00 04 00 00 00 04 00
0030 00 00 04 00 00 00 6e 61 6d 65 04 00 00 00 08 00
0040 00 00 54 68 69 6e 20 42 6f 74 04 00 00 00 05 00
0050 00 00 72 65 61 64 79 00 00 00 01 00 00 00 00 00
0060 00 00 04 00 00 00 05 00 00 00 63 6f 6c 6f 72 00
0070 00 00 02 00 00 00 00 00 00 00 04 00 00 00 04 00
     … (hex truncated)
     = {"t":"rpc","node":"Net","method":"_push_roster","args":[{"_t":"dict","v":[[2,{"name":"Thin Bot","ready":false,"color":0,"skin":0}],[234289745,{"name":"Full Bot","ready":false,"color":3,"skin":1}]]},"pinecrest",true,{"pinecrest":2},"pinecrest"],"ch":0,"rel":true,"mode":2}
+  4.456s S→C binary 39 bytes
len 27 00 00 00   (raw TCP prefix: 39 bytes)
0000 03 00 00 03 00 4e 65 74 09 5f 72 74 74 5f 70 69
0010 6e 67 02 02 00 00 00 04 00 00 00 03 00 01 00 66
0020 66 66 66 66 66 30 40
     = {"t":"rpc","node":"Net","method":"_rtt_ping","args":[4,16.4],"ch":0,"rel":false,"mode":0}
+  4.456s C→S binary 27 bytes
len 1b 00 00 00   (raw TCP prefix: 27 bytes)
0000 03 00 00 03 00 4e 65 74 09 5f 72 74 74 5f 70 6f
0010 6e 67 01 02 00 00 00 04 00 00 00
     = {"t":"rpc","node":"Net","method":"_rtt_pong","args":[4],"ch":0,"rel":false}
+  4.581s S→C binary 338 bytes
len 52 01 00 00   (raw TCP prefix: 338 bytes)
0000 03 02 00 03 00 4e 65 74 0c 5f 70 75 73 68 5f 72
0010 6f 73 74 65 72 05 1b 00 00 00 02 00 00 00 02 00
0020 00 00 02 00 00 00 1b 00 00 00 04 00 00 00 04 00
0030 00 00 04 00 00 00 6e 61 6d 65 04 00 00 00 08 00
0040 00 00 54 68 69 6e 20 42 6f 74 04 00 00 00 05 00
0050 00 00 72 65 61 64 79 00 00 00 01 00 00 00 01 00
0060 00 00 04 00 00 00 05 00 00 00 63 6f 6c 6f 72 00
0070 00 00 02 00 00 00 00 00 00 00 04 00 00 00 04 00
     … (hex truncated)
     = {"t":"rpc","node":"Net","method":"_push_roster","args":[{"_t":"dict","v":[[2,{"name":"Thin Bot","ready":true,"color":0,"skin":0}],[234289745,{"name":"Full Bot","ready":false,"color":3,"skin":1}]]},"pinecrest",true,{"pinecrest":2},"pinecrest"],"ch":0,"rel":true,"mode":2}
+  5.671s C→S binary 32 bytes
len 20 00 00 00   (raw TCP prefix: 32 bytes)
0000 03 02 00 03 00 4e 65 74 0e 5f 72 65 71 75 65 73
0010 74 5f 72 65 61 64 79 01 01 00 00 00 01 00 00 00
     = {"t":"rpc","node":"Net","method":"_request_ready","args":[true],"ch":0,"rel":true}
+  5.692s S→C binary 338 bytes
len 52 01 00 00   (raw TCP prefix: 338 bytes)
0000 03 02 00 03 00 4e 65 74 0c 5f 70 75 73 68 5f 72
0010 6f 73 74 65 72 05 1b 00 00 00 02 00 00 00 02 00
0020 00 00 02 00 00 00 1b 00 00 00 04 00 00 00 04 00
0030 00 00 04 00 00 00 6e 61 6d 65 04 00 00 00 08 00
0040 00 00 54 68 69 6e 20 42 6f 74 04 00 00 00 05 00
0050 00 00 72 65 61 64 79 00 00 00 01 00 00 00 01 00
0060 00 00 04 00 00 00 05 00 00 00 63 6f 6c 6f 72 00
0070 00 00 02 00 00 00 00 00 00 00 04 00 00 00 04 00
     … (hex truncated)
     = {"t":"rpc","node":"Net","method":"_push_roster","args":[{"_t":"dict","v":[[2,{"name":"Thin Bot","ready":true,"color":0,"skin":0}],[234289745,{"name":"Full Bot","ready":true,"color":3,"skin":1}]]},"pinecrest",true,{"pinecrest":2},"pinecrest"],"ch":0,"rel":true,"mode":2}
+  5.692s S→C binary 338 bytes
len 52 01 00 00   (raw TCP prefix: 338 bytes)
0000 03 02 00 03 00 4e 65 74 0c 5f 70 75 73 68 5f 72
0010 6f 73 74 65 72 05 1b 00 00 00 02 00 00 00 02 00
0020 00 00 02 00 00 00 1b 00 00 00 04 00 00 00 04 00
0030 00 00 04 00 00 00 6e 61 6d 65 04 00 00 00 08 00
0040 00 00 54 68 69 6e 20 42 6f 74 04 00 00 00 05 00
0050 00 00 72 65 61 64 79 00 00 00 01 00 00 00 00 00
0060 00 00 04 00 00 00 05 00 00 00 63 6f 6c 6f 72 00
0070 00 00 02 00 00 00 00 00 00 00 04 00 00 00 04 00
     … (hex truncated)
     = {"t":"rpc","node":"Net","method":"_push_roster","args":[{"_t":"dict","v":[[2,{"name":"Thin Bot","ready":false,"color":0,"skin":0}],[234289745,{"name":"Full Bot","ready":false,"color":3,"skin":1}]]},"pinecrest",true,{"pinecrest":2},"pinecrest"],"ch":0,"rel":true,"mode":2}
```

Repeats not shown in this section: 1× `S→C _rtt_ping`, 1× `C→S _rtt_pong`.

## Run start and catch-up burst

> Run starts on this concrete map id: load the level, build `Main/Players/P_<id>` for every roster peer, then `_report_in_run(true)` (spec-full §5).

```text
+  5.692s S→C binary 40 bytes
len 28 00 00 00   (raw TCP prefix: 40 bytes)
0000 03 02 00 03 00 4e 65 74 0a 5f 73 74 61 72 74 5f
0010 72 75 6e 01 04 00 00 00 09 00 00 00 70 69 6e 65
0020 63 72 65 73 74 00 00 00
     = {"t":"rpc","node":"Net","method":"_start_run","args":["pinecrest"],"ch":0,"rel":true,"mode":2}
```
> Client finished loading (`true`) or unloaded the run scene (`false`).

```text
+  5.692s C→S binary 32 bytes
len 20 00 00 00   (raw TCP prefix: 32 bytes)
0000 03 02 00 03 00 4e 65 74 0e 5f 72 65 70 6f 72 74
0010 5f 69 6e 5f 72 75 6e 01 01 00 00 00 01 00 00 00
     = {"t":"rpc","node":"Net","method":"_report_in_run","args":[true],"ch":0,"rel":true}
+  6.488s S→C binary 39 bytes
len 27 00 00 00   (raw TCP prefix: 39 bytes)
0000 03 00 00 03 00 4e 65 74 09 5f 72 74 74 5f 70 69
0010 6e 67 02 02 00 00 00 06 00 00 00 03 00 01 00 4b
0020 37 89 41 60 65 34 40
     = {"t":"rpc","node":"Net","method":"_rtt_ping","args":[6,20.395999999999997],"ch":0,"rel":false,"mode":0}
+  6.489s C→S binary 27 bytes
len 1b 00 00 00   (raw TCP prefix: 27 bytes)
0000 03 00 00 03 00 4e 65 74 09 5f 72 74 74 5f 70 6f
0010 6e 67 01 02 00 00 00 06 00 00 00
     = {"t":"rpc","node":"Net","method":"_rtt_pong","args":[6],"ch":0,"rel":false}
```
> Catch-up #1: endless-tape state (choice pending, endless, victory locked).

```text
+  9.063s S→C binary 58 bytes
len 3a 00 00 00   (raw TCP prefix: 58 bytes)
0000 03 02 00 0b 00 47 61 6d 65 4d 61 6e 61 67 65 72
0010 10 5f 73 79 6e 63 5f 74 61 70 65 5f 73 74 61 74
0020 65 03 01 00 00 00 00 00 00 00 01 00 00 00 00 00
0030 00 00 01 00 00 00 00 00 00 00
     = {"t":"rpc","node":"GameManager","method":"_sync_tape_state","args":[false,false,false],"ch":0,"rel":true,"mode":2}
+  9.063s S→C binary 45 bytes
len 2d 00 00 00   (raw TCP prefix: 45 bytes)
0000 03 02 00 18 00 47 61 6d 65 4d 61 6e 61 67 65 72
0010 2f 4d 75 74 61 74 69 6f 6e 52 6f 6c 6c 0e 5f 72
0020 65 73 65 74 5f 72 75 6e 5f 72 70 63 00
     = {"t":"rpc","node":"GameManager/MutationRoll","method":"_reset_run_rpc","args":[],"ch":0,"rel":true,"mode":2}
```
> Shared decon charge pool.

```text
+  9.064s S→C binary 37 bytes
len 25 00 00 00   (raw TCP prefix: 37 bytes)
0000 03 02 00 0b 00 47 61 6d 65 4d 61 6e 61 67 65 72
0010 0b 5f 73 79 6e 63 5f 64 65 63 6f 6e 01 02 00 00
0020 00 05 00 00 00
     = {"t":"rpc","node":"GameManager","method":"_sync_decon","args":[5],"ch":0,"rel":true,"mode":2}
```
> Storm intensity override (-1 = none).

```text
+  9.065s S→C binary 38 bytes
len 26 00 00 00   (raw TCP prefix: 38 bytes)
0000 03 02 00 0e 00 57 65 61 74 68 65 72 4d 61 6e 61
0010 67 65 72 09 5f 6f 76 65 72 72 69 64 65 01 03 00
0020 00 00 00 00 80 bf
     = {"t":"rpc","node":"WeatherManager","method":"_override","args":[-1.0],"ch":0,"rel":true,"mode":2}
```
> Phase change: `[phase enum, wave, seconds_left]`. Count down locally (client-responsibilities §Weather).

```text
+  9.065s S→C binary 59 bytes
len 3b 00 00 00   (raw TCP prefix: 59 bytes)
0000 03 02 00 0e 00 57 65 61 74 68 65 72 4d 61 6e 61
0010 67 65 72 0e 5f 72 65 63 65 69 76 65 5f 70 68 61
0020 73 65 03 02 00 00 00 00 00 00 00 02 00 00 00 01
0030 00 00 00 03 00 00 00 00 00 40 41
     = {"t":"rpc","node":"WeatherManager","method":"_receive_phase","args":[0,1,12.0],"ch":0,"rel":true,"mode":2}
+  9.066s S→C binary 58 bytes
len 3a 00 00 00   (raw TCP prefix: 58 bytes)
0000 03 02 00 0b 00 47 61 6d 65 4d 61 6e 61 67 65 72
0010 10 5f 73 79 6e 63 5f 74 61 70 65 5f 73 74 61 74
0020 65 03 01 00 00 00 00 00 00 00 01 00 00 00 00 00
0030 00 00 01 00 00 00 00 00 00 00
     = {"t":"rpc","node":"GameManager","method":"_sync_tape_state","args":[false,false,false],"ch":0,"rel":true,"mode":2}
+  9.066s S→C binary 59 bytes
len 3b 00 00 00   (raw TCP prefix: 59 bytes)
0000 03 02 00 0e 00 57 65 61 74 68 65 72 4d 61 6e 61
0010 67 65 72 0e 5f 72 65 63 65 69 76 65 5f 70 68 61
0020 73 65 03 02 00 00 00 00 00 00 00 02 00 00 00 01
0030 00 00 00 03 00 00 00 00 00 40 41
     = {"t":"rpc","node":"WeatherManager","method":"_receive_phase","args":[0,1,12.0],"ch":0,"rel":true,"mode":2}
```
> Catch-up only: current smoothed storm intensity.

```text
+  9.066s S→C binary 47 bytes
len 2f 00 00 00   (raw TCP prefix: 47 bytes)
0000 03 02 00 0e 00 57 65 61 74 68 65 72 4d 61 6e 61
0010 67 65 72 12 5f 72 65 63 65 69 76 65 5f 69 6e 74
0020 65 6e 73 69 74 79 01 03 00 00 00 00 00 00 00
     = {"t":"rpc","node":"WeatherManager","method":"_receive_intensity","args":[0.0],"ch":0,"rel":true,"mode":2}
+  9.066s S→C binary 38 bytes
len 26 00 00 00   (raw TCP prefix: 38 bytes)
0000 03 02 00 0e 00 57 65 61 74 68 65 72 4d 61 6e 61
0010 67 65 72 09 5f 6f 76 65 72 72 69 64 65 01 03 00
0020 00 00 00 00 80 bf
     = {"t":"rpc","node":"WeatherManager","method":"_override","args":[-1.0],"ch":0,"rel":true,"mode":2}
+  9.066s S→C binary 37 bytes
len 25 00 00 00   (raw TCP prefix: 37 bytes)
0000 03 02 00 0b 00 47 61 6d 65 4d 61 6e 61 67 65 72
0010 0b 5f 73 79 6e 63 5f 64 65 63 6f 6e 01 02 00 00
0020 00 05 00 00 00
     = {"t":"rpc","node":"GameManager","method":"_sync_decon","args":[5],"ch":0,"rel":true,"mode":2}
```
> Active enemy/player mutation id lists (typed `Array[String]` in binary!).

```text
+  9.066s S→C binary 67 bytes
len 43 00 00 00   (raw TCP prefix: 67 bytes)
0000 03 02 00 18 00 47 61 6d 65 4d 61 6e 61 67 65 72
0010 2f 4d 75 74 61 74 69 6f 6e 52 6f 6c 6c 0c 5f 73
0020 79 6e 63 5f 61 63 74 69 76 65 02 1c 00 01 00 04
0030 00 00 00 00 00 00 00 1c 00 01 00 04 00 00 00 00
0040 00 00 00
     = {"t":"rpc","node":"GameManager/MutationRoll","method":"_sync_active","args":[[],[]],"ch":0,"rel":true,"mode":2}
```
> Vending cabinets `{key: [[item,tier,price,offer_serial],...]}` and airdrop.

```text
+  9.066s S→C binary 636 bytes
len 7c 02 00 00   (raw TCP prefix: 636 bytes)
0000 03 02 00 18 00 47 61 6d 65 4d 61 6e 61 67 65 72
0010 2f 43 72 61 74 65 4d 61 6e 61 67 65 72 09 5f 73
0020 6e 61 70 73 68 6f 74 03 02 00 00 00 01 00 00 00
0030 1b 00 00 00 03 00 00 00 04 00 00 00 0f 00 00 00
0040 48 61 72 64 77 61 72 65 53 74 61 74 69 6f 6e 00
0050 1c 00 00 00 03 00 00 00 1c 00 00 00 04 00 00 00
0060 04 00 00 00 04 00 00 00 66 72 61 67 02 00 00 00
0070 00 00 00 00 02 00 00 00 06 00 00 00 02 00 00 00
0080 01 00 00 00 1c 00 00 00 04 00 00 00 04 00 00 00
0090 0b 00 00 00 73 70 72 61 79 5f 72 69 66 6c 65 00
00a0 02 00 00 00 00 00 00 00 02 00 00 00 0b 00 00 00
00b0 02 00 00 00 02 00 00 00 1c 00 00 00 04 00 00 00
00c0 04 00 00 00 0d 00 00 00 6c 69 67 68 74 6e 69 6e
00d0 67 5f 72 6f 64 00 00 00 02 00 00 00 01 00 00 00
00e0 02 00 00 00 12 00 00 00 02 00 00 00 03 00 00 00
00f0 04 00 00 00 11 00 00 00 47 61 73 53 74 61 74 69
0100 6f 6e 53 75 72 70 6c 75 73 00 00 00 1c 00 00 00
0110 03 00 00 00 1c 00 00 00 04 00 00 00 04 00 00 00
0120 0b 00 00 00 73 68 69 65 6c 64 5f 64 6f 6d 65 00
0130 02 00 00 00 00 00 00 00 02 00 00 00 06 00 00 00
0140 02 00 00 00 04 00 00 00 1c 00 00 00 04 00 00 00
0150 04 00 00 00 0b 00 00 00 6e 61 69 6c 5f 64 72 69
0160 76 65 72 00 02 00 00 00 00 00 00 00 02 00 00 00
0170 0b 00 00 00 02 00 00 00 05 00 00 00 1c 00 00 00
0180 04 00 00 00 04 00 00 00 0e 00 00 00 62 61 74 74
0190 65 72 79 5f 7a 61 70 70 65 72 00 00 02 00 00 00
01a0 01 00 00 00 02 00 00 00 12 00 00 00 02 00 00 00
01b0 06 00 00 00 04 00 00 00 11 00 00 00 54 6f 77 6e
01c0 53 71 75 61 72 65 53 74 61 74 69 6f 6e 00 00 00
01d0 1c 00 00 00 03 00 00 00 1c 00 00 00 04 00 00 00
01e0 04 00 00 00 07 00 00 00 6d 65 64 5f 74 69 6e 00
01f0 02 00 00 00 00 00 00 00 02 00 00 00 06 00 00 00
0200 02 00 00 00 07 00 00 00 1c 00 00 00 04 00 00 00
0210 04 00 00 00 0c 00 00 00 70 75 6d 70 5f 73 68 6f
0220 74 67 75 6e 02 00 00 00 00 00 00 00 02 00 00 00
0230 0b 00 00 00 02 00 00 00 08 00 00 00 1c 00 00 00
0240 04 00 00 00 04 00 00 00 0e 00 00 00 66 6c 61 72
0250 65 5f 6c 61 75 6e 63 68 65 72 00 00 02 00 00 00
0260 01 00 00 00 02 00 00 00 12 00 00 00 02 00 00 00
0270 09 00 00 00 1c 00 00 00 00 00 00 00
     = {"t":"rpc","node":"GameManager/CrateManager","method":"_snapshot","args":[1,{"HardwareStation":[["frag",0,6,1],["spray_rifle",0,11,2],["lightning_rod",1,18,3]],"GasStationSurplus":[["shield_dome",0,6,4],["nail_driver",0,11,5],["battery_zapper",1,18,6]],"TownSquareStation":[["med_tin",0,6,7],["pump_shotgun",0,11,8],["flare_launcher",1,18,9]]},[]],"ch":0,"rel":true,"mode":2}
```
> Wave progress for the HUD at ~3.6 Hz: wave, remaining, total, recovery, endless score.

```text
+  9.067s S→C binary 77 bytes
len 4d 00 00 00   (raw TCP prefix: 77 bytes)
0000 03 01 00 0c 00 4d 61 69 6e 2f 45 6e 65 6d 69 65
0010 73 0e 5f 73 79 6e 63 5f 70 72 6f 67 72 65 73 73
0020 05 02 00 00 00 01 00 00 00 02 00 00 00 2a 00 00
0030 00 02 00 00 00 2a 00 00 00 03 00 01 00 cd cc cc
0040 cc cc cc 00 40 02 00 00 00 00 00 00 00
     = {"t":"rpc","node":"Main/Enemies","method":"_sync_progress","args":[1,42,42,2.1,0],"ch":0,"rel":false,"mode":1}
```
> Puddle growth keyed by *absolute* NodePath (`{"_t":"dict"}` form).

```text
+  9.067s S→C binary 1162 bytes
len 8a 04 00 00   (raw TCP prefix: 1162 bytes)
0000 03 02 00 0e 00 57 65 61 74 68 65 72 4d 61 6e 61
0010 67 65 72 0d 5f 73 79 6e 63 5f 70 75 64 64 6c 65
0020 73 01 1b 00 00 00 0f 00 00 00 16 00 00 00 05 00
0030 00 80 00 00 00 00 01 00 00 00 04 00 00 00 72 6f
0040 6f 74 04 00 00 00 4d 61 69 6e 05 00 00 00 4c 65
0050 76 65 6c 00 00 00 07 00 00 00 50 75 64 64 6c 65
0060 73 00 05 00 00 00 4d 61 69 6e 57 00 00 00 03 00
0070 00 00 00 00 00 00 16 00 00 00 05 00 00 80 00 00
0080 00 00 01 00 00 00 04 00 00 00 72 6f 6f 74 04 00
0090 00 00 4d 61 69 6e 05 00 00 00 4c 65 76 65 6c 00
00a0 00 00 07 00 00 00 50 75 64 64 6c 65 73 00 05 00
00b0 00 00 4d 61 69 6e 43 00 00 00 03 00 00 00 00 00
00c0 00 00 16 00 00 00 05 00 00 80 00 00 00 00 01 00
00d0 00 00 04 00 00 00 72 6f 6f 74 04 00 00 00 4d 61
00e0 69 6e 05 00 00 00 4c 65 76 65 6c 00 00 00 07 00
00f0 00 00 50 75 64 64 6c 65 73 00 05 00 00 00 4d 61
0100 69 6e 45 00 00 00 03 00 00 00 00 00 00 00 16 00
0110 00 00 05 00 00 80 00 00 00 00 01 00 00 00 04 00
0120 00 00 72 6f 6f 74 04 00 00 00 4d 61 69 6e 05 00
0130 00 00 4c 65 76 65 6c 00 00 00 07 00 00 00 50 75
0140 64 64 6c 65 73 00 08 00 00 00 4d 61 69 6e 46 61
0150 72 45 03 00 00 00 00 00 00 00 16 00 00 00 05 00
0160 00 80 00 00 00 00 01 00 00 00 04 00 00 00 72 6f
0170 6f 74 04 00 00 00 4d 61 69 6e 05 00 00 00 4c 65
0180 76 65 6c 00 00 00 07 00 00 00 50 75 64 64 6c 65
0190 73 00 04 00 00 00 4c 61 6e 65 03 00 00 00 00 00
01a0 00 00 16 00 00 00 05 00 00 80 00 00 00 00 01 00
01b0 00 00 04 00 00 00 72 6f 6f 74 04 00 00 00 4d 61
01c0 69 6e 05 00 00 00 4c 65 76 65 6c 00 00 00 07 00
01d0 00 00 50 75 64 64 6c 65 73 00 07 00 00 00 43 69
01e0 72 63 6c 65 57 00 03 00 00 00 00 00 00 00 16 00
01f0 00 00 05 00 00 80 00 00 00 00 01 00 00 00 04 00
0200 00 00 72 6f 6f 74 04 00 00 00 4d 61 69 6e 05 00
0210 00 00 4c 65 76 65 6c 00 00 00 07 00 00 00 50 75
0220 64 64 6c 65 73 00 07 00 00 00 43 69 72 63 6c 65
0230 45 00 03 00 00 00 00 00 00 00 16 00 00 00 05 00
0240 00 80 00 00 00 00 01 00 00 00 04 00 00 00 72 6f
0250 6f 74 04 00 00 00 4d 61 69 6e 05 00 00 00 4c 65
0260 76 65 6c 00 00 00 07 00 00 00 50 75 64 64 6c 65
0270 73 00 04 00 00 00 4c 6f 74 57 03 00 00 00 00 00
0280 00 00 16 00 00 00 05 00 00 80 00 00 00 00 01 00
0290 00 00 04 00 00 00 72 6f 6f 74 04 00 00 00 4d 61
02a0 69 6e 05 00 00 00 4c 65 76 65 6c 00 00 00 07 00
02b0 00 00 50 75 64 64 6c 65 73 00 04 00 00 00 4c 6f
02c0 74 43 03 00 00 00 00 00 00 00 16 00 00 00 05 00
02d0 00 80 00 00 00 00 01 00 00 00 04 00 00 00 72 6f
02e0 6f 74 04 00 00 00 4d 61 69 6e 05 00 00 00 4c 65
02f0 76 65 6c 00 00 00 07 00 00 00 50 75 64 64 6c 65
0300 73 00 04 00 00 00 4c 6f 74 45 03 00 00 00 00 00
0310 00 00 16 00 00 00 05 00 00 80 00 00 00 00 01 00
0320 00 00 04 00 00 00 72 6f 6f 74 04 00 00 00 4d 61
0330 69 6e 05 00 00 00 4c 65 76 65 6c 00 00 00 07 00
0340 00 00 50 75 64 64 6c 65 73 00 06 00 00 00 53 71
0350 75 61 72 65 00 00 03 00 00 00 00 00 00 00 16 00
0360 00 00 05 00 00 80 00 00 00 00 01 00 00 00 04 00
0370 00 00 72 6f 6f 74 04 00 00 00 4d 61 69 6e 05 00
0380 00 00 4c 65 76 65 6c 00 00 00 07 00 00 00 50 75
0390 64 64 6c 65 73 00 03 00 00 00 47 61 73 00 03 00
03a0 00 00 00 00 00 00 16 00 00 00 05 00 00 80 00 00
03b0 00 00 01 00 00 00 04 00 00 00 72 6f 6f 74 04 00
03c0 00 00 4d 61 69 6e 05 00 00 00 4c 65 76 65 6c 00
03d0 00 00 07 00 00 00 50 75 64 64 6c 65 73 00 04 00
03e0 00 00 50 61 72 6b 03 00 00 00 00 00 00 00 16 00
03f0 00 00 05 00 00 80 00 00 00 00 01 00 00 00 04 00
0400 00 00 72 6f 6f 74 04 00 00 00 4d 61 69 6e 05 00
0410 00 00 4c 65 76 65 6c 00 00 00 07 00 00 00 50 75
0420 64 64 6c 65 73 00 09 00 00 00 42 61 63 6b 79 61
0430 72 64 73 00 00 00 03 00 00 00 00 00 00 00 16 00
0440 00 00 05 00 00 80 00 00 00 00 01 00 00 00 04 00
0450 00 00 72 6f 6f 74 04 00 00 00 4d 61 69 6e 05 00
0460 00 00 4c 65 76 65 6c 00 00 00 07 00 00 00 50 75
0470 64 64 6c 65 73 00 05 00 00 00 41 6c 6c 65 79 00
0480 00 00 03 00 00 00 00 00 00 00
     = {"t":"rpc","node":"WeatherManager","method":"_sync_puddles","args":[{"_t":"dict","v":[[{"_t":"np","v":"/root/Main/Level/Puddles/MainW"},0.0],[{"_t":"np","v":"/root/Main/Level/Puddles/MainC"},0.0],[{"_t":"np","v":"/root/Main/Level/Puddles/MainE"},0.0],[{"_t":"np","v":"/root/Main/Level/Puddles/MainFarE"},0.0],[{"_t":"np","v":"/root/Main/Level/Puddles/Lane"},0.0],[{"_t":"np","v":"/root/Main/Level/Puddles/CircleW"},0.0],[{"_t":"np","v":"/root/Main/Level/Puddles/CircleE"},0.0],[{"_t":"np","v":"/root/Main/Level/Puddles/LotW"},0.0],[{"_t":"np","v":"/root/Main/Level/Puddles/LotC"},0.0],[{"_t":"np","v":"/root/Main/Level/Puddles/LotE"},0.0],[{"_t":"np","v":"/root/Main/Level/Puddles/Square"},0.0],[{"_t":"np","v":"/root/Main/Level/Puddles/Gas"},0.0],[{"_t":"np","v":"/root/Main/Level/Puddles/Park"},0.0],[{"_t":"np","v":"/root/Main/Level/Puddles/Backyards"},0.0],[{"_t":"np","v":"/root/Main/Level/Puddles/Alley"},0.0]]}],"ch":0,"rel":true,"mode":2}
```
> World pickups/effects snapshot; arg0 is the `run_id` for RPCs with a `run` argument.

```text
+  9.068s S→C binary 72 bytes
len 48 00 00 00   (raw TCP prefix: 72 bytes)
0000 03 02 00 0c 00 4d 61 69 6e 2f 52 75 6e 4c 6f 6f
0010 74 09 5f 73 6e 61 70 73 68 6f 74 05 02 00 00 00
0020 01 00 00 00 1c 00 00 00 00 00 00 00 1c 00 00 00
0030 00 00 00 00 1c 00 01 00 04 00 00 00 00 00 00 00
0040 01 00 00 00 00 00 00 00
     = {"t":"rpc","node":"Main/RunLoot","method":"_snapshot","args":[1,[],[],[],false],"ch":0,"rel":true,"mode":2}
```
> Public held item per player (relayed to everyone including the owner).

```text
+  9.069s S→C binary 110 bytes
len 6e 00 00 00   (raw TCP prefix: 110 bytes)
0000 03 02 00 2b 00 4d 61 69 6e 2f 50 6c 61 79 65 72
0010 73 2f 50 5f 32 2f 48 65 61 64 2f 43 61 6d 65 72
0020 61 33 44 2f 57 65 61 70 6f 6e 48 6f 6c 64 65 72
0030 0c 5f 65 71 75 69 70 5f 73 74 61 74 65 06 02 00
0040 00 00 01 00 00 00 02 00 00 00 01 00 00 00 04 00
0050 00 00 00 00 00 00 02 00 00 00 00 00 00 00 03 00
0060 00 00 00 00 00 00 03 00 00 00 00 00 80 3f
     = {"t":"rpc","node":"Main/Players/P_2/Head/Camera3D/WeaponHolder","method":"_equip_state","args":[1,1,"",0,0.0,1.0],"ch":0,"rel":true,"mode":2}
+  9.069s S→C binary 118 bytes
len 76 00 00 00   (raw TCP prefix: 118 bytes)
0000 03 02 00 33 00 4d 61 69 6e 2f 50 6c 61 79 65 72
0010 73 2f 50 5f 32 33 34 32 38 39 37 34 35 2f 48 65
0020 61 64 2f 43 61 6d 65 72 61 33 44 2f 57 65 61 70
0030 6f 6e 48 6f 6c 64 65 72 0c 5f 65 71 75 69 70 5f
0040 73 74 61 74 65 06 02 00 00 00 01 00 00 00 02 00
0050 00 00 01 00 00 00 04 00 00 00 00 00 00 00 02 00
0060 00 00 00 00 00 00 03 00 00 00 00 00 00 00 03 00
0070 00 00 00 00 80 3f
     = {"t":"rpc","node":"Main/Players/P_234289745/Head/Camera3D/WeaponHolder","method":"_equip_state","args":[1,1,"",0,0.0,1.0],"ch":0,"rel":true,"mode":2}
```
> Owner-only authoritative inventory; drop updates with `rev <= last` (client-responsibilities §Inventory).

```text
+  9.069s S→C binary 216 bytes
len d8 00 00 00   (raw TCP prefix: 216 bytes)
0000 03 02 00 33 00 4d 61 69 6e 2f 50 6c 61 79 65 72
0010 73 2f 50 5f 32 33 34 32 38 39 37 34 35 2f 48 65
0020 61 64 2f 43 61 6d 65 72 61 33 44 2f 57 65 61 70
0030 6f 6e 48 6f 6c 64 65 72 0e 5f 70 72 69 76 61 74
0040 65 5f 73 74 61 74 65 0d 02 00 00 00 01 00 00 00
0050 02 00 00 00 01 00 00 00 1c 00 00 00 05 00 00 00
0060 1c 00 00 00 00 00 00 00 1c 00 00 00 00 00 00 00
0070 1c 00 00 00 00 00 00 00 1c 00 00 00 00 00 00 00
0080 1c 00 00 00 00 00 00 00 1b 00 00 00 00 00 00 00
0090 02 00 00 00 00 00 00 00 04 00 00 00 00 00 00 00
00a0 02 00 00 00 00 00 00 00 02 00 00 00 00 00 00 00
00b0 02 00 00 00 00 00 00 00 03 00 00 00 00 00 00 00
00c0 03 00 00 00 00 00 80 3f 03 00 00 00 00 00 00 00
00d0 03 00 00 00 00 00 00 00
     = {"t":"rpc","node":"Main/Players/P_234289745/Head/Camera3D/WeaponHolder","method":"_private_state","args":[1,1,[[],[],[],[],[]],{},0,"",0,0,0,0.0,1.0,0.0,0.0],"ch":0,"rel":true,"mode":2}
```
> Last frame of the catch-up burst. Only now may run-scoped RPCs be sent (spec-full §5).

```text
+  9.069s S→C binary 28 bytes
len 1c 00 00 00   (raw TCP prefix: 28 bytes)
0000 03 02 00 03 00 4e 65 74 12 5f 63 6f 6e 66 69 72
0010 6d 5f 72 75 6e 5f 72 65 61 64 79 00
     = {"t":"rpc","node":"Net","method":"_confirm_run_ready","args":[],"ch":0,"rel":true,"mode":2}
```
> Owner-reported shelter/puddle state; the host trusts it for acid drain (client-responsibilities §Exposure).

```text
+  9.069s C→S binary 63 bytes
len 3f 00 00 00   (raw TCP prefix: 63 bytes)
0000 03 02 00 18 00 4d 61 69 6e 2f 50 6c 61 79 65 72
0010 73 2f 50 5f 32 33 34 32 38 39 37 34 35 10 5f 72
0020 65 70 6f 72 74 5f 65 78 70 6f 73 75 72 65 02 01
0030 00 00 00 00 00 00 00 01 00 00 00 00 00 00 00
     = {"t":"rpc","node":"Main/Players/P_234289745","method":"_report_exposure","args":[false,false],"ch":0,"rel":true}
```
> Pick a starter kit (0 pump_shotgun, 1 nail_driver, 2 service_revolver).

```text
+  9.069s C→S binary 51 bytes
len 33 00 00 00   (raw TCP prefix: 51 bytes)
0000 03 02 00 0c 00 4d 61 69 6e 2f 52 75 6e 4c 6f 6f
0010 74 10 5f 72 65 71 75 65 73 74 5f 73 74 61 72 74
0020 65 72 02 02 00 00 00 01 00 00 00 02 00 00 00 01
0030 00 00 00
     = {"t":"rpc","node":"Main/RunLoot","method":"_request_starter","args":[1,1],"ch":0,"rel":true}
```
> Host relay of a player's transform to every run peer, *including the owner* (ignore your own).

```text
+  9.071s S→C binary 87 bytes
len 57 00 00 00   (raw TCP prefix: 87 bytes)
0000 03 01 00 10 00 4d 61 69 6e 2f 50 6c 61 79 65 72
0010 73 2f 50 5f 32 10 5f 72 65 6c 61 79 5f 74 72 61
0020 6e 73 66 6f 72 6d 04 09 00 00 00 00 00 00 c0 da
0030 af 75 3d 00 00 00 3f 03 00 00 00 00 00 00 00 03
0040 00 00 00 00 00 00 80 09 00 00 00 00 00 00 00 00
0050 00 00 00 00 00 00 00
     = {"t":"rpc","node":"Main/Players/P_2","method":"_relay_transform","args":[{"_t":"v3","v":[-2.0,0.05998215824365616,0.5]},0.0,-0.0,{"_t":"v3","v":[0.0,0.0,0.0]}],"ch":0,"rel":false,"mode":1}
```
> Host-owned vitals at 5 Hz: hp, suit, state, bleed, tarp, max_hp, static charge, invulnerable.

```text
+  9.071s S→C binary 104 bytes
len 68 00 00 00   (raw TCP prefix: 104 bytes)
0000 03 01 00 10 00 4d 61 69 6e 2f 50 6c 61 79 65 72
0010 73 2f 50 5f 32 0d 5f 61 70 70 6c 79 5f 76 69 74
0020 61 6c 73 08 03 00 00 00 00 00 c8 42 03 00 00 00
0030 00 00 c8 42 04 00 00 00 02 00 00 00 6f 6b 00 00
0040 03 00 00 00 00 00 00 00 01 00 00 00 00 00 00 00
0050 03 00 00 00 00 00 c8 42 03 00 00 00 00 00 00 00
0060 01 00 00 00 00 00 00 00
     = {"t":"rpc","node":"Main/Players/P_2","method":"_apply_vitals","args":[100.0,100.0,"ok",0.0,false,100.0,0.0,false],"ch":0,"rel":false,"mode":1}
+  9.072s S→C binary 112 bytes
len 70 00 00 00   (raw TCP prefix: 112 bytes)
0000 03 01 00 18 00 4d 61 69 6e 2f 50 6c 61 79 65 72
0010 73 2f 50 5f 32 33 34 32 38 39 37 34 35 0d 5f 61
0020 70 70 6c 79 5f 76 69 74 61 6c 73 08 03 00 00 00
0030 00 00 c8 42 03 00 00 00 00 00 c8 42 04 00 00 00
0040 02 00 00 00 6f 6b 00 00 03 00 00 00 00 00 00 00
0050 01 00 00 00 00 00 00 00 03 00 00 00 00 00 c8 42
0060 03 00 00 00 00 00 00 00 01 00 00 00 00 00 00 00
     = {"t":"rpc","node":"Main/Players/P_234289745","method":"_apply_vitals","args":[100.0,100.0,"ok",0.0,false,100.0,0.0,false],"ch":0,"rel":false,"mode":1}
+  9.073s S→C binary 77 bytes
len 4d 00 00 00   (raw TCP prefix: 77 bytes)
0000 03 01 00 0c 00 4d 61 69 6e 2f 45 6e 65 6d 69 65
0010 73 0e 5f 73 79 6e 63 5f 70 72 6f 67 72 65 73 73
0020 05 02 00 00 00 01 00 00 00 02 00 00 00 2a 00 00
0030 00 02 00 00 00 2a 00 00 00 03 00 01 00 cd cc cc
0040 cc cc cc 00 40 02 00 00 00 00 00 00 00
     = {"t":"rpc","node":"Main/Enemies","method":"_sync_progress","args":[1,42,42,2.1,0],"ch":0,"rel":false,"mode":1}
+  9.074s S→C binary 280 bytes
len 18 01 00 00   (raw TCP prefix: 280 bytes)
0000 03 02 00 33 00 4d 61 69 6e 2f 50 6c 61 79 65 72
0010 73 2f 50 5f 32 33 34 32 38 39 37 34 35 2f 48 65
0020 61 64 2f 43 61 6d 65 72 61 33 44 2f 57 65 61 70
0030 6f 6e 48 6f 6c 64 65 72 0e 5f 70 72 69 76 61 74
0040 65 5f 73 74 61 74 65 0d 02 00 00 00 01 00 00 00
0050 02 00 00 00 02 00 00 00 1c 00 00 00 05 00 00 00
0060 1c 00 00 00 04 00 00 00 02 00 00 00 02 00 00 00
0070 04 00 00 00 0b 00 00 00 6e 61 69 6c 5f 64 72 69
     … (hex truncated)
     = {"t":"rpc","node":"Main/Players/P_234289745/Head/Camera3D/WeaponHolder","method":"_private_state","args":[1,2,[[2,"nail_driver",0,24],[],[],[],[]],{"nail":60},0,"",0,2,1,0.0,1.0,0.0,0.0],"ch":0,"rel":true,"mode":2}
```
> Starter kit granted.

```text
+  9.074s S→C binary 44 bytes
len 2c 00 00 00   (raw TCP prefix: 44 bytes)
0000 03 02 00 0c 00 4d 61 69 6e 2f 52 75 6e 4c 6f 6f
0010 74 11 5f 73 74 61 72 74 65 72 5f 61 63 63 65 70
0020 74 65 64 01 02 00 00 00 01 00 00 00
     = {"t":"rpc","node":"Main/RunLoot","method":"_starter_accepted","args":[1],"ch":0,"rel":true,"mode":2}
```
> Skip the rest of Calm/Clearing (counts toward the all-ready threshold).

```text
+  9.086s C→S binary 32 bytes
len 20 00 00 00   (raw TCP prefix: 32 bytes)
0000 03 02 00 0b 00 47 61 6d 65 4d 61 6e 61 67 65 72
0010 0e 5f 72 65 71 75 65 73 74 5f 72 65 61 64 79 00
     = {"t":"rpc","node":"GameManager","method":"_request_ready","args":[],"ch":0,"rel":true}
```
> Owner transform at 20 Hz, unreliable-ordered (client-responsibilities §Movement).

```text
+  9.086s C→S binary 98 bytes
len 62 00 00 00   (raw TCP prefix: 98 bytes)
0000 03 01 00 18 00 4d 61 69 6e 2f 50 6c 61 79 65 72
0010 73 2f 50 5f 32 33 34 32 38 39 37 34 35 0f 5f 70
0020 75 73 68 5f 74 72 61 6e 73 66 6f 72 6d 04 09 00
0030 00 00 49 e1 5f 40 00 00 00 00 27 31 13 3f 03 00
0040 01 00 e5 f9 10 21 c8 ee f9 bf 03 00 00 00 00 00
0050 00 00 09 00 00 00 37 b3 ef 41 00 00 00 00 86 eb
0060 bf 3f
     = {"t":"rpc","node":"Main/Players/P_234289745","method":"_push_transform","args":[{"_t":"v3","v":[3.4981253905924494,0.0,0.5749687539060175]},-1.6207963267948966,0.0,{"_t":"v3","v":[29.962507811848987,0.0,1.4993750781203508]}],"ch":0,"rel":false}
+  9.102s C→S binary 98 bytes
len 62 00 00 00   (raw TCP prefix: 98 bytes)
0000 03 01 00 18 00 4d 61 69 6e 2f 50 6c 61 79 65 72
0010 73 2f 50 5f 32 33 34 32 38 39 37 34 35 0f 5f 70
0020 75 73 68 5f 74 72 61 6e 73 66 6f 72 6d 04 09 00
0030 00 00 39 85 5f 40 00 00 00 00 06 56 26 3f 03 00
0040 01 00 7a 93 aa ba 61 88 08 40 03 00 00 00 00 00
0050 00 00 09 00 00 00 fb 28 e6 bd 00 00 00 00 b8 70
0060 bf 3f
     = {"t":"rpc","node":"Main/Players/P_234289745","method":"_push_transform","args":[{"_t":"v3","v":[3.4925062479170386,0.0,0.6497501249702422]},3.066592653589791,0.0,{"_t":"v3","v":[-0.1123828535082172,0.0,1.4956274212844933]}],"ch":0,"rel":false}
```
> Ready-up tally `[count, needed]` (broadcast).

```text
+  9.105s S→C binary 48 bytes
len 30 00 00 00   (raw TCP prefix: 48 bytes)
0000 03 02 00 0b 00 47 61 6d 65 4d 61 6e 61 67 65 72
0010 0e 5f 72 65 61 64 79 5f 63 68 61 6e 67 65 64 02
0020 02 00 00 00 01 00 00 00 02 00 00 00 02 00 00 00
     = {"t":"rpc","node":"GameManager","method":"_ready_changed","args":[1,2],"ch":0,"rel":true,"mode":2}
+  9.105s S→C binary 99 bytes
len 63 00 00 00   (raw TCP prefix: 99 bytes)
0000 03 01 00 18 00 4d 61 69 6e 2f 50 6c 61 79 65 72
0010 73 2f 50 5f 32 33 34 32 38 39 37 34 35 10 5f 72
0020 65 6c 61 79 5f 74 72 61 6e 73 66 6f 72 6d 04 09
0030 00 00 00 49 e1 5f 40 00 00 00 00 27 31 13 3f 03
0040 00 01 00 e5 f9 10 21 c8 ee f9 bf 03 00 00 00 00
0050 00 00 00 09 00 00 00 37 b3 ef 41 00 00 00 00 86
0060 eb bf 3f
     = {"t":"rpc","node":"Main/Players/P_234289745","method":"_relay_transform","args":[{"_t":"v3","v":[3.4981253147125244,0.0,0.5749687552452087]},-1.6207963267948966,0.0,{"_t":"v3","v":[29.962507247924805,0.0,1.4993751049041748]}],"ch":0,"rel":false,"mode":1}
+  9.184s S→C binary 48 bytes
len 30 00 00 00   (raw TCP prefix: 48 bytes)
0000 03 02 00 0b 00 47 61 6d 65 4d 61 6e 61 67 65 72
0010 0e 5f 72 65 61 64 79 5f 63 68 61 6e 67 65 64 02
0020 02 00 00 00 02 00 00 00 02 00 00 00 02 00 00 00
     = {"t":"rpc","node":"GameManager","method":"_ready_changed","args":[2,2],"ch":0,"rel":true,"mode":2}
```

Repeats not shown in this section: 6× `S→C _relay_transform`, 5× `C→S _push_transform`, 2× `S→C _equip_state`.

## Run: wave 1 calm

```text
+  9.184s S→C binary 59 bytes
len 3b 00 00 00   (raw TCP prefix: 59 bytes)
0000 03 02 00 0e 00 57 65 61 74 68 65 72 4d 61 6e 61
0010 67 65 72 0e 5f 72 65 63 65 69 76 65 5f 70 68 61
0020 73 65 03 02 00 00 00 00 00 00 00 02 00 00 00 01
0030 00 00 00 03 00 00 00 00 00 40 40
     = {"t":"rpc","node":"WeatherManager","method":"_receive_phase","args":[0,1,3.0],"ch":0,"rel":true,"mode":2}
+  9.184s S→C binary 99 bytes
len 63 00 00 00   (raw TCP prefix: 99 bytes)
0000 03 01 00 18 00 4d 61 69 6e 2f 50 6c 61 79 65 72
0010 73 2f 50 5f 32 33 34 32 38 39 37 34 35 10 5f 72
0020 65 6c 61 79 5f 74 72 61 6e 73 66 6f 72 6d 04 09
0030 00 00 00 06 2e 5a 40 00 00 00 00 1d d6 81 3f 03
0040 00 01 00 73 93 aa ba 61 88 06 40 03 00 00 00 00
0050 00 00 00 09 00 00 00 1f 34 f5 be 00 00 00 00 14
0060 ee b5 3f
     = {"t":"rpc","node":"Main/Players/P_234289745","method":"_relay_transform","args":[{"_t":"v3","v":[3.4090590476989746,0.0,1.014346718788147]},2.816592653589788,0.0,{"_t":"v3","v":[-0.478913277387619,0.0,1.421328067779541]}],"ch":0,"rel":false,"mode":1}
+  9.184s S→C binary 87 bytes
len 57 00 00 00   (raw TCP prefix: 87 bytes)
0000 03 01 00 10 00 4d 61 69 6e 2f 50 6c 61 79 65 72
0010 73 2f 50 5f 32 10 5f 72 65 6c 61 79 5f 74 72 61
0020 6e 73 66 6f 72 6d 04 09 00 00 00 00 00 00 c0 da
0030 af 75 3d 00 00 00 3f 03 00 00 00 00 00 00 00 03
0040 00 00 00 00 00 00 00 09 00 00 00 00 00 00 00 00
0050 00 00 00 00 00 00 00
     = {"t":"rpc","node":"Main/Players/P_2","method":"_relay_transform","args":[{"_t":"v3","v":[-2.0,0.05998215824365616,0.5]},0.0,0.0,{"_t":"v3","v":[0.0,0.0,0.0]}],"ch":0,"rel":false,"mode":1}
+  9.198s C→S binary 98 bytes
len 62 00 00 00   (raw TCP prefix: 98 bytes)
0000 03 01 00 18 00 4d 61 69 6e 2f 50 6c 61 79 65 72
0010 73 2f 50 5f 32 33 34 32 38 39 37 34 35 0f 5f 70
0020 75 73 68 5f 74 72 61 6e 73 66 6f 72 6d 04 09 00
0030 00 00 ff 6b 58 40 00 00 00 00 b1 c4 8a 3f 03 00
0040 01 00 23 2d 44 54 fb 21 06 40 03 00 00 00 00 00
0050 00 00 09 00 00 00 4e a2 0c bf 00 00 00 00 8c a3
0060 b2 3f
     = {"t":"rpc","node":"Main/Players/P_234289745","method":"_push_transform","args":[{"_t":"v3","v":[3.3815914910043277,0.0,1.0841275134629758]},2.766592653589798,0.0,{"_t":"v3","v":[-0.549351565334808,0.0,1.3956160455959754]}],"ch":0,"rel":false}
+  9.213s C→S binary 98 bytes
len 62 00 00 00   (raw TCP prefix: 98 bytes)
0000 03 01 00 18 00 4d 61 69 6e 2f 50 6c 61 79 65 72
0010 73 2f 50 5f 32 33 34 32 38 39 37 34 35 0f 5f 70
0020 75 73 68 5f 74 72 61 6e 73 66 6f 72 6d 04 09 00
0030 00 00 63 71 56 40 00 00 00 00 6d 83 93 3f 03 00
0040 01 00 b2 c6 dd ed 94 bb 05 40 03 00 00 00 00 00
0050 00 00 09 00 00 00 8f 50 1e bf 00 00 00 00 b6 e6
0060 ae 3f
     = {"t":"rpc","node":"Main/Players/P_234289745","method":"_push_transform","args":[{"_t":"v3","v":[3.3506706535290154,0.0,1.1524483011668454]},2.7165926535897933,0.0,{"_t":"v3","v":[-0.6184167495062454,0.0,1.3664157540773925]}],"ch":0,"rel":false}
+  9.247s S→C binary 39 bytes
len 27 00 00 00   (raw TCP prefix: 39 bytes)
0000 03 00 00 03 00 4e 65 74 09 5f 72 74 74 5f 70 69
0010 6e 67 02 02 00 00 00 07 00 00 00 03 00 01 00 81
0020 73 46 94 f6 c6 32 40
     = {"t":"rpc","node":"Net","method":"_rtt_ping","args":[7,18.777199999999997],"ch":0,"rel":false,"mode":0}
+  9.247s C→S binary 27 bytes
len 1b 00 00 00   (raw TCP prefix: 27 bytes)
0000 03 00 00 03 00 4e 65 74 09 5f 72 74 74 5f 70 6f
0010 6e 67 01 02 00 00 00 07 00 00 00
     = {"t":"rpc","node":"Net","method":"_rtt_pong","args":[7],"ch":0,"rel":false}
+  9.264s S→C binary 104 bytes
len 68 00 00 00   (raw TCP prefix: 104 bytes)
0000 03 01 00 10 00 4d 61 69 6e 2f 50 6c 61 79 65 72
0010 73 2f 50 5f 32 0d 5f 61 70 70 6c 79 5f 76 69 74
0020 61 6c 73 08 03 00 00 00 00 00 c8 42 03 00 00 00
0030 00 00 c8 42 04 00 00 00 02 00 00 00 6f 6b 00 00
0040 03 00 00 00 00 00 00 00 01 00 00 00 00 00 00 00
0050 03 00 00 00 00 00 c8 42 03 00 00 00 00 00 00 00
0060 01 00 00 00 00 00 00 00
     = {"t":"rpc","node":"Main/Players/P_2","method":"_apply_vitals","args":[100.0,100.0,"ok",0.0,false,100.0,0.0,false],"ch":0,"rel":false,"mode":1}
+  9.264s S→C binary 112 bytes
len 70 00 00 00   (raw TCP prefix: 112 bytes)
0000 03 01 00 18 00 4d 61 69 6e 2f 50 6c 61 79 65 72
0010 73 2f 50 5f 32 33 34 32 38 39 37 34 35 0d 5f 61
0020 70 70 6c 79 5f 76 69 74 61 6c 73 08 03 00 00 00
0030 00 00 c8 42 03 00 00 00 00 00 c8 42 04 00 00 00
0040 02 00 00 00 6f 6b 00 00 03 00 00 00 00 00 00 00
0050 01 00 00 00 00 00 00 00 03 00 00 00 00 00 c8 42
0060 03 00 00 00 00 00 00 00 01 00 00 00 00 00 00 00
     = {"t":"rpc","node":"Main/Players/P_234289745","method":"_apply_vitals","args":[100.0,100.0,"ok",0.0,false,100.0,0.0,false],"ch":0,"rel":false,"mode":1}
+  9.341s S→C binary 77 bytes
len 4d 00 00 00   (raw TCP prefix: 77 bytes)
0000 03 01 00 0c 00 4d 61 69 6e 2f 45 6e 65 6d 69 65
0010 73 0e 5f 73 79 6e 63 5f 70 72 6f 67 72 65 73 73
0020 05 02 00 00 00 01 00 00 00 02 00 00 00 2a 00 00
0030 00 02 00 00 00 2a 00 00 00 03 00 01 00 cd cc cc
0040 cc cc cc 00 40 02 00 00 00 00 00 00 00
     = {"t":"rpc","node":"Main/Enemies","method":"_sync_progress","args":[1,42,42,2.1,0],"ch":0,"rel":false,"mode":1}
+  9.637s S→C binary 77 bytes
len 4d 00 00 00   (raw TCP prefix: 77 bytes)
0000 03 01 00 0c 00 4d 61 69 6e 2f 45 6e 65 6d 69 65
0010 73 0e 5f 73 79 6e 63 5f 70 72 6f 67 72 65 73 73
0020 05 02 00 00 00 01 00 00 00 02 00 00 00 2a 00 00
0030 00 02 00 00 00 2a 00 00 00 03 00 01 00 cd cc cc
0040 cc cc cc 00 40 02 00 00 00 00 00 00 00
     = {"t":"rpc","node":"Main/Enemies","method":"_sync_progress","args":[1,42,42,2.1,0],"ch":0,"rel":false,"mode":1}
+ 10.243s S→C binary 39 bytes
len 27 00 00 00   (raw TCP prefix: 39 bytes)
0000 03 00 00 03 00 4e 65 74 09 5f 72 74 74 5f 70 69
0010 6e 67 02 02 00 00 00 08 00 00 00 03 00 01 00 a7
0020 1d fe 9a ac f1 31 40
     = {"t":"rpc","node":"Net","method":"_rtt_ping","args":[8,17.944039999999998],"ch":0,"rel":false,"mode":0}
+ 10.243s C→S binary 27 bytes
len 1b 00 00 00   (raw TCP prefix: 27 bytes)
0000 03 00 00 03 00 4e 65 74 09 5f 72 74 74 5f 70 6f
0010 6e 67 01 02 00 00 00 08 00 00 00
     = {"t":"rpc","node":"Net","method":"_rtt_pong","args":[8],"ch":0,"rel":false}
```

Repeats not shown in this section: 169× `S→C _relay_transform`, 121× `C→S _push_transform`, 26× `S→C _apply_vitals`, 8× `S→C _sync_progress`, 1× `S→C _rtt_ping`, 1× `C→S _rtt_pong`.

## Run: wave 1 drizzle

```text
+ 12.169s S→C binary 59 bytes
len 3b 00 00 00   (raw TCP prefix: 59 bytes)
0000 03 02 00 0e 00 57 65 61 74 68 65 72 4d 61 6e 61
0010 67 65 72 0e 5f 72 65 63 65 69 76 65 5f 70 68 61
0020 73 65 03 02 00 00 00 02 00 00 00 02 00 00 00 01
0030 00 00 00 03 00 00 00 00 00 f0 41
     = {"t":"rpc","node":"WeatherManager","method":"_receive_phase","args":[2,1,30.0],"ch":0,"rel":true,"mode":2}
+ 12.182s C→S binary 98 bytes
len 62 00 00 00   (raw TCP prefix: 98 bytes)
0000 03 01 00 18 00 4d 61 69 6e 2f 50 6c 61 79 65 72
0010 73 2f 50 5f 32 33 34 32 38 39 37 34 35 0f 5f 70
0020 75 73 68 5f 74 72 61 6e 73 66 6f 72 6d 04 09 00
0030 00 00 65 9a 5c 40 00 00 00 00 da 3e 65 3f 03 00
0040 01 00 14 54 99 c9 be 32 07 40 03 00 00 00 00 00
0050 00 00 09 00 00 00 d0 e3 b7 be 00 00 00 00 f4 64
0060 ba 3f
     = {"t":"rpc","node":"Main/Players/P_234289745","method":"_push_transform","args":[{"_t":"v3","v":[3.4469234407943268,0.0,0.8954902735591688]},2.899777960769379,0.0,{"_t":"v3","v":[-0.35915995595416916,0.0,1.456205828548911]}],"ch":0,"rel":false}
+ 12.184s S→C binary 73 bytes
len 49 00 00 00   (raw TCP prefix: 73 bytes)
0000 03 01 00 0c 00 4d 61 69 6e 2f 45 6e 65 6d 69 65
0010 73 0e 5f 73 79 6e 63 5f 70 72 6f 67 72 65 73 73
0020 05 02 00 00 00 01 00 00 00 02 00 00 00 2a 00 00
0030 00 02 00 00 00 2a 00 00 00 03 00 00 00 00 00 a0
0040 3f 02 00 00 00 00 00 00 00
     = {"t":"rpc","node":"Main/Enemies","method":"_sync_progress","args":[1,42,42,1.25,0],"ch":0,"rel":false,"mode":1}
+ 12.190s S→C binary 99 bytes
len 63 00 00 00   (raw TCP prefix: 99 bytes)
0000 03 01 00 18 00 4d 61 69 6e 2f 50 6c 61 79 65 72
0010 73 2f 50 5f 32 33 34 32 38 39 37 34 35 10 5f 72
0020 65 6c 61 79 5f 74 72 61 6e 73 66 6f 72 6d 04 09
0030 00 00 00 65 9a 5c 40 00 00 00 00 da 3e 65 3f 03
0040 00 01 00 14 54 99 c9 be 32 07 40 03 00 00 00 00
0050 00 00 00 09 00 00 00 d0 e3 b7 be 00 00 00 00 f4
0060 64 ba 3f
     = {"t":"rpc","node":"Main/Players/P_234289745","method":"_relay_transform","args":[{"_t":"v3","v":[3.4469234943389893,0.0,0.895490288734436]},2.899777960769379,0.0,{"_t":"v3","v":[-0.3591599464416504,0.0,1.4562058448791504]}],"ch":0,"rel":false,"mode":1}
+ 12.199s S→C binary 87 bytes
len 57 00 00 00   (raw TCP prefix: 87 bytes)
0000 03 01 00 10 00 4d 61 69 6e 2f 50 6c 61 79 65 72
0010 73 2f 50 5f 32 10 5f 72 65 6c 61 79 5f 74 72 61
0020 6e 73 66 6f 72 6d 04 09 00 00 00 00 00 00 c0 da
0030 af 75 3d 00 00 00 3f 03 00 00 00 00 00 00 00 03
0040 00 00 00 00 00 00 00 09 00 00 00 00 00 00 00 00
0050 00 00 00 00 00 00 00
     = {"t":"rpc","node":"Main/Players/P_2","method":"_relay_transform","args":[{"_t":"v3","v":[-2.0,0.05998215824365616,0.5]},0.0,0.0,{"_t":"v3","v":[0.0,0.0,0.0]}],"ch":0,"rel":false,"mode":1}
+ 12.228s C→S binary 98 bytes
len 62 00 00 00   (raw TCP prefix: 98 bytes)
0000 03 01 00 18 00 4d 61 69 6e 2f 50 6c 61 79 65 72
0010 73 2f 50 5f 32 33 34 32 38 39 37 34 35 0f 5f 70
0020 75 73 68 5f 74 72 61 6e 73 66 6f 72 6d 04 09 00
0030 00 00 eb 38 5b 40 00 00 00 00 c3 a1 77 3f 03 00
0040 01 00 b2 ed 32 63 58 cc 06 40 03 00 00 00 00 00
0050 00 00 09 00 00 00 65 ec dc be 00 00 00 00 1e dd
0060 b7 3f
     = {"t":"rpc","node":"Main/Players/P_234289745","method":"_push_transform","args":[{"_t":"v3","v":[3.425348887937794,0.0,0.9673120452700681]},2.849777960769381,0.0,{"_t":"v3","v":[-0.43149105713065516,0.0,1.4364354342179864]}],"ch":0,"rel":false}
+ 12.247s S→C binary 39 bytes
len 27 00 00 00   (raw TCP prefix: 39 bytes)
0000 03 00 00 03 00 4e 65 74 09 5f 72 74 74 5f 70 69
0010 6e 67 02 02 00 00 00 0a 00 00 00 03 00 01 00 a6
0020 13 bf 18 80 e4 33 40
     = {"t":"rpc","node":"Net","method":"_rtt_ping","args":[10,19.892579599999998],"ch":0,"rel":false,"mode":0}
+ 12.247s C→S binary 27 bytes
len 1b 00 00 00   (raw TCP prefix: 27 bytes)
0000 03 00 00 03 00 4e 65 74 09 5f 72 74 74 5f 70 6f
0010 6e 67 01 02 00 00 00 0a 00 00 00
     = {"t":"rpc","node":"Net","method":"_rtt_pong","args":[10],"ch":0,"rel":false}
+ 12.262s S→C binary 104 bytes
len 68 00 00 00   (raw TCP prefix: 104 bytes)
0000 03 01 00 10 00 4d 61 69 6e 2f 50 6c 61 79 65 72
0010 73 2f 50 5f 32 0d 5f 61 70 70 6c 79 5f 76 69 74
0020 61 6c 73 08 03 00 00 00 00 00 c8 42 03 00 00 00
0030 00 00 c8 42 04 00 00 00 02 00 00 00 6f 6b 00 00
0040 03 00 00 00 00 00 00 00 01 00 00 00 00 00 00 00
0050 03 00 00 00 00 00 c8 42 03 00 00 00 00 00 00 00
0060 01 00 00 00 00 00 00 00
     = {"t":"rpc","node":"Main/Players/P_2","method":"_apply_vitals","args":[100.0,100.0,"ok",0.0,false,100.0,0.0,false],"ch":0,"rel":false,"mode":1}
+ 12.262s S→C binary 112 bytes
len 70 00 00 00   (raw TCP prefix: 112 bytes)
0000 03 01 00 18 00 4d 61 69 6e 2f 50 6c 61 79 65 72
0010 73 2f 50 5f 32 33 34 32 38 39 37 34 35 0d 5f 61
0020 70 70 6c 79 5f 76 69 74 61 6c 73 08 03 00 00 00
0030 00 00 c8 42 03 00 00 00 00 00 c8 42 04 00 00 00
0040 02 00 00 00 6f 6b 00 00 03 00 00 00 00 00 00 00
0050 01 00 00 00 00 00 00 00 03 00 00 00 00 00 c8 42
0060 03 00 00 00 00 00 00 00 01 00 00 00 00 00 00 00
     = {"t":"rpc","node":"Main/Players/P_234289745","method":"_apply_vitals","args":[100.0,100.0,"ok",0.0,false,100.0,0.0,false],"ch":0,"rel":false,"mode":1}
+ 12.464s S→C binary 77 bytes
len 4d 00 00 00   (raw TCP prefix: 77 bytes)
0000 03 01 00 0c 00 4d 61 69 6e 2f 45 6e 65 6d 69 65
0010 73 0e 5f 73 79 6e 63 5f 70 72 6f 67 72 65 73 73
0020 05 02 00 00 00 01 00 00 00 02 00 00 00 2a 00 00
0030 00 02 00 00 00 2a 00 00 00 03 00 01 00 f6 ee ee
0040 ee ee ee ee 3f 02 00 00 00 00 00 00 00
     = {"t":"rpc","node":"Main/Enemies","method":"_sync_progress","args":[1,42,42,0.9666666666666675,0],"ch":0,"rel":false,"mode":1}
+ 13.257s S→C binary 39 bytes
len 27 00 00 00   (raw TCP prefix: 39 bytes)
0000 03 00 00 03 00 4e 65 74 09 5f 72 74 74 5f 70 69
0010 6e 67 02 02 00 00 00 0b 00 00 00 03 00 01 00 8e
0020 5a 1f de 8c b9 32 40
     = {"t":"rpc","node":"Net","method":"_rtt_ping","args":[11,18.72480572],"ch":0,"rel":false,"mode":0}
+ 13.257s C→S binary 27 bytes
len 1b 00 00 00   (raw TCP prefix: 27 bytes)
0000 03 00 00 03 00 4e 65 74 09 5f 72 74 74 5f 70 6f
0010 6e 67 01 02 00 00 00 0b 00 00 00
     = {"t":"rpc","node":"Net","method":"_rtt_pong","args":[11],"ch":0,"rel":false}
```
> Spawn `[net_id, kind enum, pos, small, elite, miniboss_wave]`.

```text
+ 13.413s S→C binary 79 bytes
len 4f 00 00 00   (raw TCP prefix: 79 bytes)
0000 03 02 00 0c 00 4d 61 69 6e 2f 45 6e 65 6d 69 65
0010 73 0c 5f 73 70 61 77 6e 5f 65 6e 65 6d 79 05 02
0020 00 00 00 01 00 00 00 02 00 00 00 00 00 00 00 09
0030 00 00 00 d0 05 11 c1 66 66 26 3f c3 63 7e c2 01
0040 00 00 00 00 00 00 00 01 00 00 00 00 00 00 00
     = {"t":"rpc","node":"Main/Enemies","method":"_spawn_enemy","args":[1,0,{"_t":"v3","v":[-9.063919067382812,0.6499999761581421,-63.5974235534668]},false,false],"ch":0,"rel":true,"mode":2}
+ 13.413s S→C binary 57 bytes
len 39 00 00 00   (raw TCP prefix: 57 bytes)
0000 03 02 00 0c 00 4d 61 69 6e 2f 45 6e 65 6d 69 65
0010 73 16 5f 72 65 63 65 69 76 65 5f 67 72 6f 75 70
0020 5f 77 61 72 6e 69 6e 67 01 09 00 00 00 d0 05 11
0030 c1 66 66 26 3f c3 63 7e c2
     = {"t":"rpc","node":"Main/Enemies","method":"_receive_group_warning","args":[{"_t":"v3","v":[-9.063919067382812,0.6499999761581421,-63.5974235534668]}],"ch":0,"rel":true,"mode":2}
```
> 20 Hz batch: PackedInt32Array ids, PackedVector3Array positions, PackedFloat32Array yaws.

```text
+ 13.460s S→C binary 76 bytes
len 4c 00 00 00   (raw TCP prefix: 76 bytes)
0000 03 01 00 0c 00 4d 61 69 6e 2f 45 6e 65 6d 69 65
0010 73 0d 5f 73 79 6e 63 5f 65 6e 65 6d 69 65 73 03
0020 1e 00 00 00 01 00 00 00 01 00 00 00 24 00 00 00
0030 01 00 00 00 6e 84 10 c1 30 4f 24 3f cb 14 7e c2
0040 20 00 00 00 01 00 00 00 6a 0c 42 c0
     = {"t":"rpc","node":"Main/Enemies","method":"_sync_enemies","args":[{"_t":"pi32","v":[1]},{"_t":"pv3","v":[[-9.032331466674805,0.6418333053588867,-63.52030563354492]]},{"_t":"pf32","v":[-3.0320076942443848]}],"ch":0,"rel":false,"mode":1}
+ 13.524s S→C binary 76 bytes
len 4c 00 00 00   (raw TCP prefix: 76 bytes)
0000 03 01 00 0c 00 4d 61 69 6e 2f 45 6e 65 6d 69 65
0010 73 0d 5f 73 79 6e 63 5f 65 6e 65 6d 69 65 73 03
0020 1e 00 00 00 01 00 00 00 01 00 00 00 24 00 00 00
0030 01 00 00 00 aa 81 0f c1 ec c3 17 3f db 76 7d c2
0040 20 00 00 00 01 00 00 00 1f 18 42 c0
     = {"t":"rpc","node":"Main/Enemies","method":"_sync_enemies","args":[{"_t":"pi32","v":[1]},{"_t":"pv3","v":[[-8.969156265258789,0.5928332805633545,-63.36606979370117]]},{"_t":"pf32","v":[-3.032722234725952]}],"ch":0,"rel":false,"mode":1}
+ 13.697s S→C binary 79 bytes
len 4f 00 00 00   (raw TCP prefix: 79 bytes)
0000 03 02 00 0c 00 4d 61 69 6e 2f 45 6e 65 6d 69 65
0010 73 0c 5f 73 70 61 77 6e 5f 65 6e 65 6d 79 05 02
0020 00 00 00 02 00 00 00 02 00 00 00 01 00 00 00 09
0030 00 00 00 d4 5e ca c0 66 66 26 3f 00 00 6f c2 01
0040 00 00 00 00 00 00 00 01 00 00 00 00 00 00 00
     = {"t":"rpc","node":"Main/Enemies","method":"_spawn_enemy","args":[2,1,{"_t":"v3","v":[-6.324075698852539,0.6499999761581421,-59.75]},false,false],"ch":0,"rel":true,"mode":2}
```

Repeats not shown in this section: 279× `S→C _relay_transform`, 159× `C→S _push_transform`, 99× `S→C _sync_enemies`, 72× `S→C _apply_vitals`, 27× `S→C _sync_progress`, 6× `S→C _rtt_ping`, 6× `C→S _rtt_pong`, 1× `S→C _spawn_enemy`.

## Run: wave 1 downpour

```text
+ 20.178s S→C binary 63 bytes
len 3f 00 00 00   (raw TCP prefix: 63 bytes)
0000 03 02 00 0e 00 57 65 61 74 68 65 72 4d 61 6e 61
0010 67 65 72 0e 5f 72 65 63 65 69 76 65 5f 70 68 61
0020 73 65 03 02 00 00 00 03 00 00 00 02 00 00 00 01
0030 00 00 00 03 00 01 00 4e 69 47 e7 d6 05 46 40
     = {"t":"rpc","node":"WeatherManager","method":"_receive_phase","args":[3,1,44.045620832318136],"ch":0,"rel":true,"mode":2}
+ 20.194s S→C binary 116 bytes
len 74 00 00 00   (raw TCP prefix: 116 bytes)
0000 03 01 00 0c 00 4d 61 69 6e 2f 45 6e 65 6d 69 65
0010 73 0d 5f 73 79 6e 63 5f 65 6e 65 6d 69 65 73 03
0020 1e 00 00 00 03 00 00 00 01 00 00 00 02 00 00 00
0030 03 00 00 00 24 00 00 00 03 00 00 00 2c 34 0e c1
0040 61 f3 a4 3d f2 a8 3b c2 f0 ea f6 c0 2e 48 a5 3d
0050 28 f4 26 c2 14 52 0a c1 cc 91 8e 39 b9 6b 4a c2
0060 20 00 00 00 03 00 00 00 45 d7 3f c0 fa 73 40 c0
0070 ea cb 40 c0
     = {"t":"rpc","node":"Main/Enemies","method":"_sync_enemies","args":[{"_t":"pi32","v":[1,2,3]},{"_t":"pv3","v":[[-8.887737274169922,0.08054233342409134,-46.91498565673828],[-7.716178894042969,0.08070407807826996,-41.738433837890625],[-8.645038604736328,0.00027192977722734213,-50.60519790649414]]},{"_t":"pf32","v":[-2.997514009475708,-3.0070786476135254,-3.0124459266662598]}],"ch":0,"rel":false,"mode":1}
+ 20.194s S→C binary 77 bytes
len 4d 00 00 00   (raw TCP prefix: 77 bytes)
0000 03 01 00 0c 00 4d 61 69 6e 2f 45 6e 65 6d 69 65
0010 73 0e 5f 73 79 6e 63 5f 70 72 6f 67 72 65 73 73
0020 05 02 00 00 00 01 00 00 00 02 00 00 00 2a 00 00
0030 00 02 00 00 00 2a 00 00 00 03 00 01 00 cd cc cc
0040 cc cc cc 00 40 02 00 00 00 00 00 00 00
     = {"t":"rpc","node":"Main/Enemies","method":"_sync_progress","args":[1,42,42,2.1,0],"ch":0,"rel":false,"mode":1}
+ 20.194s S→C binary 87 bytes
len 57 00 00 00   (raw TCP prefix: 87 bytes)
0000 03 01 00 10 00 4d 61 69 6e 2f 50 6c 61 79 65 72
0010 73 2f 50 5f 32 10 5f 72 65 6c 61 79 5f 74 72 61
0020 6e 73 66 6f 72 6d 04 09 00 00 00 00 00 00 c0 da
0030 af 75 3d 00 00 00 3f 03 00 00 00 4d 37 09 3e 03
0040 00 00 00 96 43 8b bc 09 00 00 00 00 00 00 00 00
0050 00 00 00 00 00 00 00
     = {"t":"rpc","node":"Main/Players/P_2","method":"_relay_transform","args":[{"_t":"v3","v":[-2.0,0.05998215824365616,0.5]},0.1340000182390213,-0.017000000923871994,{"_t":"v3","v":[0.0,0.0,0.0]}],"ch":0,"rel":false,"mode":1}
+ 20.222s C→S binary 98 bytes
len 62 00 00 00   (raw TCP prefix: 98 bytes)
0000 03 01 00 18 00 4d 61 69 6e 2f 50 6c 61 79 65 72
0010 73 2f 50 5f 32 33 34 32 38 39 37 34 35 0f 5f 70
0020 75 73 68 5f 74 72 61 6e 73 66 6f 72 6d 04 09 00
0030 00 00 60 46 aa 3f 00 00 00 00 c7 cc eb 3f 03 00
0040 01 00 f3 74 ff 5f 4a 32 fb 3f 03 00 00 00 00 00
0050 00 00 09 00 00 00 fb de ad bf 00 00 00 00 62 ca
0060 22 bf
     = {"t":"rpc","node":"Main/Players/P_234289745","method":"_push_transform","args":[{"_t":"v3","v":[1.3302726628815993,0.0,1.8421867582107552]},1.6997779607693786,0.0,{"_t":"v3","v":[-1.3583672791849954,0.0,-0.6359006399590728]}],"ch":0,"rel":false}
+ 20.225s S→C binary 99 bytes
len 63 00 00 00   (raw TCP prefix: 99 bytes)
0000 03 01 00 18 00 4d 61 69 6e 2f 50 6c 61 79 65 72
0010 73 2f 50 5f 32 33 34 32 38 39 37 34 35 10 5f 72
0020 65 6c 61 79 5f 74 72 61 6e 73 66 6f 72 6d 04 09
0030 00 00 00 60 46 aa 3f 00 00 00 00 c7 cc eb 3f 03
0040 00 01 00 f3 74 ff 5f 4a 32 fb 3f 03 00 00 00 00
0050 00 00 00 09 00 00 00 fb de ad bf 00 00 00 00 62
0060 ca 22 bf
     = {"t":"rpc","node":"Main/Players/P_234289745","method":"_relay_transform","args":[{"_t":"v3","v":[1.3302726745605469,0.0,1.8421868085861206]},1.6997779607693786,0.0,{"_t":"v3","v":[-1.3583673238754272,0.0,-0.635900616645813]}],"ch":0,"rel":false,"mode":1}
+ 20.256s S→C binary 39 bytes
len 27 00 00 00   (raw TCP prefix: 39 bytes)
0000 03 00 00 03 00 4e 65 74 09 5f 72 74 74 5f 70 69
0010 6e 67 02 02 00 00 00 12 00 00 00 03 00 01 00 3e
0020 03 5e ae 36 74 34 40
     = {"t":"rpc","node":"Net","method":"_rtt_ping","args":[18,20.453959367706595],"ch":0,"rel":false,"mode":0}
+ 20.256s C→S binary 27 bytes
len 1b 00 00 00   (raw TCP prefix: 27 bytes)
0000 03 00 00 03 00 4e 65 74 09 5f 72 74 74 5f 70 6f
0010 6e 67 01 02 00 00 00 12 00 00 00
     = {"t":"rpc","node":"Net","method":"_rtt_pong","args":[18],"ch":0,"rel":false}
+ 20.273s S→C binary 116 bytes
len 74 00 00 00   (raw TCP prefix: 116 bytes)
0000 03 01 00 0c 00 4d 61 69 6e 2f 45 6e 65 6d 69 65
0010 73 0d 5f 73 79 6e 63 5f 65 6e 65 6d 69 65 73 03
0020 1e 00 00 00 03 00 00 00 01 00 00 00 02 00 00 00
0030 03 00 00 00 24 00 00 00 03 00 00 00 f0 5d 0e c1
0040 61 f3 a4 3d 9a fe 3a c2 dc 1d f6 c0 2e 48 a5 3d
0050 bc 36 26 c2 20 7d 0a c1 cc 91 8e 39 65 c1 49 c2
0060 20 00 00 00 03 00 00 00 9f cb 3f c0 fa 73 40 c0
0070 c4 c1 40 c0
     = {"t":"rpc","node":"Main/Enemies","method":"_sync_enemies","args":[{"_t":"pi32","v":[1,2,3]},{"_t":"pv3","v":[[-8.897933959960938,0.08054233342409134,-46.748634338378906],[-7.691144943237305,0.08070407807826996,-41.55345153808594],[-8.655548095703125,0.00027192977722734213,-50.43886184692383]]},{"_t":"pf32","v":[-2.996803045272827,-3.0070786476135254,-3.011826515197754]}],"ch":0,"rel":false,"mode":1}
+ 20.275s S→C binary 108 bytes
len 6c 00 00 00   (raw TCP prefix: 108 bytes)
0000 03 01 00 10 00 4d 61 69 6e 2f 50 6c 61 79 65 72
0010 73 2f 50 5f 32 0d 5f 61 70 70 6c 79 5f 76 69 74
0020 61 6c 73 08 03 00 00 00 00 00 c8 42 03 00 01 00
0030 5d 02 be 79 35 62 57 40 04 00 00 00 02 00 00 00
0040 6f 6b 00 00 03 00 00 00 00 00 00 00 01 00 00 00
0050 00 00 00 00 03 00 00 00 00 00 c8 42 03 00 00 00
0060 00 00 00 00 01 00 00 00 00 00 00 00
     = {"t":"rpc","node":"Main/Players/P_2","method":"_apply_vitals","args":[100.0,93.53451388888921,"ok",0.0,false,100.0,0.0,false],"ch":0,"rel":false,"mode":1}
+ 20.275s S→C binary 116 bytes
len 74 00 00 00   (raw TCP prefix: 116 bytes)
0000 03 01 00 18 00 4d 61 69 6e 2f 50 6c 61 79 65 72
0010 73 2f 50 5f 32 33 34 32 38 39 37 34 35 0d 5f 61
0020 70 70 6c 79 5f 76 69 74 61 6c 73 08 03 00 00 00
0030 00 00 c8 42 03 00 01 00 5d 02 be 79 35 62 57 40
0040 04 00 00 00 02 00 00 00 6f 6b 00 00 03 00 00 00
0050 00 00 00 00 01 00 00 00 00 00 00 00 03 00 00 00
0060 00 00 c8 42 03 00 00 00 00 00 00 00 01 00 00 00
0070 00 00 00 00
     = {"t":"rpc","node":"Main/Players/P_234289745","method":"_apply_vitals","args":[100.0,93.53451388888921,"ok",0.0,false,100.0,0.0,false],"ch":0,"rel":false,"mode":1}
+ 20.286s C→S binary 98 bytes
len 62 00 00 00   (raw TCP prefix: 98 bytes)
0000 03 01 00 18 00 4d 61 69 6e 2f 50 6c 61 79 65 72
0010 73 2f 50 5f 32 33 34 32 38 39 37 34 35 0f 5f 70
0020 75 73 68 5f 74 72 61 6e 73 66 6f 72 6d 04 09 00
0030 00 00 ae cb a1 3f 00 00 00 00 fd 4c e7 3f 03 00
0040 01 00 f3 74 ff 5f 4a 32 fb 3f 03 00 00 00 00 00
0050 00 00 09 00 00 00 ed 95 a9 bf 00 00 00 00 8c f7
0060 33 bf
     = {"t":"rpc","node":"Main/Players/P_234289745","method":"_push_transform","args":[{"_t":"v3","v":[1.264028268477893,0.0,1.8070369583146269]},1.6997779607693786,0.0,{"_t":"v3","v":[-1.3248878880741266,0.0,-0.7029959979225664]}],"ch":0,"rel":false}
+ 20.476s S→C binary 77 bytes
len 4d 00 00 00   (raw TCP prefix: 77 bytes)
0000 03 01 00 0c 00 4d 61 69 6e 2f 45 6e 65 6d 69 65
0010 73 0e 5f 73 79 6e 63 5f 70 72 6f 67 72 65 73 73
0020 05 02 00 00 00 01 00 00 00 02 00 00 00 2a 00 00
0030 00 02 00 00 00 2a 00 00 00 03 00 01 00 16 11 11
0040 11 11 11 fd 3f 02 00 00 00 00 00 00 00
     = {"t":"rpc","node":"Main/Enemies","method":"_sync_progress","args":[1,42,42,1.8166666666666678,0],"ch":0,"rel":false,"mode":1}
+ 21.254s S→C binary 39 bytes
len 27 00 00 00   (raw TCP prefix: 39 bytes)
0000 03 00 00 03 00 4e 65 74 09 5f 72 74 74 5f 70 69
0010 6e 67 02 02 00 00 00 13 00 00 00 03 00 01 00 78
0020 35 a8 13 f3 6a 33 40
     = {"t":"rpc","node":"Net","method":"_rtt_ping","args":[19,19.417771557394616],"ch":0,"rel":false,"mode":0}
+ 21.254s C→S binary 27 bytes
len 1b 00 00 00   (raw TCP prefix: 27 bytes)
0000 03 00 00 03 00 4e 65 74 09 5f 72 74 74 5f 70 6f
0010 6e 67 01 02 00 00 00 13 00 00 00
     = {"t":"rpc","node":"Net","method":"_rtt_pong","args":[19],"ch":0,"rel":false}
+ 22.297s S→C binary 79 bytes
len 4f 00 00 00   (raw TCP prefix: 79 bytes)
0000 03 02 00 0c 00 4d 61 69 6e 2f 45 6e 65 6d 69 65
0010 73 0c 5f 73 70 61 77 6e 5f 65 6e 65 6d 79 05 02
0020 00 00 00 04 00 00 00 02 00 00 00 00 00 00 00 09
0030 00 00 00 5a 1d 19 c2 66 66 26 3f b4 67 74 c2 01
0040 00 00 00 00 00 00 00 01 00 00 00 00 00 00 00
     = {"t":"rpc","node":"Main/Enemies","method":"_spawn_enemy","args":[4,0,{"_t":"v3","v":[-38.278663635253906,0.6499999761581421,-61.10127258300781]},false,false],"ch":0,"rel":true,"mode":2}
+ 22.297s S→C binary 57 bytes
len 39 00 00 00   (raw TCP prefix: 57 bytes)
0000 03 02 00 0c 00 4d 61 69 6e 2f 45 6e 65 6d 69 65
0010 73 16 5f 72 65 63 65 69 76 65 5f 67 72 6f 75 70
0020 5f 77 61 72 6e 69 6e 67 01 09 00 00 00 5a 1d 19
0030 c2 66 66 26 3f b4 67 74 c2
     = {"t":"rpc","node":"Main/Enemies","method":"_receive_group_warning","args":[{"_t":"v3","v":[-38.278663635253906,0.6499999761581421,-61.10127258300781]}],"ch":0,"rel":true,"mode":2}
+ 22.576s S→C binary 79 bytes
len 4f 00 00 00   (raw TCP prefix: 79 bytes)
0000 03 02 00 0c 00 4d 61 69 6e 2f 45 6e 65 6d 69 65
0010 73 0c 5f 73 70 61 77 6e 5f 65 6e 65 6d 79 05 02
0020 00 00 00 05 00 00 00 02 00 00 00 01 00 00 00 09
0030 00 00 00 00 5b 26 c2 66 66 26 3f 26 96 71 c2 01
0040 00 00 00 00 00 00 00 01 00 00 00 00 00 00 00
     = {"t":"rpc","node":"Main/Enemies","method":"_spawn_enemy","args":[5,1,{"_t":"v3","v":[-41.5888671875,0.6499999761581421,-60.396629333496094]},false,false],"ch":0,"rel":true,"mode":2}
```
> Hitscan request: `[run_id, serial, origin(eye), dir, aiming, predicted]`; host resolves hits (client-responsibilities §Weapons).

```text
+ 25.672s C→S binary 135 bytes
len 87 00 00 00   (raw TCP prefix: 135 bytes)
0000 03 02 00 33 00 4d 61 69 6e 2f 50 6c 61 79 65 72
0010 73 2f 50 5f 32 33 34 32 38 39 37 34 35 2f 48 65
0020 61 64 2f 43 61 6d 65 72 61 33 44 2f 57 65 61 70
0030 6f 6e 48 6f 6c 64 65 72 0d 5f 72 65 71 75 65 73
0040 74 5f 73 68 6f 74 06 02 00 00 00 01 00 00 00 02
0050 00 00 00 02 00 00 00 09 00 00 00 22 bf 22 40 33
0060 33 d3 3f 7d fb f2 3f 09 00 00 00 17 b4 ce be 0b
0070 df cc bc 68 1f 6a bf 01 00 00 00 00 00 00 00 01
0080 00 00 00 01 00 00 00
     = {"t":"rpc","node":"Main/Players/P_234289745/Head/Camera3D/WeaponHolder","method":"_request_shot","args":[1,2,{"_t":"v3","v":[2.542915730416492,1.65,1.8982998640013977]},{"_t":"v3","v":[-0.4037177271239382,-0.02500869928309973,-0.9145417222664305]},false,true],"ch":0,"rel":true}
```
> Authoritative shot effect with `traces[[end, impact]]`, relayed to everyone; skip local re-play when `predicted` and it is yours.

```text
+ 25.690s S→C binary 182 bytes
len b6 00 00 00   (raw TCP prefix: 182 bytes)
0000 03 01 00 33 00 4d 61 69 6e 2f 50 6c 61 79 65 72
0010 73 2f 50 5f 32 33 34 32 38 39 37 34 35 2f 48 65
0020 61 64 2f 43 61 6d 65 72 61 33 44 2f 57 65 61 70
0030 6f 6e 48 6f 6c 64 65 72 08 5f 73 68 6f 74 5f 66
0040 78 07 02 00 00 00 01 00 00 00 04 00 00 00 0b 00
0050 00 00 6e 61 69 6c 5f 64 72 69 76 65 72 00 09 00
0060 00 00 22 bf 22 40 33 33 d3 3f 7d fb f2 3f 09 00
0070 00 00 17 b4 ce be 0b df cc bc 68 1f 6a bf 1c 00
0080 00 00 01 00 00 00 1c 00 00 00 02 00 00 00 09 00
0090 00 00 e6 99 0e c1 96 ad 89 3f 7c e5 c5 c1 02 00
00a0 00 00 00 00 00 00 01 00 00 00 00 00 00 00 01 00
00b0 00 00 01 00 00 00
     = {"t":"rpc","node":"Main/Players/P_234289745/Head/Camera3D/WeaponHolder","method":"_shot_fx","args":[1,"nail_driver",{"_t":"v3","v":[2.5429158210754395,1.649999976158142,1.8982998132705688]},{"_t":"v3","v":[-0.4037177264690399,-0.02500869892537594,-0.9145417213439941]},[[{"_t":"v3","v":[-8.912572860717773,1.0756099224090576,-24.73705291748047]},0]],false,true],"ch":0,"rel":false,"mode":1}
+ 25.690s S→C binary 284 bytes
len 1c 01 00 00   (raw TCP prefix: 284 bytes)
0000 03 02 00 33 00 4d 61 69 6e 2f 50 6c 61 79 65 72
0010 73 2f 50 5f 32 33 34 32 38 39 37 34 35 2f 48 65
0020 61 64 2f 43 61 6d 65 72 61 33 44 2f 57 65 61 70
0030 6f 6e 48 6f 6c 64 65 72 0e 5f 70 72 69 76 61 74
0040 65 5f 73 74 61 74 65 0d 02 00 00 00 01 00 00 00
0050 02 00 00 00 03 00 00 00 1c 00 00 00 05 00 00 00
0060 1c 00 00 00 04 00 00 00 02 00 00 00 02 00 00 00
0070 04 00 00 00 0b 00 00 00 6e 61 69 6c 5f 64 72 69
0080 76 65 72 00 02 00 00 00 00 00 00 00 02 00 00 00
0090 17 00 00 00 1c 00 00 00 00 00 00 00 1c 00 00 00
00a0 00 00 00 00 1c 00 00 00 00 00 00 00 1c 00 00 00
00b0 00 00 00 00 1b 00 00 00 01 00 00 00 04 00 00 00
00c0 04 00 00 00 6e 61 69 6c 02 00 00 00 3c 00 00 00
00d0 02 00 00 00 00 00 00 00 04 00 00 00 00 00 00 00
00e0 02 00 00 00 00 00 00 00 02 00 00 00 02 00 00 00
00f0 02 00 00 00 01 00 00 00 03 00 00 00 00 00 00 00
0100 03 00 00 00 00 00 80 3f 03 00 00 00 00 00 00 00
0110 03 00 01 00 c3 f5 28 5c 8f c2 b5 3f
     = {"t":"rpc","node":"Main/Players/P_234289745/Head/Camera3D/WeaponHolder","method":"_private_state","args":[1,3,[[2,"nail_driver",0,23],[],[],[],[]],{"nail":60},0,"",0,2,1,0.0,1.0,0.0,0.085],"ch":0,"rel":true,"mode":2}
+ 25.878s C→S binary 135 bytes
len 87 00 00 00   (raw TCP prefix: 135 bytes)
0000 03 02 00 33 00 4d 61 69 6e 2f 50 6c 61 79 65 72
0010 73 2f 50 5f 32 33 34 32 38 39 37 34 35 2f 48 65
0020 61 64 2f 43 61 6d 65 72 61 33 44 2f 57 65 61 70
0030 6f 6e 48 6f 6c 64 65 72 0d 5f 72 65 71 75 65 73
0040 74 5f 73 68 6f 74 06 02 00 00 00 01 00 00 00 02
0050 00 00 00 02 00 00 00 09 00 00 00 5b 46 10 40 33
0060 33 d3 3f 88 38 fd 3f 09 00 00 00 27 db d0 be fe
0070 43 d1 bc 0b a4 69 bf 01 00 00 00 00 00 00 00 01
     … (hex truncated)
     = {"t":"rpc","node":"Main/Players/P_234289745/Head/Camera3D/WeaponHolder","method":"_request_shot","args":[1,2,{"_t":"v3","v":[2.2542942637334877,1.65,1.9782876673476795]},{"_t":"v3","v":[-0.4079220103657788,-0.025545116061597962,-0.9126593452677406]},false,true],"ch":0,"rel":true}
+ 25.880s S→C binary 182 bytes
len b6 00 00 00   (raw TCP prefix: 182 bytes)
0000 03 01 00 33 00 4d 61 69 6e 2f 50 6c 61 79 65 72
0010 73 2f 50 5f 32 33 34 32 38 39 37 34 35 2f 48 65
0020 61 64 2f 43 61 6d 65 72 61 33 44 2f 57 65 61 70
0030 6f 6e 48 6f 6c 64 65 72 08 5f 73 68 6f 74 5f 66
0040 78 07 02 00 00 00 01 00 00 00 04 00 00 00 0b 00
0050 00 00 6e 61 69 6c 5f 64 72 69 76 65 72 00 09 00
0060 00 00 5b 46 10 40 33 33 d3 3f 88 38 fd 3f 09 00
0070 00 00 27 db d0 be fe 43 d1 bc 0b a4 69 bf 1c 00
     … (hex truncated)
     = {"t":"rpc","node":"Main/Players/P_234289745/Head/Camera3D/WeaponHolder","method":"_shot_fx","args":[1,"nail_driver",{"_t":"v3","v":[2.2542941570281982,1.649999976158142,1.978287696838379]},{"_t":"v3","v":[-0.40792199969291687,-0.025545116513967514,-0.9126593470573425]},[[{"_t":"v3","v":[-9.83846664428711,0.8473240733146667,-24.36788558959961]},0]],false,true],"ch":0,"rel":false,"mode":1}
+ 25.880s S→C binary 284 bytes
len 1c 01 00 00   (raw TCP prefix: 284 bytes)
0000 03 02 00 33 00 4d 61 69 6e 2f 50 6c 61 79 65 72
0010 73 2f 50 5f 32 33 34 32 38 39 37 34 35 2f 48 65
0020 61 64 2f 43 61 6d 65 72 61 33 44 2f 57 65 61 70
0030 6f 6e 48 6f 6c 64 65 72 0e 5f 70 72 69 76 61 74
0040 65 5f 73 74 61 74 65 0d 02 00 00 00 01 00 00 00
0050 02 00 00 00 04 00 00 00 1c 00 00 00 05 00 00 00
0060 1c 00 00 00 04 00 00 00 02 00 00 00 02 00 00 00
0070 04 00 00 00 0b 00 00 00 6e 61 69 6c 5f 64 72 69
     … (hex truncated)
     = {"t":"rpc","node":"Main/Players/P_234289745/Head/Camera3D/WeaponHolder","method":"_private_state","args":[1,4,[[2,"nail_driver",0,22],[],[],[],[]],{"nail":60},0,"",0,2,1,0.0,1.0,0.0,0.085],"ch":0,"rel":true,"mode":2}
+ 26.287s S→C binary 81 bytes
len 51 00 00 00   (raw TCP prefix: 81 bytes)
0000 03 00 00 0c 00 4d 61 69 6e 2f 45 6e 65 6d 69 65
0010 73 0e 5f 65 6e 65 6d 79 5f 69 6d 70 61 63 74 73
0020 01 1c 00 00 00 01 00 00 00 1c 00 00 00 03 00 00
0030 00 02 00 00 00 02 00 00 00 09 00 00 00 f1 17 d8
0040 be ef 9b 36 bd 06 cd 67 bf 01 00 00 00 00 00 00
0050 00
     = {"t":"rpc","node":"Main/Enemies","method":"_enemy_impacts","args":[[[2,{"_t":"v3","v":[-0.4220576584339142,-0.0445823036134243,-0.9054721593856812]},false]]],"ch":0,"rel":false,"mode":0}
```
> Hit markers for your shots: `[[killed, critical, pos, damage, enemy_id], ...]`.

```text
+ 26.287s S→C binary 116 bytes
len 74 00 00 00   (raw TCP prefix: 116 bytes)
0000 03 02 00 18 00 4d 61 69 6e 2f 50 6c 61 79 65 72
0010 73 2f 50 5f 32 33 34 32 38 39 37 34 35 0d 5f 72
0020 65 63 65 69 76 65 5f 68 69 74 73 02 02 00 00 00
0030 01 00 00 00 1c 00 00 00 01 00 00 00 1c 00 00 00
0040 05 00 00 00 01 00 00 00 00 00 00 00 01 00 00 00
0050 00 00 00 00 09 00 00 00 28 f0 1f c1 e4 7a d6 3e
0060 28 58 b8 c1 02 00 00 00 04 00 00 00 02 00 00 00
0070 02 00 00 00
     = {"t":"rpc","node":"Main/Players/P_234289745","method":"_receive_hits","args":[1,[[false,false,{"_t":"v3","v":[-9.996131896972656,0.4189063310623169,-23.043045043945312]},4,2]]],"ch":0,"rel":true,"mode":2}
+ 27.305s S→C binary 81 bytes
len 51 00 00 00   (raw TCP prefix: 81 bytes)
0000 03 00 00 0c 00 4d 61 69 6e 2f 45 6e 65 6d 69 65
0010 73 0e 5f 65 6e 65 6d 79 5f 69 6d 70 61 63 74 73
0020 01 1c 00 00 00 01 00 00 00 1c 00 00 00 03 00 00
0030 00 02 00 00 00 02 00 00 00 09 00 00 00 d8 77 e1
0040 be ff 17 15 bd 00 a7 65 bf 01 00 00 00 00 00 00
0050 00
     = {"t":"rpc","node":"Main/Enemies","method":"_enemy_impacts","args":[[[2,{"_t":"v3","v":[-0.4403674602508545,-0.03639983758330345,-0.8970794677734375]},false]]],"ch":0,"rel":false,"mode":0}
+ 27.305s S→C binary 116 bytes
len 74 00 00 00   (raw TCP prefix: 116 bytes)
0000 03 02 00 18 00 4d 61 69 6e 2f 50 6c 61 79 65 72
0010 73 2f 50 5f 32 33 34 32 38 39 37 34 35 0d 5f 72
0020 65 63 65 69 76 65 5f 68 69 74 73 02 02 00 00 00
0030 01 00 00 00 1c 00 00 00 01 00 00 00 1c 00 00 00
0040 05 00 00 00 01 00 00 00 00 00 00 00 01 00 00 00
0050 00 00 00 00 09 00 00 00 29 f7 24 c1 ca d1 3f 3f
0060 bc 91 a9 c1 02 00 00 00 05 00 00 00 02 00 00 00
0070 02 00 00 00
     = {"t":"rpc","node":"Main/Players/P_234289745","method":"_receive_hits","args":[1,[[false,false,{"_t":"v3","v":[-10.310341835021973,0.7492948770523071,-21.19615936279297]},5,2]]],"ch":0,"rel":true,"mode":2}
+ 27.880s S→C binary 57 bytes
len 39 00 00 00   (raw TCP prefix: 57 bytes)
0000 03 02 00 0c 00 4d 61 69 6e 2f 45 6e 65 6d 69 65
0010 73 16 5f 72 65 63 65 69 76 65 5f 67 72 6f 75 70
0020 5f 77 61 72 6e 69 6e 67 01 09 00 00 00 74 30 6f
0030 42 66 66 26 3f 5d 8a 24 42
     = {"t":"rpc","node":"Main/Enemies","method":"_receive_group_warning","args":[{"_t":"v3","v":[59.79731750488281,0.6499999761581421,41.1351203918457]}],"ch":0,"rel":true,"mode":2}
```
> World pickup appeared: `[run_id, pickup_id, [pos, item[], flavor, claim_peer]]`.

```text
+ 28.747s S→C binary 97 bytes
len 61 00 00 00   (raw TCP prefix: 97 bytes)
0000 03 02 00 0c 00 4d 61 69 6e 2f 52 75 6e 4c 6f 6f
0010 74 06 5f 73 70 61 77 6e 03 02 00 00 00 01 00 00
0020 00 02 00 00 00 01 00 00 00 1c 00 00 00 04 00 00
0030 00 09 00 00 00 53 dd 27 c1 09 0d 65 3a 96 97 ac
0040 c1 1c 00 00 00 00 00 00 00 04 00 00 00 05 00 00
0050 00 73 63 72 61 70 00 00 00 02 00 00 00 00 00 00
0060 00
     = {"t":"rpc","node":"Main/RunLoot","method":"_spawn","args":[1,1,[{"_t":"v3","v":[-10.491534233093262,0.0008737599127925932,-21.574016571044922]},[],"scrap",0]],"ch":0,"rel":true,"mode":2}
```
> Enemy died: `[net_id, drops, at, throw_vec, critical]`.

```text
+ 28.747s S→C binary 129 bytes
len 81 00 00 00   (raw TCP prefix: 129 bytes)
0000 03 02 00 0c 00 4d 61 69 6e 2f 45 6e 65 6d 69 65
0010 73 0e 5f 64 65 73 70 61 77 6e 5f 65 6e 65 6d 79
0020 05 02 00 00 00 02 00 00 00 1c 00 00 00 01 00 00
0030 00 1c 00 00 00 02 00 00 00 09 00 00 00 53 dd 27
0040 c1 09 0d 65 3a 96 97 ac c1 04 00 00 00 05 00 00
0050 00 73 63 72 61 70 00 00 00 09 00 00 00 53 dd 27
0060 c1 09 0d 65 3a 96 97 ac c1 09 00 00 00 e3 bb a9
0070 be 00 00 00 00 b5 33 12 bf 01 00 00 00 00 00 00
0080 00
     = {"t":"rpc","node":"Main/Enemies","method":"_despawn_enemy","args":[2,[[{"_t":"v3","v":[-10.491534233093262,0.0008737599127925932,-21.574016571044922]},"scrap"]],{"_t":"v3","v":[-10.491534233093262,0.0008737599127925932,-21.574016571044922]},{"_t":"v3","v":[-0.33151158690452576,0.0,-0.5711014866828918]},false],"ch":0,"rel":true,"mode":2}
+ 29.185s S→C binary 97 bytes
len 61 00 00 00   (raw TCP prefix: 97 bytes)
0000 03 02 00 0c 00 4d 61 69 6e 2f 52 75 6e 4c 6f 6f
0010 74 06 5f 73 70 61 77 6e 03 02 00 00 00 01 00 00
0020 00 02 00 00 00 02 00 00 00 1c 00 00 00 04 00 00
0030 00 09 00 00 00 ae c0 27 c1 72 f2 65 3a dc ae ad
0040 c1 1c 00 00 00 00 00 00 00 04 00 00 00 05 00 00
0050 00 73 63 72 61 70 00 00 00 02 00 00 00 00 00 00
0060 00
     = {"t":"rpc","node":"Main/RunLoot","method":"_spawn","args":[1,2,[{"_t":"v3","v":[-10.484540939331055,0.0008771783905103803,-21.71038055419922]},[],"scrap",0]],"ch":0,"rel":true,"mode":2}
+ 29.185s S→C binary 129 bytes
len 81 00 00 00   (raw TCP prefix: 129 bytes)
0000 03 02 00 0c 00 4d 61 69 6e 2f 45 6e 65 6d 69 65
0010 73 0e 5f 64 65 73 70 61 77 6e 5f 65 6e 65 6d 79
0020 05 02 00 00 00 01 00 00 00 1c 00 00 00 01 00 00
0030 00 1c 00 00 00 02 00 00 00 09 00 00 00 ae c0 27
0040 c1 72 f2 65 3a dc ae ad c1 04 00 00 00 05 00 00
0050 00 73 63 72 61 70 00 00 00 09 00 00 00 ae c0 27
0060 c1 72 f2 65 3a dc ae ad c1 09 00 00 00 04 97 b9
0070 be 00 00 00 00 68 3f 1b bf 01 00 00 00 00 00 00
     … (hex truncated)
     = {"t":"rpc","node":"Main/Enemies","method":"_despawn_enemy","args":[1,[[{"_t":"v3","v":[-10.484540939331055,0.0008771783905103803,-21.71038055419922]},"scrap"]],{"_t":"v3","v":[-10.484540939331055,0.0008771783905103803,-21.71038055419922]},{"_t":"v3","v":[-0.3624802827835083,0.0,-0.6064362525939941]},false],"ch":0,"rel":true,"mode":2}
```
> Lightning: negative seed = ambient, positive = tactical (item) strike.

```text
+ 37.510s S→C binary 56 bytes
len 38 00 00 00   (raw TCP prefix: 56 bytes)
0000 03 02 00 0e 00 57 65 61 74 68 65 72 4d 61 6e 61
0010 67 65 72 07 5f 73 74 72 69 6b 65 02 09 00 00 00
0020 0a a9 d9 40 00 00 00 00 63 75 2d 42 02 00 01 00
0030 7b 40 5d 09 ff ff ff ff
     = {"t":"rpc","node":"WeatherManager","method":"_strike","args":[{"_t":"v3","v":[6.801884651184082,0.0,43.3646354675293]},-4137860997],"ch":0,"rel":true,"mode":2}
+ 62.435s S→C binary 56 bytes
len 38 00 00 00   (raw TCP prefix: 56 bytes)
0000 03 02 00 0e 00 57 65 61 74 68 65 72 4d 61 6e 61
0010 67 65 72 07 5f 73 74 72 69 6b 65 02 09 00 00 00
0020 76 22 21 c2 00 00 00 00 ef 60 54 c1 02 00 01 00
0030 99 62 52 13 ff ff ff ff
     = {"t":"rpc","node":"WeatherManager","method":"_strike","args":[{"_t":"v3","v":[-40.283653259277344,0.0,-13.273665428161621]},-3970800999],"ch":0,"rel":true,"mode":2}
+ 63.756s C→S binary 105 bytes
len 69 00 00 00   (raw TCP prefix: 105 bytes)
0000 03 02 00 33 00 4d 61 69 6e 2f 50 6c 61 79 65 72
0010 73 2f 50 5f 32 33 34 32 38 39 37 34 35 2f 48 65
0020 61 64 2f 43 61 6d 65 72 61 33 44 2f 57 65 61 70
0030 6f 6e 48 6f 6c 64 65 72 07 5f 61 63 74 69 6f 6e
0040 04 02 00 00 00 01 00 00 00 04 00 00 00 06 00 00
0050 00 72 65 6c 6f 61 64 00 00 02 00 00 00 02 00 00
0060 00 02 00 00 00 ff ff ff ff
     = {"t":"rpc","node":"Main/Players/P_234289745/Head/Camera3D/WeaponHolder","method":"_action","args":[1,"reload",2,-1],"ch":0,"rel":true}
+ 63.758s S→C binary 138 bytes
len 8a 00 00 00   (raw TCP prefix: 138 bytes)
0000 03 02 00 33 00 4d 61 69 6e 2f 50 6c 61 79 65 72
0010 73 2f 50 5f 32 33 34 32 38 39 37 34 35 2f 48 65
0020 61 64 2f 43 61 6d 65 72 61 33 44 2f 57 65 61 70
0030 6f 6e 48 6f 6c 64 65 72 0c 5f 65 71 75 69 70 5f
0040 73 74 61 74 65 06 02 00 00 00 01 00 00 00 02 00
0050 00 00 1b 00 00 00 04 00 00 00 0b 00 00 00 6e 61
0060 69 6c 5f 64 72 69 76 65 72 00 02 00 00 00 00 00
0070 00 00 03 00 01 00 66 66 66 66 66 66 fa 3f 03 00
0080 01 00 66 66 66 66 66 66 fa 3f
     = {"t":"rpc","node":"Main/Players/P_234289745/Head/Camera3D/WeaponHolder","method":"_equip_state","args":[1,27,"nail_driver",0,1.65,1.65],"ch":0,"rel":true,"mode":2}
+ 65.411s S→C binary 134 bytes
len 86 00 00 00   (raw TCP prefix: 134 bytes)
0000 03 02 00 33 00 4d 61 69 6e 2f 50 6c 61 79 65 72
0010 73 2f 50 5f 32 33 34 32 38 39 37 34 35 2f 48 65
0020 61 64 2f 43 61 6d 65 72 61 33 44 2f 57 65 61 70
0030 6f 6e 48 6f 6c 64 65 72 0c 5f 65 71 75 69 70 5f
0040 73 74 61 74 65 06 02 00 00 00 01 00 00 00 02 00
0050 00 00 1c 00 00 00 04 00 00 00 0b 00 00 00 6e 61
0060 69 6c 5f 64 72 69 76 65 72 00 02 00 00 00 00 00
0070 00 00 03 00 00 00 00 00 00 00 03 00 01 00 66 66
     … (hex truncated)
     = {"t":"rpc","node":"Main/Players/P_234289745/Head/Camera3D/WeaponHolder","method":"_equip_state","args":[1,28,"nail_driver",0,0.0,1.65],"ch":0,"rel":true,"mode":2}
+ 70.627s C→S binary 105 bytes
len 69 00 00 00   (raw TCP prefix: 105 bytes)
0000 03 02 00 33 00 4d 61 69 6e 2f 50 6c 61 79 65 72
0010 73 2f 50 5f 32 33 34 32 38 39 37 34 35 2f 48 65
0020 61 64 2f 43 61 6d 65 72 61 33 44 2f 57 65 61 70
0030 6f 6e 48 6f 6c 64 65 72 07 5f 61 63 74 69 6f 6e
0040 04 02 00 00 00 01 00 00 00 04 00 00 00 06 00 00
0050 00 72 65 6c 6f 61 64 00 00 02 00 00 00 02 00 00
0060 00 02 00 00 00 ff ff ff ff
     = {"t":"rpc","node":"Main/Players/P_234289745/Head/Camera3D/WeaponHolder","method":"_action","args":[1,"reload",2,-1],"ch":0,"rel":true}
```

Repeats not shown in this section: 1874× `S→C _relay_transform`, 1070× `C→S _push_transform`, 802× `S→C _sync_enemies`, 492× `S→C _apply_vitals`, 188× `S→C _sync_progress`, 65× `S→C _shot_fx`, 56× `S→C _private_state`, 52× `S→C _rtt_ping`, 52× `C→S _rtt_pong`, 52× `C→S _request_shot`, 41× `S→C _spawn`, 40× `S→C _despawn_enemy`, 38× `S→C _enemy_impacts`, 37× `S→C _spawn_enemy`, 34× `S→C _receive_hits`, 23× `S→C _equip_state`, 5× `S→C _receive_group_warning`.

## Run: wave 1 clearing

```text
+ 73.778s S→C binary 59 bytes
len 3b 00 00 00   (raw TCP prefix: 59 bytes)
0000 03 02 00 0e 00 57 65 61 74 68 65 72 4d 61 6e 61
0010 67 65 72 0e 5f 72 65 63 65 69 76 65 5f 70 68 61
0020 73 65 03 02 00 00 00 04 00 00 00 02 00 00 00 01
0030 00 00 00 03 00 00 00 00 00 70 41
     = {"t":"rpc","node":"WeatherManager","method":"_receive_phase","args":[4,1,15.0],"ch":0,"rel":true,"mode":2}
+ 73.778s S→C binary 59 bytes
len 3b 00 00 00   (raw TCP prefix: 59 bytes)
0000 03 02 00 11 00 47 61 6d 65 4d 61 6e 61 67 65 72
0010 2f 46 65 61 74 73 0b 5f 66 65 61 74 5f 65 76 65
0020 6e 74 02 04 00 00 00 07 00 00 00 6e 6f 5f 72 6f
0030 6f 66 00 02 00 00 00 01 00 00 00
     = {"t":"rpc","node":"GameManager/Feats","method":"_feat_event","args":["no_roof",1],"ch":0,"rel":true,"mode":2}
```
> Centre-screen banner text, colour, seconds.

```text
+ 73.778s S→C binary 77 bytes
len 4d 00 00 00   (raw TCP prefix: 77 bytes)
0000 03 02 00 0b 00 47 61 6d 65 4d 61 6e 61 67 65 72
0010 07 5f 62 61 6e 6e 65 72 03 04 00 00 00 0c 00 00
0020 00 57 41 56 45 20 31 20 43 4c 45 41 52 14 00 00
0030 00 cd cc cc 3e e0 df 5f 3f db da 5a 3f 00 00 80
0040 3f 03 00 01 00 9a 99 99 99 99 99 01 40
     = {"t":"rpc","node":"GameManager","method":"_banner","args":["WAVE 1 CLEAR",{"_t":"color","v":[0.4000000059604645,0.8745098114013672,0.8549019694328308,1.0]},2.2],"ch":0,"rel":true,"mode":2}
+ 73.778s S→C binary 41 bytes
len 29 00 00 00   (raw TCP prefix: 41 bytes)
0000 03 02 00 18 00 47 61 6d 65 4d 61 6e 61 67 65 72
0010 2f 4d 75 74 61 74 69 6f 6e 52 6f 6c 6c 0a 5f 63
0020 6c 65 61 72 5f 72 70 63 00
     = {"t":"rpc","node":"GameManager/MutationRoll","method":"_clear_rpc","args":[],"ch":0,"rel":true,"mode":2}
+ 73.792s C→S binary 32 bytes
len 20 00 00 00   (raw TCP prefix: 32 bytes)
0000 03 02 00 0b 00 47 61 6d 65 4d 61 6e 61 67 65 72
0010 0e 5f 72 65 71 75 65 73 74 5f 72 65 61 64 79 00
     = {"t":"rpc","node":"GameManager","method":"_request_ready","args":[],"ch":0,"rel":true}
+ 73.794s S→C binary 73 bytes
len 49 00 00 00   (raw TCP prefix: 73 bytes)
0000 03 01 00 0c 00 4d 61 69 6e 2f 45 6e 65 6d 69 65
0010 73 0e 5f 73 79 6e 63 5f 70 72 6f 67 72 65 73 73
0020 05 02 00 00 00 01 00 00 00 02 00 00 00 00 00 00
0030 00 02 00 00 00 2a 00 00 00 03 00 00 00 00 00 00
0040 00 02 00 00 00 00 00 00 00
     = {"t":"rpc","node":"Main/Enemies","method":"_sync_progress","args":[1,0,42,0.0,0],"ch":0,"rel":false,"mode":1}
+ 73.794s S→C binary 48 bytes
len 30 00 00 00   (raw TCP prefix: 48 bytes)
0000 03 02 00 0b 00 47 61 6d 65 4d 61 6e 61 67 65 72
0010 0e 5f 72 65 61 64 79 5f 63 68 61 6e 67 65 64 02
0020 02 00 00 00 01 00 00 00 02 00 00 00 02 00 00 00
     = {"t":"rpc","node":"GameManager","method":"_ready_changed","args":[1,2],"ch":0,"rel":true,"mode":2}
+ 73.794s S→C binary 87 bytes
len 57 00 00 00   (raw TCP prefix: 87 bytes)
0000 03 01 00 10 00 4d 61 69 6e 2f 50 6c 61 79 65 72
0010 73 2f 50 5f 32 10 5f 72 65 6c 61 79 5f 74 72 61
0020 6e 73 66 6f 72 6d 04 09 00 00 00 00 00 00 c0 da
0030 af 75 3d 00 00 00 3f 03 00 00 00 be 9f ba 3f 03
0040 00 00 00 77 be 1f bd 09 00 00 00 00 00 00 00 00
0050 00 00 00 00 00 00 00
     = {"t":"rpc","node":"Main/Players/P_2","method":"_relay_transform","args":[{"_t":"v3","v":[-2.0,0.05998215824365616,0.5]},1.4579999446868896,-0.039000000804662704,{"_t":"v3","v":[0.0,0.0,0.0]}],"ch":0,"rel":false,"mode":1}
+ 73.794s S→C binary 104 bytes
len 68 00 00 00   (raw TCP prefix: 104 bytes)
0000 03 01 00 10 00 4d 61 69 6e 2f 50 6c 61 79 65 72
0010 73 2f 50 5f 32 0d 5f 61 70 70 6c 79 5f 76 69 74
0020 61 6c 73 08 03 00 00 00 00 00 c8 42 03 00 00 00
0030 00 00 34 42 04 00 00 00 02 00 00 00 6f 6b 00 00
0040 03 00 00 00 00 00 00 00 01 00 00 00 00 00 00 00
0050 03 00 00 00 00 00 c8 42 03 00 00 00 00 00 00 00
0060 01 00 00 00 00 00 00 00
     = {"t":"rpc","node":"Main/Players/P_2","method":"_apply_vitals","args":[100.0,45.0,"ok",0.0,false,100.0,0.0,false],"ch":0,"rel":false,"mode":1}
+ 73.794s S→C binary 112 bytes
len 70 00 00 00   (raw TCP prefix: 112 bytes)
0000 03 01 00 18 00 4d 61 69 6e 2f 50 6c 61 79 65 72
0010 73 2f 50 5f 32 33 34 32 38 39 37 34 35 0d 5f 61
0020 70 70 6c 79 5f 76 69 74 61 6c 73 08 03 00 00 00
0030 00 00 c8 42 03 00 00 00 00 00 34 42 04 00 00 00
0040 02 00 00 00 6f 6b 00 00 03 00 00 00 00 00 00 00
0050 01 00 00 00 00 00 00 00 03 00 00 00 00 00 c8 42
0060 03 00 00 00 00 00 00 00 01 00 00 00 00 00 00 00
     = {"t":"rpc","node":"Main/Players/P_234289745","method":"_apply_vitals","args":[100.0,45.0,"ok",0.0,false,100.0,0.0,false],"ch":0,"rel":false,"mode":1}
+ 73.822s C→S binary 98 bytes
len 62 00 00 00   (raw TCP prefix: 98 bytes)
0000 03 01 00 18 00 4d 61 69 6e 2f 50 6c 61 79 65 72
0010 73 2f 50 5f 32 33 34 32 38 39 37 34 35 0f 5f 70
0020 75 73 68 5f 74 72 61 6e 73 66 6f 72 6d 04 09 00
0030 00 00 77 89 3a 40 00 00 00 00 60 5a 30 bf 03 00
0040 01 00 75 b3 ce 7c c8 9c 01 c0 03 00 00 00 00 00
0050 00 00 09 00 00 00 13 0a 9b 3f 00 00 00 00 70 71
0060 62 3f
     = {"t":"rpc","node":"Main/Players/P_234289745","method":"_push_transform","args":[{"_t":"v3","v":[2.9146402358649506,0.0,-0.6888789841430065]},-2.2015542746143475,0.0,{"_t":"v3","v":[1.2112449223589916,0.0,0.8845434003597852]}],"ch":0,"rel":false}
+ 73.824s S→C binary 99 bytes
len 63 00 00 00   (raw TCP prefix: 99 bytes)
0000 03 01 00 18 00 4d 61 69 6e 2f 50 6c 61 79 65 72
0010 73 2f 50 5f 32 33 34 32 38 39 37 34 35 10 5f 72
0020 65 6c 61 79 5f 74 72 61 6e 73 66 6f 72 6d 04 09
0030 00 00 00 77 89 3a 40 00 00 00 00 60 5a 30 bf 03
0040 00 01 00 75 b3 ce 7c c8 9c 01 c0 03 00 00 00 00
0050 00 00 00 09 00 00 00 13 0a 9b 3f 00 00 00 00 70
0060 71 62 3f
     = {"t":"rpc","node":"Main/Players/P_234289745","method":"_relay_transform","args":[{"_t":"v3","v":[2.914640188217163,0.0,-0.6888790130615234]},-2.2015542746143475,0.0,{"_t":"v3","v":[1.2112449407577515,0.0,0.8845434188842773]}],"ch":0,"rel":false,"mode":1}
```
> World pickup collected/expired: `[run_id, pickup_id, collector]`.

```text
+ 73.870s S→C binary 50 bytes
len 32 00 00 00   (raw TCP prefix: 50 bytes)
0000 03 02 00 0c 00 4d 61 69 6e 2f 52 75 6e 4c 6f 6f
0010 74 07 5f 72 65 6d 6f 76 65 03 02 00 00 00 01 00
0020 00 00 02 00 00 00 01 00 00 00 02 00 00 00 00 00
0030 00 00
     = {"t":"rpc","node":"Main/RunLoot","method":"_remove","args":[1,1,0],"ch":0,"rel":true,"mode":2}
+ 73.884s C→S binary 98 bytes
len 62 00 00 00   (raw TCP prefix: 98 bytes)
0000 03 01 00 18 00 4d 61 69 6e 2f 50 6c 61 79 65 72
0010 73 2f 50 5f 32 33 34 32 38 39 37 34 35 0f 5f 70
0020 75 73 68 5f 74 72 61 6e 73 66 6f 72 6d 04 09 00
0030 00 00 43 44 3e 40 00 00 00 00 28 45 24 bf 03 00
0040 01 00 d0 19 35 e3 2e 03 02 c0 03 00 00 00 00 00
0050 00 00 09 00 00 00 d7 2f 95 3f 00 00 00 00 58 a8
0060 71 3f
     = {"t":"rpc","node":"Main/Players/P_234289745","method":"_push_transform","args":[{"_t":"v3","v":[2.972916357728665,0.0,-0.641680235820866]},-2.2515542746143424,0.0,{"_t":"v3","v":[1.165522437274289,0.0,0.943974966442811]}],"ch":0,"rel":false}
+ 73.917s S→C binary 48 bytes
len 30 00 00 00   (raw TCP prefix: 48 bytes)
0000 03 02 00 0b 00 47 61 6d 65 4d 61 6e 61 67 65 72
0010 0e 5f 72 65 61 64 79 5f 63 68 61 6e 67 65 64 02
0020 02 00 00 00 02 00 00 00 02 00 00 00 02 00 00 00
     = {"t":"rpc","node":"GameManager","method":"_ready_changed","args":[2,2],"ch":0,"rel":true,"mode":2}
+ 73.917s S→C binary 59 bytes
len 3b 00 00 00   (raw TCP prefix: 59 bytes)
0000 03 02 00 0e 00 57 65 61 74 68 65 72 4d 61 6e 61
0010 67 65 72 0e 5f 72 65 63 65 69 76 65 5f 70 68 61
0020 73 65 03 02 00 00 00 04 00 00 00 02 00 00 00 01
0030 00 00 00 03 00 00 00 00 00 40 40
     = {"t":"rpc","node":"WeatherManager","method":"_receive_phase","args":[4,1,3.0],"ch":0,"rel":true,"mode":2}
+ 74.088s S→C binary 73 bytes
len 49 00 00 00   (raw TCP prefix: 73 bytes)
0000 03 01 00 0c 00 4d 61 69 6e 2f 45 6e 65 6d 69 65
0010 73 0e 5f 73 79 6e 63 5f 70 72 6f 67 72 65 73 73
0020 05 02 00 00 00 01 00 00 00 02 00 00 00 00 00 00
0030 00 02 00 00 00 2a 00 00 00 03 00 00 00 00 00 00
0040 00 02 00 00 00 00 00 00 00
     = {"t":"rpc","node":"Main/Enemies","method":"_sync_progress","args":[1,0,42,0.0,0],"ch":0,"rel":false,"mode":1}
+ 74.243s S→C binary 39 bytes
len 27 00 00 00   (raw TCP prefix: 39 bytes)
0000 03 00 00 03 00 4e 65 74 09 5f 72 74 74 5f 70 69
0010 6e 67 02 02 00 00 00 48 00 00 00 03 00 01 00 c7
0020 bf be 4d 18 7e 31 40
     = {"t":"rpc","node":"Net","method":"_rtt_ping","args":[72,17.49255834490739],"ch":0,"rel":false,"mode":0}
+ 74.244s C→S binary 27 bytes
len 1b 00 00 00   (raw TCP prefix: 27 bytes)
0000 03 00 00 03 00 4e 65 74 09 5f 72 74 74 5f 70 6f
0010 6e 67 01 02 00 00 00 48 00 00 00
     = {"t":"rpc","node":"Net","method":"_rtt_pong","args":[72],"ch":0,"rel":false}
+ 74.260s S→C binary 50 bytes
len 32 00 00 00   (raw TCP prefix: 50 bytes)
0000 03 02 00 0c 00 4d 61 69 6e 2f 52 75 6e 4c 6f 6f
0010 74 07 5f 72 65 6d 6f 76 65 03 02 00 00 00 01 00
0020 00 00 02 00 00 00 02 00 00 00 02 00 00 00 00 00
0030 00 00
     = {"t":"rpc","node":"Main/RunLoot","method":"_remove","args":[1,2,0],"ch":0,"rel":true,"mode":2}
+ 75.242s S→C binary 39 bytes
len 27 00 00 00   (raw TCP prefix: 39 bytes)
0000 03 00 00 03 00 4e 65 74 09 5f 72 74 74 5f 70 69
0010 6e 67 02 02 00 00 00 49 00 00 00 03 00 01 00 a5
0020 ec 6b 36 44 58 31 40
     = {"t":"rpc","node":"Net","method":"_rtt_ping","args":[73,17.344790841435174],"ch":0,"rel":false,"mode":0}
+ 75.242s C→S binary 27 bytes
len 1b 00 00 00   (raw TCP prefix: 27 bytes)
0000 03 00 00 03 00 4e 65 74 09 5f 72 74 74 5f 70 6f
0010 6e 67 01 02 00 00 00 49 00 00 00
     = {"t":"rpc","node":"Net","method":"_rtt_pong","args":[73],"ch":0,"rel":false}
```

Repeats not shown in this section: 107× `S→C _relay_transform`, 60× `C→S _push_transform`, 28× `S→C _apply_vitals`, 10× `S→C _sync_progress`, 3× `S→C _remove`, 1× `S→C _rtt_ping`, 1× `C→S _rtt_pong`.

## Run: wave 2 calm

```text
+ 76.909s S→C binary 59 bytes
len 3b 00 00 00   (raw TCP prefix: 59 bytes)
0000 03 02 00 0e 00 57 65 61 74 68 65 72 4d 61 6e 61
0010 67 65 72 0e 5f 72 65 63 65 69 76 65 5f 70 68 61
0020 73 65 03 02 00 00 00 00 00 00 00 02 00 00 00 02
0030 00 00 00 03 00 00 00 00 00 f0 41
     = {"t":"rpc","node":"WeatherManager","method":"_receive_phase","args":[0,2,30.0],"ch":0,"rel":true,"mode":2}
+ 76.909s S→C binary 233 bytes
len e9 00 00 00   (raw TCP prefix: 233 bytes)
0000 03 02 00 18 00 47 61 6d 65 4d 61 6e 61 67 65 72
0010 2f 43 72 61 74 65 4d 61 6e 61 67 65 72 06 5f 73
0020 74 6f 63 6b 03 02 00 00 00 01 00 00 00 04 00 00
0030 00 0f 00 00 00 48 61 72 64 77 61 72 65 53 74 61
0040 74 69 6f 6e 00 1c 00 00 00 03 00 00 00 1c 00 00
0050 00 04 00 00 00 04 00 00 00 0a 00 00 00 73 75 69
0060 74 5f 70 61 74 63 68 00 00 02 00 00 00 00 00 00
0070 00 02 00 00 00 06 00 00 00 02 00 00 00 0a 00 00
0080 00 1c 00 00 00 04 00 00 00 04 00 00 00 0f 00 00
0090 00 70 72 65 73 73 75 72 65 5f 77 61 73 68 65 72
00a0 00 02 00 00 00 01 00 00 00 02 00 00 00 0a 00 00
00b0 00 02 00 00 00 0b 00 00 00 1c 00 00 00 04 00 00
00c0 00 04 00 00 00 07 00 00 00 68 61 72 70 6f 6f 6e
00d0 00 02 00 00 00 02 00 00 00 02 00 00 00 12 00 00
00e0 00 02 00 00 00 0c 00 00 00
     = {"t":"rpc","node":"GameManager/CrateManager","method":"_stock","args":[1,"HardwareStation",[["suit_patch",0,6,10],["pressure_washer",1,10,11],["harpoon",2,18,12]]],"ch":0,"rel":true,"mode":2}
+ 76.909s S→C binary 225 bytes
len e1 00 00 00   (raw TCP prefix: 225 bytes)
0000 03 02 00 18 00 47 61 6d 65 4d 61 6e 61 67 65 72
0010 2f 43 72 61 74 65 4d 61 6e 61 67 65 72 06 5f 73
0020 74 6f 63 6b 03 02 00 00 00 01 00 00 00 04 00 00
0030 00 11 00 00 00 47 61 73 53 74 61 74 69 6f 6e 53
0040 75 72 70 6c 75 73 00 00 00 1c 00 00 00 03 00 00
0050 00 1c 00 00 00 04 00 00 00 04 00 00 00 04 00 00
0060 00 66 72 61 67 02 00 00 00 00 00 00 00 02 00 00
0070 00 06 00 00 00 02 00 00 00 0d 00 00 00 1c 00 00
     … (hex truncated)
     = {"t":"rpc","node":"GameManager/CrateManager","method":"_stock","args":[1,"GasStationSurplus",[["frag",0,6,13],["pump_shotgun",1,10,14],["harpoon",2,18,15]]],"ch":0,"rel":true,"mode":2}
+ 76.909s S→C binary 93 bytes
len 5d 00 00 00   (raw TCP prefix: 93 bytes)
0000 03 02 00 0b 00 47 61 6d 65 4d 61 6e 61 67 65 72
0010 07 5f 62 61 6e 6e 65 72 03 04 00 00 00 1b 00 00
0020 00 53 55 52 50 4c 55 53 20 53 55 50 50 4c 59 20
0030 44 52 4f 50 20 49 4e 42 4f 55 4e 44 00 14 00 00
0040 00 cb fd 70 3f c3 8f 5c 3f 48 7b 2e 3f 00 00 80
0050 3f 03 00 01 00 9a 99 99 99 99 99 09 40
     = {"t":"rpc","node":"GameManager","method":"_banner","args":["SURPLUS SUPPLY DROP INBOUND",{"_t":"color","v":[0.9413725733757019,0.8615686297416687,0.6815686225891113,1.0]},3.2],"ch":0,"rel":true,"mode":2}
+ 76.909s S→C binary 53 bytes
len 35 00 00 00   (raw TCP prefix: 53 bytes)
0000 03 02 00 18 00 47 61 6d 65 4d 61 6e 61 67 65 72
0010 2f 43 72 61 74 65 4d 61 6e 61 67 65 72 0e 5f 61
0020 6e 6e 6f 75 6e 63 65 5f 64 72 6f 70 01 02 00 00
0030 00 01 00 00 00
     = {"t":"rpc","node":"GameManager/CrateManager","method":"_announce_drop","args":[1],"ch":0,"rel":true,"mode":2}
+ 76.922s C→S binary 32 bytes
len 20 00 00 00   (raw TCP prefix: 32 bytes)
0000 03 02 00 0b 00 47 61 6d 65 4d 61 6e 61 67 65 72
0010 0e 5f 72 65 71 75 65 73 74 5f 72 65 61 64 79 00
     = {"t":"rpc","node":"GameManager","method":"_request_ready","args":[],"ch":0,"rel":true}
+ 76.923s C→S binary 98 bytes
len 62 00 00 00   (raw TCP prefix: 98 bytes)
0000 03 01 00 18 00 4d 61 69 6e 2f 50 6c 61 79 65 72
0010 73 2f 50 5f 32 33 34 32 38 39 37 34 35 0f 5f 70
0020 75 73 68 5f 74 72 61 6e 73 66 6f 72 6d 04 09 00
0030 00 00 db 5a 91 3f 00 00 00 00 b5 e9 dc 3f 03 00
0040 01 00 03 68 b3 7b 85 69 ef 3f 03 00 00 00 00 00
0050 00 00 09 00 00 00 f4 9c 9f bf 00 00 00 00 9f 5a
0060 55 bf
     = {"t":"rpc","node":"Main/Players/P_234289745","method":"_push_transform","args":[{"_t":"v3","v":[1.1355851662067755,0.0,1.7258821293738775]},0.981631032565247,0.0,{"_t":"v3","v":[-1.2469772780568622,0.0,-0.8334140370010568]}],"ch":0,"rel":false}
+ 76.925s S→C binary 81 bytes
len 51 00 00 00   (raw TCP prefix: 81 bytes)
0000 03 02 00 18 00 47 61 6d 65 4d 61 6e 61 67 65 72
0010 2f 43 72 61 74 65 4d 61 6e 61 67 65 72 0e 5f 61
0020 69 72 64 72 6f 70 5f 73 70 61 77 6e 03 02 00 00
0030 00 01 00 00 00 09 00 00 00 00 00 00 00 30 5c 8f
0040 3d 00 00 40 c1 03 00 01 00 33 33 33 33 33 33 03
0050 40
     = {"t":"rpc","node":"GameManager/CrateManager","method":"_airdrop_spawn","args":[1,{"_t":"v3","v":[0.0,0.0700000524520874,-12.0]},2.4],"ch":0,"rel":true,"mode":2}
```

Repeats not shown in this section: 1× `S→C _stock`.

## Mutation draft

> Mutation draft: enemy mutation id + 3 player mutation card ids. Vote with `_request_vote(i)`.

```text
+ 76.925s S→C binary 128 bytes
len 80 00 00 00   (raw TCP prefix: 128 bytes)
0000 03 02 00 18 00 47 61 6d 65 4d 61 6e 61 67 65 72
0010 2f 4d 75 74 61 74 69 6f 6e 52 6f 6c 6c 09 5f 64
0020 65 61 6c 5f 72 70 63 02 04 00 00 00 00 00 00 00
0030 1c 00 00 00 03 00 00 00 04 00 00 00 0e 00 00 00
0040 72 65 66 6c 65 78 5f 74 65 6e 64 6f 6e 73 00 00
0050 04 00 00 00 0b 00 00 00 63 68 69 74 69 6e 5f 73
0060 75 69 74 00 04 00 00 00 11 00 00 00 61 64 72 65
0070 6e 61 6c 69 6e 65 5f 67 6c 61 6e 64 73 00 00 00
     = {"t":"rpc","node":"GameManager/MutationRoll","method":"_deal_rpc","args":["",["reflex_tendons","chitin_suit","adrenaline_glands"]],"ch":0,"rel":true,"mode":2}
```
> Vote for card index.

```text
+ 76.925s C→S binary 52 bytes
len 34 00 00 00   (raw TCP prefix: 52 bytes)
0000 03 02 00 18 00 47 61 6d 65 4d 61 6e 61 67 65 72
0010 2f 4d 75 74 61 74 69 6f 6e 52 6f 6c 6c 0d 5f 72
0020 65 71 75 65 73 74 5f 76 6f 74 65 01 02 00 00 00
0030 00 00 00 00
     = {"t":"rpc","node":"GameManager/MutationRoll","method":"_request_vote","args":[0],"ch":0,"rel":true}
+ 76.925s S→C binary 77 bytes
len 4d 00 00 00   (raw TCP prefix: 77 bytes)
0000 03 01 00 0c 00 4d 61 69 6e 2f 45 6e 65 6d 69 65
0010 73 0e 5f 73 79 6e 63 5f 70 72 6f 67 72 65 73 73
0020 05 02 00 00 00 02 00 00 00 02 00 00 00 36 00 00
0030 00 02 00 00 00 36 00 00 00 03 00 01 00 cd cc cc
0040 cc cc cc 00 40 02 00 00 00 00 00 00 00
     = {"t":"rpc","node":"Main/Enemies","method":"_sync_progress","args":[2,54,54,2.1,0],"ch":0,"rel":false,"mode":1}
+ 76.925s S→C binary 50 bytes
len 32 00 00 00   (raw TCP prefix: 50 bytes)
0000 03 02 00 0c 00 4d 61 69 6e 2f 52 75 6e 4c 6f 6f
0010 74 07 5f 72 65 6d 6f 76 65 03 02 00 00 00 01 00
0020 00 00 02 00 00 00 06 00 00 00 02 00 00 00 00 00
0030 00 00
     = {"t":"rpc","node":"Main/RunLoot","method":"_remove","args":[1,6,0],"ch":0,"rel":true,"mode":2}
+ 76.925s S→C binary 99 bytes
len 63 00 00 00   (raw TCP prefix: 99 bytes)
0000 03 01 00 18 00 4d 61 69 6e 2f 50 6c 61 79 65 72
0010 73 2f 50 5f 32 33 34 32 38 39 37 34 35 10 5f 72
0020 65 6c 61 79 5f 74 72 61 6e 73 66 6f 72 6d 04 09
0030 00 00 00 db 5a 91 3f 00 00 00 00 b5 e9 dc 3f 03
0040 00 01 00 03 68 b3 7b 85 69 ef 3f 03 00 00 00 00
0050 00 00 00 09 00 00 00 f4 9c 9f bf 00 00 00 00 9f
0060 5a 55 bf
     = {"t":"rpc","node":"Main/Players/P_234289745","method":"_relay_transform","args":[{"_t":"v3","v":[1.1355851888656616,0.0,1.7258821725845337]},0.981631032565247,0.0,{"_t":"v3","v":[-1.2469773292541504,0.0,-0.8334140181541443]}],"ch":0,"rel":false,"mode":1}
```
> Vote tally `[n0, n1, n2]`.

```text
+ 76.925s S→C binary 73 bytes
len 49 00 00 00   (raw TCP prefix: 73 bytes)
0000 03 02 00 18 00 47 61 6d 65 4d 61 6e 61 67 65 72
0010 2f 4d 75 74 61 74 69 6f 6e 52 6f 6c 6c 0a 5f 76
0020 6f 74 65 73 5f 72 70 63 01 1c 00 00 00 03 00 00
0030 00 02 00 00 00 01 00 00 00 02 00 00 00 00 00 00
0040 00 02 00 00 00 00 00 00 00
     = {"t":"rpc","node":"GameManager/MutationRoll","method":"_votes_rpc","args":[[1,0,0]],"ch":0,"rel":true,"mode":2}
+ 76.926s S→C binary 87 bytes
len 57 00 00 00   (raw TCP prefix: 87 bytes)
0000 03 01 00 10 00 4d 61 69 6e 2f 50 6c 61 79 65 72
0010 73 2f 50 5f 32 10 5f 72 65 6c 61 79 5f 74 72 61
0020 6e 73 66 6f 72 6d 04 09 00 00 00 00 00 00 c0 da
0030 af 75 3d 00 00 00 3f 03 00 00 00 be 9f ba 3f 03
0040 00 00 00 00 00 00 00 09 00 00 00 00 00 00 00 00
0050 00 00 00 00 00 00 00
     = {"t":"rpc","node":"Main/Players/P_2","method":"_relay_transform","args":[{"_t":"v3","v":[-2.0,0.05998215824365616,0.5]},1.4579999446868896,0.0,{"_t":"v3","v":[0.0,0.0,0.0]}],"ch":0,"rel":false,"mode":1}
+ 76.940s S→C binary 73 bytes
len 49 00 00 00   (raw TCP prefix: 73 bytes)
0000 03 02 00 18 00 47 61 6d 65 4d 61 6e 61 67 65 72
0010 2f 4d 75 74 61 74 69 6f 6e 52 6f 6c 6c 0a 5f 76
0020 6f 74 65 73 5f 72 70 63 01 1c 00 00 00 03 00 00
0030 00 02 00 00 00 02 00 00 00 02 00 00 00 00 00 00
0040 00 02 00 00 00 00 00 00 00
     = {"t":"rpc","node":"GameManager/MutationRoll","method":"_votes_rpc","args":[[2,0,0]],"ch":0,"rel":true,"mode":2}
+ 76.985s C→S binary 98 bytes
len 62 00 00 00   (raw TCP prefix: 98 bytes)
0000 03 01 00 18 00 4d 61 69 6e 2f 50 6c 61 79 65 72
0010 73 2f 50 5f 32 33 34 32 38 39 37 34 35 0f 5f 70
0020 75 73 68 5f 74 72 61 6e 73 66 6f 72 6d 04 09 00
0030 00 00 9b a6 89 3f 00 00 00 00 d6 2f d7 3f 03 00
0040 01 00 38 ce 19 e2 eb cf ed 3f 03 00 00 00 00 00
0050 00 00 09 00 00 00 fd 14 9a bf 00 00 00 00 c2 0a
0060 65 bf
     = {"t":"rpc","node":"Main/Players/P_234289745","method":"_push_transform","args":[{"_t":"v3","v":[1.0753968892098555,0.0,1.6811473606274485]},0.9316310325652415,0.0,{"_t":"v3","v":[-1.2037655399383995,0.0,-0.8946953749285802]}],"ch":0,"rel":false}
+ 77.031s C→S binary 98 bytes
len 62 00 00 00   (raw TCP prefix: 98 bytes)
0000 03 01 00 18 00 4d 61 69 6e 2f 50 6c 61 79 65 72
0010 73 2f 50 5f 32 33 34 32 38 39 37 34 35 0f 5f 70
0020 75 73 68 5f 74 72 61 6e 73 66 6f 72 6d 04 09 00
0030 00 00 15 3e 82 3f 00 00 00 00 3a 15 d1 3f 03 00
0040 01 00 7f 34 80 48 52 36 ec 3f 03 00 00 00 00 00
0050 00 00 09 00 00 00 6f 2a 94 bf 00 00 00 00 55 28
0060 74 bf
     = {"t":"rpc","node":"Main/Players/P_234289745","method":"_push_transform","args":[{"_t":"v3","v":[1.0175196384659364,0.0,1.6334603386091178]},0.881631032565238,0.0,{"_t":"v3","v":[-1.1575450148783828,0.0,-0.953740440366615]}],"ch":0,"rel":false}
+ 77.048s S→C binary 104 bytes
len 68 00 00 00   (raw TCP prefix: 104 bytes)
0000 03 01 00 10 00 4d 61 69 6e 2f 50 6c 61 79 65 72
0010 73 2f 50 5f 32 0d 5f 61 70 70 6c 79 5f 76 69 74
0020 61 6c 73 08 03 00 00 00 00 00 c8 42 03 00 00 00
0030 00 00 34 42 04 00 00 00 02 00 00 00 6f 6b 00 00
0040 03 00 00 00 00 00 00 00 01 00 00 00 00 00 00 00
0050 03 00 00 00 00 00 c8 42 03 00 00 00 00 00 00 00
0060 01 00 00 00 00 00 00 00
     = {"t":"rpc","node":"Main/Players/P_2","method":"_apply_vitals","args":[100.0,45.0,"ok",0.0,false,100.0,0.0,false],"ch":0,"rel":false,"mode":1}
+ 77.048s S→C binary 112 bytes
len 70 00 00 00   (raw TCP prefix: 112 bytes)
0000 03 01 00 18 00 4d 61 69 6e 2f 50 6c 61 79 65 72
0010 73 2f 50 5f 32 33 34 32 38 39 37 34 35 0d 5f 61
0020 70 70 6c 79 5f 76 69 74 61 6c 73 08 03 00 00 00
0030 00 00 c8 42 03 00 00 00 00 00 34 42 04 00 00 00
0040 02 00 00 00 6f 6b 00 00 03 00 00 00 00 00 00 00
0050 01 00 00 00 00 00 00 00 03 00 00 00 00 00 c8 42
0060 03 00 00 00 00 00 00 00 01 00 00 00 00 00 00 00
     = {"t":"rpc","node":"Main/Players/P_234289745","method":"_apply_vitals","args":[100.0,45.0,"ok",0.0,false,100.0,0.0,false],"ch":0,"rel":false,"mode":1}
+ 77.205s S→C binary 77 bytes
len 4d 00 00 00   (raw TCP prefix: 77 bytes)
0000 03 01 00 0c 00 4d 61 69 6e 2f 45 6e 65 6d 69 65
0010 73 0e 5f 73 79 6e 63 5f 70 72 6f 67 72 65 73 73
0020 05 02 00 00 00 02 00 00 00 02 00 00 00 36 00 00
0030 00 02 00 00 00 36 00 00 00 03 00 01 00 cd cc cc
0040 cc cc cc 00 40 02 00 00 00 00 00 00 00
     = {"t":"rpc","node":"Main/Enemies","method":"_sync_progress","args":[2,54,54,2.1,0],"ch":0,"rel":false,"mode":1}
+ 77.253s S→C binary 39 bytes
len 27 00 00 00   (raw TCP prefix: 39 bytes)
0000 03 00 00 03 00 4e 65 74 09 5f 72 74 74 5f 70 69
0010 6e 67 02 02 00 00 00 4b 00 00 00 03 00 01 00 b8
0020 29 96 6c 21 26 30 40
     = {"t":"rpc","node":"Net","method":"_rtt_ping","args":[75,16.148947512303238],"ch":0,"rel":false,"mode":0}
+ 77.253s C→S binary 27 bytes
len 1b 00 00 00   (raw TCP prefix: 27 bytes)
0000 03 00 00 03 00 4e 65 74 09 5f 72 74 74 5f 70 6f
0010 6e 67 01 02 00 00 00 4b 00 00 00
     = {"t":"rpc","node":"Net","method":"_rtt_pong","args":[75],"ch":0,"rel":false}
```
> Draft result: `[pick, enemy_list, player_list, granted]`; resume the Calm countdown after 2.2 s.

```text
+ 77.533s S→C binary 126 bytes
len 7e 00 00 00   (raw TCP prefix: 126 bytes)
0000 03 02 00 18 00 47 61 6d 65 4d 61 6e 61 67 65 72
0010 2f 4d 75 74 61 74 69 6f 6e 52 6f 6c 6c 0b 5f 72
0020 65 73 75 6c 74 5f 72 70 63 04 02 00 00 00 00 00
0030 00 00 1c 00 00 00 00 00 00 00 1c 00 01 00 04 00
0040 00 00 01 00 00 00 04 00 00 00 0e 00 00 00 72 65
0050 66 6c 65 78 5f 74 65 6e 64 6f 6e 73 00 00 1c 00
0060 00 00 01 00 00 00 04 00 00 00 0e 00 00 00 72 65
0070 66 6c 65 78 5f 74 65 6e 64 6f 6e 73 00 00
     = {"t":"rpc","node":"GameManager/MutationRoll","method":"_result_rpc","args":[0,[],["reflex_tendons"],["reflex_tendons"]],"ch":0,"rel":true,"mode":2}
+ 78.249s S→C binary 39 bytes
len 27 00 00 00   (raw TCP prefix: 39 bytes)
0000 03 00 00 03 00 4e 65 74 09 5f 72 74 74 5f 70 69
0010 6e 67 02 02 00 00 00 4c 00 00 00 03 00 01 00 01
0020 ea 35 ff b0 1a 30 40
     = {"t":"rpc","node":"Net","method":"_rtt_ping","args":[76,16.104263258612267],"ch":0,"rel":false,"mode":0}
+ 78.249s C→S binary 27 bytes
len 1b 00 00 00   (raw TCP prefix: 27 bytes)
0000 03 00 00 03 00 4e 65 74 09 5f 72 74 74 5f 70 6f
0010 6e 67 01 02 00 00 00 4c 00 00 00
     = {"t":"rpc","node":"Net","method":"_rtt_pong","args":[76],"ch":0,"rel":false}
+ 81.994s S→C binary 50 bytes
len 32 00 00 00   (raw TCP prefix: 50 bytes)
0000 03 02 00 0c 00 4d 61 69 6e 2f 52 75 6e 4c 6f 6f
0010 74 07 5f 72 65 6d 6f 76 65 03 02 00 00 00 01 00
0020 00 00 02 00 00 00 07 00 00 00 02 00 00 00 00 00
0030 00 00
     = {"t":"rpc","node":"Main/RunLoot","method":"_remove","args":[1,7,0],"ch":0,"rel":true,"mode":2}
```

Repeats not shown in this section: 1148× `S→C _relay_transform`, 654× `C→S _push_transform`, 300× `S→C _apply_vitals`, 114× `S→C _sync_progress`, 31× `S→C _rtt_ping`, 31× `C→S _rtt_pong`, 28× `S→C _remove`.

## Run: wave 2 drizzle

```text
+109.760s S→C binary 59 bytes
len 3b 00 00 00   (raw TCP prefix: 59 bytes)
0000 03 02 00 0e 00 57 65 61 74 68 65 72 4d 61 6e 61
0010 67 65 72 0e 5f 72 65 63 65 69 76 65 5f 70 68 61
0020 73 65 03 02 00 00 00 02 00 00 00 02 00 00 00 02
0030 00 00 00 03 00 00 00 00 00 f0 41
     = {"t":"rpc","node":"WeatherManager","method":"_receive_phase","args":[2,2,30.0],"ch":0,"rel":true,"mode":2}
+109.760s S→C binary 104 bytes
len 68 00 00 00   (raw TCP prefix: 104 bytes)
0000 03 01 00 10 00 4d 61 69 6e 2f 50 6c 61 79 65 72
0010 73 2f 50 5f 32 0d 5f 61 70 70 6c 79 5f 76 69 74
0020 61 6c 73 08 03 00 00 00 00 00 c8 42 03 00 00 00
0030 00 00 34 42 04 00 00 00 02 00 00 00 6f 6b 00 00
0040 03 00 00 00 00 00 00 00 01 00 00 00 00 00 00 00
0050 03 00 00 00 00 00 c8 42 03 00 00 00 00 00 00 00
0060 01 00 00 00 00 00 00 00
     = {"t":"rpc","node":"Main/Players/P_2","method":"_apply_vitals","args":[100.0,45.0,"ok",0.0,false,100.0,0.0,false],"ch":0,"rel":false,"mode":1}
+109.760s S→C binary 112 bytes
len 70 00 00 00   (raw TCP prefix: 112 bytes)
0000 03 01 00 18 00 4d 61 69 6e 2f 50 6c 61 79 65 72
0010 73 2f 50 5f 32 33 34 32 38 39 37 34 35 0d 5f 61
0020 70 70 6c 79 5f 76 69 74 61 6c 73 08 03 00 00 00
0030 00 00 c8 42 03 00 00 00 00 00 34 42 04 00 00 00
0040 02 00 00 00 6f 6b 00 00 03 00 00 00 00 00 00 00
0050 01 00 00 00 00 00 00 00 03 00 00 00 00 00 c8 42
0060 03 00 00 00 00 00 00 00 01 00 00 00 00 00 00 00
     = {"t":"rpc","node":"Main/Players/P_234289745","method":"_apply_vitals","args":[100.0,45.0,"ok",0.0,false,100.0,0.0,false],"ch":0,"rel":false,"mode":1}
+109.773s C→S binary 98 bytes
len 62 00 00 00   (raw TCP prefix: 98 bytes)
0000 03 01 00 18 00 4d 61 69 6e 2f 50 6c 61 79 65 72
0010 73 2f 50 5f 32 33 34 32 38 39 37 34 35 0f 5f 70
0020 75 73 68 5f 74 72 61 6e 73 66 6f 72 6d 04 09 00
0030 00 00 09 f1 2a 3f 00 00 00 00 56 ce 41 be 03 00
0040 01 00 5e 7f b1 19 d1 f4 dc bf 03 00 00 00 00 00
0050 00 00 09 00 00 00 72 da 27 3f 00 00 00 00 d2 a9
0060 ac bf
     = {"t":"rpc","node":"Main/Players/P_234289745","method":"_push_transform","args":[{"_t":"v3","v":[0.6677404214549745,0.0,-0.1892636762335813]},-0.45244243153682884,0.0,{"_t":"v3","v":[0.6556769677422603,0.0,-1.348932542061616]}],"ch":0,"rel":false}
+109.775s S→C binary 73 bytes
len 49 00 00 00   (raw TCP prefix: 73 bytes)
0000 03 01 00 0c 00 4d 61 69 6e 2f 45 6e 65 6d 69 65
0010 73 0e 5f 73 79 6e 63 5f 70 72 6f 67 72 65 73 73
0020 05 02 00 00 00 02 00 00 00 02 00 00 00 36 00 00
0030 00 02 00 00 00 36 00 00 00 03 00 00 00 00 00 a0
0040 3f 02 00 00 00 00 00 00 00
     = {"t":"rpc","node":"Main/Enemies","method":"_sync_progress","args":[2,54,54,1.25,0],"ch":0,"rel":false,"mode":1}
+109.775s S→C binary 99 bytes
len 63 00 00 00   (raw TCP prefix: 99 bytes)
0000 03 01 00 18 00 4d 61 69 6e 2f 50 6c 61 79 65 72
0010 73 2f 50 5f 32 33 34 32 38 39 37 34 35 10 5f 72
0020 65 6c 61 79 5f 74 72 61 6e 73 66 6f 72 6d 04 09
0030 00 00 00 09 f1 2a 3f 00 00 00 00 56 ce 41 be 03
0040 00 01 00 5e 7f b1 19 d1 f4 dc bf 03 00 00 00 00
0050 00 00 00 09 00 00 00 72 da 27 3f 00 00 00 00 d2
0060 a9 ac bf
     = {"t":"rpc","node":"Main/Players/P_234289745","method":"_relay_transform","args":[{"_t":"v3","v":[0.6677404046058655,0.0,-0.18926367163658142]},-0.45244243153682884,0.0,{"_t":"v3","v":[0.6556769609451294,0.0,-1.3489325046539307]}],"ch":0,"rel":false,"mode":1}
+109.790s S→C binary 87 bytes
len 57 00 00 00   (raw TCP prefix: 87 bytes)
0000 03 01 00 10 00 4d 61 69 6e 2f 50 6c 61 79 65 72
0010 73 2f 50 5f 32 10 5f 72 65 6c 61 79 5f 74 72 61
0020 6e 73 66 6f 72 6d 04 09 00 00 00 00 00 00 c0 da
0030 af 75 3d 00 00 00 3f 03 00 00 00 be 9f ba 3f 03
0040 00 00 00 00 00 00 00 09 00 00 00 00 00 00 00 00
0050 00 00 00 00 00 00 00
     = {"t":"rpc","node":"Main/Players/P_2","method":"_relay_transform","args":[{"_t":"v3","v":[-2.0,0.05998215824365616,0.5]},1.4579999446868896,0.0,{"_t":"v3","v":[0.0,0.0,0.0]}],"ch":0,"rel":false,"mode":1}
+109.835s C→S binary 98 bytes
len 62 00 00 00   (raw TCP prefix: 98 bytes)
0000 03 01 00 18 00 4d 61 69 6e 2f 50 6c 61 79 65 72
0010 73 2f 50 5f 32 33 34 32 38 39 37 34 35 0f 5f 70
0020 75 73 68 5f 74 72 61 6e 73 66 6f 72 6d 04 09 00
0030 00 00 ca 2f 34 3f 00 00 00 00 b9 8d 82 be 03 00
0040 01 00 48 59 72 26 02 14 e0 bf 03 00 00 00 00 00
0050 00 00 09 00 00 00 16 e7 38 3f 00 00 00 00 c4 40
0060 a8 bf
     = {"t":"rpc","node":"Main/Players/P_234289745","method":"_push_transform","args":[{"_t":"v3","v":[0.703854224961074,0.0,-0.25498750310766183]},-0.5024424315368288,0.0,{"_t":"v3","v":[0.7222760701219899,0.0,-1.3144765374816103]}],"ch":0,"rel":false}
+110.069s S→C binary 77 bytes
len 4d 00 00 00   (raw TCP prefix: 77 bytes)
0000 03 01 00 0c 00 4d 61 69 6e 2f 45 6e 65 6d 69 65
0010 73 0e 5f 73 79 6e 63 5f 70 72 6f 67 72 65 73 73
0020 05 02 00 00 00 02 00 00 00 02 00 00 00 36 00 00
0030 00 02 00 00 00 36 00 00 00 03 00 01 00 f6 ee ee
0040 ee ee ee ee 3f 02 00 00 00 00 00 00 00
     = {"t":"rpc","node":"Main/Enemies","method":"_sync_progress","args":[2,54,54,0.9666666666666675,0],"ch":0,"rel":false,"mode":1}
+110.242s S→C binary 39 bytes
len 27 00 00 00   (raw TCP prefix: 39 bytes)
0000 03 00 00 03 00 4e 65 74 09 5f 72 74 74 5f 70 69
0010 6e 67 02 02 00 00 00 6c 00 00 00 03 00 01 00 73
0020 fd bc 3a ed 4b 30 40
     = {"t":"rpc","node":"Net","method":"_rtt_ping","args":[108,16.29658858407988],"ch":0,"rel":false,"mode":0}
+110.243s C→S binary 27 bytes
len 1b 00 00 00   (raw TCP prefix: 27 bytes)
0000 03 00 00 03 00 4e 65 74 09 5f 72 74 74 5f 70 6f
0010 6e 67 01 02 00 00 00 6c 00 00 00
     = {"t":"rpc","node":"Net","method":"_rtt_pong","args":[108],"ch":0,"rel":false}
+111.006s S→C binary 79 bytes
len 4f 00 00 00   (raw TCP prefix: 79 bytes)
0000 03 02 00 0c 00 4d 61 69 6e 2f 45 6e 65 6d 69 65
0010 73 0c 5f 73 70 61 77 6e 5f 65 6e 65 6d 79 05 02
0020 00 00 00 2b 00 00 00 02 00 00 00 00 00 00 00 09
0030 00 00 00 71 6c 21 42 66 66 26 3f 28 d4 75 c2 01
0040 00 00 00 00 00 00 00 01 00 00 00 00 00 00 00
     = {"t":"rpc","node":"Main/Enemies","method":"_spawn_enemy","args":[43,0,{"_t":"v3","v":[40.355899810791016,0.6499999761581421,-61.457183837890625]},false,false],"ch":0,"rel":true,"mode":2}
+111.006s S→C binary 57 bytes
len 39 00 00 00   (raw TCP prefix: 57 bytes)
0000 03 02 00 0c 00 4d 61 69 6e 2f 45 6e 65 6d 69 65
0010 73 16 5f 72 65 63 65 69 76 65 5f 67 72 6f 75 70
0020 5f 77 61 72 6e 69 6e 67 01 09 00 00 00 71 6c 21
0030 42 66 66 26 3f 28 d4 75 c2
     = {"t":"rpc","node":"Main/Enemies","method":"_receive_group_warning","args":[{"_t":"v3","v":[40.355899810791016,0.6499999761581421,-61.457183837890625]}],"ch":0,"rel":true,"mode":2}
+111.066s S→C binary 76 bytes
len 4c 00 00 00   (raw TCP prefix: 76 bytes)
0000 03 01 00 0c 00 4d 61 69 6e 2f 45 6e 65 6d 69 65
0010 73 0d 5f 73 79 6e 63 5f 65 6e 65 6d 69 65 73 03
0020 1e 00 00 00 01 00 00 00 2b 00 00 00 24 00 00 00
0030 01 00 00 00 d1 28 21 42 30 4f 24 3f 1c a0 75 c2
0040 20 00 00 00 01 00 00 00 cb 03 25 40
     = {"t":"rpc","node":"Main/Enemies","method":"_sync_enemies","args":[{"_t":"pi32","v":[43]},{"_t":"pv3","v":[[40.289859771728516,0.6418333053588867,-61.40635681152344]]},{"_t":"pf32","v":[2.5783565044403076]}],"ch":0,"rel":false,"mode":1}
+111.128s S→C binary 76 bytes
len 4c 00 00 00   (raw TCP prefix: 76 bytes)
0000 03 01 00 0c 00 4d 61 69 6e 2f 45 6e 65 6d 69 65
0010 73 0d 5f 73 79 6e 63 5f 65 6e 65 6d 69 65 73 03
0020 1e 00 00 00 01 00 00 00 2b 00 00 00 24 00 00 00
0030 01 00 00 00 91 a1 20 42 ec c3 17 3f 04 38 75 c2
0040 20 00 00 00 01 00 00 00 01 27 25 40
     = {"t":"rpc","node":"Main/Enemies","method":"_sync_enemies","args":[{"_t":"pi32","v":[43]},{"_t":"pv3","v":[[40.157779693603516,0.5928332805633545,-61.30470275878906]]},{"_t":"pf32","v":[2.580505609512329]}],"ch":0,"rel":false,"mode":1}
+111.191s S→C binary 50 bytes
len 32 00 00 00   (raw TCP prefix: 50 bytes)
0000 03 02 00 0c 00 4d 61 69 6e 2f 52 75 6e 4c 6f 6f
0010 74 07 5f 72 65 6d 6f 76 65 03 02 00 00 00 01 00
0020 00 00 02 00 00 00 24 00 00 00 02 00 00 00 00 00
0030 00 00
     = {"t":"rpc","node":"Main/RunLoot","method":"_remove","args":[1,36,0],"ch":0,"rel":true,"mode":2}
+111.238s S→C binary 39 bytes
len 27 00 00 00   (raw TCP prefix: 39 bytes)
0000 03 00 00 03 00 4e 65 74 09 5f 72 74 74 5f 70 69
0010 6e 67 02 02 00 00 00 6d 00 00 00 03 00 01 00 04
0020 4b 84 0f 26 35 30 40
     = {"t":"rpc","node":"Net","method":"_rtt_ping","args":[109,16.207612008855918],"ch":0,"rel":false,"mode":0}
+111.238s C→S binary 27 bytes
len 1b 00 00 00   (raw TCP prefix: 27 bytes)
0000 03 00 00 03 00 4e 65 74 09 5f 72 74 74 5f 70 6f
0010 6e 67 01 02 00 00 00 6d 00 00 00
     = {"t":"rpc","node":"Net","method":"_rtt_pong","args":[109],"ch":0,"rel":false}
+111.289s S→C binary 79 bytes
len 4f 00 00 00   (raw TCP prefix: 79 bytes)
0000 03 02 00 0c 00 4d 61 69 6e 2f 45 6e 65 6d 69 65
0010 73 0c 5f 73 70 61 77 6e 5f 65 6e 65 6d 79 05 02
0020 00 00 00 2c 00 00 00 02 00 00 00 01 00 00 00 09
0030 00 00 00 4e fe 1b 42 66 66 26 3f 04 72 73 c2 01
0040 00 00 00 00 00 00 00 01 00 00 00 00 00 00 00
     = {"t":"rpc","node":"Main/Enemies","method":"_spawn_enemy","args":[44,1,{"_t":"v3","v":[38.99834442138672,0.6499999761581421,-60.86134338378906]},false,false],"ch":0,"rel":true,"mode":2}
+111.290s S→C binary 77 bytes
len 4d 00 00 00   (raw TCP prefix: 77 bytes)
0000 03 02 00 0b 00 47 61 6d 65 4d 61 6e 61 67 65 72
0010 07 5f 62 61 6e 6e 65 72 03 04 00 00 00 0d 00 00
0020 00 47 55 54 54 45 52 20 41 4d 42 55 53 48 00 00
0030 00 14 00 00 00 00 00 80 3f c4 c3 43 3f cb ca ca
0040 3e 00 00 80 3f 03 00 00 00 00 00 00 40
     = {"t":"rpc","node":"GameManager","method":"_banner","args":["GUTTER AMBUSH",{"_t":"color","v":[1.0,0.7647058963775635,0.3960784375667572,1.0]},2.0],"ch":0,"rel":true,"mode":2}
+111.290s S→C binary 57 bytes
len 39 00 00 00   (raw TCP prefix: 57 bytes)
0000 03 02 00 0c 00 4d 61 69 6e 2f 45 6e 65 6d 69 65
0010 73 16 5f 72 65 63 65 69 76 65 5f 67 72 6f 75 70
0020 5f 77 61 72 6e 69 6e 67 01 09 00 00 00 00 00 60
0030 41 00 00 00 00 00 00 80 40
     = {"t":"rpc","node":"Main/Enemies","method":"_receive_group_warning","args":[{"_t":"v3","v":[14.0,0.0,4.0]}],"ch":0,"rel":true,"mode":2}
+111.314s C→S binary 135 bytes
len 87 00 00 00   (raw TCP prefix: 135 bytes)
0000 03 02 00 33 00 4d 61 69 6e 2f 50 6c 61 79 65 72
0010 73 2f 50 5f 32 33 34 32 38 39 37 34 35 2f 48 65
0020 61 64 2f 43 61 6d 65 72 61 33 44 2f 57 65 61 70
0030 6f 6e 48 6f 6c 64 65 72 0d 5f 72 65 71 75 65 73
0040 74 5f 73 68 6f 74 06 02 00 00 00 01 00 00 00 02
0050 00 00 00 02 00 00 00 09 00 00 00 93 f8 25 40 33
0060 33 d3 3f 8f af 60 bf 09 00 00 00 eb 13 5d 3f c3
0070 76 0e bc 89 0e 01 3f 01 00 00 00 00 00 00 00 01
0080 00 00 00 01 00 00 00
     = {"t":"rpc","node":"Main/Players/P_234289745/Head/Camera3D/WeaponHolder","method":"_request_shot","args":[1,2,{"_t":"v3","v":[2.593296747010009,1.65,-0.8776788341218504]},{"_t":"v3","v":[0.8635851557632337,-0.008695307237314159,0.504128029747841]},false,true],"ch":0,"rel":true}
+111.318s S→C binary 81 bytes
len 51 00 00 00   (raw TCP prefix: 81 bytes)
0000 03 00 00 0c 00 4d 61 69 6e 2f 45 6e 65 6d 69 65
0010 73 0e 5f 65 6e 65 6d 79 5f 69 6d 70 61 63 74 73
0020 01 1c 00 00 00 01 00 00 00 1c 00 00 00 03 00 00
0030 00 02 00 00 00 2e 00 00 00 09 00 00 00 61 10 5f
0040 3f 06 99 ab bc e5 fe fa 3e 01 00 00 00 00 00 00
0050 00
     = {"t":"rpc","node":"Main/Enemies","method":"_enemy_impacts","args":[[[46,{"_t":"v3","v":[0.8713436722755432,-0.020946990698575974,0.4902259409427643]},false]]],"ch":0,"rel":false,"mode":0}
+111.318s S→C binary 116 bytes
len 74 00 00 00   (raw TCP prefix: 116 bytes)
0000 03 02 00 18 00 4d 61 69 6e 2f 50 6c 61 79 65 72
0010 73 2f 50 5f 32 33 34 32 38 39 37 34 35 0d 5f 72
0020 65 63 65 69 76 65 5f 68 69 74 73 02 02 00 00 00
0030 01 00 00 00 1c 00 00 00 01 00 00 00 1c 00 00 00
0040 05 00 00 00 01 00 00 00 00 00 00 00 01 00 00 00
0050 00 00 00 00 09 00 00 00 f8 ac 45 41 be 29 b5 3f
0060 76 a7 93 40 02 00 00 00 09 00 00 00 02 00 00 00
0070 2e 00 00 00
     = {"t":"rpc","node":"Main/Players/P_234289745","method":"_receive_hits","args":[1,[[false,false,{"_t":"v3","v":[12.354728698730469,1.4153363704681396,4.614192008972168]},9,46]]],"ch":0,"rel":true,"mode":2}
+111.318s S→C binary 182 bytes
len b6 00 00 00   (raw TCP prefix: 182 bytes)
0000 03 01 00 33 00 4d 61 69 6e 2f 50 6c 61 79 65 72
0010 73 2f 50 5f 32 33 34 32 38 39 37 34 35 2f 48 65
0020 61 64 2f 43 61 6d 65 72 61 33 44 2f 57 65 61 70
0030 6f 6e 48 6f 6c 64 65 72 08 5f 73 68 6f 74 5f 66
0040 78 07 02 00 00 00 01 00 00 00 04 00 00 00 0b 00
0050 00 00 6e 61 69 6c 5f 64 72 69 76 65 72 00 09 00
0060 00 00 93 f8 25 40 33 33 d3 3f 8f af 60 bf 09 00
0070 00 00 eb 13 5d 3f c3 76 0e bc 89 0e 01 3f 1c 00
0080 00 00 01 00 00 00 1c 00 00 00 02 00 00 00 09 00
0090 00 00 f8 ac 45 41 be 29 b5 3f 76 a7 93 40 02 00
00a0 00 00 02 00 00 00 01 00 00 00 00 00 00 00 01 00
00b0 00 00 01 00 00 00
     = {"t":"rpc","node":"Main/Players/P_234289745/Head/Camera3D/WeaponHolder","method":"_shot_fx","args":[1,"nail_driver",{"_t":"v3","v":[2.593296766281128,1.649999976158142,-0.8776788115501404]},{"_t":"v3","v":[0.8635851740837097,-0.008695307187736034,0.5041280388832092]},[[{"_t":"v3","v":[12.354728698730469,1.4153363704681396,4.614192008972168]},2]],false,true],"ch":0,"rel":false,"mode":1}
+111.318s S→C binary 288 bytes
len 20 01 00 00   (raw TCP prefix: 288 bytes)
0000 03 02 00 33 00 4d 61 69 6e 2f 50 6c 61 79 65 72
0010 73 2f 50 5f 32 33 34 32 38 39 37 34 35 2f 48 65
0020 61 64 2f 43 61 6d 65 72 61 33 44 2f 57 65 61 70
0030 6f 6e 48 6f 6c 64 65 72 0e 5f 70 72 69 76 61 74
0040 65 5f 73 74 61 74 65 0d 02 00 00 00 01 00 00 00
0050 02 00 00 00 3d 00 00 00 1c 00 00 00 05 00 00 00
0060 1c 00 00 00 04 00 00 00 02 00 00 00 02 00 00 00
0070 04 00 00 00 0b 00 00 00 6e 61 69 6c 5f 64 72 69
0080 76 65 72 00 02 00 00 00 00 00 00 00 02 00 00 00
0090 11 00 00 00 1c 00 00 00 00 00 00 00 1c 00 00 00
00a0 00 00 00 00 1c 00 00 00 00 00 00 00 1c 00 00 00
00b0 00 00 00 00 1b 00 00 00 01 00 00 00 04 00 00 00
00c0 04 00 00 00 6e 61 69 6c 02 00 00 00 0c 00 00 00
00d0 02 00 00 00 00 00 00 00 04 00 00 00 00 00 00 00
00e0 02 00 00 00 00 00 00 00 02 00 00 00 02 00 00 00
00f0 02 00 00 00 01 00 00 00 03 00 00 00 00 00 00 00
0100 03 00 01 00 66 66 66 66 66 66 fa 3f 03 00 00 00
0110 00 00 00 00 03 00 01 00 9c c4 20 b0 72 68 b1 3f
     = {"t":"rpc","node":"Main/Players/P_234289745/Head/Camera3D/WeaponHolder","method":"_private_state","args":[1,61,[[2,"nail_driver",0,17],[],[],[],[]],{"nail":12},0,"",0,2,1,0.0,1.65,0.0,0.068],"ch":0,"rel":true,"mode":2}
+111.362s S→C binary 130 bytes
len 82 00 00 00   (raw TCP prefix: 130 bytes)
0000 03 02 00 2b 00 4d 61 69 6e 2f 50 6c 61 79 65 72
0010 73 2f 50 5f 32 2f 48 65 61 64 2f 43 61 6d 65 72
0020 61 33 44 2f 57 65 61 70 6f 6e 48 6f 6c 64 65 72
0030 0c 5f 65 71 75 69 70 5f 73 74 61 74 65 06 02 00
0040 00 00 01 00 00 00 02 00 00 00 1e 00 00 00 04 00
0050 00 00 0c 00 00 00 70 75 6d 70 5f 73 68 6f 74 67
0060 75 6e 02 00 00 00 00 00 00 00 03 00 01 00 2b 87
0070 16 d9 ce f7 d3 3f 03 00 01 00 2b 87 16 d9 ce f7
0080 d3 3f
     = {"t":"rpc","node":"Main/Players/P_2/Head/Camera3D/WeaponHolder","method":"_equip_state","args":[1,30,"pump_shotgun",0,0.312,0.312],"ch":0,"rel":true,"mode":2}
+111.516s C→S binary 135 bytes
len 87 00 00 00   (raw TCP prefix: 135 bytes)
0000 03 02 00 33 00 4d 61 69 6e 2f 50 6c 61 79 65 72
0010 73 2f 50 5f 32 33 34 32 38 39 37 34 35 2f 48 65
0020 61 64 2f 43 61 6d 65 72 61 33 44 2f 57 65 61 70
0030 6f 6e 48 6f 6c 64 65 72 0d 5f 72 65 71 75 65 73
0040 74 5f 73 68 6f 74 06 02 00 00 00 01 00 00 00 02
0050 00 00 00 02 00 00 00 09 00 00 00 27 bb 36 40 33
0060 33 d3 3f 1a 7b 3b bf 09 00 00 00 ea dc 5c 3f 65
0070 8c a2 bc f3 57 01 3f 01 00 00 00 00 00 00 00 01
     … (hex truncated)
     = {"t":"rpc","node":"Main/Players/P_234289745/Head/Camera3D/WeaponHolder","method":"_request_shot","args":[1,2,{"_t":"v3","v":[2.8551728445119524,1.65,-0.7323471126307459]},{"_t":"v3","v":[0.8627459004534993,-0.019842335473953907,0.505248248857549]},false,true],"ch":0,"rel":true}
+111.519s S→C binary 81 bytes
len 51 00 00 00   (raw TCP prefix: 81 bytes)
0000 03 00 00 0c 00 4d 61 69 6e 2f 45 6e 65 6d 69 65
0010 73 0e 5f 65 6e 65 6d 79 5f 69 6d 70 61 63 74 73
0020 01 1c 00 00 00 01 00 00 00 1c 00 00 00 03 00 00
0030 00 02 00 00 00 2e 00 00 00 09 00 00 00 8b d5 5c
0040 3f 53 ed a0 bc 0a 65 01 3f 01 00 00 00 00 00 00
0050 00
     = {"t":"rpc","node":"Main/Enemies","method":"_enemy_impacts","args":[[[46,{"_t":"v3","v":[0.8626334071159363,-0.019644415006041527,0.5054479837417603]},false]]],"ch":0,"rel":false,"mode":0}
+111.519s S→C binary 116 bytes
len 74 00 00 00   (raw TCP prefix: 116 bytes)
0000 03 02 00 18 00 4d 61 69 6e 2f 50 6c 61 79 65 72
0010 73 2f 50 5f 32 33 34 32 38 39 37 34 35 0d 5f 72
0020 65 63 65 69 76 65 5f 68 69 74 73 02 02 00 00 00
0030 01 00 00 00 1c 00 00 00 01 00 00 00 1c 00 00 00
0040 05 00 00 00 01 00 00 00 00 00 00 00 01 00 00 00
0050 00 00 00 00 09 00 00 00 98 9e 43 41 67 e2 b7 3f
0060 85 45 98 40 02 00 00 00 09 00 00 00 02 00 00 00
0070 2e 00 00 00
     = {"t":"rpc","node":"Main/Players/P_234289745","method":"_receive_hits","args":[1,[[false,false,{"_t":"v3","v":[12.226219177246094,1.4365967512130737,4.758486270904541]},9,46]]],"ch":0,"rel":true,"mode":2}
+111.519s S→C binary 182 bytes
len b6 00 00 00   (raw TCP prefix: 182 bytes)
0000 03 01 00 33 00 4d 61 69 6e 2f 50 6c 61 79 65 72
0010 73 2f 50 5f 32 33 34 32 38 39 37 34 35 2f 48 65
0020 61 64 2f 43 61 6d 65 72 61 33 44 2f 57 65 61 70
0030 6f 6e 48 6f 6c 64 65 72 08 5f 73 68 6f 74 5f 66
0040 78 07 02 00 00 00 01 00 00 00 04 00 00 00 0b 00
0050 00 00 6e 61 69 6c 5f 64 72 69 76 65 72 00 09 00
0060 00 00 27 bb 36 40 33 33 d3 3f 1a 7b 3b bf 09 00
0070 00 00 eb dc 5c 3f 66 8c a2 bc f4 57 01 3f 1c 00
     … (hex truncated)
     = {"t":"rpc","node":"Main/Players/P_234289745/Head/Camera3D/WeaponHolder","method":"_shot_fx","args":[1,"nail_driver",{"_t":"v3","v":[2.855172872543335,1.649999976158142,-0.7323471307754517]},{"_t":"v3","v":[0.8627459406852722,-0.01984233781695366,0.5052483081817627]},[[{"_t":"v3","v":[12.226219177246094,1.4365967512130737,4.758486270904541]},2]],false,true],"ch":0,"rel":false,"mode":1}
+111.519s S→C binary 288 bytes
len 20 01 00 00   (raw TCP prefix: 288 bytes)
0000 03 02 00 33 00 4d 61 69 6e 2f 50 6c 61 79 65 72
0010 73 2f 50 5f 32 33 34 32 38 39 37 34 35 2f 48 65
0020 61 64 2f 43 61 6d 65 72 61 33 44 2f 57 65 61 70
0030 6f 6e 48 6f 6c 64 65 72 0e 5f 70 72 69 76 61 74
0040 65 5f 73 74 61 74 65 0d 02 00 00 00 01 00 00 00
0050 02 00 00 00 3e 00 00 00 1c 00 00 00 05 00 00 00
0060 1c 00 00 00 04 00 00 00 02 00 00 00 02 00 00 00
0070 04 00 00 00 0b 00 00 00 6e 61 69 6c 5f 64 72 69
     … (hex truncated)
     = {"t":"rpc","node":"Main/Players/P_234289745/Head/Camera3D/WeaponHolder","method":"_private_state","args":[1,62,[[2,"nail_driver",0,16],[],[],[],[]],{"nail":12},0,"",0,2,1,0.0,1.65,0.0,0.068],"ch":0,"rel":true,"mode":2}
+111.597s S→C binary 50 bytes
len 32 00 00 00   (raw TCP prefix: 50 bytes)
0000 03 02 00 0c 00 4d 61 69 6e 2f 52 75 6e 4c 6f 6f
0010 74 07 5f 72 65 6d 6f 76 65 03 02 00 00 00 01 00
0020 00 00 02 00 00 00 25 00 00 00 02 00 00 00 00 00
0030 00 00
     = {"t":"rpc","node":"Main/RunLoot","method":"_remove","args":[1,37,0],"ch":0,"rel":true,"mode":2}
+111.659s S→C binary 130 bytes
len 82 00 00 00   (raw TCP prefix: 130 bytes)
0000 03 02 00 2b 00 4d 61 69 6e 2f 50 6c 61 79 65 72
0010 73 2f 50 5f 32 2f 48 65 61 64 2f 43 61 6d 65 72
0020 61 33 44 2f 57 65 61 70 6f 6e 48 6f 6c 64 65 72
0030 0c 5f 65 71 75 69 70 5f 73 74 61 74 65 06 02 00
0040 00 00 01 00 00 00 02 00 00 00 1f 00 00 00 04 00
0050 00 00 0c 00 00 00 70 75 6d 70 5f 73 68 6f 74 67
0060 75 6e 02 00 00 00 00 00 00 00 03 00 01 00 2b 87
0070 16 d9 ce f7 d3 3f 03 00 01 00 2b 87 16 d9 ce f7
     … (hex truncated)
     = {"t":"rpc","node":"Main/Players/P_2/Head/Camera3D/WeaponHolder","method":"_equip_state","args":[1,31,"pump_shotgun",0,0.312,0.312],"ch":0,"rel":true,"mode":2}
+113.078s S→C binary 97 bytes
len 61 00 00 00   (raw TCP prefix: 97 bytes)
0000 03 02 00 0c 00 4d 61 69 6e 2f 52 75 6e 4c 6f 6f
0010 74 06 5f 73 70 61 77 6e 03 02 00 00 00 01 00 00
0020 00 02 00 00 00 2c 00 00 00 1c 00 00 00 04 00 00
0030 00 09 00 00 00 00 14 43 41 d2 5c 79 3d 3b ac 82
0040 40 1c 00 00 00 00 00 00 00 04 00 00 00 05 00 00
0050 00 73 63 72 61 70 00 00 00 02 00 00 00 00 00 00
0060 00
     = {"t":"rpc","node":"Main/RunLoot","method":"_spawn","args":[1,44,[{"_t":"v3","v":[12.1923828125,0.06087953597307205,4.083524227142334]},[],"scrap",0]],"ch":0,"rel":true,"mode":2}
+113.078s S→C binary 129 bytes
len 81 00 00 00   (raw TCP prefix: 129 bytes)
0000 03 02 00 0c 00 4d 61 69 6e 2f 45 6e 65 6d 69 65
0010 73 0e 5f 64 65 73 70 61 77 6e 5f 65 6e 65 6d 79
0020 05 02 00 00 00 2d 00 00 00 1c 00 00 00 01 00 00
0030 00 1c 00 00 00 02 00 00 00 09 00 00 00 00 14 43
0040 41 d2 5c 79 3d 3b ac 82 40 04 00 00 00 05 00 00
0050 00 73 63 72 61 70 00 00 00 09 00 00 00 00 14 43
0060 41 d2 5c 79 3d 3b ac 82 40 09 00 00 00 9a 7d 55
0070 3f 00 00 00 00 2a 80 4f 3e 01 00 00 00 01 00 00
0080 00
     = {"t":"rpc","node":"Main/Enemies","method":"_despawn_enemy","args":[45,[[{"_t":"v3","v":[12.1923828125,0.06087953597307205,4.083524227142334]},"scrap"]],{"_t":"v3","v":[12.1923828125,0.06087953597307205,4.083524227142334]},{"_t":"v3","v":[0.8339477777481079,0.0,0.20263734459877014]},true],"ch":0,"rel":true,"mode":2}
+113.078s S→C binary 97 bytes
len 61 00 00 00   (raw TCP prefix: 97 bytes)
0000 03 02 00 0c 00 4d 61 69 6e 2f 52 75 6e 4c 6f 6f
0010 74 06 5f 73 70 61 77 6e 03 02 00 00 00 01 00 00
0020 00 02 00 00 00 2d 00 00 00 1c 00 00 00 04 00 00
0030 00 09 00 00 00 d8 76 63 41 2e 56 79 3d 9c 48 6f
0040 40 1c 00 00 00 00 00 00 00 04 00 00 00 05 00 00
0050 00 73 63 72 61 70 00 00 00 02 00 00 00 00 00 00
0060 00
     = {"t":"rpc","node":"Main/RunLoot","method":"_spawn","args":[1,45,[{"_t":"v3","v":[14.216514587402344,0.06087320297956467,3.73880672454834]},[],"scrap",0]],"ch":0,"rel":true,"mode":2}
+113.078s S→C binary 129 bytes
len 81 00 00 00   (raw TCP prefix: 129 bytes)
0000 03 02 00 0c 00 4d 61 69 6e 2f 45 6e 65 6d 69 65
0010 73 0e 5f 64 65 73 70 61 77 6e 5f 65 6e 65 6d 79
0020 05 02 00 00 00 31 00 00 00 1c 00 00 00 01 00 00
0030 00 1c 00 00 00 02 00 00 00 09 00 00 00 d8 76 63
0040 41 2e 56 79 3d 9c 48 6f 40 04 00 00 00 05 00 00
0050 00 73 63 72 61 70 00 00 00 09 00 00 00 d8 76 63
0060 41 2e 56 79 3d 9c 48 6f 40 09 00 00 00 17 db 4e
0070 3f 00 00 00 00 fc c7 2d 3e 01 00 00 00 01 00 00
     … (hex truncated)
     = {"t":"rpc","node":"Main/Enemies","method":"_despawn_enemy","args":[49,[[{"_t":"v3","v":[14.216514587402344,0.06087320297956467,3.73880672454834]},"scrap"]],{"_t":"v3","v":[14.216514587402344,0.06087320297956467,3.73880672454834]},{"_t":"v3","v":[0.8080305457115173,0.0,0.16970819234848022]},true],"ch":0,"rel":true,"mode":2}
+115.779s S→C binary 67 bytes
len 43 00 00 00   (raw TCP prefix: 67 bytes)
0000 03 02 00 11 00 47 61 6d 65 4d 61 6e 61 67 65 72
0010 2f 46 65 61 74 73 0b 5f 66 65 61 74 5f 65 76 65
0020 6e 74 02 04 00 00 00 10 00 00 00 63 61 62 6c 65
0030 5f 73 75 62 73 63 72 69 62 65 72 02 00 00 00 01
0040 00 00 00
     = {"t":"rpc","node":"GameManager/Feats","method":"_feat_event","args":["cable_subscriber",1],"ch":0,"rel":true,"mode":2}
```

Repeats not shown in this section: 208× `S→C _relay_transform`, 119× `C→S _push_transform`, 69× `S→C _sync_enemies`, 54× `S→C _apply_vitals`, 20× `S→C _sync_progress`, 15× `S→C _shot_fx`, 11× `C→S _request_shot`, 11× `S→C _receive_hits`, 11× `S→C _private_state`, 10× `S→C _enemy_impacts`, 9× `S→C _equip_state`, 7× `S→C _spawn_enemy`, 4× `S→C _rtt_ping`, 4× `C→S _rtt_pong`, 4× `S→C _spawn`, 3× `S→C _remove`, 3× `S→C _despawn_enemy`.

## Results and return to the lobby

> Run over: `[won, results]`. Show results, unload, send `_report_in_run(false)`; next `_push_roster` is the lobby.

```text
+115.779s S→C binary 661 bytes
len 95 02 00 00   (raw TCP prefix: 661 bytes)
0000 03 02 00 0b 00 47 61 6d 65 4d 61 6e 61 67 65 72
0010 07 5f 66 69 6e 69 73 68 02 01 00 00 00 00 00 00
0020 00 1b 00 00 00 09 00 00 00 04 00 00 00 03 00 00
0030 00 77 6f 6e 00 01 00 00 00 00 00 00 00 04 00 00
0040 00 06 00 00 00 6d 61 70 5f 69 64 00 00 04 00 00
0050 00 09 00 00 00 70 69 6e 65 63 72 65 73 74 00 00
0060 00 04 00 00 00 05 00 00 00 77 61 76 65 73 00 00
0070 00 02 00 00 00 01 00 00 00 04 00 00 00 0c 00 00
0080 00 77 61 76 65 5f 72 65 61 63 68 65 64 02 00 00
0090 00 02 00 00 00 04 00 00 00 07 00 00 00 65 6e 64
00a0 6c 65 73 73 00 01 00 00 00 00 00 00 00 04 00 00
00b0 00 0d 00 00 00 65 6e 64 6c 65 73 73 5f 73 63 6f
00c0 72 65 00 00 00 02 00 00 00 00 00 00 00 04 00 00
00d0 00 07 00 00 00 73 65 63 6f 6e 64 73 00 02 00 00
00e0 00 6a 00 00 00 04 00 00 00 0f 00 00 00 73 71 75
00f0 61 64 5f 6d 75 74 61 74 69 6f 6e 73 00 1c 00 00
0100 00 01 00 00 00 04 00 00 00 0e 00 00 00 52 45 46
0110 4c 45 58 20 54 45 4e 44 4f 4e 53 00 00 04 00 00
0120 00 07 00 00 00 70 6c 61 79 65 72 73 00 1b 00 00
0130 00 02 00 00 00 02 00 00 00 02 00 00 00 1b 00 00
0140 00 06 00 00 00 04 00 00 00 04 00 00 00 6e 61 6d
0150 65 04 00 00 00 08 00 00 00 54 68 69 6e 20 42 6f
0160 74 04 00 00 00 05 00 00 00 6b 69 6c 6c 73 00 00
0170 00 02 00 00 00 07 00 00 00 04 00 00 00 07 00 00
0180 00 72 65 76 69 76 65 73 00 02 00 00 00 00 00 00
0190 00 04 00 00 00 06 00 00 00 74 75 72 6e 65 64 00
01a0 00 02 00 00 00 00 00 00 00 04 00 00 00 06 00 00
01b0 00 63 75 72 73 65 64 00 00 04 00 00 00 00 00 00
01c0 00 04 00 00 00 06 00 00 00 77 65 61 70 6f 6e 00
01d0 00 04 00 00 00 0c 00 00 00 50 75 6d 70 20 53 68
01e0 6f 74 67 75 6e 02 00 00 00 51 fa f6 0d 1b 00 00
01f0 00 06 00 00 00 04 00 00 00 04 00 00 00 6e 61 6d
0200 65 04 00 00 00 08 00 00 00 46 75 6c 6c 20 42 6f
0210 74 04 00 00 00 05 00 00 00 6b 69 6c 6c 73 00 00
0220 00 02 00 00 00 08 00 00 00 04 00 00 00 07 00 00
0230 00 72 65 76 69 76 65 73 00 02 00 00 00 00 00 00
0240 00 04 00 00 00 06 00 00 00 74 75 72 6e 65 64 00
0250 00 02 00 00 00 00 00 00 00 04 00 00 00 06 00 00
0260 00 63 75 72 73 65 64 00 00 04 00 00 00 00 00 00
0270 00 04 00 00 00 06 00 00 00 77 65 61 70 6f 6e 00
0280 00 04 00 00 00 0b 00 00 00 4e 61 69 6c 20 44 72
0290 69 76 65 72 00
     = {"t":"rpc","node":"GameManager","method":"_finish","args":[false,{"won":false,"map_id":"pinecrest","waves":1,"wave_reached":2,"endless":false,"endless_score":0,"seconds":106,"squad_mutations":["REFLEX TENDONS"],"players":{"_t":"dict","v":[[2,{"name":"Thin Bot","kills":7,"revives":0,"turned":0,"cursed":"","weapon":"Pump Shotgun"}],[234289745,{"name":"Full Bot","kills":8,"revives":0,"turned":0,"cursed":"","weapon":"Nail Driver"}]]}}],"ch":0,"rel":true,"mode":2}
+115.779s S→C binary 298 bytes
len 2a 01 00 00   (raw TCP prefix: 298 bytes)
0000 03 02 00 03 00 4e 65 74 0c 5f 70 75 73 68 5f 72
0010 6f 73 74 65 72 05 1b 00 00 00 02 00 00 00 02 00
0020 00 00 02 00 00 00 1b 00 00 00 04 00 00 00 04 00
0030 00 00 04 00 00 00 6e 61 6d 65 04 00 00 00 08 00
0040 00 00 54 68 69 6e 20 42 6f 74 04 00 00 00 05 00
0050 00 00 72 65 61 64 79 00 00 00 01 00 00 00 00 00
0060 00 00 04 00 00 00 05 00 00 00 63 6f 6c 6f 72 00
0070 00 00 02 00 00 00 00 00 00 00 04 00 00 00 04 00
0080 00 00 73 6b 69 6e 02 00 00 00 00 00 00 00 02 00
0090 00 00 51 fa f6 0d 1b 00 00 00 04 00 00 00 04 00
00a0 00 00 04 00 00 00 6e 61 6d 65 04 00 00 00 08 00
00b0 00 00 46 75 6c 6c 20 42 6f 74 04 00 00 00 05 00
00c0 00 00 72 65 61 64 79 00 00 00 01 00 00 00 00 00
00d0 00 00 04 00 00 00 05 00 00 00 63 6f 6c 6f 72 00
00e0 00 00 02 00 00 00 03 00 00 00 04 00 00 00 04 00
00f0 00 00 73 6b 69 6e 02 00 00 00 01 00 00 00 04 00
0100 00 00 09 00 00 00 70 69 6e 65 63 72 65 73 74 00
0110 00 00 01 00 00 00 01 00 00 00 1b 00 00 00 00 00
0120 00 00 04 00 00 00 00 00 00 00
     = {"t":"rpc","node":"Net","method":"_push_roster","args":[{"_t":"dict","v":[[2,{"name":"Thin Bot","ready":false,"color":0,"skin":0}],[234289745,{"name":"Full Bot","ready":false,"color":3,"skin":1}]]},"pinecrest",true,{},""],"ch":0,"rel":true,"mode":2}
+116.252s S→C binary 39 bytes
len 27 00 00 00   (raw TCP prefix: 39 bytes)
0000 03 00 00 03 00 4e 65 74 09 5f 72 74 74 5f 70 69
0010 6e 67 02 02 00 00 00 72 00 00 00 03 00 01 00 76
0020 9f ff 0f 55 fb 2f 40
     = {"t":"rpc","node":"Net","method":"_rtt_ping","args":[114,15.990883350328414],"ch":0,"rel":false,"mode":0}
+116.252s C→S binary 27 bytes
len 1b 00 00 00   (raw TCP prefix: 27 bytes)
0000 03 00 00 03 00 4e 65 74 09 5f 72 74 74 5f 70 6f
0010 6e 67 01 02 00 00 00 72 00 00 00
     = {"t":"rpc","node":"Net","method":"_rtt_pong","args":[114],"ch":0,"rel":false}
+117.251s S→C binary 39 bytes
len 27 00 00 00   (raw TCP prefix: 39 bytes)
0000 03 00 00 03 00 4e 65 74 09 5f 72 74 74 5f 70 69
0010 6e 67 02 02 00 00 00 73 00 00 00 03 00 01 00 9f
0020 ef 32 8b bb fc 2f 40
     = {"t":"rpc","node":"Net","method":"_rtt_ping","args":[115,15.993618345229889],"ch":0,"rel":false,"mode":0}
+117.251s C→S binary 27 bytes
len 1b 00 00 00   (raw TCP prefix: 27 bytes)
0000 03 00 00 03 00 4e 65 74 09 5f 72 74 74 5f 70 6f
0010 6e 67 01 02 00 00 00 73 00 00 00
     = {"t":"rpc","node":"Net","method":"_rtt_pong","args":[115],"ch":0,"rel":false}
+117.783s S→C binary 63 bytes
len 3f 00 00 00   (raw TCP prefix: 63 bytes)
0000 03 02 00 0e 00 57 65 61 74 68 65 72 4d 61 6e 61
0010 67 65 72 0e 5f 72 65 63 65 69 76 65 5f 70 68 61
0020 73 65 03 02 00 00 00 03 00 00 00 02 00 00 00 02
0030 00 00 00 03 00 01 00 98 ce 6e ef 6e 0a 45 40
     = {"t":"rpc","node":"WeatherManager","method":"_receive_phase","args":[3,2,42.081510476212486],"ch":0,"rel":true,"mode":2}
+120.294s C→S binary 32 bytes
len 20 00 00 00   (raw TCP prefix: 32 bytes)
0000 03 02 00 03 00 4e 65 74 0e 5f 72 65 70 6f 72 74
0010 5f 69 6e 5f 72 75 6e 01 01 00 00 00 00 00 00 00
     = {"t":"rpc","node":"Net","method":"_report_in_run","args":[false],"ch":0,"rel":true}
+120.780s S→C binary 45 bytes
len 2d 00 00 00   (raw TCP prefix: 45 bytes)
0000 03 02 00 18 00 47 61 6d 65 4d 61 6e 61 67 65 72
0010 2f 4d 75 74 61 74 69 6f 6e 52 6f 6c 6c 0e 5f 72
0020 65 73 65 74 5f 72 75 6e 5f 72 70 63 00
     = {"t":"rpc","node":"GameManager/MutationRoll","method":"_reset_run_rpc","args":[],"ch":0,"rel":true,"mode":2}
+121.843s S→C binary 186 bytes
len ba 00 00 00   (raw TCP prefix: 186 bytes)
0000 03 02 00 03 00 4e 65 74 0c 5f 70 75 73 68 5f 72
0010 6f 73 74 65 72 05 1b 00 00 00 01 00 00 00 02 00
0020 00 00 51 fa f6 0d 1b 00 00 00 04 00 00 00 04 00
0030 00 00 04 00 00 00 6e 61 6d 65 04 00 00 00 08 00
0040 00 00 46 75 6c 6c 20 42 6f 74 04 00 00 00 05 00
0050 00 00 72 65 61 64 79 00 00 00 01 00 00 00 00 00
0060 00 00 04 00 00 00 05 00 00 00 63 6f 6c 6f 72 00
0070 00 00 02 00 00 00 03 00 00 00 04 00 00 00 04 00
     … (hex truncated)
     = {"t":"rpc","node":"Net","method":"_push_roster","args":[{"_t":"dict","v":[[234289745,{"name":"Full Bot","ready":false,"color":3,"skin":1}]]},"pinecrest",true,{},""],"ch":0,"rel":true,"mode":2}
```

Repeats not shown in this section: 5× `S→C _rtt_ping`, 5× `C→S _rtt_pong`.

## Leave

> Clean exit. The server removes the peer and closes the socket.

```text
+122.854s C→S text (raw TCP prefix 0d 00 00 00)
     {"t":"leave"}
# transport closed by server after leave (EOFError)
```

## Frame totals

| Kind | Frames |
| --- | ---: |
| `_relay_transform` | 3805 |
| `_push_transform` | 2203 |
| `_apply_vitals` | 986 |
| `_sync_enemies` | 976 |
| `_sync_progress` | 381 |
| `_rtt_ping` | 119 |
| `_rtt_pong` | 119 |
| `_shot_fx` | 84 |
| `_private_state` | 73 |
| `_request_shot` | 67 |
| `_enemy_impacts` | 52 |
| `_spawn_enemy` | 51 |
| `_receive_hits` | 49 |
| `_spawn` | 49 |
| `_despawn_enemy` | 47 |
| `_equip_state` | 40 |
| `_remove` | 40 |
| `_receive_phase` | 10 |
| `_receive_group_warning` | 10 |
| `_push_roster` | 8 |
| `_request_ready` | 4 |
| `_ready_changed` | 4 |
| `_banner` | 3 |
| `_stock` | 3 |
| `_chat_rpc` | 2 |
| `_report_in_run` | 2 |
| `_sync_tape_state` | 2 |
| `_reset_run_rpc` | 2 |
| `_sync_decon` | 2 |
| `_override` | 2 |
| `_snapshot` | 2 |
| `_strike` | 2 |
| `_action` | 2 |
| `_feat_event` | 2 |
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
| `_announce_drop` | 1 |
| `_airdrop_spawn` | 1 |
| `_deal_rpc` | 1 |
| `_request_vote` | 1 |
| `_result_rpc` | 1 |
| `_finish` | 1 |
| `leave` | 1 |
