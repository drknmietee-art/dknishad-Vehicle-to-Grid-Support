function best = pso_tune(quick)
%PSO_TUNE  Metaheuristic (PSO) tuning of the APF controller (Eq. 19-20).
%
%  Optimises x = [Kp_dc, Ki_dc, HB] by minimising the multi-objective
%  fitness of Eq. (19):
%
%       J = w1 * THD_i  +  w2 * int |Vdc* - Vdc| dt
%
%  using the particle-swarm update of Eq. (20) with the Table-2 settings
%  (N = 30, kmax = 100, w: 0.9->0.4, c1 = c2 = 2, w1 = 0.6, w2 = 0.4).
%
%  Usage:
%     best = pso_tune          % QUICK demo run (6 particles, 8 iterations)
%     best = pso_tune(false)   % FULL Table-2 run (30 x 100 = 3000 sims - slow!)
%
%  The best gains are written to the base workspace (used by the model),
%  printed, and saved to optimized_gains.mat.

if nargin < 1, quick = true; end

evalin('base','model_params');      % model dialogs resolve from base workspace
pso     = evalin('base','pso');     % Table-2 settings (static workspace: fetch
Vdc_ref = evalin('base','Vdc_ref'); %  values instead of running the script here)
mdl = 'EVCS_APF_V2G';

if ~bdIsLoaded(mdl)
    if exist([mdl '.slx'],'file'), load_system(mdl);
    else, build_apf_v2g_model;
    end
end
set_param(mdl,'FastRestart','on');

% ---------------- PSO settings (Table 2) ----------------
if quick
    N = 6;  kmax = 8;
    fprintf('QUICK mode: N=%d, kmax=%d. Use pso_tune(false) for the full Table-2 run.\n',N,kmax);
else
    N = pso.N;  kmax = pso.kmax;
end
wmax = pso.wmax;  wmin = pso.wmin;
c1 = pso.c1;      c2 = pso.c2;
lb = pso.lb;      ub = pso.ub;
Tpso = 0.5;                          % full horizon: must include the V2G phase!
                                     % (a shorter horizon made PSO pick gains
                                     %  that only work in G2V)

% ---------------- baseline sanity check (Table-3 gains) ----------------
%  If even the known-good gains produce a huge J, the fitness evaluation
%  itself is broken (logging, sim errors) - abort instead of "optimising"
%  noise and saving garbage gains.
x0 = pso.x0;
J0 = fitness(x0);
fprintf('Baseline (Table 3, Kp=%.2f Ki=%.1f HB=%.2f):  J0 = %.4f\n', x0(1), x0(2), x0(3), J0);
if ~isfinite(J0) || J0 > 50
    set_param(mdl,'FastRestart','off');
    error(['Baseline fitness J0 = %.3g is invalid -> the fitness evaluation is\n' ...
           'broken (check THD_log / Vdc_log and any warnings above). Not tuning.'], J0);
end

% ---------------- initialise swarm ----------------
rng('shuffle');
D  = numel(lb);
X  = lb + rand(N,D).*(ub-lb);        % positions  [Kp Ki HB]
X(1,:) = x0;                         % seed particle 1 with the paper's gains
V  = zeros(N,D);                     % velocities
Pb = X;  Pbf = inf(N,1);             % personal bests
Gb = x0;  Gbf = J0;                  % global best starts at the baseline
hist = nan(kmax,1);

% ---------------- main loop (Eq. 20) ----------------
for k = 1:kmax
    w = wmax - (wmax-wmin)*(k-1)/max(kmax-1,1);   % inertia 0.9 -> 0.4
    for i = 1:N
        J = fitness(X(i,:));
        if J < Pbf(i), Pbf(i) = J; Pb(i,:) = X(i,:); end
        if J < Gbf,    Gbf    = J; Gb      = X(i,:); end
    end
    r1 = rand(N,D);  r2 = rand(N,D);
    V = w*V + c1*r1.*(Pb - X) + c2*r2.*(Gb - X);
    X = X + V;
    X = min(max(X, lb), ub);                       % clamp to bounds
    hist(k) = Gbf;
    fprintf('Iter %3d/%d :  J = %.4f   Kp = %.3f  Ki = %.2f  HB = %.3f\n', ...
            k, kmax, Gbf, Gb(1), Gb(2), Gb(3));
end
set_param(mdl,'FastRestart','off');

% ---------------- results ----------------
best.Kp_dc = Gb(1);  best.Ki_dc = Gb(2);  best.HB = Gb(3);  best.J = Gbf;
best.J_baseline = J0;  best.history = hist;
assignin('base','Kp_dc',best.Kp_dc);
assignin('base','Ki_dc',best.Ki_dc);
assignin('base','HB',   best.HB);
if Gbf <= J0
    save('optimized_gains.mat','best');
    fprintf('Improved on the Table-3 baseline (J %.4f -> %.4f) - gains saved.\n', J0, Gbf);
else
    if exist('optimized_gains.mat','file'), delete('optimized_gains.mat'); end
    fprintf('No improvement over the baseline - keeping Table-3 gains (stale file removed).\n');
end

figure('Name','PSO convergence (cf. Fig. 9)');
plot(hist,'LineWidth',1.5); grid on;
xlabel('Iteration'); ylabel('Fitness J (Eq. 19)');
title('Convergence of the metaheuristic optimization');
saveas(gcf,'pso_convergence.png');

fprintf('\nOptimised gains (cf. Table 3):  Kp = %.3f  Ki = %.2f  HB = %.3f  (J = %.4f)\n', ...
        Gb(1), Gb(2), Gb(3), Gbf);
fprintf('Saved to optimized_gains.mat. Run  >> run_all  to simulate with them.\n');

% =================================================================
    function J = fitness(x)
        % Eq. (19): J = w1*THD + w2*int|Vdc*-Vdc|dt   (per-unit weighted)
        assignin('base','Kp_dc',x(1));
        assignin('base','Ki_dc',x(2));
        assignin('base','HB',   x(3));
        try
            simOut = sim(mdl,'StopTime',num2str(Tpso));
            thd = getLog(simOut,'THD_log');
            vdc = getLog(simOut,'Vdc_log');
            % worst-mode THD: evaluate G2V (0.20-0.29 s) and V2G (0.40-0.50 s)
            % separately and take the worse one, so both modes must comply
            mG = thd.Time > 0.20 & thd.Time < 0.29;
            mV = thd.Time > 0.40;
            THDpct = max(100*mean(thd.Data(mG)), 100*mean(thd.Data(mV)));
            % normalised DC-link voltage error integral
            m2  = vdc.Time > 0.1;
            eV  = trapz(vdc.Time(m2), abs(Vdc_ref - vdc.Data(m2))) / (Tpso*Vdc_ref) * 100;
            J   = pso.w1*THDpct + pso.w2*eV;
            if ~isfinite(J), J = 1e6; end
        catch err
            warning('Simulation failed for x=[%.3g %.3g %.3g]: %s', x(1),x(2),x(3),err.message);
            J = 1e6;                    % penalise infeasible candidates
        end
    end

    function ts = getLog(simOut, name)
        % robust retrieval of a To-Workspace timeseries
        try
            ts = simOut.(name);
        catch
            ts = evalin('base', name);
        end
    end
end
