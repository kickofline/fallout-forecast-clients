# Known issues and wire quirks

Applies to Open Protocol `v:1`, game protocol `19`.

## 1. Thin ping number format

A Thin connection can send `{"t":"ping","ms":4242}` and receive
`{"t":"pong","ms":4242.0}`. Thin echoes the parsed JSON number. Compare the
numeric value and accept an integral float in an integer field. Full normalizes
integral ping values to integers.

## 2. Full lobby handshake timeout

The five-second transport hello deadline ends at `welcome`. After `welcome`, the server enforces a ten-second join deadline for `Net._hello` to add the peer to the lobby roster. The server sends `Full tier join timed out` when it can still write and closes the connection. It ignores a `Net._hello` whose inner string does not parse to a dictionary. Send a valid inner JSON object immediately after `welcome` and impose your own deadline for a roster containing `welcome.you` or a `Net._reject` reply.

## 3. Full results broadcasts

`GameManager._finish` ends the client run. Global RPCs can still arrive while
the dedicated server waits five seconds to unload the scene, including a
mutation reset at teardown. Stop transforming and issuing run requests at
`_finish`. Keep handling transport controls and `Net` messages, and start
applying run state again on the next `Net._start_run`.

## 4. Full callsign cleaning

The Full game handshake applies the same cleaning as the Thin callsign but
keeps up to 32 characters (Thin keeps 18). `Net._request_name` cleans and trims
to 18 and ignores names that are empty after cleaning. A cleaned name can still
hold emoji and combining marks, so 32 characters can be well over 32 bytes in
UTF-8. Render all names and chat as plain text.

## 5. Packed array and typed dictionary decoding

A Full client must understand both the Godot built-in type word before a typed
binary array's count and tagged dictionaries with non-string keys in JSON.
Mutation lists use typed arrays even when empty; the lobby roster uses integer
keys, and the puddle sync uses NodePath keys. The worked examples in
[spec-full.md](spec-full.md#10-worked-binary-examples) and the matching
[JSON mapping](spec-full.md#7-variant--json-mapping) show both cases.

## 6. Thin starter on late join

The Thin server attempts to grant the kit once on entry to `run`. The inventory
can refuse it during a mutation draft, a tape choice or a pause. This follows
from the source path and can leave a late-joining Thin player without the
automatic kit. There is no Thin starter retry action in v1. Treat an empty
hotbar as authoritative and render it. The player can scavenge after play
resumes. A new connection can receive the normal kit if it joins at a time
when inventory actions are available.

## 7. Abnormal WebSocket closure

Godot reports a missed transport Pong and a socket lost without a close frame
with the same close-code sentinel. The server logs both possible causes in
that case. A client can receive an abnormal close without a server diagnostic.
