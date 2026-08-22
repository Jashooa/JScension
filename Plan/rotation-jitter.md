# Rotation Jitter Plan

## Problem

The auto rotation currently submits the next eligible spell at the earliest possible moment. With the spell queue window enabled, cast starts can become nearly perfectly back-to-back. Add an optional bounded post-ready delay so the actual interval between cast starts varies.

Jitter must delay the emitted cast, not merely vary the time at which the client receives a queue request. A request sent anywhere inside the spell queue window still starts at the prior cast's end and therefore does not humanise the inter-cast interval.

## Scope

- Add one profile-level maximum jitter setting.
- Apply jitter only to automatic rotation pulses.
- Keep manual `PulseOnce()` casts immediate.
- Keep jitter disabled by default.
- Intentionally trade queue-window throughput for timing variation when jitter is enabled.
- Do not change rule evaluation semantics or condition behavior.
- Do not add per-spell random behavior in this change.

## Chosen behavior

The setting represents a maximum random delay after a rule first becomes eligible:

```text
jitter = 0.0s -> current behavior
jitter = 0.25s -> each eligible automatic cast waits a random 0..0.25s
```

The delay is anchored to the first pulse where the candidate passes its
ordinary rule conditions. It is not anchored to cast end. The existing GCD
and queue-window gates still decide whether the cast can be emitted when the
delay expires.

```text
dueAt = eligibleAt + random(0, jitterWindow)
```

Draw one delay when a candidate first becomes eligible. Do not draw a new value every pulse. Otherwise the deadline moves continuously and a cast can be postponed indefinitely.

The pending jitter reservation is identified by the candidate rule and cast target. If the candidate changes, the condition stops passing, the spell becomes unavailable, or the rotation is disabled, discard the reservation and draw again for the next candidate.

## Queue-window policy

Jitter runs before the existing GCD and queue-window gates. The spell queue
remains available whenever the sampled release time lands before the current
cast ends.

- `dueAt` before the queue window: the existing gate waits, then submits at
  queue-window entry.
- `dueAt` inside the queue window: submit normally and let the client queue it.
- `dueAt` after the current cast ends: submit while idle, producing a real
  inter-cast gap.
- `jitter = 0` retains the existing immediate queue-window behavior.
- `PulseOnce()` always bypasses jitter.

This preserves queueing opportunistically while allowing some samples to miss
the queue window and create the intended timing variation. The UI must state
that jitter can reduce throughput.

## State model

Keep the jitter state private to the rotation engine:

```lua
local jitterPending = {
    key = nil,
    dueAt = nil,
    eligibleAt = nil,
}
```

A candidate key should include enough identity to prevent reuse after a rule or target changes:

```text
rule identity + spell + target
```

Suggested flow in `Rotation.CastBest()`:

1. Preserve player-dead, compatibility, and other global safety gates.
2. Select the first passing rule without emitting through the GCD or
   queue-window gates yet.
3. If this is a manual cast, use the existing immediate path.
4. If jitter is disabled, use the existing GCD and queue-window path unchanged.
5. If the candidate differs from the pending jitter key, store
   `eligibleAt = currentTime` and draw one delay.
6. If current time is before `dueAt`, return without emitting.
7. Re-run normal rule selection at or after `dueAt`.
8. Run the existing GCD and queue-window gates. If they are still blocking,
   retain the pending candidate and retry on the next pulse.
9. Emit only if the same candidate still passes and the normal gates allow it.
10. Clear the pending jitter state after an emit or candidate invalidation.

The implementation must avoid changing behavior when the setting is zero. The
existing GCD and queue-window calculations remain the source of truth for the
zero-jitter path.

Revalidate all existing conditions at release time. Jitter must never reserve a
cast against stale conditions.


## Profile schema

Add a profile field:

```lua
jitterWindow = 0.0
```

Use named constants for the default and editor maximum. Recommended initial bounds:

```text
DEFAULT_JITTER_WINDOW = 0.0
minimum = 0.0
maximum = 1.0
step = 0.05
```

Sanitization must coerce invalid values and clamp out-of-range values. Existing profiles receive `0.0`, preserving current behavior.

Add a setter following the existing timing setters:

```lua
Profile.setJitterWindow(seconds)
```

Changing the setting should clear any pending jitter reservation so a stale deadline cannot survive a profile edit.

## UI

Add a slider to `Accessibility/UI/Panels/RotationMainSettings.lua` near `Pulse interval`, `Spell queue window`, and `Anti-spam window`:

```text
Cast jitter
Maximum random delay before an automatic cast
```

Use the profile setter and refresh behavior already used by the other timing controls.

## Randomness

Use a bounded uniform delay. Draw once per pending candidate.

Do not reseed the global random generator on every cast. Avoid changing global random state if the client exposes a suitable existing random source. If a deterministic test seam is needed, keep the random draw in a small private helper that tests can replace or control.

Jitter must not affect:

- rule priority;
- condition results;
- cooldown calculations;
- anti-spam timestamps;
- manual casts.

Jitter intentionally changes queue-window behavior when enabled. Record
`lastAttemptTime` and `lastCastAt` only when a cast is actually emitted, not
when jitter begins.

## Critical files

- `Accessibility/Core/Profile.lua`
  - default, sanitization, setter.
- `Accessibility/Utils/Constants.lua`
  - default and maximum jitter constants.
- `Accessibility/Core/Rotation.lua`
  - pending candidate, eligibility-time random delay, release-time revalidation, and queue-window interaction.
- `Accessibility/Accessibility.lua`
  - only if manual/automatic pulse context needs an explicit distinction. Prefer passing context or a small rotation API rather than duplicating cast logic.
- `Accessibility/UI/Panels/RotationMainSettings.lua`
  - jitter slider.
- `Accessibility/tests/run.lua`
  - profile, timing, manual bypass, queue-window, and deterministic jitter coverage.

## Verification

1. Existing Lua suite passes with jitter defaulted to zero.
2. Profile sanitization clamps negative, excessive, string, and missing values.
3. Jitter disabled produces the current immediate-cast behavior.
4. Automatic casts with jitter enabled do not emit before the stored deadline.
5. The random delay is drawn once per candidate, not once per pulse.
6. Conditions are re-evaluated at the deadline; invalid candidates are discarded.
7. A higher-priority rule replacing the pending candidate cancels the old delay.
8. Manual `PulseOnce()` bypasses jitter.
9. A sampled release time inside the queue window submits normally and the client queues the spell.
10. A sampled release time after the current cast ends produces the intended inter-cast gap.
11. A sampled release time before the queue window remains blocked until the existing queue gate opens.
12. With jitter disabled, active casts inside the queue window retain the existing immediate queue behavior.
13. GCD and anti-spam timestamps begin at actual emission time.
14. Rotation behavior is unchanged when the setting is zero.

## Risks and boundaries

- Jitter intentionally reduces throughput and can miss the client queue window. The UI must make this tradeoff explicit.
- Random timing is not a substitute for state tracking or cast confirmation. This feature only varies emission timing.
- A single global jitter value is intentionally simple. Per-rule jitter, non-uniform distributions, and adaptive latency-based jitter can be added later without changing the pending-candidate contract.
