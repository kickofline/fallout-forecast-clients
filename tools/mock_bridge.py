#!/usr/bin/env python3
"""Mock car bridge (docs/car-bridge-protocol.md, v1). Python 3.8+ stdlib only.

Plays the bridge side of the contract with fake data so the car client can be
developed without the real game: lobby with bot teammates, map vote, force
start, loading, a run with moving enemies/teammates/pickups/projectiles,
events (shots, hits, kills, hurt, lightning, puddles, banners, sounds),
weather phases, a mutation draft, the Endless tape prompt and results.

    python tools/mock_bridge.py [--port 8790] [--fast] [--map pinecrest]
                                [--waves 2] [--autostart SECONDS] [--quiet]

Connect the client to ws://127.0.0.1:8790/ (desktop) or ws://10.0.2.2:8790/
(Android emulator).
"""
import argparse
import asyncio
import base64
import hashlib
import json
import math
import random
import socket
import struct
import time

GUID = "258EAFA5-E914-47DA-95CA-C5AB0DC85B11"
MAPS = [
    {"id": "pinecrest", "name": "Pinecrest"},
    {"id": "harbor", "name": "Harbor Point"},
    {"id": "maple_hollow", "name": "Maple Hollow"},
]
ENEMY_TYPES = ["drip", "gutter", "mister", "hailstone", "sleet", "smog", "static", "thunderhead", "undertow"]
ENEMY_HP = {"drip": 30, "gutter": 45, "mister": 35, "hailstone": 120, "sleet": 50, "smog": 60,
            "static": 55, "thunderhead": 90, "undertow": 70, "cloudburst": 600, "cumulus": 2000}
ITEMS = {
    "pump_shotgun": ("Pump Shotgun", 6, "weapon"),
    "service_revolver": ("Service Revolver", 6, "weapon"),
    "spray_rifle": ("Spray Rifle", 30, "weapon"),
    "hunting_rifle": ("Hunting Rifle", 5, "weapon"),
    "nail_driver": ("Nail Driver", 24, "weapon"),
    "med_tin": ("Med Tin", 0, "item"),
    "suit_patch": ("Suit Patch", 0, "item"),
}
CARDS = [
    {"id": "acid_blood", "title": "ACID BLOOD", "desc": "Taking health damage splashes burning acid around you", "icon": "acid_blood"},
    {"id": "chitin_suit", "title": "CHITIN SUIT", "desc": "+25 max health and suit drains 35% slower in rain", "icon": "chitin_suit"},
    {"id": "magnet_hands", "title": "MAGNET HANDS", "desc": "Pull pickups from 3x range and refill 60% ammo per drop", "icon": "magnet_hands"},
]
BITS = {"fire": 1, "aim": 2, "jump": 4, "crouch": 8, "sprint": 16, "reload": 32, "interact": 64,
        "use_item": 128, "drop_item": 256, "ping": 512, "ready_up": 1024}


def r2(v):
    return [round(v[0], 2), round(v[1], 2), round(v[2], 2)]


# ----------------------------------------------------------------- websocket
class WS:
    def __init__(self, reader, writer):
        self.r = reader
        self.w = writer
        self.closed = False

    async def handshake(self):
        request = await self.r.readuntil(b"\r\n\r\n")
        headers = {}
        for line in request.decode("latin1").split("\r\n")[1:]:
            if ":" in line:
                k, v = line.split(":", 1)
                headers[k.strip().lower()] = v.strip()
        key = headers.get("sec-websocket-key")
        if not key:
            self.w.write(b"HTTP/1.1 200 OK\r\nContent-Type: text/plain\r\nContent-Length: 17\r\n\r\nmock car bridge\r\n")
            await self.w.drain()
            return False
        accept = base64.b64encode(hashlib.sha1((key + GUID).encode()).digest()).decode()
        self.w.write(("HTTP/1.1 101 Switching Protocols\r\nUpgrade: websocket\r\nConnection: Upgrade\r\n"
                      "Sec-WebSocket-Accept: %s\r\n\r\n" % accept).encode())
        await self.w.drain()
        return True

    async def recv(self):
        """Returns a text message, or None when closed."""
        buf = b""
        while True:
            h = await self.r.readexactly(2)
            fin, op = h[0] & 0x80, h[0] & 0x0F
            masked, ln = h[1] & 0x80, h[1] & 0x7F
            if ln == 126:
                ln = struct.unpack(">H", await self.r.readexactly(2))[0]
            elif ln == 127:
                ln = struct.unpack(">Q", await self.r.readexactly(8))[0]
            mask = await self.r.readexactly(4) if masked else b"\0\0\0\0"
            data = bytearray(await self.r.readexactly(ln))
            for i in range(ln):
                data[i] ^= mask[i % 4]
            if op == 8:
                await self._frame(8, bytes(data[:2]))
                self.closed = True
                return None
            if op == 9:
                await self._frame(10, bytes(data))
                continue
            if op == 10:
                continue
            buf += data
            if fin:
                return buf.decode("utf-8", "replace")

    async def _frame(self, op, payload):
        if self.closed:
            return
        n = len(payload)
        if n < 126:
            head = struct.pack(">BB", 0x80 | op, n)
        elif n < 65536:
            head = struct.pack(">BBH", 0x80 | op, 126, n)
        else:
            head = struct.pack(">BBQ", 0x80 | op, 127, n)
        try:
            self.w.write(head + payload)
            await self.w.drain()
        except (ConnectionError, OSError):
            self.closed = True

    async def send(self, obj):
        await self._frame(1, json.dumps(obj, separators=(",", ":")).encode())

    async def close(self):
        await self._frame(8, struct.pack(">H", 1000))
        self.closed = True
        try:
            self.w.close()
        except Exception:
            pass


