# Projected State Effects for Queue-Window Casting

## Problem

The rotation evaluates conditions against delayed game state. A cast can be submitted during the spell queue window before the game reports its effect.

Example:

- `Summon Air Elemental` starts.
- `pet` still does not exist during the cast.
- `unit_exists(pet)` remains false.
- The same rule passes again during the queue window and submits a duplicate cast.

The same problem applies to generator/consumer rotations:

- `Shock` generates 20 Static.
- `Aeroblast` consumes 50 Static.
- The Static aura may not update before the next rule evaluation.

## Decisions

- Keep `Aura.find()` authoritative and unchanged.
- Do not rename it to `findRaw()`.
- Add a projected view as `State.Aura.find()`.
- Keep `Unit.exists()` authoritative and expose projected unit queries through `State.Unit.exists()` where conditions need them.
- Conditions remain the only user-facing rule requirements.
- State changes are typed cast effects, not pseudo-conditions.
- Keep the existing `IsUsableSpell()` contract: `usable ~= true` blocks the spell.
- Do not override `IsUsableSpell()` with projected state.
- Projection may affect condition evaluation, but it must not make a spell pass the existing usability gate.
- Deterministic effects may be projected immediately after a cast is accepted.
- Uncertain effects use conservative bounds or remain unresolved until actual state is observed.
- Actual game state always wins during reconciliation.

## Data model

Attach state changes to a rotation rule. Keep the schema separate from conditions, but reuse the existing field-descriptor and sanitization patterns.

Example deterministic generator:

```lua
{
    type = "aura",
    unit = "player",
    aura = STATIC_AURA_ID,
    kind = "buff",
    operation = "add_stacks",
    value = 20,
    timing = "success",
    certainty = "exact",
}
```

Example consumer with uncertain consumption:

```lua
{
    type = "aura",
    unit = "player",
    aura = STATIC_AURA_ID,
    kind = "buff",
    operation = "remove_stacks",
    value = 50,
    timing = "success",
    certainty = "bounded",
    minimumDelta = -50,
    maximumDelta = 0,
}
```

Example summon effect:

```lua
{
    type = "unit",
    unit = "pet",
    operation = "set_exists",
    value = true,
    timing = "success",
    certainty = "exact",
}
```

Use stable spell IDs for aura identity. Display names remain an editor concern.

Initial supported effect types:

- `aura`: add/remove/set stacks, apply/remove.
- `unit`: set exists/absent.
- `boolean`: set true/false.

Do not support arbitrary Lua state effects initially.

## Module structure

### Existing authoritative modules

- `Accessibility/Game/Aura.lua`
  - Keep `Aura.find()` as the direct `UnitBuff`/`UnitDebuff` reader.
  - It returns observed state only.
- `Accessibility/Game/Unit.lua`
  - Keep `Unit.exists()` and related APIs authoritative.

### New state projection module

Add `Accessibility/Core/State.lua`.

Responsibilities:

- Own pending cast effects.
- Provide projected queries:
  - `State.Aura.find(...)`
  - `State.Unit.exists(...)`
- Add/remove effects by cast token.
- Track cast phases.
- Reconcile pending projections against authoritative reads.
- Never mutate the raw `Aura` or `Unit` state.

### New state definitions module

Add `Accessibility/Core/StateDefinitions.lua` if the editor schema becomes large enough to justify a separate registry.

Responsibilities:

- Define state-change types and ordered fields.
- Describe state changes for the editor.
- Sanitize state-change values.
- Apply typed effects to projected state.
- Validate effect operations and certainty values.

Reuse existing condition field infrastructure rather than creating a second editor framework.

### Condition integration

Pass `State` into `ConditionDefinitions.Build()`.

Update state-sensitive condition evaluators:

- `unit_exists` -> `State.Unit.exists()`.
- `unit_aura_present` -> `State.Aura.find()`.
- `unit_aura_missing` -> `State.Aura.find()`.
- `unit_aura_stacks` -> `State.Aura.find()`.
- `unit_aura_remains` -> `State.Aura.find()` if duration projection is supported.

