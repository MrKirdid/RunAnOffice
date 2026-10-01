"""Run an Office pacing sim: a solo, no-Robux bot played against the Luau configs on disk.

The bot rolls, carries the best part to the worst matching slot, opens desk gifts, hires every
passing employee worth it, and always saves for the cheapest next thing (desk, tree node or gear).
Medians over many seeded runs are what the prices in DeskPurchase.luau and Upgrades.luau are fitted
to -- see fit.py. Bot timings (TRIP, HIRE, ROLL_OVERHEAD) are a guess at a real player.

python3 tools/pacing/sim.py [--pads N] [--runs N] [--hours H]
"""

import argparse
import bisect
import math
import random
import re
import statistics
from pathlib import Path

DEFAULT_ROOT = Path(__file__).resolve().parents[2]


# ---------------------------------------------------------------- config parsing

def num(s):
    return float(s.replace("_", ""))


def load(root):
    shared = root / "src/Shared"
    parts_src = (shared / "Configs/Parts.luau").read_text()
    base_src, var_src = parts_src.split("Variants")
    entry = re.compile(r"(\w+)\s*=\s*\{\s*Value\s*=\s*([\d._]+),\s*Rarity\s*=\s*([\d._]+)")
    base = {n: (num(v), num(r)) for n, v, r in entry.findall(base_src)}
    variants = {n: (num(v), num(r)) for n, v, r in entry.findall(var_src)}

    emp_src = (shared / "Configs/Employees.luau").read_text()
    emp = {
        n: (num(v), 1 / num(r))
        for n, v, r in re.findall(r'\[?"?([\w ]+?)"?\]?\s*=\s*\{\s*Value\s*=\s*([\d.]+),\s*Rarity\s*=\s*1\s*/\s*([\d_]+)', emp_src)
    }

    up_src = (shared / "Configs/Upgrades.luau").read_text()
    up_src = up_src.split("local Upgrades")[1]
    nodes = {}
    for name, body in re.findall(r"\n\t(\w+)\s*=\s*\{(.*?)\n\t\}", up_src, re.S):
        parent = re.search(r'Parent\s*=\s*"(\w+)"', body)
        cost = re.search(r"Cost\s*=\s*([\d_]+)", body)
        action = "IsAction = true" in body
        if action:
            continue
        nodes[name] = {
            "parent": parent.group(1) if parent else None,
            "cost": num(cost.group(1)) if cost else 0,
        }

    def_src = (shared / "Configs/UpgradeDefinitions.luau").read_text()
    effects = {}
    for name, fn, arg in re.findall(r"(\w+)\s*=\s*\{\s*Effect\s*=\s*\"[^\"]*\",\s*OnPurchase\s*=\s*(\w+)\(([^)]*)\)", def_src):
        args = [a.strip().strip('"') for a in arg.split(",")]
        effects[name] = (fn, args)

    dp_src = (shared / "Utilities/DeskPurchase.luau").read_text()
    block = dp_src.split("local Prices = {")[1].split("\n}")[0]
    block = re.sub(r"--[^\n]*", "", block)
    prices = [num(x) for x in re.findall(r"[\d_]+", block)]

    gear_src = (shared / "Configs/Gears.luau").read_text().split("List = {")[1]
    gears = [num(x) for x in re.findall(r"Price\s*=\s*([\d_]+)", gear_src)]

    pd_src = (shared / "PlayerData.luau").read_text()
    pads = int(re.search(r"RerollPads\s*=\s*(\d+)", pd_src).group(1))

    off_src = (root / "src/Server/Services/OfflineEarningsService.luau").read_text()

    return dict(base=base, variants=variants, emp=emp, nodes=nodes, effects=effects,
                prices=prices, pads=pads, gears=sorted(gears), offline_src=off_src)


# ---------------------------------------------------------------- rolling maths (mirrors Rolling.luau)

