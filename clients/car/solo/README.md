# Solo authority

`local_link.gd` implements FullLink for Open Protocol v1 and game protocol 19. FullNet uses the same lobby, loading, catch-up, gameplay and results messages for solo and online play. The link queues requests and emits messages from `poll()`. Pausing stops the host clock and the local world update while the menu and RTT probes remain responsive.

The authority simulates the five campaign waves and endless continuation, the district weather and forecast, acid exposure, nine enemy kinds, Cloudburst and Cumulus. It resolves inventory, shots, projectiles, drops, vending, pickups, decon, mutations and solo self-revive. Player movement and exposure reports come from the Full client.

## Tuning

- Set `LocalLink.max_alive` before starting a run. The default is 18, the accepted range is 1–60, and the cap includes burst reinforcements and summons. It limits simultaneous enemies while keeping the wave budget.
- Set `LocalLink.rng_seed` for reproducible encounters. The default uses a random seed.
- `arena.gd` staggers enemy decisions at approximately 10 Hz, allows one new navigation path per poll and refreshes each path about once a second. Enemy transforms are batched at up to 20 Hz. Navigation is optional and falls back to ground and wall rays.
- The shared `res://data/game_data.json` supplies item and weather definitions. `level_markers.json` is the protocol marker export without shelter volumes, which the client physics builder loads. `rpc_requests.json` is indexed from the protocol schema by node and method, with argument types and optional defaults for client requests.

## Simulation differences

- Enemies are math-only records using world rays, coarse steering and spherical hit regions. Lunges and charges follow the ground. Undertow lurks and surfaces once per arrival, and static blinks use a short ground probe. Spores use capped circular hazards. Cumulus uses coarse hover and part hit volumes. In-process shots use current world positions.
- Airdrops use authored crate anchors. Deployable protection and weapon-specific effects use coarse area tests. Local unlock and feat events cover a subset of the native progression. Self-revive is the solo revive path. Turned melee and friendly fire are multiplayer mechanics.
- Desktop checks cover Cloudburst and reaching the Cumulus wave. Boss victory and endless continuation remain unverified end to end.

## Checks

Run from the repository root with Godot 3.6.3 and the synced assets.

```powershell
godot --path clients/car --no-window -s ../../tools/godot_check.gd
godot --path clients/car --no-window --disable-render-loop --fixed-fps 60 -s res://tests/solo_smoke.gd
godot --path clients/car --no-window --disable-render-loop --fixed-fps 60 -s res://tests/solo_smoke.gd -- --solo-load
godot --path clients/car --no-window --resolution 640x360 --fixed-fps 60 -s res://tests/solo_client.gd
```

The FullLink-only bot checks message types and delivery flags against the schema. It walks the exported collisions, clears three waves on each map, and triggers defeat to check self-revive, out, results and restart. Its combat runs report shelter, then verify acid drain separately. The load flag lets all 18 enemy slots fill and reports the time spent inside `poll()` excluding bot callbacks. The real-client test selects Solo and a district through the title buttons, exercises pause and resumes the world through to the results screen.
