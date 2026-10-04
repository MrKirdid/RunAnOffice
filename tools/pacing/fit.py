"""Fit desk prices and tree node costs to the pacing targets by iterating the sim.

Desk prices are nudged until the median bot buys each desk at its DESK_TARGETS time. Each node's
cost is set to NODE_TARGETS seconds of the income the bot has at the node's target time. Starts
from the prices on disk, so a re-fit after a small change converges in a few passes.

python3 tools/pacing/fit.py [--passes N] [--smooth N] [--seeds N] [--write]

--write puts the result into DeskPurchase.luau and Upgrades.luau; then check it with sim.py.
"""

import argparse
import math
import random
import re
import statistics as st
import sys

import sim

M, H = 60, 3600

# a fresh save has 1000 cash and an unstaffed starter desk: desk 2 must leave enough for a hire,
# or a player who buys it first is left with no cash and no income
DESK2 = 500

# when each desk should be bought, in seconds of active play (desk 1 is the starter)
DESK_TARGETS = [0, 30, 75, 120, 180, 255, 345, 465,
                10 * M, 14 * M, 19 * M, 25 * M, 32 * M, 40 * M, 49 * M, 60 * M,
                70 * M, 83 * M, 96 * M, 110 * M, 125 * M, 142 * M, 160 * M, 180 * M,
                200 * M, 225 * M, 250 * M, 280 * M, 310 * M, 345 * M, 380 * M, 420 * M]

# node: (target time, cost in seconds of income at that time). Stages: start nodes by 4m under
# 15s each, floor 1 5-15m at 20-60s, floor 2 15m-1h at 2-5m, floor 3 1h-3h at 5-10m, floor 4
# 3h-6h30 at 10-20m, Luckiest ~7h at ~40m. Cash III and IV sit at the top of their stage.
NODE_TARGETS = {
    # the pad chain off the right of Exit: pad 2 in the first minute (free in the tutorial), then 5,
    # 10, 10 and 20 minutes apart
    "RollerI": (45, 8), "RollerII": (6 * M, 30), "RollerIII": (16 * M, 60), "RollerIV": (26 * M, 120),
    "RollerV": (46 * M, 240),
    "CashI": (90, 10), "SpeedI": (135, 10), "LuckyI": (180, 12), "SmartRoller": (225, 14),
    "SpeedII": (5 * M, 20), "NewNode": (6.5 * M, 25), "FasterEmployees": (8 * M, 30),
    "GearSlotsI": (9.5 * M, 35), "LuckyII": (11 * M, 45), "CashII": (13.5 * M, 45),
    "FasterRolls": (17 * M, 120), "NewNode3": (22 * M, 150), "FasterEmployeesII": (28 * M, 180),
    "GearSlotsII": (34 * M, 210), "FasterRollsPlus": (41 * M, 240), "HypeRoller": (100 * M, 400),
    "CashIII": (55 * M, 300),
    "LuckyIII": (65 * M, 300), "LegendaryChances": (80 * M, 360), "NewNode2": (95 * M, 390),
    "NewNode5": (115 * M, 450), "NewNode4": (135 * M, 480), "LuckyIV": (155 * M, 540), "CashIV": (175 * M, 600),
    "MythicChances": (190 * M, 600), "MegaRoller": (220 * M, 720), "LuckyV": (250 * M, 780),
    "NewNode6": (200 * M, 700), "GigaRoller": (310 * M, 960), "GodlyChances": (345 * M, 1080),
    "NewNode8": (380 * M, 1200),
    "Luckiest": (420 * M, 2400),
}


def readable(v):
    """Two significant figures, the same rounding DeskPurchase.Readable shows."""
    if v < 1000:
        return float(round(v / 10) * 10 if v >= 100 else round(v))
    scale = 10 ** (math.floor(math.log10(v)) - 1)
    return float(round(v / scale) * scale)


def run(cfg, seeds, hours=8.5):
    return [sim.Bot(cfg, random.Random(s)).run(hours) for s in range(seeds)]


def med(xs):
    xs = [x for x in xs if x is not None]
    return st.median(xs) if xs else None