Other code should continue using authoritative `Aura.find()` and `Unit.exists()` when it needs actual game state.

## Projection lifecycle

Each accepted cast receives a token and provisional effects.

```text
cast submitted
    -> add provisional effects

cast starts
    -> mark token active

cast succeeds
    -> wait for authoritative state observation
    -> remove provisional effects

cast fails/interrupted/cancelled
    -> remove provisional effects immediately

timeout
    -> remove provisional effects and log the timeout
```

For an observed Static value of 30 with a pending Shock effect of +20:

```text
Aura.find()       -> 30
State.Aura.find() -> 50
```

When the real aura reports 50, remove the pending effect. Do not write 50 into the authoritative cache.

For an uncertain effect, discard the projection after the first valid post-cast authoritative observation. The observed result wins regardless of whether it matches the prediction.

## Pending effect storage

Use cast tokens rather than spell names as keys. A spell may have multiple relevant cast instances or rules.

```lua
State.pending[token] = {
    phase = "queued", -- queued, active, settling
    spell = spell,
    effects = effects,
    issuedAt = GetTime(),
}
```

A pending effect should include enough information to:

- apply a projected value;
- identify its authoritative source;
- roll back on failure;
- reconcile after success;
- expire safely if no cast event arrives.

## Queue-window behavior

Do not add a global same-spell lock.

- Repeatable rules may queue the same spell again.
- State effects update the projected state.
- A state-changing rule such as Summon Air Elemental should stop passing once its projected pet state becomes present.
- A second Aeroblast should only pass if projected Static satisfies its existing condition and the spell still passes `IsUsableSpell()`.
- The queue window remains a timing admission gate, not a state confirmation mechanism.

## IsUsableSpell boundary

`Rotation.evaluateRule()` currently checks `Spell.usable()` before conditions.

Keep the current behavior:

```text
IsUsableSpell result is not true -> spell is blocked
```

Projected state must not override this gate. Therefore:

- Projected conditions can prevent duplicate state-changing casts.
- Projected state does not make Aeroblast usable before the real Static aura update.
- Generator-to-consumer queueing is intentionally limited by the authoritative usability gate.

If this boundary changes later, it requires a separate client-specific design and verification. Do not solve it by removing `IsUsableSpell()` globally or requiring every rule to duplicate generic spell-safety conditions.

## Uncertain effects

Represent uncertain deltas as bounds:

```text
Aeroblast delta: [-50, 0]
```

For conservative condition evaluation:

- `>=` and `>` use the projected minimum.
- `<=` and `<` use the projected maximum.
- `==` is true only when the interval is exactly the requested value.
- Unknown boolean/aura existence must not satisfy a dependent condition.

Expected values must not be used for cast eligibility.

## Reconciliation and cache rules

- The authoritative aura read is always the baseline.
- Projections are overlays returned only by projected queries.
- Never mutate an authoritative aura cache with predicted values.
- Never apply a pending effect twice after the real aura update arrives.
- Remove a projection after an authoritative post-cast observation, even when the actual value differs from the prediction.
- Roll back immediately on failure/interruption.
- Expire pending effects after a bounded timeout if no start/success/failure event arrives.

## Verification plan

Add deterministic tests for:

1. `Aura.find()` remains unchanged by projections.
2. `State.Aura.find()` overlays an exact aura-stack gain.
3. A real aura update removes the projection without double application.
4. Failed casts roll back the projection.
5. Summon effects make projected pet existence true.
6. A deterministic Shock projection enables an aura-stack condition at the projected value.
7. A second consumer is blocked when projected stacks are insufficient.
8. Bounded random effects fail closed when the dependent condition is not guaranteed.
9. Repeatable spells are not globally blocked by unrelated pending effects.
10. `IsUsableSpell()` remains a hard gate.

Manual validation should cover:

- Summon Air Elemental does not duplicate inside the queue window.
- Repeated generator spells still queue normally.
- Static conditions use projected aura stacks only inside rotation evaluation.
- The UI and diagnostics still display authoritative aura state unless explicitly showing projection/debug information.