# ----------------------------------------------------------------- game sim
class Run:
    def __init__(self, s, args):
        self.s = s
        self.args = args
        self.t0 = time.monotonic()
        self.tick = 0
        self.fast = args.fast
        self.wave = 1
        self.phase = "calm"
        self.phase_left = 6.0 if self.fast else 20.0
        self.intensity = 0.0
        self.pos = [0.0, 0.0, 0.5]
        self.vel = [0.0, 0.0, 0.0]
        self.yaw = 0.0
        self.pitch = 0.0
        self.hp, self.hp_max = 100.0, 100.0
        self.suit, self.suit_max = 100.0, 100.0
        self.state = "ok"
        self.slot = 0
        self.slots = [
            {"item": "pump_shotgun", "name": "Pump Shotgun", "ammo": 6, "mag": 6, "reserve": 30, "count": 1, "tier": 1},
            {"item": "service_revolver", "name": "Service Revolver", "ammo": 6, "mag": 6, "reserve": 24, "count": 1, "tier": 0},
            {"item": "med_tin", "name": "Med Tin", "ammo": None, "mag": None, "reserve": None, "count": 2},
            None, None]
        self.scrap = 35
        self.decon = 4
        self.score = 0
        self.kills = 0
        self.downs = 0
        self.fire_cd = 0.0
        self.reload_left = 0.0
        self.prev_b = 0
        self.prev_slot = 0
        self.b = 0
        self.mv = [0.0, 0.0]
        self.last_seq = 0
        self.vy = 0.0
        self.crouch = False
        self.enemies = {}
        self.next_id = 1000
        self.spawn_left = 1.0
        self.wave_budget = 0
        self.pickups = {}
        self.projectiles = {}
        self.puddles = {}
        self.events = []
        self.draft_open = False
        self.draft_left = 0.0
        self.tape_open = False
        self.done = False
        self.endless = False
        self.mutations = []
        self.bots = [
            {"id": 3, "name": "SAM", "pos": [3.0, 0.0, 3.0], "yaw": 0.0, "pitch": 0.0, "state": "ok", "item": "spray_rifle",
             "crouch": False, "suit_color": "#ff5689", "skin": "default", "ang": 0.0, "cd": 0.0},
            {"id": 4, "name": "DREW", "pos": [-4.0, 0.0, -2.0], "yaw": 0.0, "pitch": 0.0, "state": "ok", "item": "hunting_rifle",
             "crouch": False, "suit_color": "#ffbf68", "skin": "default", "ang": 2.0, "cd": 0.0},
        ]
        for i, (item, (name, _, kind)) in enumerate(list(ITEMS.items())[:6]):
            pid = 5000 + i
            ang = i * 1.05
            self.pickups[pid] = {"id": pid, "item": item, "pos": r2([math.cos(ang) * 9, 0.3, math.sin(ang) * 9]),
                                 "kind": "weapon" if kind == "weapon" else ("health" if item == "med_tin" else "suit")}
        self.pickups[5100] = {"id": 5100, "item": "airdrop", "pos": [14.0, 0.0, -12.0], "kind": "airdrop"}
        self.pickups[5101] = {"id": 5101, "item": "supply_station", "pos": [-16.0, 0.0, 10.0], "kind": "station"}
        self.ev({"e": "banner", "text": "WAVE 1 — CALM BEFORE THE STORM"})

    def ev(self, e):
        self.events.append(e)

    def ms(self):
        return int((time.monotonic() - self.s.clock0) * 1000)

    def apply_input(self, m):
        self.last_seq = int(m.get("seq", self.last_seq))
        mv = m.get("mv") or [0, 0]
        self.mv = [float(mv[0]), float(mv[1])]
        self.yaw = float(m.get("yaw", self.yaw))
        self.pitch = max(-1.53, min(1.53, float(m.get("pitch", self.pitch))))
        self.b = int(m.get("b", 0))
        slot = int(m.get("slot", 0))
        if slot and slot != self.prev_slot:
            self.slot = max(0, min(4, slot - 1))
            self.reload_left = 0.0
        self.prev_slot = slot
        wheel = int(m.get("wheel", 0))
        if wheel:
            self.slot = (self.slot + wheel) % 5

    def pressed(self, name):
        bit = BITS[name]
        return bool(self.b & bit) and not (self.prev_b & bit)

    def held(self, name):
        return bool(self.b & BITS[name])

    def forward(self):
        return [-math.sin(self.yaw) * math.cos(self.pitch), math.sin(self.pitch), -math.cos(self.yaw) * math.cos(self.pitch)]

    def step(self, dt):
        self.tick += 1
        if self.done:
            return
        self.update_weather(dt)
        if not self.draft_open and not self.tape_open:
            self.update_player(dt)
            self.update_enemies(dt)
            self.update_bots(dt)
        self.update_projectiles(dt)
        self.prev_b = self.b

    # -- weather / waves
    def set_phase(self, phase, length):
        self.phase = phase
        self.phase_left = length
        names = {"calm": "CALM", "drizzle": "DRIZZLE", "downpour": "DOWNPOUR", "acid_storm": "ACID STORM", "clearing": "CLEARING"}
        self.ev({"e": "banner", "text": "WAVE %d — %s" % (self.wave, names[phase])})
        self.ev({"e": "sound", "name": "storm_phase", "at": None})

    def update_weather(self, dt):
        if self.draft_open:
            self.draft_left -= dt
            if self.draft_left <= 0:
                self.choose_card(0)
            return
        if self.tape_open:
            return
        self.phase_left -= dt
        target = {"calm": 0.0, "drizzle": 0.35, "downpour": 0.75, "acid_storm": 1.0, "clearing": 0.1}[self.phase]
        self.intensity += (target - self.intensity) * min(1.0, dt * 0.5)
        f = 0.5 if self.fast else 1.0
        if self.phase_left <= 0:
            if self.phase == "calm":
                if self.wave >= 2 and len(self.mutations) < self.wave - 1:
                    self.open_draft()
                    return
                self.set_phase("drizzle", 25 * f)
                self.wave_budget = 8 + self.wave * 4
            elif self.phase == "drizzle":
                self.set_phase("acid_storm" if self.wave >= 5 else "downpour", 30 * f)
                self.wave_budget += 8
            elif self.phase in ("downpour", "acid_storm"):
                self.set_phase("clearing", 8 * f)
            elif self.phase == "clearing":
                if self.wave >= self.args.waves and not self.endless:
                    self.tape_open = True
                    self.s.send_soon({"t": "tape", "time_left": None, "can_choose": True})
                    return
                self.wave += 1
                self.set_phase("calm", 10 * f)
        if self.phase in ("downpour", "acid_storm") and random.random() < dt * 0.15:
            at = [random.uniform(-30, 30), 0, random.uniform(-30, 30)]
            self.ev({"e": "lightning", "at": r2(at)})
            self.ev({"e": "sound", "name": "thunder", "at": None})
        if self.phase in ("drizzle", "downpour", "acid_storm") and random.random() < dt * 0.08 and len(self.puddles) < 6:
            pid = self.next_id
            self.next_id += 1
            self.puddles[pid] = 1
            self.ev({"e": "puddle", "id": pid, "pos": r2([random.uniform(-20, 20), 0.02, random.uniform(-20, 20)]),
                     "radius": round(random.uniform(1.2, 3.0), 2), "on": True})
        if self.phase == "clearing" and self.puddles:
            pid = next(iter(self.puddles))
            del self.puddles[pid]
            self.ev({"e": "puddle", "id": pid, "on": False})

    def open_draft(self):
        self.draft_open = True
        self.draft_left = 15.0
        self.s.send_soon({"t": "draft", "kind": "mutation", "cards": CARDS, "time_left": 15})

    def choose_card(self, i):
        if not self.draft_open:
            return
        self.draft_open = False
        self.mutations.append(CARDS[max(0, min(2, i))]["id"])
        self.s.send_soon({"t": "draft_done"})
        self.ev({"e": "banner", "text": "SQUAD MUTATION — " + CARDS[max(0, min(2, i))]["title"]})
        self.set_phase("drizzle", 25 * (0.5 if self.fast else 1.0))
        self.wave_budget = 8 + self.wave * 4

    def choose_tape(self, i):
        if not self.tape_open:
            return
        self.tape_open = False
        if i == 0:
            self.endless = True
            self.wave += 1
            self.set_phase("calm", 6)
        else:
            self.done = True

    # -- player
    def cur(self):
        return self.slots[self.slot]

    def update_player(self, dt):
        if self.state == "downed":
            self.hp += dt * 4
            if self.hp >= 30:
                self.state = "ok"
            return
        self.crouch = self.held("crouch")
        speed = 2.5 if self.crouch else (8.0 if self.held("sprint") else 5.0)
        fx, fz = -math.sin(self.yaw), -math.cos(self.yaw)
        rx, rz = math.cos(self.yaw), -math.sin(self.yaw)
        mx, my = self.mv
        vx = (rx * mx - fx * my) * speed
        vz = (rz * mx - fz * my) * speed
        if self.pos[1] <= 0.0 and self.pressed("jump"):
            self.vy = 4.5
        self.vy -= 12.0 * dt
        self.pos[0] = max(-38, min(38, self.pos[0] + vx * dt))
        self.pos[2] = max(-38, min(38, self.pos[2] + vz * dt))
        self.pos[1] = max(0.0, self.pos[1] + self.vy * dt)
        if self.pos[1] <= 0.0:
            self.vy = 0.0
        self.vel = [vx, self.vy, vz]
        exposed = self.phase != "calm" and not (abs(self.pos[0] + 16) < 3 and abs(self.pos[2] - 10) < 3)
        if exposed and self.phase in ("drizzle", "downpour", "acid_storm"):
            self.suit = max(0.0, self.suit - dt * self.intensity * 1.5)
            if self.suit <= 0:
                self.hp -= dt * 2
        # Weapon.
        self.fire_cd -= dt
        item = self.cur()
        if self.reload_left > 0:
            self.reload_left -= dt
            if self.reload_left <= 0 and item:
                need = (item.get("mag") or 0) - (item.get("ammo") or 0)
                take = min(need, item["reserve"])
                item["ammo"] += take
                item["reserve"] -= take
        if item and item.get("mag"):
            if self.pressed("reload") and item["ammo"] < item["mag"] and item["reserve"] > 0:
                self.reload_left = 1.2
                self.ev({"e": "sound", "name": "reload", "at": None})
            auto = item["item"] in ("spray_rifle", "nail_driver")
            want = self.held("fire") if auto else self.pressed("fire")
            if want and self.fire_cd <= 0 and self.reload_left <= 0:
                if item["ammo"] > 0:
                    item["ammo"] -= 1
                    self.fire_cd = 0.12 if auto else 0.45
                    self.shoot(item)
                else:
                    self.ev({"e": "sound", "name": "dry_fire", "at": None})
                    self.fire_cd = 0.3
        elif item and (self.pressed("use_item") or self.pressed("fire")):
            if item["count"] > 0:
                item["count"] -= 1
                self.hp = min(self.hp_max, self.hp + 40)
                self.ev({"e": "sound", "name": "gun_med_tin", "at": None})
                if item["count"] <= 0:
                    self.slots[self.slot] = None
        # Pickups.
        if self.pressed("interact"):
            near = self.nearest_pickup()
            if near:
                pk = self.pickups.pop(near)
                self.ev({"e": "pickup", "item": pk["item"]})
                self.ev({"e": "sound", "name": "pickup", "at": None})
                if pk["item"] in ITEMS:
                    name, mag, kind = ITEMS[pk["item"]]
                    gun = mag > 0
                    entry = {"item": pk["item"], "name": name, "ammo": mag if gun else None, "mag": mag if gun else None,
                             "reserve": mag * 3 if gun else None, "count": 1}
                    free = [i for i, s in enumerate(self.slots) if s is None]
                    if free:
                        self.slots[free[0]] = entry
                    else:
                        self.slots[self.slot] = entry
                else:
                    self.scrap += 15
        if self.hp <= 0 and self.state == "ok":
            self.state = "downed"
            self.downs += 1
            self.hp = 1
            self.ev({"e": "banner", "text": "YOU ARE DOWN"})

    def nearest_pickup(self):
        best, bd = None, 2.5
        for pid, pk in self.pickups.items():
            d = math.dist([pk["pos"][0], pk["pos"][2]], [self.pos[0], self.pos[2]])
            if d < bd:
                best, bd = pid, d
        return best

    def eye(self):
        return [self.pos[0], self.pos[1] + (0.95 if self.crouch else 1.65), self.pos[2]]

    def shoot(self, item):
        eye = self.eye()
        fwd = self.forward()
        pellets = 6 if item["item"] == "pump_shotgun" else 1
        self.ev({"e": "sound", "name": "gun_" + item["item"], "at": None})
        best = None
        for _ in range(pellets):
            spread = 0.08 if pellets > 1 else 0.01
            d = [fwd[0] + random.uniform(-spread, spread), fwd[1] + random.uniform(-spread, spread), fwd[2] + random.uniform(-spread, spread)]
            n = math.sqrt(sum(c * c for c in d))
            d = [c / n for c in d]
            hit_e, hit_t = None, 60.0
            for e in self.enemies.values():
                if e["anim"] == "die":
                    continue
                c = [e["pos"][0], e["pos"][1] + 1.0, e["pos"][2]]
                oc = [c[i] - eye[i] for i in range(3)]
                t = sum(oc[i] * d[i] for i in range(3))
                if t <= 0 or t > hit_t:
                    continue
                closest = [eye[i] + d[i] * t for i in range(3)]
                if math.dist(closest, c) < (0.9 if e["type"] in ("hailstone", "thunderhead") else 0.6):
                    hit_e, hit_t = e, t
            to = [eye[i] + d[i] * hit_t for i in range(3)]
            self.ev({"e": "shot", "by": self.s.peer, "weapon": item["item"], "from": r2(eye), "to": r2(to)})
            if hit_e:
                head = to[1] > hit_e["pos"][1] + 1.5
                dmg = (14 if pellets > 1 else 34) * (2 if head else 1)
                hit_e["hp_abs"] -= dmg
                hit_e["anim"] = "stagger"
                hit_e["stagger"] = 0.2
                self.ev({"e": "hit", "at": r2(to), "head": head, "dmg": dmg})
                if hit_e["hp_abs"] <= 0 and hit_e["anim"] != "die":
                    hit_e["anim"] = "die"
                    hit_e["die_left"] = 0.8
                    self.kills += 1
                    self.score += 100
                    self.ev({"e": "kill", "enemy": hit_e["id"], "type": hit_e["type"]})
                    self.ev({"e": "sound", "name": "enemy_death", "at": r2(hit_e["pos"])})
                    if random.random() < 0.3:
                        pid = self.next_id
                        self.next_id += 1
                        self.pickups[pid] = {"id": pid, "item": random.choice(["ammo", "scrap"]), "pos": r2(hit_e["pos"]),
                                             "kind": random.choice(["ammo", "scrap"])}

    # -- enemies
    def spawn_enemy(self, etype=None):
        etype = etype or random.choice(ENEMY_TYPES[: 3 + self.wave * 2])
        ang = random.uniform(0, math.tau)
        eid = self.next_id
        self.next_id += 1
        self.enemies[eid] = {"id": eid, "type": etype, "pos": [math.cos(ang) * 30, 0.0, math.sin(ang) * 30], "yaw": 0.0,
                             "hp_abs": ENEMY_HP[etype], "max": ENEMY_HP[etype], "anim": "spawn", "spawn": 0.8,
                             "atk": 0.0, "stagger": 0.0, "die_left": 0.0, "spit": random.uniform(2, 5)}

    def update_enemies(self, dt):
        fighting = self.phase in ("drizzle", "downpour", "acid_storm")
        self.spawn_left -= dt
        if fighting and self.wave_budget > 0 and self.spawn_left <= 0 and len(self.enemies) < 14:
            self.spawn_left = 1.5
            self.wave_budget -= 1
            self.spawn_enemy()
        if self.phase == "calm" and self.tick < 40 and not self.enemies:
            for t in ("drip", "gutter", "mister", "hailstone"):
                self.spawn_enemy(t)
        targets = [(self.pos, None)] + [(b["pos"], b) for b in self.bots]
        for eid in list(self.enemies):
            e = self.enemies[eid]
            if e["anim"] == "die":
                e["die_left"] -= dt
                if e["die_left"] <= 0:
                    del self.enemies[eid]
                continue
            if e["spawn"] > 0:
                e["spawn"] -= dt
                if e["spawn"] <= 0:
                    e["anim"] = "idle"
                continue
            if e["stagger"] > 0:
                e["stagger"] -= dt
                continue
            tgt = min(targets, key=lambda t: math.dist([t[0][0], t[0][2]], [e["pos"][0], e["pos"][2]]))[0]
            dx, dz = tgt[0] - e["pos"][0], tgt[2] - e["pos"][2]
            d = math.hypot(dx, dz) or 1.0
            e["yaw"] = math.atan2(-dx, -dz)
            speed = {"drip": 3.2, "gutter": 2.4, "hailstone": 1.6}.get(e["type"], 2.8)
            if e["type"] == "mister" and d < 14:
                e["spit"] -= dt
                e["anim"] = "windup" if e["spit"] < 0.5 else "idle"
                if e["spit"] <= 0:
                    e["spit"] = random.uniform(3, 5)
                    pid = self.next_id
                    self.next_id += 1
                    p0 = [e["pos"][0], 1.4, e["pos"][2]]
                    v = [dx / d * 12, 2.0, dz / d * 12]
                    self.projectiles[pid] = {"id": pid, "kind": "acid_spit", "pos": p0, "vel": v, "life": 2.0}
                    self.ev({"e": "sound", "name": "mister_spit", "at": r2(p0)})
                continue
            if d > 1.6:
                e["anim"] = "walk"
                e["pos"][0] += dx / d * speed * dt
                e["pos"][2] += dz / d * speed * dt
            else:
                e["atk"] -= dt
                e["anim"] = "attack" if e["atk"] < 0.4 else "windup"
                if e["atk"] <= 0:
                    e["atk"] = 1.2
                    if tgt is self.pos and self.state == "ok":
                        dmg = 8
                        self.hp -= dmg
                        self.ev({"e": "hurt", "dir": r2([-dx / d, 0, -dz / d]), "amt": dmg})
                        self.ev({"e": "sound", "name": "player_hurt", "at": None})

    def update_projectiles(self, dt):
        for pid in list(self.projectiles):
            p = self.projectiles[pid]
            p["vel"][1] -= 6 * dt
            for i in range(3):
                p["pos"][i] += p["vel"][i] * dt
            p["life"] -= dt
            if p["life"] <= 0 or p["pos"][1] <= 0:
                del self.projectiles[pid]
                if p["pos"][1] <= 0.2:
                    self.ev({"e": "sound", "name": "acid_splash", "at": r2(p["pos"])})

    def update_bots(self, dt):
        for b in self.bots:
            b["ang"] += dt * 0.25
            target = [math.cos(b["ang"]) * 7 + (2 if b["id"] == 3 else -2), 0.0, math.sin(b["ang"]) * 7]
            dx, dz = target[0] - b["pos"][0], target[2] - b["pos"][2]
            b["pos"][0] += dx * min(1, dt * 2)
            b["pos"][2] += dz * min(1, dt * 2)
            alive = [e for e in self.enemies.values() if e["anim"] not in ("die", "spawn")]
            if alive:
                e = min(alive, key=lambda e: math.dist(e["pos"], b["pos"]))
                ex, ez = e["pos"][0] - b["pos"][0], e["pos"][2] - b["pos"][2]
                b["yaw"] = math.atan2(-ex, -ez)
                b["cd"] -= dt
                if b["cd"] <= 0 and math.hypot(ex, ez) < 25:
                    b["cd"] = 0.6
                    frm = [b["pos"][0], 1.5, b["pos"][2]]
                    to = [e["pos"][0], 1.0, e["pos"][2]]
                    self.ev({"e": "shot", "by": b["id"], "weapon": b["item"], "from": r2(frm), "to": r2(to)})
                    e["hp_abs"] -= 12
                    if e["hp_abs"] <= 0:
                        e["anim"] = "die"
                        e["die_left"] = 0.8
                        self.ev({"e": "kill", "enemy": e["id"], "type": e["type"]})
            else:
                b["yaw"] = math.atan2(-dx, -dz) if abs(dx) + abs(dz) > 0.01 else b["yaw"]

    # -- output
    def prompt(self):
        near = self.nearest_pickup()
        if near:
            pk = self.pickups[near]
            if pk["kind"] == "station":
                return "[E] Buy supplies"
            if pk["kind"] == "airdrop":
                return "[E] Open airdrop"
            name = ITEMS.get(pk["item"], (pk["item"].replace("_", " ").title(),))[0]
            return "[E] Pick up " + name
        return ""

    def snapshot(self):
        cur = self.cur()
        snap = {
            "t": "snap", "tick": self.tick, "t_ms": self.ms(), "ack": self.last_seq,
            "you": {"id": self.s.peer, "pos": r2(self.pos), "vel": r2(self.vel), "yaw": round(self.yaw, 3),
                    "pitch": round(self.pitch, 3), "state": self.state, "hp": round(self.hp, 1), "hp_max": self.hp_max,
                    "suit": round(self.suit, 1), "suit_max": self.suit_max,
                    "exposed": self.phase not in ("calm",), "sheltered": self.phase == "calm",
                    "in_puddle": False, "crouch": self.crouch, "aiming": self.held("aim"),
                    "reloading": self.reload_left > 0, "slot": self.slot + 1, "slots": self.slots, "scrap": self.scrap,
                    "revive": 0.0, "interact_progress": 0.0, "prompt": self.prompt(),
                    "pouch": "", "grenades": 2, "domes": 1},
            "players": [{k: b[k] for k in ("id", "name", "pos", "yaw", "pitch", "state", "item", "crouch", "suit_color", "skin")}
                        for b in self.bots],
            "enemies": [{"id": e["id"], "type": e["type"], "pos": r2(e["pos"]), "yaw": round(e["yaw"], 3),
                         "hp": None, "anim": e["anim"]} for e in self.enemies.values()],
            "projectiles": [{"id": p["id"], "kind": p["kind"], "pos": r2(p["pos"]), "vel": r2(p["vel"])}
                            for p in self.projectiles.values()],
            "weather": {"phase": self.phase, "intensity": round(self.intensity, 2), "wave": self.wave,
                        "phase_time_left": round(max(0.0, self.phase_left), 1),
                        "lightning": any(e.get("e") == "lightning" for e in self.events)},
            "run": {"alive_enemies": len(self.enemies), "wave": self.wave, "endless": self.endless,
                    "shared_decon": self.decon, "score": self.score, "wave_total": self.wave_budget + len(self.enemies)},
        }
        for b in snap["players"]:
            b["pos"] = r2(b["pos"])
            b["yaw"] = round(b["yaw"], 3)
        if self.tick % 5 == 1:
            snap["pickups"] = list(self.pickups.values())
            snap["full"] = True
        return snap


