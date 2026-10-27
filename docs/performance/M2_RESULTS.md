# M2 results: optimizations, before and after

Each change is measured on its own with the same benchmark as the baseline: Mage `:late`, Elwynn,
seed 1234, `FIXED_DT=16.667`, vsync off, 1600×900 foreground window, fresh `BENILLA_HOME`, the
`play` build (see [M2_BASELINE.md](M2_BASELINE.md)). Candidates and their ranking come from
[M2_PROFILE.md](M2_PROFILE.md). All results are local and automated; no human playtest yet.

## #1: minimap redraw throttled to 20 Hz

**The change** (`crates/benilla-app/src/survivors/minimap.rs`):
- `compose` rebuilt the 192×192 minimap image and re-uploaded it to the GPU **every frame**. It
  now runs at most `REDRAW_HZ` = 20 times a second (`redraw_due`, carrying the remainder over),
  and at once when the map comes back into view.
- **Visual only:** the arrow and enemy dots refresh 20 times a second. No gameplay state, no RNG.
- **New test:** `the_minimap_redraws_at_its_rate_whatever_the_frame_rate` (30/60/144/500 fps).
- **Checks:** 38 survivors tests pass, including the unchanged golden tables; survivors lint
  clean; rustfmt clean.

**How it was measured:**
- Six runs in total. Three (2026-10-26 01:15–02:25) were discarded: two crashed at startup with
  "Couldn't get swap chain texture" (the display had gone to sleep), and one was disturbed by it.
- Six clean runs followed with the display kept on: labels `opt1-minimap` (3) and
  `opt1-minimap-b` (3).

**Workload check.** Even with the fixed step, the runs do not all land on the same load:

| Run | Units / entities | State |
|---|---|---|
| `opt1-minimap` run 1 | 313 / 32.9k | the hero died 10 s into play, so only 3 s were measured; excluded from whole-run figures |
| `opt1-minimap` run 2 | 626 / 51.2k | high-gem |
| `opt1-minimap` run 3 | 342 / 34.8k | low-gem, like the baseline |
| `opt1-minimap-b` run 1 | 574 / 48.9k | high-gem |
| `opt1-minimap-b` run 2 | 331 / 32.7k | low-gem |
| `opt1-minimap-b` run 3 | 321 / 31.9k | low-gem (reached GameOver near the end of its window) |

The 3 baseline fixed-step runs were all low-gem (299–320 units). This is a methodology finding: a
fixed step reduces run-to-run drift but does not remove it. Comparisons are therefore made two
ways.

### A. Whole runs at the baseline's load (low-gem runs only)

| | Runs | Median frame | p95 | p99 | Main thread |
|---|---|---|---|---|---|
| Baseline | 3 | 13.77 (13.56–14.12) | 19.57 | 25.79 | 12.16 |
| Minimap 20 Hz | 3 | **11.96** (11.84–13.01) | **17.51** | **21.60** | **10.32** |
| Change | | **−1.81 ms (−13%)** | **−2.06 ms (−11%)** | **−4.19 ms (−16%)** | **−1.84 ms (−15%)** |

All times are in ms: the median of the three runs' per-run values, with the run range in brackets.

### B. Load-matched, all clean runs (`scripts/survivors-bench.sh bins …`)

Frames grouped by the entity count of the second they fall in:

| Entities | Set | Frames | Median | p95 | p99 | Main p50 |
|---|---|---|---|---|---|---|
| 30–35k (reference load) | baseline, fixed step | 24,225 | 13.55 | 18.49 | 22.18 | 11.72 |
| | minimap, first set | 5,599 | **11.86** | 17.34 | 24.98 | **10.16** |
| | minimap, second set | 17,170 | **11.50** | 15.90 | 20.30 | **9.90** |
| 35–40k | baseline, fixed step | 4,664 | 16.39 | 25.31 | 33.65 | 14.84 |
| | minimap, first set | 8,335 | **13.97** | 18.92 | 22.31 | **11.72** |
| | minimap, second set | 7,671 | **13.68** | 19.60 | 23.13 | **11.98** |
| 50–55k (high-gem) | baseline, real step† | 8,851 | 18.24 | 22.46 | 25.08 | 15.89 |
| | minimap, first set | 7,137 | **16.77** | 20.52 | 22.41 | **14.84** |
| | minimap, second set | 4,633 | **16.23** | 22.03 | 24.66 | **14.06** |

