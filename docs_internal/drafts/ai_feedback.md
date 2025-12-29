# Archived: AI feedback snapshot (historical)

> This is a historical feedback snapshot. The current API/doc state may differ; treat this as input, not truth.

# From a clean-room analysis (AI that was never involved in building)

If I’m a **mid-level Project Zomboid Lua modder** and I open the three smoke test files for the first time, my reaction is basically:

> **“Oh, this is a framework-y abstraction layer that’s trying to make game events idempotent and structured… but it’s *not* how most PZ mods are written.”**

Below is what I would understand quickly, what feels “smart but unfamiliar”, and where I’d struggle.

---

## 1) Immediate gut reaction (first 30 seconds)

### ✅ What feels familiar

* It’s Lua, clean formatting, self-contained “smoke test” modules.
* I recognize **PZ Events** usage (like `Events.OnTick`) right away. 
* I recognize the overall pattern: **register something → do something → allow stop/cleanup**.

### ❗What feels *very unfamiliar*

* Everything is built around `PromiseKeeper`, `situations`, `actions`, `policy`, and “occurranceKey”.
* This is not normal “PZ event handler style”.
* Looks like something designed with larger architectural goals:
  **deduplication**, **state persistence**, **automation rules**, and **event → action mapping**.

---

## 2) What I understand (once I read a bit)

### ✅ Big picture: this is an “event-to-action automation system”

All three files show the same pattern:

1. Define a *situation* (a stream of things happening / being observed).
2. Map each situation occurrence to:

   * a `subject`
   * an `occurranceKey`
3. Define an *action* (what to do when a situation occurs)
4. Define a *promise* (a rule: “when situation happens → run action, following a policy”)
5. Return a handle with `stop()` and sometimes `fire()`.

That structure is very consistent.

---

### ✅ “PromiseKeeper” appears to be doing:

* Managing **subscriptions**
* Enforcing **policy** (like maxRuns, chance)
* Ensuring **idempotence** via `occurranceKey`

Example: In the PZ Events smoke test, `occurranceKey` is forced to be stable:

```lua
occurranceKey = "player:" .. tostring(getPlayer():getPlayerNum())
```

This means even though OnTick fires constantly, PromiseKeeper can treat it as the same “occurrence”. 

So as a modder I’d think:

> “Ah, this system wants every event to produce a stable ID so it knows whether it has seen it before.”

That’s a concept most PZ mods don’t care about, but it makes sense if you want persistence / retry / “do once”.

---

## 3) File-by-file: what I read into each

---

### A) `smoke_pk_pz_events.lua`

This is the easiest to understand.

* It maps `Events.OnTick` into a PromiseKeeper situation.
* It makes the subject `getPlayer()`
* It prints a debug line, but only once.

Policy:

```lua
policy = { maxRuns = 1, chance = 1 }
```

So this is basically:

✅ “Run this action only once when the player ticks (which is immediately).” 

**What I understand clearly:**

* It’s a proof that PromiseKeeper can hook into a PZ Event
* It demonstrates how to make “OnTick” usable as a stable situation stream

**My modder brain says:**

> “This is basically replacing `Events.OnTick.Add(function() ... end)` with a higher-level declarative rule system.”

---

### B) `smoke_pk_luaevent.lua`

This one shows a custom event emitter (`Starlit/LuaEvent`).

I’d quickly understand:

* It creates a new LuaEvent object
* It maps it into a situation stream
* It can “fire” payloads into it
* It logs them once

The key mapping line:

```lua
return pk.factories.fromLuaEvent(event, function(payload)
  return { occurranceKey = tostring(payload or "none"), subject = payload }
end)
```

So the event payload itself becomes both the subject and the stable ID. 

**Reaction:**

> “Oh, they’re demonstrating that PromiseKeeper can wrap *any* emitter, not just PZ Events.”

This makes PromiseKeeper look like a general reactive engine.

---

### C) `smoke_pk_worldobserver.lua`

This one is the most “frameworky”.

It introduces **WorldObserver**, which looks like another system that generates “situations” (observations like squares with corpses). 

Key idea:

* WorldObserver defines a situation:

  ```lua
  wo.situations.define("corpseSquares", function()
    return WorldObserver.observations:squares():squareHasCorpse()
  end)
  ```
* PromiseKeeper *does not define the core situation itself*, it just searches the WO registry:

  ```lua
  pk.situations.searchIn(WorldObserver)
  ```

Then it sets up an “interest spec” describing spatial query config:

```lua
spec = { type="squares", scope="near", radius=3, staleness=3, highlight=true }
```

That’s very different from normal PZ mods. 

**What I understand:**

* This is building a system that tracks world state in a structured way.
* “Corpse squares near player” becomes a stream of observations.
* PromiseKeeper turns those into actions once, keyed by `WoMeta.occurranceKey`.

