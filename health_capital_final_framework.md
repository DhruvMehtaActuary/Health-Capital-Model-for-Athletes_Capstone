# Health Capital Framework
### Actuarial Risk Architecture for Fast-Bowler Workload Management
**Version 2.0 — Finalized Architecture (post acute/chronic revision)**

---

## Revision note (v1.0 → v2.0)

v1.0 treated workload as a single scalar `W_i(t)` and fatigue as the only
fast-moving driver of damage. That could not represent a genuinely U-shaped
risk relationship (both overload *and* under-conditioning being dangerous).
v2.0 fixes this by adding a fourth latent state — **chronic capacity `C_i(t)`**
— and rebuilding damage accrual as a function of the *acute-to-chronic
mismatch*, not fatigue alone. Everything else from v1.0 (jump mechanism,
hazard structure, scenario engine, portfolio aggregation, engineering stack)
carries over unchanged. This is the last structural revision before coding —
see the readiness verdict at the bottom.

---

## 0. Design Philosophy (unchanged)

Health Capital `H(t)` is a **latent stock variable**, inferred, never observed
directly, evolving as a hidden state in a partially observed stochastic
process (POMP), with injury as a state-dependent point-process event.

---

## 1. State Vector (revised — now 4-dimensional)

```
X_i(t) = [ H_i(t),  F_i(t),  C_i(t),  D_i(t) ]
```

| Symbol | Meaning | Behavior |
|---|---|---|
| `H_i(t)` | Health Capital — instantaneous capacity | Mean-reverting diffusion + jumps |
| `F_i(t)` | Acute fatigue | Fast, mean-reverting, driven by recent load |
| `C_i(t)` | **Chronic capacity / conditioning** *(new)* | Slow-adapting EWMA-style tracker of sustained load — represents built-up tolerance |
| `D_i(t)` | Accumulated micro-damage | Slow, path-dependent, driven by the *F:C mismatch*, not `F` alone |

`C_i(t)` is the model's internal, continuous-time analog of the acute:chronic
workload idea — but it is a **mechanism inside the model**, not an external
ACWR heuristic bolted on top. ACWR itself is retained only as an external
**benchmark model** to test against (§7), per your instruction not to hard-code
its thresholds into the mechanism.

---

## 2. Workload Input (revised — now a decomposed vector, not one scalar)

Raw daily inputs, logged per session rather than manually re-entered as
derived metrics:

```
w_i(t) = ( recent_volume_i(t),   match_overs_i(t),
           spell_max_i(t),       rest_gap_i(t),        format_i(t) )
```

- `recent_volume_i(t)`, `rest_gap_i(t)` are **derived automatically** from the
  logged session history (rolling window, consecutive-day counter) — the
  coach only ever enters a session (overs, format, spell breakdown), never
  re-types a rolling average. This satisfies the earlier "many optional
  inputs, minimal friction" usability requirement more cleanly than v1.0 did.
- `format_i(t)` is a physiological-load multiplier (Test > ODI > T20 per
  over, calibratable, not assumed equal).

**Acute load composite** (feeds `F`, weighted per your stated ranking —
weekly/recent volume > match overs > consecutive days without rest > overs
per spell; weights adjustable, not fixed):

```
A_i(t) = w1·recent_volume_i(t) + w2·match_overs_i(t)
       + w3·rest_gap_i(t)      + w4·spell_max_i(t)      [format-adjusted]
```

---

## 3. Dynamics (revised SDE system)

### 3.1 Acute fatigue (fast state)
```
dF_i(t) = -κ_F F_i(t) dt + A_i(t) dt - β_R R_i(t) dt + σ_F dW_i^F(t)
```
Fatigue half-life prior: **~3 days** (sensitivity range 2–4 days).

