# Monetization

Supersedes `docs/packs.txt`. Nothing here is wired up yet: `MarketplaceService` appears
nowhere in `src/`, and `Gamepasses = {}` in `PlayerData.luau` is the only hook that exists.

## What the economy actually is (read before pricing anything)

- **Rolls are free.** `RollingService` charges nothing; pads spin on a timer, luck decides.
- **Cash buys desks and tree nodes.** Desks cost `250 * 1.28^n`; a full 32-desk plot is
  roughly 2.5M. Employees cost 100-1,000. That is the whole cash ramp, and it is finite.
- **The endgame is the chase**: Premium parts at 1 in 769k, King Ceo at 1 in 15k. Pads
  (1 to 9) and luck (tree to ~30) are the only things that speed it up.
- The item shop is not built. Offline earnings are planned, not built. No rebirths.

So: cash products are early-to-mid game only and must not be big enough to end the cash
ramp in minutes. Luck and pads are the long-tail levers. The chase is protected by never
handing out the top two tiers.

## The test every item passed

1. It removes a friction the player has already felt, or gives something they already want.
2. It does not do the same job as another item.
3. A ten-year-old can read it in one line and one number.
4. Owning it makes nobody else's game worse.
5. The price sits where the wallet is (gift cards: 800, 2,000) and the conversion band fits
   the value: 25-75 converts 8-15%, 100-300 4-8%, 500+ under 4%.

## Five buyers, one store

| Buyer   | Spends            | Buys                                            |
|---------|-------------------|-------------------------------------------------|
| Free    | 0                 | Nothing. Reaches everything, gets server luck from others, sees the odds. |
| Pocket  | one buy under 100 | Sprint 25, Fast Spin 49, rung 19, Starter 49    |
| Regular | 100-500 a month   | Auto Roll, Lucky Roller, a gear, skips, pads    |
| Big     | 500-2,000         | VIP 399, Everything 999, Executive 999          |
| Whale   | 2,000+            | CEO 2,999, Founder 9,999, 8x server luck on repeat |

Price points: 9 19 25 39 49 69 79 99 149 199 249 299 399 599 999 2,999 9,999.

## Fairness rules

- Nothing paid is required for anything.
- Paid luck is personal or shared with the whole server. It never takes from anyone.
- Hardcore parts, Premium parts and King Ceo are never in a pack. The top of the chase is
  earn-only, which is what makes it worth chasing -- and worth flexing.
- Packs are components only. They never claim a "worth": parts have no Robux list price,
  so there is nothing honest to sum. The Everything bundle is 23% off real list prices.
- Every luck product shows its odds table before purchase.
- One strikethrough: the Roblox Plus price (20% off, Roblox pays the difference).
- Raising a price never upsets an owner; lowering one does. Permanents err low; Managed
  Pricing moves them up.

## Gamepasses

| Pass          | R$  | Plus | What it is |
|---------------|----:|-----:|------------|
| Sprint Shoes  |  25 |   20 | 2.5x walkspeed. The first yes. |
| Fast Spin     |  49 |   39 | Rolls resolve 2x faster. Comfort. |
| Auto Roll     | 149 |  119 | Pads spin themselves while you are on your plot. The idle pass; rolls are free, so this sells time. |
| Lucky Roller  | 199 |  159 | 2x luck, permanently. The flagship; *PRI.* |
| VIP           | 399 |  319 | +25% income, one day of income on purchase, +1 pad, VIP chat tag and plot-sign title, the Golden Coil gear, a free 1h time skip claimable daily. |
| Founder       | 9,999 | 7,999 | Name on the Founders wall on the map, Founder chat tag and plot-sign title. Nothing else. Not in the bundle. |

**Gears** -- equipped one at a time.

| Gear       | R$  | Plus | Effect |
|------------|----:|-----:|--------|
| Grav Coil  |  79 |   63 | Higher jump, slower fall. |
| Trolley    |  99 |   79 | Carry two parts at once from the pads. |
| Jetpack    | 299 |  239 | Fly. The flex everyone on the map sees. |

**Everything -- 999 (Plus 799).** The five passes above Founder, and the three gears.
1,298 apart, 23% off.
Fits the $10 card plus leftovers, or the $25 card with 1,001 to spare.

**Planned, priced, not shipped:**
- *Double Daily -- 49.* Needs a 7-day login streak. Build the streak: it is the cheapest
  retention mechanic that exists, and this pass is how it pays for itself.
- *Longer Lock -- 199.* +50% desk lock time, permanent. Ships with stealing. A permanent
  small edge is the same category as walkspeed; a "lock now" consumable is not sold.

**Cut, and why:** Divine Hunter (same job as Lucky Roller, harder to read, doubles the odds
UI); Magnet (same job as Trolley); Instant Hires (touches the employee race); Extra Floors
(floors are cash only); Super Deals (discounts the sink).

