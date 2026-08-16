# Solar‑Powered EV Charging Station with a Metaheuristic‑Tuned Shunt APF and V2G Support

MATLAB/Simulink implementation and analysis code for the paper
**"Power Quality Improvement in Solar‑Powered EV Charging Stations Using a
Metaheuristic‑Tuned Active Power Filter with Vehicle‑to‑Grid Support."**

The system integrates a P&O‑MPPT solar PV boost stage, a three‑phase shunt
Active Power Filter (APF) with synchronous‑reference‑frame (d–q) current control
and a PSO‑tuned DC‑link PI loop, and a bidirectional EV charger supporting both
grid‑to‑vehicle (G2V) and vehicle‑to‑grid (V2G) operation on a shared DC link.

Compliance is assessed using the **Total Demand Distortion (TDD)** of IEEE Std 519:
the proposed scheme attains a worst‑mode TDD of **2.65 %** (versus 21.7 %
uncompensated) while regulating the DC link during irradiance transients and V2G.

---

## Requirements

- MATLAB **R2024b** (R2023b+ should work)
- Simulink
- Simscape + **Simscape Electrical** (Specialized Power Systems)

## Repository layout

```
EVCS_APF_V2G.slx            The Simulink model (self‑contained, powergui discrete)
model_params.m              All parameters — Table 1 (system), Table 2 (PSO), Table 3 (gains)
build_apf_v2g_model.m       Rebuilds EVCS_APF_V2G.slx programmatically from scratch
run_all.m                   Builds (if needed), simulates 0.5 s, plots baseline results

pso_tune.m                  Original PSO tuner (Eq. 19–20)
pso_tune_short.m            Short, genuine PSO run (random start → real convergence curve)

apf_metrics.m               Shared engine: set params → simulate → THD / TDD / DC‑link metrics
ablation_study.m            Ablation: APF on/off, tuned/un‑tuned, PV/V2G on/off
complexity_analysis.m       Offline O(N·kmax) cost + online O(1) per‑sample flop budget
robustness_analysis.m       Voltage/frequency/Lf/Cdc/load sweeps vs TDD (IEEE‑519)
sensitivity_analysis.m      One‑at‑a‑time gain/plant sweeps + tornado ranking

pv_ripple_probe.m           Diagnostic: PV‑side filtering sweep
harmonic_diagnose.m         Diagnostic: FFT of source current (PV on/off) vs load
export_paper_figures.m      Exports the paper's result figures (Fig. 3, 9–13)
make_fig9_convergence.m     Regenerates the PSO convergence figure (Fig. 9)

results/                    Pre‑generated figures (PNG) and result tables (CSV)
```

## Quick start

```matlab
% from this folder, in MATLAB
run_all                 % builds EVCS_APF_V2G.slx (if needed), simulates, plots

% metaheuristic tuning (writes optimized_gains.mat)
pso_tune_short          % short genuine run (~a few minutes with FastRestart)
% pso_tune(false)       % full Table‑2 run: 30 × 100 (slow)

% analysis (each writes figures + CSV tables to results\)
ablation_study
complexity_analysis        % add (true) for a quick single‑point run
robustness_analysis        % add (true) for a coarse 3‑point sweep
sensitivity_analysis       % add (true) for a coarse 3‑point sweep

% export the paper's result figures
export_paper_figures
```

All analysis scripts share `apf_metrics.m`, which resets the base workspace to
`model_params.m`, applies per‑case overrides, simulates, and returns per‑mode
THD, IEEE‑519 **TDD**, DC‑link regulation and runtime.

## Key parameters (`model_params.m`)

| Quantity | Symbol | Value |
|---|---|---|
| Grid line‑to‑line voltage | V_LL | 415 V, 50 Hz |
| Reference DC‑link voltage | V_dc* | 750 V |
| DC‑link capacitance | C_dc | 3000 µF |
| APF coupling inductor | L_f | 1.5 mH |
| PV array rated power | P_pv | ~24 kW (10 × 8 SPR‑305E) |
| EV battery | — | 360 V / 40 Ah Li‑ion |
| Optimised gains (Table 3) | Kp, Ki, HB | 1.85, 24.6, 0.35 A |
| Discrete sample time | Ts | 2 µs |

## Notes on metrics

Because the grid fundamental current falls during V2G (the battery and PV supply
most of the load), the ratio‑based **THD** in the V2G window is inflated even
though the absolute harmonic content is unchanged. Compliance is therefore
reported as **TDD** (harmonics referenced to the maximum demand current), the
metric defined by IEEE Std 519. See `harmonic_diagnose.m` and Section 5.4 of the
paper.

## Citation

If you use this code, please cite the paper above.

## License

Released under the MIT License — see `LICENSE`.
