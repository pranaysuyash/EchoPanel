# Randomized Exploratory Testing Pack (EchoPanel) — v1.0

**Goal**: Provide a set of short exploratory scripts that reliably uncover state bugs and missing UX states.

---

## Inputs
- Surface: `macapp | landing | server`
- Time budget: `<15m | 30m | 60m>`

---

## Output (required)
- 10–25 exploratory “scripts” (step sequences) with:
  - What to do
  - What to observe
  - Expected failure modes
- A small set of “edge state injections”:
  - backend down / reconnect
  - permission denied / revoked
  - long session (≥30m) memory/perf perception
  - rapid start/stop

---

## Stop condition
Stop after the script pack.