**My modder brain says:**

> “This is trying to make world scanning cheap, structured, and reusable, instead of writing brute-force loops.”

---

## 4) What I struggle with (as a mid-level modder)

This is the important part — what would make me pause.

---

### ❓ 1) What is PromiseKeeper *exactly*?

As a modder, I can infer its goals, but I don’t have the mental model yet:

* Is it persistent across saves?
* Does it store promise completion state?
* Is it like a scheduler?
* Is it like an achievement/quest engine?
* Does it run actions on server, client, both?
* How does it handle multiplayer desync?

These smoke tests don’t answer that — they only prove it can run.
So I’d feel like:

> “I see the API, but I don’t know the lifecycle rules.”

---

### ❓ 2) Why the names: *situations*, *situationFactoryId*, *actions.define*?

The naming feels like something from a bigger design system, not typical mod scripting.

I’d struggle to know:

* when to use `situations.define` vs `wo.situations.define`
* what the *factory* is supposed to mean
* whether “define” registers globally or per-instance

Especially here:

```lua
pk.situations.define("corpseSquares", mapWO("corpseSquares", ...))
```

That’s two layers of definition. 

So I’d think:

> “I get that WO defines observation, PK maps to occurrences, but… why can’t PK just listen directly?”

---

### ❓ 3) occurranceKey rules are not obvious

In all files, the system’s correctness depends on `occurranceKey`.

But a mid-level modder will ask:

* Is it required to be unique forever?
* Can it repeat after forget?
* What happens if collision happens?
* Should it be stable across sessions?
* Is it per promise, per namespace, global?
* How is it stored?

Example:

In `smoke_pk_luaevent.lua`, `occurranceKey = tostring(payload)` means:

* payload `"hello"` and `"hello"` collide → second one won’t run again if promise persists state. 

That might be correct, or might be surprising.
So I’d struggle with: **how careful do I need to be?**

---

### ❓ 4) “policy” feels powerful, but unclear

The policy is always:

```lua
{ maxRuns = 1, chance = 1 }
```

As a modder, I’d wonder:

* can policy include cooldowns?
* can it include time windows?
* can it include retries?
* can it include conditional checks?
* is chance rolled per occurrence?

It’s a *very game-y* concept, but not documented here.
So I’d be curious, but I’d need docs.

---

### ❓ 5) Stopping is done via `promise.forget()`

This is interesting, because in normal PZ mods, stopping means:

* remove event handler
* clean timers
* clear tables

But here, the “stop” method always does:

```lua
promise.forget()
```

So I’d wonder:

* does “forget” unregister events?
* does it delete saved state?
* does it stop active observation loops?
* is it safe to call multiple times?

It’s also called out as important:

> “Stop + forget to keep smoke testing iterative (no persisted state surprise).” 

This implies that promises may persist.
That’s a major conceptual leap for a modder used to “scripts run fresh each load”.

---

## 5) What I’d praise as a modder

Even if I struggle, I’d still think this is very cool.

### ✅ Strengths I see

* **Very modular** — situations and actions separated cleanly
* **Testable** — these are literally smoke tests with console instructions at top
* **Extensible** — works for PZ Events, custom emitters, and WorldObserver
* **Encourages good habits** — stable IDs, stop/cleanup, no hidden global side effects
* **Declarative logic** — “when this happens, do this once” is super readable once you learn the system

---

## 6) If I were reviewing this as a mid-level modder, I’d say:

### “What I understand”

* This is a system that maps event-like things into **structured occurrences**
* Every occurrence has a stable ID + subject
* You register **situations** and **actions**
* A **promise** binds them together with a policy
* It can work with:

  * native PZ events (`Events.OnTick`) 
  * custom Lua events (Starlit LuaEvent) 
  * world scanning/observation (WorldObserver) 

### “What I struggle with”

* Understanding PromiseKeeper’s persistence + lifecycle rules
* Understanding what “forget” does mechanically
* Knowing what policies exist beyond maxRuns/chance
* Knowing how occurranceKey should be designed safely
* Understanding how WorldObserver ties into performance and update cycles

---

## 7) What I’d *want next* (as a modder)

If I had these files, my next asks would be:

1. **A tiny doc**: “PromiseKeeper in 5 minutes: mental model”
2. Examples of policies:

   * once per day
   * once per square
   * 20% chance per tick
3. A warning section: **how to choose occurranceKey**
4. Multiplayer notes
5. A real gameplay example (loot spawn, moodle trigger, quest step, etc.)

---

If you want, I can also rewrite these smoke tests into “typical PZ mod style” equivalents (plain `Events.OnTick.Add(...)` etc.) so you can see exactly what extra layers PromiseKeeper is adding — and where it’s beneficial vs overkill.