class Table:
    def __init__(self, entries):
        self.names = sorted(entries)
        self.rarity = [entries[n][1] for n in self.names]
        self.value = [entries[n][0] for n in self.names]
        common, rarest = max(self.rarity), min(self.rarity)
        span = math.log(common / rarest)
        self.scarcity = [math.log(common / r) / span if span > 0 else 0 for r in self.rarity]
        self._cache = {}

    def cum(self, luck):
        luck = round(max(luck, 0), 4)
        c = self._cache.get(luck)
        if c is None:
            w = [r * luck ** s for r, s in zip(self.rarity, self.scarcity)]
            total, acc, c = sum(w), 0.0, []
            for x in w:
                acc += x
                c.append(acc / total)
            self._cache[luck] = c
        return c

    def pick(self, rng, luck):
        c = self.cum(luck)
        i = bisect.bisect_left(c, rng.random())
        return min(i, len(c) - 1)

    def chances(self, luck):
        c = self.cum(luck)
        return {n: c[i] - (c[i - 1] if i else 0) for i, n in enumerate(self.names)}


TIER_CEILINGS = [("Common", 5), ("Uncommon", 20), ("Rare", 100), ("Epic", 500),
                 ("Legendary", 10_000), ("Mythic", 150_000), ("Divine", math.inf)]
TIER_ORDER = [t for t, _ in TIER_CEILINGS]


def tier_of(odds):
    for name, ceil in TIER_CEILINGS:
        if odds <= ceil:
            return name
    return "Divine"


# ---------------------------------------------------------------- bot behaviour

TRIP = 10.0         # walk a part from the pads to a desk and back
HIRE = 5.0          # walk to a passing employee and buy them
BUY = 2.0           # press a desk board / a tree node
ROLL_OVERHEAD = 4.0 # stand on the prompt and press it
SPAWN = 5.0         # EmployeeService.SpawnRate
TUTORIAL_LUCKY = {6, 11}
HIRE_PAYBACK = 300
NOTICE = 1.0         # share of passing employees the player actually sees  # seconds of extra income a staff upgrade must repay in


