# Azeroth Bonk: roadmap

Turning survivors mode (`crates/benilla-app/src/survivors/`) into a deeper, Megabonk-style 3D
survival roguelite, while keeping the WoW engine, assets and visuals exactly as they are. Megabonk is
a reference for mechanics and pacing only: no code, assets or exact content come from it.

Status key: **Done** = acceptance criteria tested (automated and manual results recorded separately).
**In progress**, **Blocked**, **Planned**. Nothing is marked done until it has been tested.

The testing checklist every milestone runs is [TESTING.md](TESTING.md).

---

## Status

### Done
- **M1, safety net** (b60f004, plus the golden fix a4c4ecf). Done 2026-10-25. Details in
  [TESTING.md § M1 record](TESTING.md#m1-record) and § First CI run.
  - **What it adds:**
    - an explicit run seed (`Run.seed`, `WOW_SURVIVORS_SEED`) and a shared seeded RNG;
    - survivors unit tests;
    - the 2 survivors lints fixed, and scoped strict clippy (`scripts/survivors-lint.sh`);
    - a `survivors` job in `check.yml`.
  - **Acceptance:**
    - local tests, lint and native checks pass;
    - the `survivors` CI job is **green on GitHub** (fork PR #1, a4c4ecf);
    - a seeded auto run with WoW data plays and logs its seed.
  - **Not verified:** a frame-exact replay of the same seed (see § Seeded runs for why).
- **M3, ability data model** (30e0c3b, plus a4c4ecf). Done 2026-10-25. Details in
  [TESTING.md § M3 record](TESTING.md#m3-record).
  - **What it adds:**
    - every ability-name check is replaced by a definition field;
    - level tables, tags, pierce and an evolution slot exist, all still at their defaults;
    - `Owned::numbers()` is the one composition the cast and the tooltips share.
  - **Acceptance:**
    - the golden tables recorded before the refactor match; the cooldowns match within a 1e-6
      tolerance across platforms, because `powi` rounds differently on each;
    - 37 survivors tests pass locally, and the `survivors` CI job is green on GitHub;
    - a seeded auto run of each of the 9 classes plays with no crash.
  - **Not seen in play:** `pyroblast`, `exorcism` and `starfire`. Their numbers and cards are
    pinned by the golden tables.

### Known CI failure (not ours)
- `check.yml`'s `host-and-ui` job fails at "browser startup and journal regressions"
  (`node --test web/tests/*.test.mjs`). Upstream's own run on `main` at dd5e330 fails the same
  way, and M1/M3 never touch `web/`. Not investigated.

### In progress
- **Milestone 0, audit and plan.** The audit is finished, and the automated baseline is recorded
  in [TESTING.md](TESTING.md#baseline-record).
- **M2, benchmark and performance: reviewed, committed (cf7e8a6), awaiting CI.** Not pushed
  yet; the `wasm` and `survivors` CI jobs have not run on it.
  - **Done:**
    - the repeatable benchmark (`scripts/survivors-bench.sh`, plus the env-gated per-frame logger
      in `auto.rs`);
    - the reference baseline, in [performance/M2_BASELINE.md](performance/M2_BASELINE.md). Mage
      `:late`, fixed step, 3 runs: median 13.77 ms, p95 19.57 ms, p99 25.79 ms, main thread
      12.2 ms, GPU 2.1 ms, 2–4% spread between runs.
  - **Findings so far:**
    - frame time is CPU-bound on the main thread;
    - real-step runs vary with how many XP gems pile up (about 18,000 extra entities, +2–4 ms);
    - normal mode shows unexplained 300–800 ms hitches during play.
  - **Phase 4 (profiling) done:** [performance/M2_PROFILE.md](performance/M2_PROFILE.md).
    Ranked:
    1. the minimap recomposite every frame (2.8 ms traced);
    2. combat-text load (2.3 ms traced);
    3. XP-gem visual weight (+2–4 ms in the high-gem state, correlation only).

    Survivors gameplay systems (separation, targeting, splash) are under 0.1 ms each, so they
    are not pursued. Normal-mode hitches were not reproducible, so they are not ranked.
  - **Phase 5, #1 done:** the minimap redraws at 20 Hz instead of every frame (visual only).
    Measured ([performance/M2_RESULTS.md](performance/M2_RESULTS.md)): median frame −13%, p95
    −11%, p99 −16%, main thread −15% at the baseline's load; −1.5 to −2.7 ms at every load
    level. 38 survivors tests pass.
  - **Method finding:** even with a fixed step, runs can drift into a high-gem state or end
    early, so results are compared both per run (matching loads only) and per entity-load bin
    (`scripts/survivors-bench.sh bins`).
  - **Phase 5, #2 tried and reverted:** a cap of 64 enemy damage numbers on screen. It engaged
    (live numbers −2/3) but the median frame did not improve at any load
    ([performance/M2_RESULTS.md](performance/M2_RESULTS.md)). The code is kept as a patch in
    `docs/performance/patches/`, not applied.
  - **Phase 5, #3 experiment done:** the same runs with and without the gem wisp model
    (a temporary switch, since removed), compared by gem count. The models are the
    cost: at 300+ gems they add 2.7–3.9 ms per frame at the median; below 100 gems, nothing
    measurable ([performance/M2_RESULTS.md](performance/M2_RESULTS.md)). No fix is applied yet.
  - **Phase 5, #3 crystal looks measured:** two sets of WoW crystal models (Maraudon,
    Un'Goro), made non-solid by `unblock_gems`. At 300+ gems they are 4.3–5.0 ms per frame faster
    than the wisp at the median (−27 to −30%); below 100 gems, no difference. The first attempt
    was void because the crystals collided (see M2_RESULTS.md #3b).
  - **#3 adopted:** XP gems are now Un'Goro crystals (blue, green, red by tier, scale 0.5),
    non-solid via `unblock_gems`; the experiment switch is removed.
  - **Phase 7 (verification) done locally** ([TESTING.md](TESTING.md#m2-record-phase-7-verification)):
    rustfmt, lint, dev and player checks, 38 survivors tests, 33 CI-filter tests, the `play`
    build, and seeded smoke runs of all 9 classes pass. The wasm check is still blocked locally
    and not yet run in CI.
  - **Reviewed** 2026-10-27 and committed as cf7e8a6.
  - **Next:** push and let CI run (`wasm` is the one check not run locally). M2 moves to Done
    once CI is green.

### Blocked
- **Local wasm check:** needs wasi-sdk 27, which `scripts/web-setup.sh` installs on Linux/macOS
  only. Run it in CI's `wasm` job or on Linux/macOS/WSL2 (see TESTING.md).
- **Manual playtest:** the WoW data is in `wow-data/Data` (fetched 2026-10-25, SHA-1 verified),
  and the native game **runs**: one seeded Mage auto run in Elwynn, 5 min, no crash (TESTING.md §
  M3 record). No human playtest yet. M2 measurements can now start whenever M2 is approved.

### Planned
Milestones 2 and 4 to 10 below, in order (M1 and M3 are done).

---

## What the audit found

### Architecture in one paragraph
`warcraft-survivors` (native) and `wenilla` (wasm) both call `benilla_app::run_survivors`
(`lib.rs:230`). That sets `survivors::ACTIVE` and boots the full benilla client straight into
`InWorld`, with networking off (`connect: false`). It also inserts `CaptureMode`, which turns off the
upstream player controller, camera view and FrameXML/Lua UI. Terrain and WMO streaming, the loading
screen, model attach, creature animation, spell visuals, combat text and sound all stay on.
Survivors spawns **local units that impersonate server-streamed ones** (`units.rs`): a fake `Guid`,
`NetEntity` and `ObjectStore`. It drives visuals by writing the same messages the network layer
would (`Fx`: `CastEvent`, `SpellGoTargets`, `SwingMessage`, `CombatTextSpawn`; `Marks`: aura fields).
That is why every WoW model, animation, missile, impact and aura visual works without new rendering
code. **This seam is the most valuable thing in the repo, and every new feature should go through
it.**

### System map

| Area | Where | State |
|---|---|---|
| State machine | `mod.rs` `Phase` {Menu, Playing, LevelUp, Paused, GameOver} | works; pause = `Time<Virtual>` |
| Run state | `mod.rs` `Run` (one large resource) | works; will need splitting as features grow |
| Hero movement and jump | `hero.rs` `drive_hero` | works; heightfield only, **no WMO/doodad collision**; circular leash |
| Camera | `hero.rs` `place_camera`; C toggles locked (61°) / orbit, wheel 1.5–70 yd | works; keep |
| Movement spell (F) | `mobility.rs`, one per class from level 5 | works; template for active abilities |
| Enemies | `enemies.rs`: ring spawns, seek and separation (3 yd hash grid), contact melee | works; no ranged, no telegraphs, no elites |
| Rosters | `data.rs` static tables (Barrens: 30 hand-tuned tiers; other zones interpolated by `ladder()`), 6 bosses per zone | works |
| Abilities | `data.rs` `AbilityDef` (73 entries) + `abilities.rs` one `match Kind` (16 kinds) | works; close to a weapon schema |
| Projectiles | none: a `Hit` is delayed by distance ÷ missile speed and cannot miss | **replace** for dodge, pierce and enemy projectiles |
| Damage | `abilities.rs` `apply_hits`: crit, DoT, CC, execute, drain, splash | works |
| Progression | XP gems → `xp_to_next` → 3 weighted cards (`hud.rs choices_for`) | works; rarity is a label only |
| Passives | 10 one-stat passives (`data.rs`) | works; additive only |
| Win/lose/results | survive `VICTORY_SECS = 900`; results screen; Enter → menu | works |
| Persistence | `survivors-pick.txt` via `local_state` (wasm-safe) | works; **the only save** |
| Test harness | `auto.rs` `WOW_SURVIVORS_AUTO=<class>[:idle|:all|:late]` | works; clock-seeded, so not reproducible |
| Tests | **0** in `survivors/` | gap |

### Preserve, extend, replace

- **Keep unchanged:** the rendering, M2/WMO/terrain, rig animation, spell visuals, particles,
  combat-text rendering, sound, the `units.rs`/`Fx`/`Marks` seam, the camera, the menu/pick screen
  and its saved pick, the 16 zones, the 9 classes, the loading screen and the color grade.
- **Extend:** `AbilityDef` (becomes a weapon definition), `Stats`/`Stat`, `choices_for`/cards
  (real rarity, evolutions, chest offers), `Enemy` (elite tier and affixes), `GemKind`/`Loot` (gold
  and chests), the mobility system (generalized into active-ability slots), results, `auto.rs`
  (seeded stress mode), and `local_state` persistence (meta unlocks).
- **Replace, with evidence:** delayed-`Hit` projectiles become real projectile entities, needed for
  pierce, dodge and enemy projectiles. Hardcoded string checks (`"pyroblast" | …`, `"magma_totem"`,
  `"renew"`) become definition fields. The per-frame `HashMap` grid and repeated full-enemy scans
  become one shared spatial grid.

### Main technical risks
1. **Combat text could be the first thing to break the frame budget.** In `combat_text/mod.rs`,
   `free_slot` scans every live text, and the overlap solver in `smart_rect.rs` cost grows
   quadratically. Splash multiplies hits. *(Static analysis, not profiled.)*
2. **The skinned-rig pool is a hard horde ceiling.** `MAX_RIG_SLOTS = 2048`
   (`benilla-world/src/mesh_tag.rs:81`) is shared by enemies, gems (each wisp is a rigged M2),
   totems, the hero and world doodads. Past it, units render in bind pose (`RigStarved`).
   Raising it changes the mesh-tag layout, which is an upstream file.
3. **CPU cost per enemy:** pose composition, blob-shadow re-projection while moving, and one
   aura state kit per debuffed enemy. Top-down framing defeats the off-screen animation LOD.
4. **Upstream carry rule (AGENTS.md).** Edits to upstream files conflict at every merge. Gameplay
   must stay inside `survivors/` or new files. `shaders.rs` and `glue/backdrop.rs` already carry
   ungated survivors edits that are not listed in `docs/UPSTREAM.md`.
5. **wasm-only breakage.** `std::time` and `env::vars_os` panic in the browser, and native
   `cargo check` won't catch it. The browser build is single-threaded and has no dev instruments
   beyond the FPS journal. `scripts/web-setup.sh` does not support Windows/Git Bash (its `uname`
   case is Linux/Darwin only), so wasm checks run in CI or need wasi-sdk installed by hand.
6. **No safety net.** There are no survivors tests. The `Rng` is seeded from the clock. The
   survivors schedule is outside the headless schedule census. `ci.yml`'s clippy and tests skip
   same-repo PRs.
7. **Saved-pick compatibility.** `survivors-pick.txt` stores indices into `data::CLASSES` and
   `MAPS`. Reordering them silently changes old saves. Only append.
8. **Collision.** There is none against buildings or doodads, so arenas depend on open ground.
   Adding obstacles is real work (avian is a dependency but unused here).
9. **Stale docs.** AGENTS.md describes `crates/wenilla-realm`, `bump-realm-pin.yml` and
   `Arnesen/wenilla` PRs. None of these exist in this fork.

---

## Milestones

Each milestone is a small, reversible PR (or a short PR series) on its own branch. "Rollback" is
always "revert the PR" at minimum. Notes say when something extra is needed.

### M1: Toolchain, baseline and a safety net
- **Player-facing:** none. This milestone makes every later one safe.
- **Reuse:** `auto.rs`, the `MinimalPlugins` test pattern (for example `combat_text/mod.rs:467`),
  `wow_data_or_skip!`.
- **Changes:** `survivors/mod.rs` (seedable `Rng`: `WOW_SURVIVORS_SEED`, read via `webenv::var`);
  new `survivors/tests.rs` (or `#[cfg(test)]` modules); `.github/workflows/` (same-repo job:
  clippy + `cargo test -p benilla-app --lib survivors`); AGENTS.md stale-section note (only if
  approved).
- **Depends on:** Rust 1.98.1 + MSVC Build Tools installed.
- **Strategy:** the baseline is recorded (TESTING.md). `clippy -D warnings` stops on an upstream
  `needless_borrow` in `benilla-world`. **Decided:** no upstream edit. `scripts/survivors-lint.sh`
  lints with `--no-deps` and fails only on findings in survivors paths. The 2 survivors lints are
  fixed.
- **As built:**
  - `Rng::seeded` (a splitmix64-scrambled seed into xorshift64*);
  - `run_seed()` (env/query, else clock);
  - `start_run` takes the seed and resets the shared `Rng`;
  - the menu's Randomize gets its own `Local<Rng>`;
  - tests live in `survivors/tests.rs`.
- **Deterministic-replay limits:** frame `dt`, input timing, loading time, query order and
  floating point (TESTING.md § Seeded runs).
  Add unit tests for the pure functions: `progress`, `wave_pool`, `target_alive`, `hp_scale`,
  `damage_scale`, `xp_to_next`, `Owned` scaling, `Run::stats`, `choices_for` (no duplicates, no
  maxed upgrades, Heal fallback), `pick`, `rarity`, roster/ability lookups for every class and
  map, and a saved-pick round-trip.
- **Tests:** these tests themselves, plus TESTING.md §A–B. Manual: one auto run to confirm
  nothing changed.
- **Performance:** none.
- **wasm risk:** the seed env var must use `webenv::var`, not `std::env`.
- **Acceptance:**
  - baseline recorded — met;
  - at least 20 survivors tests pass — met (26);
  - the same seed and the same picks deal the same offers — met in unit tests
    (`the_same_seed_and_picks_deal_the_same_cards`). In a live run this holds only as far as the
    limits above allow;
  - the new CI job is green on GitHub — **not yet verified**.

### M2: Stress harness and cheap performance fixes
- **Player-facing:** smoother late runs; damage numbers readable in crowds.
- **Reuse:** the FPS journal, `WOW_FRAME_PHASES`, `WOW_GPU_MS`, `trace_chrome`, the `live_fps`
  percentile code, `auto.rs`.
- **Changes:** `survivors/auto.rs` (`WOW_SURVIVORS_STRESS=<n>,<secs>,<seed>`: idle hero, fixed
  map, `:late`-style build, steps 100/250/500/1000, logs p50/p95/p99, rigs, `RigStarved`, texts);
  new `survivors/grid.rs` (one reused flat spatial grid, built once per frame, used by separation,
  `around`, `densest`, chain, splash and totems); `survivors/units.rs` `Fx::number` (merge damage
  per enemy per frame; survivors-side cap on numbers spawned per frame); an explicit enemy cap
  that leaves rig headroom; visual caps on melee/orbit impacts and debuff marks.
- **Depends on:** M1.
- **Strategy:** measure first, then fix one item at a time, re-measuring after each. Do not touch
  `combat_text/` or engine files unless the stress test proves survivors-side caps are not enough.
- **Tests:** unit tests for the grid queries (same results as the brute-force versions on random
  bodies) and for number merging. Stress-test before/after table recorded in TESTING.md.
- **Performance:** the target is native p95 ≤ 16.7 ms at the run's peak horde (≈300 with rings)
  with zero starved rigs. Record the headroom at 500 and 1000.
- **wasm risk:** low; pure logic. Record one browser journal at peak if a wasm build is possible.
- **Acceptance:** the stress mode is reproducible (same seed gives the same spawn count curve);
  before/after numbers are recorded; gameplay is unchanged in a seeded auto run (same kills ±5%).

### M3: Weapon data model (no behavior change)
- **Player-facing:** none intended. This is a refactor for M4 and later.
- **Reuse:** `AbilityDef`, the `ability!` macro, the `Kind` dispatch, `Params`.
- **Changes:** `survivors/data.rs`: add `targeting: Targeting {Nearest, Toughest, Densest, Random}`,
  `tags: &[Tag]`, `pierce`, a per-definition `levels: &[LevelBonus]` (default = today's formula),
  `evolves: Option<Evolution>`, and flags replacing the `"magma_totem"` and `"renew"` string checks.
  `abilities.rs` and `hud.rs:1761` read these fields instead of the string matches. `mod.rs`
  `Owned` reads `levels`.
- **Depends on:** M1 (tests pin the current numbers).
- **Strategy:** a pure refactor. Tests capture `Owned` damage, cooldown, count, radius and duration
  for every ability at levels 1 to 8 **before** the change, and must match exactly after.
- **Tests:** a golden-number test over all 73 abilities × 8 levels. Manual: one seeded auto run
  per class shows the same build log.
- **Performance / wasm:** neutral.
- **Acceptance:** golden test identical; no string-keyed behavior left in `abilities.rs`.
- **Rollback:** revert. No save-format change.
- **As built (2026-10-25, uncommitted):**
  - **New `AbilityDef` fields**, each defaulted in `ab()`:
    - `target: Target {Nearest, Toughest}`;
    - `pulse`, `state_visual`, `impact`;
    - `tags: &[Tag]`, `pierce`, `levels: &[LevelBonus]`, `evolves: Option<Evolution>`.

    The plan's `Densest`/`Random` targets were not added: no Bolt, Strike or Melee uses them, and
    the area kinds already pick their own centre.
  - **The key checks they replace:**
    - the toughest set (pyroblast, aimed_shot, exorcism, starfire) in `abilities.rs` and `hud.rs`;
    - the `magma_totem` pulse in `abilities.rs` and `hud.rs`;
    - the `lightning_shield` hero visual in `hero.rs`;
    - the Orbit's hardcoded impact 403 (now `impact_of`).

    `"renew"` (`hero.rs`) is a *passive*, so it is out of M3's scope and stays.
  - **`Owned`** reads an ability's own `levels` table when it has one (it must cover every rank;
    a test enforces this), else the old formulas verbatim. A new `Owned::numbers()` is the single
    composition the cast (`abilities.rs` `Params`) and the tooltips (`hud.rs` `cast_at`) share.
  - **`cards.rs` rarity:** "this rank adds a target" now asks `count(next) > count(cur)` instead
    of hardcoding ranks 3/5/7, so it follows any future level table.
  - **New fields with nothing to read them yet:** `tags`, `pierce` and `evolves`, plus the `Tag`
    and `Evolution` types. They carry narrow `#[allow(dead_code)]` attributes until M4/M5 read
    them. No ability sets them, which a test enforces.
  - **Golden tables, recorded from b60f004:**
    - `testdata/abilities.golden`: every definition, plus damage, dot (at might 1 and 1.3), count,
      duration, cooldown (haste 0 / 0.4 / 0.8) and radius (area 1 / 1.5 / 2.25) at ranks 1–8,
      through `numbers()`;
    - `testdata/cards.golden`: every new-spell and upgrade card's text and rarity.

    Both were regenerated on a clean checkout of b60f004, and the ability table came out
    byte-identical to the one recorded earlier. The refactored code matches both bit for bit.
- **Not changed:** no new weapon, evolution, balance or visual change. The remaining hardcoded
  buff visuals (Shield 17, Immune 642, Heal 774 in `hero.rs`) are spell ids, not key checks, and
  stay. The `Kind::Aura` doc claims a hero visual that only the Orbit gets; this predates M3 and
  is noted, not changed.

### M4: First playable "Bonk" slice (detailed below)
Elites, gold, chests, real rarity, two new stats, one evolution per class (starting with Mage), a
10-minute run with a final boss, and expanded results.

### M5: Real projectiles and dodgeable enemy attacks
- **Player-facing:** bolts fly and can pierce. Some enemies shoot, and you can step out of a shot.
  Ground telegraphs warn before area attacks.
- **Reuse:** `Fx::cast` for missile visuals (the spell's own missile model plays on a target
  entity); `spawn_area_object` for ground telegraph visuals (the spell's own area kit); the M2 grid
  for hit tests.
- **Changes:** new `survivors/projectile.rs` (a `Projectile` component: position, velocity, pierce,
  hit set, lifetime; swept-sphere vs grid); `abilities.rs` Bolt uses it when `pierce > 0` or the
  definition says so; new `survivors/enemy_attacks.rs` (enemy `Attack` definitions: windup, telegraph
  radius/shape, damage); `data.rs` (ranged and caster foes per zone).
- **Depends on:** M2 (grid), M3 (definition fields).
- **Strategy:** keep delayed-`Hit` as the default for spells that should never miss. Use real
  projectiles only where they add gameplay. Check whether an invisible "dummy target" unit can carry
  the WoW missile visual along a straight line. If it can't, travel visuals fall back to impact-only
  and we need an engine decision (flag it before changing upstream code).
- **Tests:** projectile hit and pierce unit tests on synthetic bodies; telegraph timing test.
  Manual: dodge a telegraphed attack in 3 zones.
- **Performance:** add 500 live projectiles to the stress mode; enforce a cap.
- **wasm risk:** low.
- **Acceptance:** a telegraphed attack can always be dodged at base move speed; pierce works;
  stress p95 stays within the M2 budget.

### M6: Bosses with mechanics and minibosses
- **Player-facing:** minibosses at fixed times; the final boss has 2 phases and 2 to 3 telegraphed
  attacks (charge, ground AoE, add summon), using WoW spell visuals.
- **Reuse:** M5 attacks, `Marks` for boss aura visuals, banners, the boss roster.
- **Changes:** `data.rs` (`BossDef` attack lists), `enemies.rs` (phase state), `hud.rs` (boss bar).
- **Depends on:** M5.
- **Acceptance:** each zone's final boss can be beaten with a mid build; its attacks have
  telegraphs; manual playtest in at least 4 zones.

### M7: World incentives: shrines, chests on the map, risk vs reward
- **Player-facing:** chests and shrines scattered inside the arena (charge shrine = stand inside it
  for a buff; cursed shrine = harder enemies for better loot), shown on the minimap.
- **Reuse:** `spawn_object` (GameObject displays), `minimap.rs` blips, `MapDef.center`/`leash`,
  `arena_scout` for open-ground placement.
- **Changes:** new `survivors/world_objects.rs`; `data.rs` per-map object anchors; `minimap.rs`.
- **Depends on:** M4 (gold and chests).
- **Risk:** no building/doodad collision, so objects must be placed on verified open ground.
- **Acceptance:** objects never spawn inside geometry in the 16 zones (manual sweep with screenshots).

### M8: Active abilities and synergies
- **Player-facing:** a second active slot (Q, a class "big" spell such as Evocation, Recklessness or
  Tranquility); tag synergies (for example 3 Frost weapons → Shatter crit bonus); remaining classes
  get evolutions.
- **Reuse:** `mobility.rs` cooldown, HUD sweep and input pattern; M3 tags.
- **Depends on:** M3, M4.
- **Acceptance:** each of the 9 classes has at least 1 evolution and 1 synergy; unit tests for
  synergy activation.

### M9: Meta progression
- **Player-facing:** gold banked after a run unlocks permanent small bonuses and extra card slots or
  rerolls; zones and classes can be gated if wanted (a design decision for later).
- **Reuse:** the `local_state` pattern from `menu.rs:61-114` (wasm-safe, localStorage on the web).
- **Changes:** new `survivors/meta.rs`, a new save file (`survivors-meta.txt`, versioned).
- **Risk:** a save-format change. Version the file and tolerate an unknown or missing file.
- **Acceptance:** round-trip test; an old or missing save loads defaults; works in the browser.

### M10: Horde scale, only if profiling demands it
Pose sharing per (display, sequence, phase bucket), verifying or forcing GPU instancing of identical
creature parts, LOD/impostors, a global particle budget, enemy entity pooling, and a larger rig pool.
Most of this touches upstream engine files, so each item needs stress-test evidence and an explicit
decision about upstream conflicts first.

---

## First playable milestone (M4), in detail

**Goal:** a complete 10-minute run that already feels like the target. Real WoW heroes, zones and
creatures; current movement and camera; a crowd to fight; upgrade choices that matter; gold,
elites, chests and an evolution; a final boss; results.

**Scope**
1. **Pacing** (`data.rs`): `VICTORY_SECS` 900 → 600 and `BOSS_EVERY_SECS` → 180 for this mode.
   That gives minibosses at 3:00 and 6:00 and the final boss at 9:00. Killing the final boss wins
   the run; surviving to 10:00 also wins. `target_alive` reaches its cap by about 8:00. Put these
   behind a `RunRules` struct so the 15-minute mode can come back as a choice.
2. **Elites** (`enemies.rs`, `Enemy`): a small elite chance on spawn (tuned, starting near 1/150),
   plus a guaranteed elite every 60 s. Elites get ×4 HP, ×1.5 damage and ×1.4 scale, wear an aura
   visual through `Marks` (a real WoW buff spell), and always drop a chest.
3. **Gold** (`GemKind::Gold`, `Run.gold`): dropped by kills at a low rate and by elites and bosses at
   a high rate. Shown on the HUD and the results screen. Spending it comes in M7 and M9; in M4,
   gold pays for a reroll on the card screen.
4. **Chests** (`GemKind::Chest`, a WoW chest GameObject display id, still to be found and checked):
   opening one enters `Phase::LevelUp` with a chest offer: upgrades of owned items only, minimum
   Rare, or an evolution if one is ready.
5. **Real rarity** (`cards.rs`, `hud.rs`): roll the rarity first (Luck-weighted odds), then let it
   scale the upgrade (Common ×1, Uncommon ×1.25, Rare ×1.5, Epic ×2, Legendary ×2.5 of the level
   bonus). The existing colors and the `Rarity` enum stay.
6. **New stats:** `Projectiles` (+count) and `Luck` (rarity odds, chest quality), added as passives
   with WoW buff names and icons.
7. **One evolution per class, starting with Mage.** Example: Frostbolt at max level plus the
   Cooldown passive, then a chest, gives an evolved Frostbolt (more bolts, pierce through M3's
   field, stronger slow). Evolutions use real 1.12 spell visuals only. Each spell id is checked
   against the client's Spell.dbc before use.
8. **Results:** add gold, elites killed, evolutions and the top damage source.

**Not in M4:** real projectiles, telegraphs, shrines, meta unlocks, new zones or new movement.
The pick screen and its saved pick stay untouched.

**Files likely to change:** `survivors/data.rs`, `mod.rs`, `enemies.rs`, `abilities.rs`,
`cards.rs`, `hud.rs`. No engine files and no new assets.

**Depends on:** M1 (tests and seed), M3 (definition fields for pierce and evolution). M2 is
recommended first because elites, chests and evolutions all add hits, numbers and visuals.

**Automated tests:** elite roll rate under a fixed seed; rarity odds shift with Luck; the chest offer
only contains owned upgrades or a ready evolution; the evolution recipe triggers exactly at max level
plus the passive; gold accounting; the run ends on a final-boss kill and at 600 s;
`choices_for`/`pick` invariants still hold.

**Manual playtest:** Mage in Elwynn Forest and in The Barrens, plus one melee class (Warrior). Each
should show: an elite appears and drops a chest; the chest offer looks right; one evolution is
reached in a normal run; the final boss shows at 9:00; the results show the new fields; Enter
returns to the menu cleanly and a second run works; Esc pauses during a chest offer.

**Performance:** run the M2 stress mode before and after. Elite auras and chest models count against
the rig pool, so keep the number of live chests capped.

**wasm risk:** low; pure gameplay logic. New env vars go through `webenv::var`.

**Acceptance:** all automated tests pass; the manual checklist passes for the 3 runs above; stress
p95 is no worse than M2's baseline by more than 10%.

**Rollback:** revert the PR. There is no save-format change (gold is per run until M9).

---

## Commands
See [TESTING.md](TESTING.md) §Commands for the exact build, run and test commands.