## Cash ladder -- developer products

Total income multiplier. Each rung unlocks the next; one on sale at a time. Ladder total 624.

| # | Cash | R$  | Plus |
|---|------|----:|-----:|
| 1 | x1.5 |  19 |   15 |
| 2 | x2   |  39 |   31 |
| 3 | x3   |  69 |   55 |
| 4 | x4   |  99 |   79 |
| 5 | x6   | 149 |  119 |
| 6 | x8   | 249 |  199 |

Why not 2x, 4x ... 512x: the whole plot costs ~2.5M and rolls are free. A 512x buyer
finishes the cash game in minutes, then has nothing to spend on, and the ladder cannibalises
every other cash product. x8 halves-and-halves the ramp six times without ending it. The
shape you wanted -- starts cheap, each unlocks the next -- is kept; the magnitude is not.

Stacks: `floor(PlotRate * TreeCash * Rung * VIP)`. The tree is additive, everything
bought is multiplicative.

## Server luck -- developer products (paid random item)

Everyone in the server gets it, the buyer's name is on a banner for the duration, tappable
to buy the next tier up. Not sequential. Higher tier replaces lower and keeps the longer
clock; same tier extends. Multiplies with tree luck and Lucky Roller.

| Tier | Duration | R$  | Plus |
|------|----------|----:|-----:|
| 2x   | 10 min   |  49 |   39 |
| 3x   | 15 min   |  99 |   79 |
| 5x   | 20 min   | 249 |  199 |
| 8x   | 30 min   | 599 |  479 |

Why it stops at 8x: tree luck reaches ~30, so 32x server luck puts Divine at about 1 in 800
for everyone in the room for 45 minutes. That is not a party, it is the top tier becoming
common -- the buyer's own Divine included. 8x for 30 minutes is a party.

No potions, by decision: no personal luck, cash or speed consumables. Lucky Roller is the
only personal luck for sale; server luck is the only repeatable luck.

## Time skips -- developer products

These are the coin packs. Each pays the player's own current income rate for N hours,
banked instantly, and the button shows the actual cash number (rate x hours). Priced by
rate rather than as flat amounts so they never go stale as desk prices change. Prompted at
the desk board when the next desk is out of reach.

| Skip    | R$  | Plus |
|---------|----:|-----:|
| 1 hour  |  19 |   15 |
| 8 hours |  49 |   39 |
| 1 day   |  99 |   79 |
| 3 days  | 249 |  199 |

Why no 7-day: with a ~2.5M plot, a week of mid-game income is the whole plot. Same problem
as the 512x rung.

## Utility -- developer products

| Item                 | R$ | Notes |
|----------------------|---:|-------|
| Reroll one desk slot |  9 | Cheapest thing in the game. One tap after a bad spin. *PRI.* |
| +1 roll pad          | 79 | Capped at 9. Pads are the chase; this is the best-value permanent in the store and should be. |

Item-shop restock (29) is planned for when the item shop exists.

## Packs

Components only, and employees where it fits. Nothing else ever goes in a pack: no pads,
rungs, skips, passes, luck or tags. A pack is "here is a desk set". Parts come in threes
(computer, keyboard, monitor), so 6 parts is two full desks. Hardcore, Premium and King
Ceo are never inside. Packs are deterministic, so none of them is a paid random item and
they show everywhere.

| Pack      | R$    | Plus  | Contents | When |
|-----------|------:|------:|----------|------|
| Starter   |    49 |    39 | 6x Steampunk (2 desks), 2x Hamster | First 24h, once. Countdown on the HUD. |
| Pro       |   399 |   319 | 12x Space (4 desks), 4x Shark Boss | Always on. |
| Executive |   999 |   799 | 24x Galaxy (8 desks), 8x MrBossy | Always on. |
| CEO       | 2,999 | 2,399 | 48x Galaxy (16 desks), 24x Space (8 desks), 16x Mr Money | Always on. |

Each tier steps up one variant: Steampunk (1 in 2,273) to Space (1 in 38k) to Galaxy
(1 in 100k). CEO furnishes three quarters of a 32-desk plot in one go, which is the
biggest thing a component pack should ever do.

Cut: Weekly. A repeatable component pack erodes the chase a little more every week, and
there is nothing else allowed in a pack to make it repeatable with.

**Founder -- 9,999 (Plus 7,999).** Not a pack: a gamepass. A name on the Founders wall on
the map, the Founder chat tag and plot-sign title nobody else can get, nothing else. Not in
the Everything bundle. Sold to be seen, and to make CEO look sane.

## Recurring