† No fixed-step baseline run reached the high-gem state. The real-step baseline is the nearest
like-for-like (same build settings, same load).

### Verdict

- **About −1.5 to −2.7 ms per frame at every load level measured**, about 8–17% at the median.
  The gain shows on the main thread, which is where the minimap runs.
- That is consistent with the trace's 2.8 ms (traced) for `compose`.
- p95 improves in every comparison. p99 improves in 4 of 5 load-matched rows and in the
  whole-run comparison; one row is mixed (24.98 vs 22.18 ms in one set at 30–35k).
- **Single long frames (not explained by this change):**
  - 202 ms in `opt1-minimap` run 3, and 381 ms in `opt1-minimap-b` run 1.
  - The fixed-step baseline had none over 100 ms, but the real-step baseline had 257 ms and
    268 ms frames.
  - The minimap now does *less* work per frame and never more than its old per-frame work. These
    look like the same intermittent stalls as in M2_PROFILE.md (cause unknown), but that is not
    proven. They are recorded, not dismissed.

**Status: kept.** A measurable improvement, visual-only, small and isolated.

## #2: cap on enemy damage numbers (tried, reverted)

**The change** (survivors side only; the engine's `combat_text` untouched):
- At most `MAX_DAMAGE_NUMBERS` = 64 enemy damage numbers on screen, counted over the numbers'
  1.5 s life on the game clock. Past that, plain hits went unshown. Crits, the hero's own numbers
  and heals always showed.
- `units.rs` (`NumberBudget`, `Fx::damage_number`), the two enemy-damage calls in
  `abilities.rs` `apply_hits`, and the resource in `mod.rs`. Two unit tests. Visual only.
- The trace had put combat text at 2.26 ms per frame (M2_PROFILE.md), and a late run spawns
  about 80 numbers a second, with about 145 alive at the median and up to about 385.

**How it was measured:** 3 runs, label `opt2-numbers`, same settings as #1 (2026-10-26). All three
ran to the time limit; no crash, no GameOver, no frame over 100 ms.

**Did the cap engage?** Yes. One extra diagnostic run (`fct-count-cap`, the engine's
`combat_text` debug log, the same instrument as the investigation; logging adds overhead, so its
frame times are not used):

| | Spawns per second (p50 / p90 / max) | Numbers alive (p50 / p90 / max) |
|---|---|---|
| Without the cap (`fct-count`) | 80 / 172 / 251 | 145 / 263 / 385 |
| With the cap (`fct-count-cap`) | 34 / 62 / 70 | 48 / 81 / 118 |

About two thirds fewer numbers on screen. The cap can be exceeded by crits, hero numbers and heals,
as designed.

**Workload check.** Average units and entities over each run's uncovered Playing frames:

| Run | Units / entities | State |
|---|---|---|
| `opt2-numbers` run 1 | 375 / 35.3k | between (its measured window started late, at 181 s real) |
| `opt2-numbers` run 2 | 522 / 45.2k | high-gem |
| `opt2-numbers` run 3 | 494 / 43.8k | high-gem |

None landed at the baseline's low-gem load, so the whole-run comparison has no matching runs and
the load-matched comparison is the one that counts.

### Load-matched against #1 (`scripts/survivors-bench.sh bins opt1-minimap opt1-minimap-b opt2-numbers`)

Times in ms. #1 is the build with only the minimap change; #2 adds the cap on top.

| Entities | Set | Frames | Median | p95 | p99 | Main p50 |
|---|---|---|---|---|---|---|
| 30–35k | #1, first set / second set | 5,599 / 17,170 | 11.86 / 11.50 | 17.34 / 15.90 | 24.98 / 20.30 | 10.16 / 9.90 |
| | #2 | 956 | 12.00 | 15.30 | 16.53 | 9.11 |
| 35–40k | #1 | 8,335 / 7,671 | 13.97 / 13.68 | 18.92 / 19.60 | 22.31 / 23.13 | 11.72 / 11.98 |
| | #2 | 4,744 | 13.90 | 17.07 | 17.98 | 9.90 |
| 40–45k | #1 | 1,111 / 698 | 14.72 / 15.41 | 18.80 / 22.12 | 20.70 / 25.58 | 12.24 / 12.50 |
| | #2 | 2,083 | 14.39 | 17.26 | 18.37 | 11.98 |
| 45–50k | #1 | 689 / 4,197 | 15.27 / 15.80 | 18.80 / 20.06 | 20.04 / 21.74 | 12.50 / 13.28 |
| | #2 | 3,491 | 16.69 | 20.33 | 22.22 | 13.80 |
| 50–55k | #1 | 7,137 / 4,633 | 16.77 / 16.23 | 20.52 / 22.03 | 22.41 / 24.66 | 14.84 / 14.06 |
| | #2 | 17,289 | 16.88 | 21.12 | 23.18 | 14.32 |

Per-run medians in the high-gem state: #2 runs 2 and 3, 15.49 and 16.23 ms; #1's high-gem runs,
16.16 and 15.90 ms.

### Verdict

- **No measurable improvement in the median frame at any load.** Against #1's two sets the
  differences run from −1.0 to +1.4 ms, both ways; #2 is slower in three of the five bins.
- The tail looked better at 30–45k (p99 about 2–8 ms lower), but those bins rest mostly on one
  #2 run (run 1) with few frames. At 45–55k, where #2 has most of its 23,000 frames, p95 and p99
  are the same as #1 or slightly worse. Not counted as a gain.
- **What this says about the profile:** cutting live numbers by two thirds did not move the
  frame. The 2.26 ms the trace showed is either mostly a fixed cost (per frame, not per number)
  or inflated by tracing itself; it is not proportional to the number count. That is a
  hypothesis, not measured.

**Status: reverted**, under the rule that a change which does not measurably help is undone.
Removing ~2/3 of the damage numbers is a visible change, and it bought nothing measurable. The
code is kept, not applied, in [patches/opt2-damage-number-cap.patch](patches/opt2-damage-number-cap.patch)
(`git apply` re-applies it) and its tests in
[patches/opt2-damage-number-cap.tests.rs](patches/opt2-damage-number-cap.tests.rs).

## #3: XP-gem visual weight (isolating experiment, not a fix)

**The question:** M2_PROFILE.md found that runs with many gems on the ground are 2–4 ms slower
per frame, but only as a correlation. Is the gem's *model* the cost?

**The experiment:** the same benchmark in two versions, differing only in whether gems have a
model:
- **A, as now** (`opt3-gems-full`): every gem is a full GameObject wisp (`BFD_WispSmall*`).
  The engine builds its rig, particle emitters and ribbons, and keeps updating them although
  `still_gems` freezes the animation.
- **B, no model** (`opt3-gems-none`, `opt3-gems-none-b`): `WOW_SURVIVORS_GEM_LOOK=none`.
  `spawn_gem` (`enemies.rs`) creates the gem as a bare entity (position, visibility, run
  cleanup) instead of through `units::spawn_object`. The value, the 350 cap, the magnet pickup,
  the RNG and the serials are unchanged; only the model is gone. **A measurement, never something
  to ship:** the player cannot see the gems.
- **Gem count per frame:** `auto.rs` now logs `gems` and `gem_bodies` in the per-frame CSV, and
  `BY=gems scripts/survivors-bench.sh bins …` groups frames by gem count. Entity bins would
  mislead here, since B has fewer entities by design.

**Gameplay check:** `gem_bodies` was 0 in every frame of version A. No wisp carries a collision
body, so removing the model cannot change movement or collisions.

**Runs** (2026-10-27, `FIXED_DT=16.667`, Mage `:late`, seed 1234; all 9 ran to the time limit,
no crash, no frame over 100 ms):

| Run | Gems (mean / max) | Units / entities |
|---|---|---|
| A run 1 | 32 / 117 | 225 / 26.2k (GameOver late in the window) |
| A run 2 | 304 / 352 | 550 / 47.0k |
| A run 3 | 89 / 161 | 345 / 34.5k |
| B run 1 | 34 / 73 | 263 / 29.2k |
| B run 2 | 60 / 133 | 270 / 29.3k |
| B run 3 | 32 / 69 | 262 / 29.2k |
| B-b run 1 | 256 / 352 | 276 / 30.4k |
| B-b run 2 | 45 / 86 | 271 / 30.1k |
| B-b run 3 | 303 / 353 | 273 / 30.4k |

The first 3 B runs never piled up gems (at most 133), so 3 more were run, as planned for thin
coverage. Two of them reached the cap. Note the entity column: without models, 300 gems add
almost nothing (30.4k vs 29.2k entities). With models, they add about 18,000 entities, about 65
per gem.

### Compared by gem count (`BY=gems … bins opt3-gems-full opt3-gems-none opt3-gems-none-b`)

Times in ms. B's two sets are pooled where both have frames, as "B / B-b".

| Gems | A frames | A median | A p95 | A p99 | A main | B frames | B median | B p95 | B p99 | B main |
|---|---|---|---|---|---|---|---|---|---|---|
| 0–50 | 5,503 | 11.99 | 17.85 | 21.49 | 9.64 | 23,451 / 5,897 | 12.26 / 11.88 | 18.80 / 17.33 | 23.36 / 19.63 | 10.68 / 9.90 |
| 50–100 | 4,911 | 12.32 | 19.26 | 29.90 | 10.42 | 11,879 / 6,442 | 12.76 / 13.61 | 19.08 / 19.17 | 23.73 / 23.30 | 10.94 / 11.72 |
| 100–150 | 6,573 | 14.26 | 19.56 | 21.95 | 11.98 | 205 / 3,089 | 11.54 / 10.62 | 15.33 / 14.77 | 16.04 / 17.60 | 9.11 / 8.85 |
| 150–300 | 601 | 13.95–14.70 | | | | – / 5,298 | 10.25–11.29 | | | |
| **300–350** | 4,851 | **16.30** | 20.24 | 22.41 | 13.54 | 12,211 (B-b) | **12.44** | 17.70 | 20.30 | 10.68 |
| **350–400** | 3,895 | **16.11** | 20.51 | 23.37 | 14.58 | 7,625 (B-b) | **13.45** | 19.34 | 22.38 | 12.24 |

(150–300: A has only 601 frames, so ranges of the bin medians are shown.)

Whole runs at matched gem load: A run 2 (304 gems mean) median 15.93 ms, main 12.65 ms; B-b run 3
(303 gems) median 12.13 ms, main 10.21 ms; B-b run 1 (256 gems) median 12.05 ms.

### Verdict

- **The gem models are the cost.** With models, frame time climbs from about 12 ms with few gems
  to about 16 ms at the 350 cap. Without them, it stays at 12–13.5 ms whatever the gem count.
- **At 300+ gems the models cost 2.7–3.9 ms per frame at the median** (main thread 2.3–2.9
  ms), and p95/p99 are 1–2.5 ms better without them. At 100–150 gems the gap is already about
  3 ms.
- **Below 100 gems** no gain shows: the medians differ by −0.1 to +1.3 ms, with B, if
  anything, slightly slower, which is within run-to-run noise.
- The B figures are the **ceiling** for any lighter gem look: a visible gem costs something, so
  a real fix saves less than this.

**Status:** experiment done. No fix applied. The `WOW_SURVIVORS_GEM_LOOK` switch is still in
`enemies.rs`, off by default, until the next step is decided: a lighter, still-WoW gem look, to be
measured against version A the same way. Changing `MAX_GEMS` or merging gems would change
pickup timing (gameplay), so neither is a candidate.

### #3b: crystal gem looks, first attempt (void: the crystals collide)

**Tried:** `WOW_SURVIVORS_GEM_LOOK=maraudon` (DiamondCrystal02 6415 / AmethystCrystal01 5011 /
RubyCrystal02 3691, scale 0.45) and `=ungoro` (UngoroCrystal_Blue01/Green01/Red01, 2971–2973,
scale 0.5). Both are far lighter than the wisp: 1–2 bones, 0–1 slow emitter, 2 batches, against
32 bones, 5 emitters and 17 batches. 3 runs each (`opt3-gems-maraudon`, `opt3-gems-ungoro`),
2026-10-27.

**Why the runs are void:** `gem_bodies` was about equal to `gems` in every crystal run. All six
crystal models carry a collision hull (`benilla-extract … m2coll`: 16 vertices / 28 triangles
for the Maraudon set, 96 / 120 for Un'Goro). The engine gives any GameObject with a hull a static
physics body (`entities/attach/mod.rs`), so the gems became solid. That is a gameplay change,
which this milestone excludes. The wisp and the turkey leg have no hull, which is why version A
measured 0. (The hulls were not checked before these runs; they should have been.)

**Also seen, not investigated:** Un'Goro runs 1 and 2 spent more frames on the level-up screen
than in play, with frames pinned near 16.7 ms. Their frame times are not used.

**Next:** make the crystals non-solid on the survivors side (remove the body as the model
attaches, as `still_gems` already does for the animation), then re-run both sets.

### #3c: crystal gem looks, non-solid (re-run)

**The fix:** `unblock_gems` (`enemies.rs`, registered next to `still_gems`) removes `RigidBody`
and `Collider` from a gem as soon as the engine adds them. Gems are now pickups that never block,
as the wisp always was. The wisp has no body to remove, so it is unaffected.

**Runs:** `opt3-gems-maraudon2` and `opt3-gems-ungoro2`, 3 each (2026-10-27, same settings).
All 6 ran to the time limit, with no crash and no frame over 100 ms. **`gem_bodies` was 0 in
every frame of every run.**

| Run | Gems (mean / max) | Units / entities | Median | p95 | p99 | Main |
|---|---|---|---|---|---|---|
| Maraudon run 1 | 47 / 99 | 235 / 24.5k | 12.56 | 18.71 | 21.68 | 10.68 |
| Maraudon run 2 | 319 / 353 | 585 / 30.7k | 11.20 | 16.88 | 20.04 | 9.48 |
| Maraudon run 3 | 306 / 353 | 562 / 31.3k | 11.17 | 15.79 | 19.31 | 9.35 |
| Un'Goro run 1 | 31 / 100 | 296 / 29.4k | 12.54 | 19.59 | 23.99 | 10.66 |
| Un'Goro run 2 | 49 / 146 | 320 / 29.4k | 12.28 | 18.07 | 20.95 | 10.14 |
| Un'Goro run 3 | 311 / 352 | 571 / 31.7k | 11.45 | 16.49 | 19.33 | 9.54 |

With 300+ gems, the crystals add about 1,000–2,000 entities, against about 18,000 for the wisps.

### Compared by gem count (`BY=gems … bins opt3-gems-full opt3-gems-none-b opt3-gems-maraudon2 opt3-gems-ungoro2`)

Median frame (main-thread p50 in brackets), ms:

| Gems | Wisp (A) | Maraudon | Un'Goro | No model (B-b) |
|---|---|---|---|---|
| 0–50 | 11.99 (9.64) | 11.55 (9.90) | 11.99 (10.16) | 11.88 (9.90) |
| 50–100 | 12.32 (10.42) | 13.92 (12.24) | 13.66 (11.46) | 13.61 (11.72) |
| 100–150 | 14.26 (11.98) | 10.71 (8.85) | 10.66 (8.07) | 10.62 (8.85) |
| **300–350** | **16.30** (13.54) | **11.35** (9.64) | **11.56** (9.90) | 12.44 (10.68) |
| **350–400** | **16.11** (14.58) | **11.20** (10.16) | **11.80** (10.42) | 13.45 (12.24) |

p95 at 300+ gems: wisp 20.24–20.51, Maraudon 16.17–16.41, Un'Goro 16.52–16.86. p99: wisp
22.41–23.37, Maraudon 19.52–19.59, Un'Goro 19.16–19.81.

**The wisp's high-gem figure rests on more than one run.** Version A has one high-gem run, but
the #1 runs had the same wisp gems, and their two high-gem runs measured 15.27–16.77 ms at
45–55k entities. Whole runs at 300+ gems: wisp 15.90–16.16 ms (3 runs); Maraudon 11.17–11.20;
Un'Goro 11.45.

### Verdict

- **At 300+ gems, both crystal looks are about 4.3–5.0 ms per frame faster than the wisp at the
  median** (−27 to −30%), with the main thread 3.6–4.4 ms lower, p95 about 3.7–4.3 ms lower and p99
  about 2.9–3.8 ms lower.
- **Below 100 gems: no measurable difference**, within run-to-run noise both ways.
- **The two crystal sets perform the same** within noise. They even measured slightly faster than
  the invisible gems (B-b). A crystal cannot cost less than nothing, so that ~1 ms shows the
  set-to-set noise: the crystals' own cost is too small to measure here.
- **The choice between them is visual:** Maraudon (no particles; white, purple, red) or Un'Goro
  (a faint glow; blue, green, red). Both are small in a busy fight (see the screenshots in
  `target/survivors-bench/shots-*`, which are local, not in git).

**Status:** measured, not adopted. Both looks are still behind `WOW_SURVIVORS_GEM_LOOK`, and the
wisp is still the default, until the look is chosen.

### #3: adopted (Un'Goro crystals)

- **XP gems are now Un'Goro crystals by default:** `UngoroCrystal_Blue01` (2971) for small
  gems, `_Green01` (2972) at 5+ XP, `_Red01` (2973) at 20+ XP, all at scale 0.5. This is the
  look benchmarked as `opt3-gems-ungoro2`. The healing turkey leg is unchanged.
- `unblock_gems` stays, so the crystals never block.
- **The experiment switch is removed** (`WOW_SURVIVORS_GEM_LOOK`, with its `none`, `maraudon`
  and `ungoro` values), along with the invisible-gem and Maraudon options. The runs labelled
  `opt3-gems-none*`, `opt3-gems-maraudon*` and `opt3-gems-ungoro*` were made with that switch and
  cannot be reproduced on the current code without re-adding it.
- **Kept for future measurements:** the `gems` and `gem_bodies` columns of the per-frame CSV
  (`auto.rs`, test driver) and `BY=gems` in `scripts/survivors-bench.sh`.
- **Not re-benchmarked after the cleanup.** The default build now spawns the same models, at the
  same scale, as the measured `ungoro` runs. One short seeded run checks that the crystals show
  and that `gem_bodies` stays at 0 (below).
- **Check run** (`default-crystals`, 2026-10-27; no gem settings, Mage `:late`, seed 1234, fixed
  step, 180 s): the Un'Goro crystals show (screenshots in `target/survivors-bench/shots-default`,
  local). The log has no "no usable model" line and no panic. `gem_bodies` was 0 in all 5,414
  play frames (up to 178 gems on the ground).
- **Checks:** survivors rustfmt clean, `scripts/survivors-lint.sh` clean, 38 survivors tests
  pass (the golden tables unchanged), and the `play` build succeeded.
