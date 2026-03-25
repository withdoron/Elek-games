# GROWTH.md — Design Protocols for Elek's Kart Racers

## The Rhythm

Every element in the game follows the same heartbeat:

**Anticipation → Action → Tension → Resolution**

- A red shell appears behind you (anticipation)
- You grab a banana (action)
- The shell closes in (tension)
- You drop the banana at the perfect moment (resolution)

This rhythm plays out at every scale: a single item use, a lap, a race, a championship. When adding anything to the game, ask: *where is the rhythm?*

---

## Protocol 1: Adding a Track

Before building, fill out this template:

```
Track Name:
Theme:          (beach, snow, jungle, city, space...)
Surface:        (asphalt, dirt, sand, ice, rainbow...)
Signature Feature: (one memorable thing — a big jump, a shortcut, a hazard)
Hazard:         (what makes this track dangerous?)
Difficulty:     (1-5 stars)
```

Rules:
- Every track needs ONE thing players remember it for
- The signature feature should create a moment of tension every lap
- Shortcuts must have risk — they're faster but you might fall off
- Test with NPCs before shipping — does the AI handle it?

---

## Protocol 2: Adding a Racer

```
Racer Name:
Color Scheme:   (primary + accent)
Speed:          (/5)
Acceleration:   (/5)
Handling:       (/5)
Stats Total:    (must equal 15)
NPC Personality: (aggressive, defensive, balanced, chaotic)
```

Rules:
- Stats always sum to 15 — no racer is strictly better
- Each racer should have a clear identity from their silhouette
- NPC personality affects item usage, not just driving line
- Test: can a new player tell racers apart at a glance?

---

## Protocol 3: Adding an Item

```
Item Name:
Type:           (offensive / defensive / utility)
Effect:         (what it does)
Counterplay:    (how to avoid or counter it)
```

Rules:
- **Every item MUST have counterplay.** No unavoidable attacks.
- Offensive items should feel satisfying to land AND to dodge
- Defensive items should require timing, not just activation
- Utility items (speed boost, etc.) should have a tradeoff
- Rubber-banding: trailing racers get better items, but never a guaranteed win

---

## Protocol 4: Adding a Feature

Answer these four questions before writing any code:

1. **What is it?** (one sentence)
2. **Why does the game need it?** (what's missing without it?)
3. **What's the simplest version?** (MVP — what can we cut?)
4. **Does it help everyone?** (new players AND experienced players?)

If you can't answer all four clearly, the feature isn't ready.

---

## Testing Checklist

Before any change is considered done:

- [ ] Game launches without errors
- [ ] Kart drives and feels good
- [ ] Settings menu works — sliders change behavior in real time
- [ ] Works with keyboard
- [ ] Works with gamepad (analog triggers)
- [ ] Settings save and load across sessions
- [ ] **IS IT FUN?**

The last one is the only one that really matters.
