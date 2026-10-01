"""How robust the pacing is: spread across seeds, slower and faster players, a desk-first buyer,
and where income comes from at each floor.

python3 tools/pacing/audit.py
"""
import random
import statistics as st

import sim

def pct(xs, q):
    xs = sorted(x for x in xs if x is not None)
    return xs[min(int(q * len(xs)), len(xs) - 1)] if xs else None

def runs(cfg, n=40, **kw):
    return [sim.Bot(cfg, random.Random(s), **kw).run(9) for s in range(n)]

def summary(label, logs):
    out = []
    for d in (8, 16, 24, 32):
        ts = [l["desk"].get(d) for l in logs]
        out.append(f"{sim.fmt(pct(ts,.5))} [{sim.fmt(pct(ts,.1))}-{sim.fmt(pct(ts,.9))}]")
    print(f"{label:<22}", " | ".join(out))

if __name__ == "__main__":
    cfg = sim.load(sim.DEFAULT_ROOT)
    base = runs(cfg)
    print("milestone: median [p10-p90]   F1 | F2 | F3 | F4")
    summary("baseline", base)
    summary("casual (1.5x slower)", runs(cfg, slow=1.5))
    summary("sweaty (0.6x)", runs(cfg, slow=0.6))
    summary("desk-first buyer", runs(cfg, desk_first=True))
    print("\nwhere income comes from at each floor done (median)")
    print(f"{'':6}{'rate':>8}{'desks':>6}{'cash x':>8}{'staff x':>8}{'parts/desk':>11}{'luck':>6}{'pads':>5}")
    for d in (8, 16, 24, 32):
        snaps = [l["snap"][d] for l in base if d in l.get("snap", {})]
        m = lambda k: st.median(s[k] for s in snaps)
        print(f"F{d//8:<5}{sim.short(m('rate')):>8}{d:>6}{m('cash'):>8.2f}{m('staff'):>8.2f}{m('parts'):>11.0f}{m('luck'):>6.2f}{m('pads'):>5.0f}")