class Session:
    count = 0

    def __init__(self, ws, args):
        Session.count += 1
        self.ws = ws
        self.args = args
        self.peer = 100 + Session.count
        self.name = "CAR"
        self.state = "connecting"
        self.ready = False
        self.vote = args.map
        self.chat = [{"from": "SAM", "text": "car player? nice"}]
        self.countdown = -1.0
        self.run = None
        self.clock0 = time.monotonic()
        self.outbox = []
        self.last_lobby = None

    def send_soon(self, msg):
        self.outbox.append(msg)

    def log(self, *a):
        if not self.args.quiet:
            print("[%d]" % self.peer, *a, flush=True)

    def lobby_msg(self):
        players = [
            {"id": self.peer, "name": self.name, "ready": self.ready, "vote": self.vote, "car": True},
            {"id": 3, "name": "SAM", "ready": True, "vote": "harbor", "car": False},
            {"id": 4, "name": "DREW", "ready": time.monotonic() - self.clock0 > 4, "vote": self.args.map, "car": False},
        ]
        return {"t": "lobby", "players": players, "maps": MAPS, "countdown": round(self.countdown, 1) if self.countdown >= 0 else -1,
                "chat": self.chat[-8:], "vote_counts": self.vote_counts(players)}

    @staticmethod
    def vote_counts(players):
        out = {}
        for p in players:
            out[p["vote"]] = out.get(p["vote"], 0) + 1
        return out

    async def status(self, state, msg=""):
        self.state = state
        await self.ws.send({"t": "status", "state": state, "msg": msg})

    async def handle(self, m):
        t = m.get("t")
        if t == "hello":
            if int(m.get("v", 0)) != 1:
                await self.ws.send({"t": "error", "msg": "protocol mismatch"})
                await self.ws.close()
                return
            self.name = str(m.get("name", "CAR"))[:16].upper() or "CAR"
            self.log("hello", self.name, m.get("client"))
            await self.ws.send({"t": "welcome", "v": 1, "game_protocol": 18, "you": self.peer, "maps": MAPS})
            await self.status("connecting", "JOINING CLOUD SERVER")
            await asyncio.sleep(0.4)
            await self.status("lobby")
            await self.ws.send(self.lobby_msg())
        elif t == "ping":
            await self.ws.send({"t": "pong", "ms": m.get("ms")})
        elif t == "lobby":
            a = m.get("a")
            if a == "ready":
                self.ready = bool(m.get("v"))
            elif a == "vote":
                self.vote = str(m.get("map", self.vote))
            elif a == "start":
                self.countdown = 0.0
            elif a == "chat":
                self.chat.append({"from": self.name, "text": str(m.get("text", ""))[:80]})
            if self.ready and self.countdown < 0:
                self.countdown = 3.0
            if not self.ready and a == "ready" and self.countdown > 0:
                self.countdown = -1.0
            await self.ws.send(self.lobby_msg())
        elif t == "in" and self.run:
            self.run.apply_input(m)
        elif t == "choice" and self.run:
            if m.get("kind") == "mutation":
                self.run.choose_card(int(m.get("i", 0)))
            elif m.get("kind") == "tape":
                self.run.choose_tape(int(m.get("i", 1)))
        elif t == "leave":
            # The real bridge leaves Cloud Play and closes the socket.
            self.log("leave")
            await self.ws.close()

    async def loop(self):
        dt = 0.05
        next_t = time.monotonic()
        lobby_left = 1.0
        while not self.ws.closed:
            next_t += dt
            if self.state == "lobby":
                lobby_left -= dt
                if self.args.autostart and time.monotonic() - self.clock0 > self.args.autostart and self.countdown < 0:
                    self.countdown = 0.0
                if self.countdown >= 0:
                    self.countdown -= dt
                    if self.countdown <= 0:
                        await self.start_run()
                if lobby_left <= 0:
                    lobby_left = 1.0
                    msg = self.lobby_msg()
                    if json.dumps(msg) != self.last_lobby:
                        self.last_lobby = json.dumps(msg)
                        await self.ws.send(msg)
            elif self.state == "run" and self.run:
                self.run.step(dt)
                await self.ws.send(self.run.snapshot())
                if self.run.events:
                    await self.ws.send({"t": "ev", "list": self.run.events})
                    self.run.events = []
                for msg in self.outbox:
                    await self.ws.send(msg)
                self.outbox.clear()
                if self.run.done or (self.run.wave > self.args.waves + 3):
                    await self.finish()
            await asyncio.sleep(max(0.0, next_t - time.monotonic()))

    async def start_run(self):
        votes = {}
        for p in self.lobby_msg()["players"]:
            votes[p["vote"]] = votes.get(p["vote"], 0) + 1
        mp = self.vote if self.countdown == 0 else max(votes, key=votes.get)
        self.countdown = -1.0
        await self.status("loading", "LOADING " + mp.upper())
        await self.ws.send({"t": "load", "map": mp})
        self.log("load", mp)
        await asyncio.sleep(1.5 if self.args.fast else 3.0)
        self.run = Run(self, self.args)
        await self.status("run")

    async def finish(self):
        r = self.run
        await self.status("results")
        await self.ws.send({"t": "results", "won": r.state != "out", "time_s": int(time.monotonic() - r.t0), "waves": r.wave,
                            "kills": r.kills + 40, "score": r.score,
                            "players": [{"name": self.name, "kills": r.kills, "downs": r.downs, "revives": 0},
                                        {"name": "SAM", "kills": 22, "downs": 1, "revives": 2},
                                        {"name": "DREW", "kills": 18, "downs": 0, "revives": 1}]})
        self.run = None
        self.ready = False
        # Like the real bridge: back to the lobby right after results.
        await asyncio.sleep(1.0)
        if not self.ws.closed and self.state == "results":
            await self.status("lobby")
            await self.ws.send(self.lobby_msg())


