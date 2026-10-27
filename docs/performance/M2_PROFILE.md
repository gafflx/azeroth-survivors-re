# M2 profile: where the frame time goes

Phase 4 of M2, 2026-10-25. Read [M2_BASELINE.md](M2_BASELINE.md) first. **No gameplay or engine
code changed for this.** It used a separate `trace_chrome` build (a feature flag only, built into
`target/trace`), plus the existing engine instruments.

## How it was measured

1. **Per-system timing.** A `trace_chrome` build ran the reference workload (Mage `:late`,
   Elwynn, seed 1234, fixed step):
   `scripts/survivors-bench.sh trace <label> late <secs>` with `FIXED_DT=16.667`.
   - The scheduler's bookkeeping spans were filtered out with `RUST_LOG`; the scheduler and query
     spans otherwise flood the trace.
   - The trace (122 GB) covered loading plus a whole `:late` run to victory. **830 s of gameplay**
     were analysed: 34,466 frames, 155–215 enemies alive.
   - It was summed per system by a small throwaway analyzer (self time, total time, worst call).
   - The trace itself was deleted afterwards. Its summary is kept in
     `target/survivors-bench/trace-late/run-1/trace-late-summary.txt` (git-ignored).
2. **Load vs frame time.** All 10 journal-equipped `:late` runs (5 real-step baseline, 3
   fixed-step, 2 census) were compared on frame time against network-style unit and entity
   counts, averaged over each run's measured window.
3. **Entity census** (`WOW_ENTITY_CENSUS=30`), 2 real-step `:late` runs.
4. **Hitch hunt** (`WOW_FRAME_PHASES=150`), 2 normal-mode runs.

**Caveat on trace numbers.** Tracing adds about 8 ms per frame (22.5 ms mean traced vs 14.4 ms
plain), mostly as a fixed cost per span. So read the trace as a **ranking**. One-call-per-frame
systems doing plain CPU work (the minimap, combat-text layout) keep roughly their real self time.
A system whose work grows with tracing does not: the FPS journal showed 2.5 ms per frame in the
trace, but turning it off in the plain build made no measurable difference (14.24/14.35 ms vs
13.56–14.12 ms median). Every candidate below is confirmed or refuted by the plain benchmark
before and after a change.

## Main-thread time, top systems (traced, ms per frame)

The per-frame figures are each system's total self time over the window divided by its 34,466
frames (41.5 traced frames per second).

| System | Self ms/frame | Worst call | Whose |
|---|---|---|---|
| `survivors::minimap::compose` | **2.78** | 5.1 ms | survivors |
| `perf::journal::journal_fps` | 2.54 | 11.6 s (once) | the measurement tool; inflated by tracing (see caveat) |
| `combat_text::float_combat_text` | **2.26** | 90.6 ms | engine module, fed by survivors' hit numbers |
| `particles::sim::simulate_particles` | 1.29 | 7.1 ms | engine |
| `rig_anim::compose` finalize + compose | 1.29 | 2.6 ms | engine (skinned animation) |
| `bevy_transform` mark_dirty + propagate | 0.71 | 1.5 ms | Bevy |
| `rig_anim::global_seq::apply_global_sequences` | 0.42 | 2.0 ms | engine |
| `bevy_ui::layout::ui_layout_system` | 0.40 | 1.6 ms | Bevy UI |
| `billboard::face_billboards` + `ribbons::simulate_ribbons` | 0.64 | 1.3 ms | engine (effects) |

On the render thread, `render_system` and the `Render` schedule add about 6.6 ms traced, in
parallel with the main thread. The GPU itself needs about 2 ms (journal). Rendering is not the
limit.

**Survivors gameplay systems are cheap.** Only the minimap made the top 45. Everything else is
below the 45th entry, about 0.09 ms per frame each: enemy movement and separation
(`move_enemies`), ability casting and targeting (`cast_abilities`), area ticks, hit and splash
handling (`apply_hits`), loot and gem pickup. **The static audit's early suspects (separation
grid, target sorting, splash scans) are not bottlenecks at this load.**

## Load vs frame time (10 runs)

| Units* | Entities | Runs | Median frame | Main thread |
|---|---|---|---|---|
| 271–316 | 30.3–33.4k | 7 | 13.55–14.12 ms | 11.8–12.9 ms |
| 400 | 37.3k | 1 | 13.82 ms | 11.5 ms |
| 458–586 | 41.7–48.0k | 5 | 16.11–17.47 ms | 13.4–14.3 ms |

\* Network-style units: enemies plus XP gems, ground areas and totems. Enemies averaged 163–175
in every run, so the extra 150–270 units are mostly XP gems.

More gems, more entities, slower frames: about 60–80 ECS entities per extra unit and **+2–4 ms per
frame**. The correlation is strong but not perfect (the 400-unit run is fast). A snapshot census
at one moment misleads (gems are collected and dropped continuously), so only window averages
are compared.

