# UI motion

How anything on screen in Run an Office moves. One vocabulary, so a panel opening and a node
landing read as the same hand.

The numbers here are not invented: they are the ones `NodeConstructor` already lands its hexes on,
lifted out and named so the rest of the UI can use them.

## Springs, not tweens

Fusion 0.3, scoped API. `Scope:Spring(Goal, Speed, Damping)` driving a `Scope:Value` goal.

A spring is used because UI targets change mid-flight: a panel can be closed halfway through
opening, a node can be hovered while it is still landing. A spring retargets from wherever it is
and stays continuous. A tween restarts, and the restart is visible.

Reach for `Scope:Tween` only when the duration itself is the design — a timed flash, a one-shot
intro that nothing can interrupt. `NodeConstructor.playTween` is the exception in this codebase:
colour and transparency fades, where a spring would wobble.

## The numbers

| Role | Speed | Damping | Why |
| --- | --- | --- | --- |
| Panel scale, opening | 28 | 0.7 | One overshoot of about 3%, then gone. This is the house pop. |
| Panel scale, closing | 36 | 1 | Never bounce on the way out -- see below |
| Node size | 32 | 0.66 | The same pop at the size a hex lands at |
| Rotation | 28 | 0.5 | Looser, so a tilt unwinds after the size has settled |
| Fade in | 16 | 1 | Slow: a backdrop must not beat its content on screen |
| Fade out | 11 | 1 | Slower still, so it lifts as the content leaves rather than before it |

Damping below 0.5 is for accents that carry no text. Text that overshoots is unreadable.

**Damping is what ends a motion, not speed.** The panel pop first ran at `0.58`, which overshot 6%
and then crawled back over a third of a second in one-percent steps. The motion was over long
before the numbers were, and that gap is what reads as a halt at the end of an opening. At `0.7`
the overshoot is 2.7% and inside 1% of the target four frames later. If an animation feels like it
stops and then finishes, raise damping before touching speed.

**Direction has its own character.** Closing is critically damped: an undershooting close springs
back up before the screen is switched off, which reads as the panel opening again on its way out.
Both `Speed` and `Damping` are `UsedAs<number>` in Fusion, so they are held as `Value`s and set per
direction -- retargeting mid-flight picks up the new feel with it.

## The patterns

### Pop in, pop out

A panel scales up into place rather than sliding. `UIMotion.Attach` puts a `UIScale` on the frame
and springs it `0.8 -> 1`, with a velocity kick on the way in so it arrives with weight.

Scaling a `UIScale` rather than the frame's own `Size` matters: every panel in this game is built
in the place with its own layout, list constraints and aspect ratios. Touching `Size` fights all of
that. A `UIScale` multiplies the whole subtree and nothing inside it has to know.

```luau
local Goal = Scope:Value(ShutScale)
local Motion = Scope:Spring(Goal, 30, 0.58)

Scope:Hydrate(Scale)({ Scale = Motion })

Goal:set(OpenScale)
Motion:addVelocity(Punch)   --> the kick. without it the pop is soft
```

Closing is aimed at `-2`, which is well past gone, and the scale shown is clamped at zero. This
matters more than it looks: a spring eases into whatever it is heading for, so a close aimed at the
size it stops at spends its last frames barely moving and is then switched off mid-air. That reads
as a panel that despawns rather than one that leaves -- a clear cut-off, with a slowdown just
before it. Aimed past zero, the panel crosses zero while it is still travelling, so what the eye
sees is one continuous movement out to nothing.

Measured, at `ShutSpeed = 5.5`: `0.847 → 0.497 → 0.101 → 0.000` over about 200ms, with the
`ScreenGui` switched off 60ms after there was already nothing on screen.

`Show` calls `setPosition(ShutScale)` before retargeting, because the spring is sitting somewhere
below zero after a close and would otherwise spend its first frames climbing back into view.

### The kick

`addVelocity` on a spring that is already near its goal is what separates a pop from a grow. The
size spring gets `2.6` when a node lands, half that when a press is released. It is the single
highest-value trick in here: the goal never changes, only the speed it arrives at.

### The tilt

A node lands from `-22°` with a looser spring than its size. Because rotation settles slower than
scale, the node reaches full size while still straightening -- which is what makes it look thrown
into place rather than faded in.

### Stagger

Rings of the upgrade tree land `0.045s` apart, keyed off depth from the centre. Stagger is always
derived from a value the layout already has -- depth, `LayoutOrder`, index -- never from a chain of
`task.wait` calls.

Folding away runs the same stagger backwards at `0.028s`: the ring furthest out goes first and the
Exit button under the cursor is the last thing left. Each node takes a spin on the way out, and the
backdrop lifts across the same window rather than before it, so the screen empties as one movement.
A screen that animates itself out sets `ShutTime` in its entry so the `ScreenGui` is not switched
off underneath the fold.

An interrupted fold is why the tree keeps a `Generation` counter: the delays from a fold that was
reopened halfway are still queued, and they check the counter before hiding anything.

### Backdrops

A screen that fills the display dims the world behind it rather than popping over it. `Dim` is how
dark it settles at -- the tree sits at `0.45`. The frame was built at `0.1`, which is very nearly
solid black across the whole display: it stopped reading as a screen over the game and started
reading as a black screen with hexes on it.

### Hover and press

`1.15x` on hover, `0.85x` while held, released with half a kick. One size spring serves all three;
the goal changes, the spring does the rest.

### Refusal

A press that cannot be honoured -- a node you cannot afford -- gets velocity on the *rotation*
spring instead of the size spring. It wobbles in place and settles. Nothing moves position, so it
reads as "no" without looking broken.

## Where it lives

| File | What it owns |
| --- | --- |
| `Shared/Utilities/UIMotion.luau` | The panel pop and the backdrop fade. One `Attach` per screen. |
| `Shared/Controllers/UIController.luau` | Which screen is open, the blur, and calling Show/Hide |
| `Shared/Controllers/UIPreloadController.luau` | Drawing every image once so it is decoded before it is needed |
| `Shared/Controllers/UpgradeTreeController/NodeConstructor.luau` | Everything a hex node does |

## Preloading

`PreloadAsync` fetches an image. It does not decode one -- that happens the first time the engine
has to draw it, and until then the first frame it appears on hitches however early the fetch was.
An `ImageLabel` sat in a `Folder`, which is how the part renders were being preloaded, never draws
at all and so never decodes.

So every image is drawn once on a screen of its own: one pixel each, `DisplayOrder = -1000`, for
three frames, then thrown away. A pixel is enough because decoding is per image rather than per
pixel. Decals on a part in the world do the same job, but only while the camera happens to be
pointed at them, and they are visible when it is.

The first pass covers the PlayerGui, the Assets folder and the render config. It is not enough on
its own: the shop restocks from saved data, screens are cloned again on respawn, and a card can
swap its own picture. Art that arrives later is exactly the art that hitches, so `DescendantAdded`
and a property watch on `Image`/`Texture` feed the same queue, debounced into batches.

The upgrade tree deliberately opts out of the panel pop. Scaling its root would change the canvas
size the pan/zoom and the hex layout are measured against, and it already has a better opening of
its own: the rings unfold from the middle. `Motion = false` in the screen's config is how a screen
says so.

## Rules

- One spring per property. Do not drive size and rotation off the same one.
- Fades are always critically damped.
- Animate scale, transparency, colour, rotation. Never animate a property that forces the layout
  to reflow every frame.
- Interrupting is normal. Every animation here is safe to reverse halfway.
- If a value is set from more than one place, it belongs on a `Value` goal, not written directly.