async def serve(reader, writer, args):
    ws = WS(reader, writer)
    sock = writer.get_extra_info("socket")
    if sock is not None:
        sock.setsockopt(socket.IPPROTO_TCP, socket.TCP_NODELAY, 1)
    try:
        if not await ws.handshake():
            writer.close()
            return
        s = Session(ws, args)
        task = asyncio.ensure_future(s.loop())
        try:
            while True:
                text = await ws.recv()
                if text is None:
                    break
                try:
                    msg = json.loads(text)
                except ValueError:
                    continue
                if isinstance(msg, dict):
                    await s.handle(msg)
        finally:
            ws.closed = True
            task.cancel()
            s.log("closed")
    except (asyncio.IncompleteReadError, ConnectionError, OSError):
        pass
    finally:
        try:
            writer.close()
        except Exception:
            pass


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--host", default="0.0.0.0")
    ap.add_argument("--port", type=int, default=8790)
    ap.add_argument("--fast", action="store_true", help="short phases for quick tests")
    ap.add_argument("--map", default="pinecrest")
    ap.add_argument("--waves", type=int, default=2, help="waves before the tape/results")
    ap.add_argument("--autostart", type=float, default=0.0, help="force start N seconds after connect")
    ap.add_argument("--quiet", action="store_true")
    args = ap.parse_args()

    async def run():
        server = await asyncio.start_server(lambda r, w: serve(r, w, args), args.host, args.port)
        print("mock car bridge on ws://%s:%d/" % (args.host, args.port), flush=True)
        async with server:
            await server.serve_forever()

    try:
        asyncio.run(run())
    except KeyboardInterrupt:
        pass


if __name__ == "__main__":
    main()