def rate_curve(logs):
    n = min(len(l["rate"]) for l in logs)
    return [st.median(l["rate"][i][1] for l in logs) for i in range(n)]


def rate_at(curve, t):
    return curve[min(int(t // 60), len(curve) - 1)]


def smooth(prices):
    """Take the noise out of a fitted curve: weighted neighbours in log space, rising 8%+ a step."""
    logs = [math.log(p) for p in prices]
    out = logs[:2]
    for i in range(2, len(logs)):
        c = logs[i + 1] if i + 1 < len(logs) else logs[i]
        out.append((logs[i - 1] + 2 * logs[i] + c) / 4)
    for i in range(2, len(out)):
        out[i] = max(out[i], out[i - 1] + math.log(1.08))
    return [math.exp(x) for x in out]


def step(cfg, seeds):
    logs = run(cfg, seeds)
    curve = rate_curve(logs)
    times = [med([l["desk"].get(d + 1, 9 * H) for l in logs]) for d in range(32)]
    prices = cfg["prices"]
    prices[1] = DESK2
    for d in range(2, 32):
        gap_t = DESK_TARGETS[d] - DESK_TARGETS[d - 1]
        gap_a = max(times[d] - times[d - 1], 5)
        # the gap sets most of it; the absolute time pulls drift back so it does not pile up
        ratio = (gap_t / gap_a) ** 0.5 * (DESK_TARGETS[d] / max(times[d], 5)) ** 0.35
        prices[d] *= min(max(ratio, 0.4), 2.5)
    for n, (t, secs) in NODE_TARGETS.items():
        cfg["nodes"][n]["cost"] = secs * rate_at(curve, t)
    print(f"  F1 {sim.fmt(times[7])} F2 {sim.fmt(times[15])} F3 {sim.fmt(times[23])} F4 {sim.fmt(times[31])}",
          file=sys.stderr)


def write(cfg, root):
    path = root / "src/Shared/Utilities/DeskPurchase.luau"
    src = path.read_text()
    head, rest = src.split("local Prices = {\n", 1)
    _, tail = rest.split("\n}\n", 1)
    lines = []
    for i, price in enumerate(cfg["prices"]):
        if i % 8 == 0:
            lines.append(f"\t--> floor {i // 8 + 1}")
        lines.append(f"\t{int(price):_},")
    path.write_text(head + "local Prices = {\n" + "\n".join(lines) + "\n}\n" + tail)

    # plain integers, the way the tree editor plugin writes them
    path = root / "src/Shared/Configs/Upgrades.luau"
    src = path.read_text()
    for name, node in cfg["nodes"].items():
        src, n = re.subn(r"(\n\t" + name + r" = \{.*?Cost = )(\d+)(,)",
                         lambda m: m.group(1) + str(int(node["cost"])) + m.group(3), src, count=1, flags=re.S)
        assert n == 1, f"no Cost for {name} in Upgrades.luau"
    path.write_text(src)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--passes", type=int, default=12)
    ap.add_argument("--smooth", type=int, default=6)
    ap.add_argument("--seeds", type=int, default=24)
    ap.add_argument("--write", action="store_true")
    a = ap.parse_args()
    cfg = sim.load(sim.DEFAULT_ROOT)
    for p in range(a.passes + a.smooth):
        if p >= a.passes:
            cfg["prices"] = smooth(cfg["prices"])
        step(cfg, a.seeds)
    cfg["prices"] = [readable(x) for x in smooth(cfg["prices"])]
    for i in range(2, len(cfg["prices"])):
        if cfg["prices"][i] <= cfg["prices"][i - 1]:
            cfg["prices"][i] = readable(cfg["prices"][i - 1] * 1.1)
    for node in cfg["nodes"].values():
        node["cost"] = readable(node["cost"])
    print("desks", " ".join(sim.short(x) for x in cfg["prices"]))
    print("nodes", " ".join(f"{n} {sim.short(d['cost'])}" for n, d in sorted(cfg["nodes"].items(), key=lambda kv: kv[1]["cost"])))
    if a.write:
        write(cfg, sim.DEFAULT_ROOT)
        print("written to DeskPurchase.luau and Upgrades.luau")


if __name__ == "__main__":
    main()