### 3.2 Chronic capacity (slow state — new)
```
dC_i(t) = κ_C ( Ā_i(t) - C_i(t) ) dt + σ_C dW_i^C(t)
```
`Ā_i(t)` = slow (~21–28 day) rolling average of `A_i(t)`. `C_i(t)` rises with
sustained, well-managed exposure (conditioning) and falls during long
lay-offs (deconditioning) — this is what lets the "returning/recurrent-injury"
archetype (#4) be represented honestly: low `C`, not low `θ`.

### 3.3 Micro-damage accrual (revised — mismatch-driven, U-shaped)
```
dD_i(t)/dt = α_D · F_i(t) · ( C* / C_i(t) )^ν   -   δ_D R_i(t),   D_i(t) ≥ 0
```
This single ratio-form mechanism produces the U-shape you specified without
an explicit piecewise rule:
- High `F` relative to a *normal* `C` → elevated damage (classic overload).
- Low `C_i(t)` (under-conditioned/returning player) → the `(C*/C_i)^ν` term
  amplifies damage from an *identical* `F` — this is the "sudden exposure to
  a bowler who hasn't built tolerance" danger you described, captured
  mechanistically rather than as a separate rule.
- A durable "workhorse" archetype with high `C_i(t)` gets a damping multiplier
  — same load, less damage — matching real conditioning effects.
Damage half-life prior (repair, not accrual): **~10–15 days** (sensitivity
range 7–21 days), explicitly a modelling prior, not a biological claim, and
kept distinct from actual injury recovery time (§4), which is months.

### 3.4 Health Capital (core process — unchanged in form)
```
dH_i(t) = κ_H ( μ_i(t) - H_i(t) ) dt - c_F F_i(t) dt + σ_H dW_i^H(t) - dJ_i(t)
μ_i(t) = θ_i - γ · D_i(t)
```
`θ_i`: player baseline durability, Bühlmann–Straub-blended (own history ×
population/archetype prior). `dJ_i(t)`: compound jump process for acute
trauma, intensity optionally rising with `F_i(t)`.

---

## 4. Injury Mechanism (revised — three parallel hazard streams, not one)

Rather than one generic hazard, three **independent latent event-time
streams**, each with its own baseline and its own sensitivity to the state
— a light, tractable form of competing risks (first-arrival-wins across the
three), matching your instruction to keep it representable without a full
competing-risks model:

| Type `k` | Primary mechanism sensitivity | Severity shape |
|---|---|---|
| Soft-tissue (e.g. hamstring) | Sensitive to `F` and sudden load spikes | Frequent, lower-to-moderate days lost, right-skewed |
| Side/trunk strain | Sensitive to `spell_max` / high-intensity burst load specifically | Fast-bowler-specific, several weeks, right-skewed |
| Lumbar bone-stress | Sensitive to accumulated `D_i(t)` more than instantaneous `F` | Infrequent, high severity, heavy-tailed (months) |

```
λ_i^(k)(t) = λ_0^(k)(t) · exp( -η_k H_i(t) + φ_k · [type-specific state term] + a_k(age_i) + γ_k Z_i )
```

- `λ_0^(k)`: parametric baseline hazard **per type**, left as a calibration
  placeholder (§6) — exact rate depends on the exposure-unit definition still
  to be pinned down, deliberately not guessed.
- `a_k(age_i)`: **nonlinear, type-specific** age modifier (not linear, not
  shared across types) — e.g. bone-stress can be elevated in both young
  (developing) and veteran (accumulated-damage) bowlers, while soft-tissue
  risk may follow a different shape. Exact curve shapes are calibration
  targets, represented as flexible (spline/quadratic) forms now.
- Observed event = earliest arrival across the three streams; type is logged
  with it, feeding the severity draw.

Days-lost is drawn from a **type-conditional, heavy/right-skewed distribution**
(e.g. log-normal or Gamma), not a fixed value — matching your instruction.

---

## 5. Bowler Archetypes (finalized — four, not three)

Each archetype is a **prior over `(θ_i, C_i(0), D_i(0), Z_i)`**, not a fixed
injury probability:

1. **Young developing pacer** (20–22): high raw pace, low `C_i(0)` (limited
   conditioning history), moderate `θ_i` with wide uncertainty, low `D_i(0)`.
2. **Prime workhorse** (26–29): high `θ_i`, high `C_i(0)`, low `D_i(0)`,
   fastest recovery parameters.
3. **Veteran high-workload bowler** (32–35): high `θ_i` but eroded by
   substantial `D_i(0)` already accumulated, slower recovery parameters
   (`κ_F`, `κ_D` shifted down).
4. **Returning/recurrent-injury bowler** (25–30): moderate-to-high `θ_i`
   (talent intact) but **low `C_i(0)`** specifically (deconditioned from
   lay-off) and elevated residual `D_i(0)` — this archetype is *why* `C` had
   to become its own state: it's the clearest real case where danger comes
   from low chronic capacity, not low fatigue tolerance or low baseline talent.

---

## 6. Estimation Strategy (unchanged from v1.0)

Mode A (simulator, ground truth via literature-informed priors above) →
Mode B (particle filter recovering `Ĥ, F̂, Ĉ, D̂` from observables, validated
against Mode A's known truth). `pomp` remains the right R package — it
handles arbitrary state dimension without any architecture change from
adding `C_i(t)`. `λ_0^(k)` values remain explicit placeholders until the
exposure-unit definition (deliveries vs. player-days vs. matches) is fixed —
this is a calibration-time task, not a coding blocker, since the simulator
runs perfectly well on a placeholder rate.

---

## 7. Scenario Engine → Multi-Horizon Coach Output (revised)

Single Monte Carlo run per scenario now records cumulative injury indicator
at **four checkpoints along the same simulated paths** (no re-simulation
needed per horizon):

- **Next match** — "is this player available for the upcoming game?"
- **Next 14 days** *(default view)* — the core workload-management question
- **Next 28 days**, **Next 90 days** — medium/long-term planning views

Each horizon, each scenario (`Current / +10% / +20% / −15%` load) produces
its own `P(injury)`, `Expected Availability`, `Risk Tier`, per type breakdown
if desired. The **ACWR-only baseline model** is coded as a separate, simpler
comparator (external heuristic, not wired into the mechanism) specifically to
produce the "improvement over ACWR" validation claim from earlier.

---

## 8. Portfolio / Squad Aggregation (unchanged from v1.0)
Frequency × severity aggregation across players → squad-level expected
days-lost distribution, usable for "probability we have N fit bowlers by
match day."

---

## 9. Engineering Architecture (unchanged, one addition)

Same stack as v1.0 (R + `pomp` core, `survival`/`flexsurv`, SQLite, Shiny
MVP with PWA packaging). One addition: the **session-log input schema**
(§2) means the Shiny input form is a simple session-entry log (date, overs,
format, spell breakdown, wellness/recovery fields), with `recent_volume` and
`rest_gap` computed server-side — never manually entered — which is both
more accurate and less friction for the coach than v1.0's implied single
workload field.

---

## 10. Build Order (unchanged structure, now correctly scoped)

1. Simulator — 4D SDE system (§3), four archetypes (§5), three hazard
   streams (§4).
2. Particle filter — recover `Ĥ, F̂, Ĉ, D̂` from observables, validate.
3. Scenario engine — multi-horizon, multi-scenario Monte Carlo (§7).
4. Shiny UI — session-log input, single-player output table.
5. Portfolio layer — persistence, squad dashboard (§8).
6. Validation harness — C-index/calibration on simulated data, ACWR
   comparator model coded alongside.
7. *(Later)* real-data recalibration of `λ_0^(k)`, age curves, severity
   distributions once actual incidence data and its exposure-unit
   definition are pinned down.

---

## 11. Remaining Open Items (calibration-time, not coding blockers)

- Exact `λ_0^(k)` values, pending exposure-unit definition (§6).
- Exact age-curve shapes `a_k(age)` per injury type (§4).
- Exact severity-distribution parameters per type (§4).
- Weight values `w1..w4` in the acute composite (§2) — a starting ranking is
  set, exact magnitudes are a calibration target.

None of these block writing the simulator: every one of them is a parameter
or prior to be set/tuned, not a missing piece of model structure. The
structure itself is now complete and internally consistent.

---

## Readiness Verdict

**Ready to start coding.** The architecture is structurally complete: state
vector, dynamics, hazard mechanism, archetypes, scenario engine, and
engineering stack are all specified and mutually consistent. The items in
§11 are calibration inputs to be set with placeholder/prior values now and
refined later — exactly the "simulation and validation engine first" mode
you specified from the start. Nothing left is an architectural unknown.