**Private servers -- 49/month.** Free for Roblox Plus members by Roblox's rule.
**Roblox Plus prompt** in the shop beside the Plus column: 250 R$/mo for each of a
signup's first three months.

## Free economy

A 10-minute first-session trial of Fast Spin and Auto Roll, then it switches off. A
play-time reward chain across a session. Five minutes of free 2x server luck the moment
anyone in the server hits their first Divine. Five minutes of server-wide 2x luck when someone brings a friend in. Group-join
reward once there is a group. The login streak, when Double Daily ships.

## Psychology, mapped to a mechanic

| Lever                 | Where it lives |
|-----------------------|----------------|
| Variable-ratio reward | The core roll loop. Already built. Do not touch. |
| Foot in the door      | 9 reroll, 19 rung, 25 Sprint, 49 Starter. |
| Anchoring / decoy     | Founder 9,999 makes CEO 2,999 sane. Everything 999 makes VIP 399 sane. |
| Empty the card        | Everything 999 + rungs fills the $10 card; Executive + Everything fills the $25. |
| Endowment             | Free first-session trial of Fast Spin and Auto Roll, then gone. |
| Goal gradient         | Progress bar to the next rung; "3 desks to the next floor" on the board. |
| Social proof          | Server-luck sponsor banner, tappable to outbid. The Founders wall. The Jetpack. |
| True near-miss        | After a roll one tier short, say so -- only when the number is real. |
| True reference price  | The Plus strikethrough. Roblox funds it, so it is honest. |

## Not doing, and why

Roblox moderates these with removal, a 2026 University of Sydney study catalogued them
across top games, Epic got a $115M refund order for the same, and parents chargeback.

- No countdowns that reset or extend. A 24h starter is 24h.
- No "worth 999" unless 999 is the sum of the listed prices of what is inside.
- No always-on "daily discount".
- No purchase prompt on a timer at a moment of loss.
- No hidden odds. Every luck product shows the full percentage table before purchase.
- No second currency (gems, tokens) bought with Robux and spent on items. Selling the
  game's own cash for Robux is fine -- that is what the time skips are.
- Nothing that hurts another player, nothing that touches the employee race, and no
  "lock now" consumable.

## Paid random items policy (in force since 26 May 2026)

- Every product marked *PRI* shows numerical odds for every outcome before purchase,
  summing to 100%, updated live with the player's current luck.
- Every outcome must give something.
- `PolicyService:GetPolicyInfoForPlayerAsync(Player).ArePaidRandomItemsRestricted` on
  join. When true (Australia, Belgium, Netherlands, UK, Brazil today): hide Lucky Roller,
  server luck and the slot reroll. Show the cash ladder, time skips, gears, pads and the
  packs in their place.
- Never bundle a random item into a deterministic pack.

## Where the store appears

- **Boost Luck** on the roll pad, opening straight onto server luck.
- **The desk board**, when the next desk is out of reach, offers a time skip.
- **A true near-miss line** after a roll one tier short, opening onto server luck.
- **The reroll button** on a freshly rolled slot -- 9 R$, one tap.
- **The sponsor banner** naming whoever bought server luck, tappable to outbid.
- **The starter countdown** pinned to the HUD for 24 hours, then gone.
- **The Plus price column** in the shop, with the Plus signup prompt beside it.
- **The shop**, one tab per section above.

## Build order

1. **Prices are never hardcoded.** Every SKU is a Creator Hub product; the client reads
   `MarketplaceService:GetProductInfo` / `GetDeveloperProductsAsync`. That lets Managed
   Pricing run its 90-day tests.
2. **`MonetizationService`.** `ProcessReceipt` idempotent: store the `PurchaseId` in the
   profile, grant, save, then return `PurchaseGranted`. Gamepass ownership cached per
   session off `UserOwnsGamePassAsync`, refreshed on `PromptGamePassPurchaseFinished`.
3. **Policy gate.** `ArePaidRandomItemsRestricted` on join, replicated, shop builds itself
   from it. Odds table fed by the same luck number `RollingService` reads.
4. **Save schema.** `OwnedProducts`, `CashRung`, `Boosts` (multiplier + `os.time()` expiry),
   rolling `PurchaseIds`, `StarterExpiresAt`, `TrialEndsAt`,
   `VipSkipClaimedAt`, `PolicyRestricted`, `Founder`. `Gears` / `EquippedGear` exist.
5. **One resolver for multipliers.** `RevenueService:Pay` reads `Data.Multipliers.Cash()`
   directly today. Cash: `floor(PlotRate * TreeCash * Rung * VIP)`. Luck: tree x
   Lucky Roller x server luck, in one function `RollingService` calls.
6. **Server luck as a server-owned object**: one replicated attribute, one expiry, one banner.
7. Shop UI with the two-column price. Founders wall on the map. Then renders.
8. Turn on **Managed Pricing** and **regional pricing** the week the store ships.