class Bot:
    def __init__(self, cfg, rng, pads=None, slow=1.0, desk_first=False):
        self.cfg, self.rng = cfg, rng
        self.slow, self.desk_first = slow, desk_first
        self.comp = Table(cfg["base"])
        self.var = Table(cfg["variants"])
        self.emp = Table(cfg["emp"])
        base_var = self.var.chances(1)
        self.var_tier = {n: tier_of(1 / base_var[n]) for n in self.var.names}
        self.t = 0.0
        self.cash = 1000.0
        self.luck = 1.0
        self.cash_mult = 1.0
        self.roll_speed = 1.0
        self.walk = 1.0
        self.pads = pads if pads is not None else cfg["pads"]
        self.rolls = 0
        self.owned = set()
        self.free_node = True
        self.gears = list(cfg["gears"][1:])
        self.last_buy = 0.0
        self.gaps = []
        mossy = cfg["variants"]["Mossy"][0]
        # desk = [parts by comp index, employee value]
        self.desks = [[[cfg["base"][c][0] * mossy for c in self.comp.names], 0.0, 0.0]]
        self.spawn_clock = 0.0
        self.log = {"desk": {1: 0.0}, "tier": {}, "node": {}, "emp": {}, "rate": []}
        self.next_rate_log = 0

    # income -------------------------------------------------------------
    def plot_rate(self):
        return sum(sum(p) * e for p, e, _ in self.desks)

    def rate(self):
        return self.plot_rate() * self.cash_mult

    def advance(self, dt, scaled=True):
        if scaled:
            dt *= self.slow
        r = self.rate()
        self.cash += r * dt
        self.t += dt
        self.spawn_clock += dt
        while self.next_rate_log <= self.t:
            self.log["rate"].append((self.next_rate_log, r))
            self.next_rate_log += 60

    # parts --------------------------------------------------------------
    def note_tier(self, vi):
        tier = self.var_tier[self.var.names[vi]]
        self.log["tier"].setdefault(tier, self.t)

    def roll(self):
        self.rolls += 1
        luck = self.luck * (100 if self.rolls in TUTORIAL_LUCKY else 1)
        spin = 1.894 / max(self.roll_speed, 0.1) + 0.25
        self.advance(ROLL_OVERHEAD)
        self.advance(spin, scaled=False)
        results = []
        for slot in range(self.pads):
            vi = self.var.pick(self.rng, luck)
            ci = self.comp.pick(self.rng, luck)
            if self.rolls == 1 and slot == 0:
                vi = self.var.names.index("Tree")
            self.note_tier(vi)
            results.append((ci, self.var.value[vi] * self.comp.value[ci]))
        # carry improvements, best gain first, one part per trip
        results.sort(key=lambda x: -x[1])
        for ci, value in results:
            best, where = 0.0, None
            for d in self.desks:
                gain = (value - d[0][ci]) * max(d[1], 1e-6)
                if gain > best:
                    best, where = gain, d
            if where is None:
                continue
            where[0][ci] = value
            self.advance(TRIP / self.walk)

    def open_gifts(self, desk):
        for ci in range(3):
            vi = self.var.pick(self.rng, self.luck)
            self.note_tier(vi)
            desk[0][ci] = self.var.value[vi] * self.comp.value[ci]
        self.advance(1.5)

    # employees ----------------------------------------------------------
    def staff(self):
        while self.spawn_clock >= SPAWN:
            self.spawn_clock -= SPAWN
            ei = self.emp.pick(self.rng, 1)
            if self.rng.random() > NOTICE:
                continue
            v = self.emp.value[ei]
            cost = round(v ** 3 * 100)
            empty = [d for d in self.desks if d[1] == 0]
            if empty:
                target, refund = empty[0], 0
            else:
                target = min(self.desks, key=lambda d: d[1])
                if v <= target[1]:
                    continue
                refund = math.floor(target[2] * 0.5)
                gain = sum(target[0]) * (v - target[1]) * self.cash_mult
                if cost - refund > gain * HIRE_PAYBACK:
                    continue
            if self.cash < cost:
                continue
            self.cash -= cost - refund
            target[1], target[2] = v, cost
            for mark in (2, 5, 8, 10):
                if v >= mark:
                    self.log["emp"].setdefault(mark, self.t)
            self.advance(HIRE)

    # spending -----------------------------------------------------------
    def desk_price(self):
        n = len(self.desks)
        prices = self.cfg["prices"]
        return prices[n] if n < len(prices) else None

    def available_nodes(self):
        nodes = self.cfg["nodes"]
        return [n for n, d in nodes.items()
                if n not in self.owned and (d["parent"] in (None, "Exit") or d["parent"] in self.owned)]

    def apply(self, node):
        fn, args = self.cfg["effects"].get(node, (None, []))
        if fn == "AddLuck":
            self.luck += float(args[0])
        elif fn == "AddPads":
            self.pads = min(self.pads + int(float(args[0])), 17)
        elif fn == "AddMultiplier":
            name, amt = args[0], float(args[1])
            if name == "Cash":
                self.cash_mult += amt
            elif name == "RollSpeed":
                self.roll_speed += amt
            elif name == "WalkSpeed":
                self.walk += amt

    def spend(self):
        # the tutorial has the player hire before anything else is bought
        if not any(e > 0 for _, e, _ in self.desks):
            return
        while True:
            options = []
            price = self.desk_price()
            if price is not None:
                options.append((price, "desk", None))
            if self.gears:
                options.append((self.gears[0], "gear", None))
            for n in self.available_nodes():
                cost = 0 if self.free_node else self.cfg["nodes"][n]["cost"]
                options.append((cost, "node", n))
            if not options:
                return
            if self.desk_first and price is not None:
                # only a node cheaper than a quarter of the next desk jumps the queue
                cheap = [o for o in options if o[1] == "node" and o[0] <= price * 0.25]
                options = cheap or [o for o in options if o[1] == "desk"]
            cost, kind, node = min(options, key=lambda o: o[0])
            if self.cash < cost:
                return
            self.cash -= cost
            self.gaps.append((self.t, self.t - self.last_buy))
            self.last_buy = self.t
            if kind == "gear":
                self.gears.pop(0)
                self.advance(BUY)
            elif kind == "desk":
                desk = [[0.0, 0.0, 0.0], 0.0, 0.0]
                self.desks.append(desk)
                self.log["desk"][len(self.desks)] = self.t
                if len(self.desks) % 8 == 0:
                    staffed = [e for _, e, _ in self.desks if e > 0] or [0]
                    self.log.setdefault("snap", {})[len(self.desks)] = dict(
                        rate=self.rate(), cash=self.cash_mult, luck=self.luck, pads=self.pads,
                        staff=sum(staffed) / len(staffed), parts=sum(sum(p) for p, _, _ in self.desks) / len(self.desks))
                self.advance(BUY)
                self.open_gifts(desk)
            else:
                self.free_node = False
                self.owned.add(node)
                self.log["node"][node] = (self.t, cost, self.rate(), self.desk_price())
                self.apply(node)
                self.advance(BUY)

    def done(self):
        return self.desk_price() is None and not self.available_nodes()

    def run(self, hours):
        while self.t < hours * 3600:
            self.roll()
            self.staff()
            self.spend()
        self.log["end"] = self.t
        self.log["gaps"] = self.gaps
        return self.log


