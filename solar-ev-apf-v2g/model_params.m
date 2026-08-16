%% model_params.m
%  System, control and simulation parameters for the model
%  "Power Quality Improvement in Solar-Powered EV Charging Stations Using a
%   Metaheuristic-Tuned Active Power Filter with Vehicle-to-Grid Support"
%
%  Loaded automatically by the model (PreLoadFcn) and by all scripts.
%  All values follow Table 1 (system), Table 2 (PSO) and Table 3 (gains).

%% ---------------- Table 1 : system parameters ----------------
VLL      = 415;        % Grid line-to-line RMS voltage [V]
fgrid    = 50;         % Grid frequency [Hz]
Rs_src   = 0.1;        % Source resistance [ohm]
Ls_src   = 0.15e-3;    % Source inductance [H]
Ppv_rated= 25e3;       % PV array rated power [W]
Vdc_ref  = 750;        % Reference DC-link voltage [V] (headroom above the
                       %  586 V line peak so the APF can slew at rectifier
                       %  commutation edges; update Table 1 accordingly)
Cdc      = 3000e-6;    % DC-link capacitance [F]
Lf       = 1.5e-3;     % APF coupling inductance [H] (lower than the paper's
                       %  2.5 mH: needed to track the 40 kW rectifier's
                       %  commutation slopes; update Table 1 accordingly)
Vbatt    = 360;        % EV battery nominal voltage [V]
Qbatt    = 40;         % EV battery capacity [Ah]
fsw      = 10e3;       % Switching frequency (boost / EV converter PWM) [Hz]

%% ---------------- Loads ----------------
Rdc_nl   = 10;         % DC-side resistance of the diode-rectifier load [ohm]
Ldc_nl   = 20e-3;      % DC-side inductance of the diode-rectifier load [H]
Plin     = 10e3;       % Linear three-phase load, active power [W]
Qlin     = 2e3;        % Linear three-phase load, inductive reactive power [var]
% NOTE: total load (~40 kW) deliberately exceeds PV (~24 kW) so the grid
% carries meaningful current in BOTH G2V and V2G modes - otherwise the
% source fundamental -> 0 and THD% blows up as an artifact of the ratio.

%% ---------------- PV stage ----------------
Irr0     = 1000;       % Initial irradiance [W/m^2]
Irr1     = 700;        % Irradiance after step [W/m^2]
t_irr    = 0.20;       % Irradiance step time [s]
Tcell    = 25;         % Cell temperature [degC]
Lboost   = 1.5e-3;     % Boost inductor [H]
Cpv      = 500e-6;     % PV-side input capacitor [F]
Npar     = 10;         % Parallel strings   (SunPower SPR-305E ~ 305 W -> ~24.4 kW)
Nser     = 8;          % Series-connected modules per string (Vmp ~ 437 V)

%% ---------------- EV charger / V2G ----------------
SOC0     = 60;         % Initial battery state of charge [%]
Lev      = 5e-3;       % Charger inductor [H]
Rev      = 0.2;        % Charger inductor series resistance [ohm] (damping)
duty0    = 0.55;       % PI integrator initial duty (~Vbatt/Vdc equilibrium)
Iev_ref  = 20;         % Battery current reference magnitude [A] (+ = G2V charge)
t_v2g    = 0.30;       % Time of G2V -> V2G transition [s]
Kp_ev    = 0.01;       % Charger current-loop PI: with internal anti-windup,
Ki_ev    = 20;         %  duty0 init and Rev damping -> zeta ~ 0.45, ~5 ms settling
ev_enable  = 1;        % 1 = charger switches enabled, 0 = both IGBTs held off
ev_openloop= 0;        % 1 = fixed duty (duty_fix) instead of the PI loop
duty_fix   = 0.58;     % fixed duty used when ev_openloop = 1
iev_sign   = 1;        % current-sensor polarity seen by the PI (+1 or -1)

%% ---------------- Table 3 : optimised controller gains ----------------
Kp_dc    = 1.85;       % DC-link PI proportional gain (PSO-optimised)
Ki_dc    = 24.6;       % DC-link PI integral gain     (PSO-optimised)
HB       = 0.35;       % Hysteresis band [A]          (PSO-optimised)

%% ---------------- SRF control ----------------
tau_lpf  = 1/(2*pi*10);            % LPF time constant for i_d DC extraction [s]
HystSign = -1;                     % Hysteresis polarity (flip to +1 if THD worsens)
Kpu      = 1/(VLL*sqrt(2/3));      % abc -> per-unit gain for the PLL input

%% ---------------- Simulation ----------------
Ts       = 2e-6;                   % Discrete sample time (powergui) [s]
                                   % (also the hysteresis sampling rate - the
                                   %  dominant lever on residual THD; sim is
                                   %  ~2.5x slower than at 5e-6)
Rrf      = 5;                      % PCC ripple filter: series R [ohm]
Crf      = 20e-6;                  % PCC ripple filter: series C [F] (star to ground)
Tstop    = 0.5;                    % Simulation stop time [s]
alpha_lpf= Ts/(tau_lpf+Ts);        % Discrete LPF coefficient

%% ---------------- Table 2 : PSO settings (used by pso_tune.m) ----------------
pso.N    = 30;                     % Population size
pso.kmax = 100;                    % Maximum iterations
pso.wmax = 0.9;  pso.wmin = 0.4;   % Inertia weight 0.9 -> 0.4
pso.c1   = 2.0;  pso.c2   = 2.0;   % Cognitive / social coefficients
pso.w1   = 0.6;  pso.w2   = 0.4;   % Fitness weights: J = w1*THD + w2*int|Vdc*-Vdc|
pso.lb   = [0.2   2   0.05];       % Lower bounds  [Kp_dc  Ki_dc  HB]
pso.ub   = [5    80   0.80];       % Upper bounds  [Kp_dc  Ki_dc  HB]
pso.x0   = [1.85 24.6 0.35];       % Table-3 gains: baseline + swarm seed