**Likely mechanism (not yet isolated):** each gem is a full GameObject M2 wisp (`enemies.rs`
`spawn_gem` → `units::spawn_object`). It has a rig, animation players, particle emitters and
ribbons. `still_gems` freezes its animation clips and global sequences, but the entities stay, so
they still go through transform propagation, visibility, particle and rig systems each frame.
Fixed-step runs stay in the low-gem state, which is why the trace (one fixed-step run)
under-represents gem cost.

## Normal-mode hitches

- **Earlier runs:** 300–824 ms frames *during play* in 2 of 3 baseline normal runs, and in the
  first M3 launch. They clustered between run clock 88 and 155 s, with only 36–52 enemies alive.
- **Hitch-hunt runs:** neither of the 2 `WOW_FRAME_PHASES=150` runs reproduced them (worst 102
  and 61 ms), so no phase breakdown was captured.
- **Rhythmic stalls:** 100–270 ms stalls on a 4 s / 19 s wall-clock rhythm appeared in 2 of 5
  real-step `:late` runs only, in both play and level-up frames.
- **Status: not reproduced on demand, cause unknown.** It could be the engine (sound streaming,
  first-time model or effect loads) or the machine (other processes). The trace showed rare long
  single calls: `footstep_sounds` up to 180 ms, `update_hovered_object` 81 ms,
  `float_combat_text` 91 ms. They are suspects only; they did not coincide with a recorded stall.
- **Not ranked for fixing.** It needs a reproducible case first.

## Ranked candidates

| # | Candidate | Evidence | Expected benefit | Risk | Effort | Validation |
|---|---|---|---|---|---|---|
| 1 | **Minimap recomposite every frame** (`survivors/minimap.rs` `compose`) | Biggest single main-thread system: 2.78 ms/frame traced. It redraws 36,864 pixels with 4 bilinear tile lookups each, one icon per live enemy, and copies 147 KB into a GPU texture every frame (`images.get_mut`, which also forces the re-upload seen in `extract_render_asset<GpuImage>`) | about 2–2.5 ms of the ~12 ms main thread, if the trace self time holds in the plain build | **Visual only**: the minimap redraws at ~15–20 Hz instead of every frame. No gameplay state, no RNG | Small, one file (survivors) | Fixed-step benchmark, 3 runs, median/p95/p99 vs baseline |
| 2 | **Combat-text load** (`combat_text/mod.rs` `float_combat_text`, fed by `survivors/units.rs` `Fx::number`) | 2.26 ms/frame traced, worst 91 ms. Cost grows with live texts (up to 4 per unit, so up to about 700 at 175 enemies), each laid out and placed by an overlap solver every frame | 1–2 ms plus fewer spikes, by sending fewer numbers from survivors (e.g. merge one enemy's hits within a frame). The engine module is upstream code, so the change goes on the survivors side | **Visual only**: fewer, merged damage numbers. Combat values unchanged | Medium | Same benchmark; count live texts before/after |
| 3 | **XP-gem visual weight** (`survivors/enemies.rs` `spawn_gem`, the wisp GameObject) | Correlation across 10 runs: +150–270 units / +11–17k entities ↔ +2–4 ms. Mechanism inferred, not isolated | Up to 2–4 ms in the high-gem state, which is the real-step state players see half the time | Must stay visual only: lighter gem visuals (e.g. no emitters/ribbons, or a static mesh). Changing `MAX_GEMS` or merging would change XP pickup timing, which is **gameplay**, so it is excluded | Medium; needs an isolating experiment first (the same run with gem visuals lightened) | Real-step and fixed-step benchmarks; units/entities columns |
| 4 | Particles, ribbons, billboards (engine) | 1.29 + 0.64 ms traced | Partly follows #3 (wisp emitters) and spell effects | Engine code (upstream carry rule) | Large | Only after #3 |
| 5 | Skinned animation for about 175 enemy rigs (engine `rig_anim`) | 1.29 + 0.42 ms traced | Engine-level (pose sharing, LOD) | Upstream conflicts; big change | Large | Deferred (roadmap M10) |

**Recommended order:** #1, then #2, measuring each separately, then the isolating experiment for
#3. Combined, #1 and #2 could plausibly bring the reference main thread from about 12 ms toward
8–9 ms. That is an estimate from traced self times, to be confirmed by measurement.

## Not pursued, with reasons

- **Separation grid, target sorting, splash scans:** each below about 0.09 ms per frame in the
  trace. Rewriting them would add risk (RNG order, float summation order) for no measurable gain.
- **The rig-slot ceiling (2,048):** the reference load uses a few hundred rigs. Not a constraint
  yet.
- **Rendering and GPU:** about 2 ms on the GPU. Not the limit.