# ---------------------------------------------------------------- reporting

def fmt(t):
    if t is None:
        return "  —  "
    t = int(t)
    h, m, s = t // 3600, t % 3600 // 60, t % 60
    return f"{h}h{m:02d}" if h else f"{m}:{s:02d}"


def short(x):
    for unit, d in (("B", 1e9), ("M", 1e6), ("K", 1e3)):
        if x >= d:
            return f"{x / d:.3g}{unit}"
    return f"{x:.0f}"


def median(xs):
    xs = [x for x in xs if x is not None]
    return statistics.median(xs) if xs else None


def rate_at(log, t):
    best = 0
    for tt, r in log["rate"]:
        if tt <= t:
            best = r
    return best


def report(cfg, logs, n_desks):
    print("DESK BOUGHT AT (median)")
    for floor in range(4):
        row = []
        for d in range(floor * 8 + 1, floor * 8 + 9):
            if d == 1:
                row.append("   d1 start")
                continue
            t = median([l["desk"].get(d) for l in logs])
            price = cfg["prices"][d - 1]
            r = median([rate_at(l, l["desk"][d]) * 1 if d in l["desk"] else None for l in logs])
            mins = price / r / 60 if r else None
            row.append(f"d{d} {fmt(t)} ({mins:.1f}m)" if mins else f"d{d} {fmt(t)}")
        print(f"  F{floor + 1}: " + " | ".join(row))

    print("\nMILESTONES (median, income then)")
    for floor in range(1, 5):
        d = floor * 8
        ts = [l["desk"].get(d) for l in logs]
        t = median(ts)
        r = median([rate_at(l, l["desk"][d]) for l in logs if d in l["desk"]])
        print(f"  Floor {floor} done {fmt(t):>6}   ~{short(r or 0)}/s")
    tree = [max(v[0] for v in l["node"].values()) if len(l["node"]) == len(cfg["nodes"]) else None for l in logs]
    print(f"  Tree done      {fmt(median(tree)):>6}")
    print("\nFIRST PART OF TIER (median)")
    print("  " + " | ".join(f"{t} {fmt(median([l['tier'].get(t) for l in logs]))}" for t in TIER_ORDER[2:]))
    print("\nFIRST STAFF (median)")
    print("  " + " | ".join(f"{m}x+ {fmt(median([l['emp'].get(m) for l in logs]))}" for m in (2, 5, 8, 10)))
    print("\nTREE NODES (median time, cost as seconds of income, cost vs next desk)")
    for n, d in sorted(cfg["nodes"].items(), key=lambda kv: kv[1]["cost"]):
        ts = [l["node"][n][0] for l in logs if n in l["node"]]
        secs = [l["node"][n][1] / l["node"][n][2] for l in logs if n in l["node"] and l["node"][n][2] > 0]
        nxt = [l["node"][n][3] for l in logs if n in l["node"] and l["node"][n][3]]
        over = " > next desk!" if nxt and d["cost"] > median(nxt) and n != "Luckiest" else ""
        print(f"  {n:<18} {short(d['cost']):>6}  at {fmt(median(ts)):>6}  {median(secs) or 0:7.0f}s{over}")


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--pads", type=int)
    ap.add_argument("--runs", type=int, default=40)
    ap.add_argument("--hours", type=float, default=9)
    ap.add_argument("--root", type=Path, default=DEFAULT_ROOT)
    a = ap.parse_args()
    cfg = load(a.root)
    logs = [Bot(cfg, random.Random(seed), a.pads).run(a.hours) for seed in range(a.runs)]
    print(f"pads={a.pads if a.pads is not None else cfg['pads']}  runs={a.runs}  nodes={len(cfg['nodes'])}  desks={len(cfg['prices'])}\n")
    report(cfg, logs, len(cfg["prices"]))


if __name__ == "__main__":
    main()