## Sanity numbers

At 5,000 DAU and the platform's ~1.25% daily buy rate, ~60 purchases a day. A store with
this much under 100 should beat that; at 3% it is ~150 a day, at a mix averaging ~90 R$
that is ~13,500 gross, ~9,500 net, roughly $36/day at DevEx. The store makes a big game
richer; it does not make a small game rich. Retention first.

## Asset ids -- computer, keyboard, monitor

```
steampunk   138960511492611   106389553350332   138719314384237
space        89613043477012    85537548013666    73375417258079
galaxy       77919124745146   106121102729895   103663739233201
hardcore     88247695074962    94202025628880   106402150086388
premium     132700700236592    77355774327641   124455662978011

starter icon   89765645822434
bundle icon   124503020428640
```

## Still needed

Renders for all 21 employees; three gear models plus the Golden Coil; pack icons for
Pro, Executive and CEO; pass icons for Fast Spin, Auto Roll, Lucky Roller, VIP, Founder
and Everything; a 512x512 store icon per SKU; the odds-table UI; the Founders
wall.

## Sources

- Gift card denominations: roblox.fandom.com/wiki/Roblox_Gift_Card; gamsgo.com/blog/robux-prices
- Roblox Plus replacing Premium, creator payouts: about.roblox.com/newsroom/2026/04/introducing-roblox-plus-subscription; tubefilter.com/2026/04/13/roblox-plus-creator-payouts
- Paid random items policy: create.roblox.com/docs/production/monetization/paid-random-items; devforum.roblox.com/t/clarifying-requirements-for-paid-random-items/4654622
- Managed Pricing: create.roblox.com/docs/production/monetization/price-optimization
- Price bands and conversion: rolearn.dev/insights/gamepass-pricing-ladder
- Starter pack share of revenue: RoCitizens case study, blog.haydz6.com/2016/08/rocitizens-case-study-improving-player-retention
- Platform conversion and spend: theshelf.com/the-blog/roblox-stats-and-spending; sqmagazine.co.uk/roblox-statistics
- Deceptive practices study: ses.library.usyd.edu.au/handle/2123/35033; ia.acs.org.au/article/2026/roblox-sucking-up-money-from-young-players--study.html

## UI to build

In build order. Every price shown anywhere comes from `GetProductInfo`; nothing is typed in.

1. **Shop window.** Tabs: Passes, Gears, Cash, Luck, Skips, Packs. One card component:
   icon, name, one-line effect, list price, Plus price, Buy. States: buy / owned / soon.
   - Cash tab shows the six rungs as steps; owned ones filled, only the next has a button.
   - Luck tab shows the four server tiers; if one is running, the active tier is greyed
     with its clock and the higher ones read "Upgrade".
   - Restricted region: the Luck tab and Lucky Roller are hidden.
   - Packs tab: each card shows the desk sets and employees as pictures, no "worth" line.
2. **Odds panel.** Opens before Lucky Roller, any server luck, and the slot reroll. Every
   rarity tier with its % now and % with the boost, summing to 100%, rounding footnote,
   Buy inside the panel. The reroll version lists variants under a Details toggle.
3. **Server luck banner.** Top strip: multiplier, countdown, sponsor name. Tap opens the
   Luck tab on the next tier. Also carries the free 5-minute Divine celebration.
4. **Boost Luck button** on the roll UI. Opens the Luck tab.
5. **Desk board upsell.** When cash is short, a second line: "Skip 1 hour, +$X", X being
   the current rate times 3,600. Prompts the 1h skip; longer skips live in the tab.
6. **Slot reroll button** on a freshly rolled slot's card: "Reroll 9". Odds panel first.
7. **Starter pack.** Popup on first join, then a HUD chip with the 24h countdown that
   reopens it. Gone at zero or on purchase, never back.
9. **Trial chip.** HUD: "Free trial, Fast Spin + Auto Roll, 09:59". On expiry a small
   popup: keep them, 49 and 149.
10. **Near-miss toast.** "Rare was one roll away", with a Boost Luck link. Only when true.
11. **Purchase feedback.** Success toast plus a grant moment: the rung number pops, a new
    pad drops in, a gear equips. Cancel or failure shows nothing.
12. **Plus line and button.** "Plus members pay X" under each price, and a Get Plus button.
    Confirm the current Plus prompt API in the docs before wiring it.
13. **Tags and titles.** VIP / CEO / FOUNDER chat prefix, and the title on the plot sign.
14. **Founders wall.** A world model on the map with a name list. Build, not screen UI.
15. **Gear hotbar.** Equip and switch gears. `Gears` / `EquippedGear` exist in the save;
    check what UI already reads them before building new.
