%% complexity_analysis.m
%  COMPUTATIONAL-COMPLEXITY analysis of the proposed metaheuristic-tuned APF.
%
%  Two parts:
%   (A) OFFLINE optimisation (PSO, Eq. 20): the cost is dominated by fitness
%       evaluations, each a full transient simulation. Number of evaluations
%       = N * kmax  (Table 2 -> 30 * 100 = 3000). This part measures the
%       wall-clock time of a single fitness simulation and how total tuning
%       time scales LINEARLY with population size N.
%   (B) ONLINE controller: per control step the SRF/PI/hysteresis law is O(1);
%       total online cost is O(fs_ctrl * T). A per-sample floating-point
%       operation budget is tabulated and compared with the Ts real-time slot.
%
%  Outputs: results\complexity_scaling.png , results\Table_complexity.csv
%
%  Usage:  >> complexity_analysis            % measured timing (a few sims)
%          >> complexity_analysis(true)      % QUICK: skip timing sweep, use 1 sim
%
%  DRAFT TEXT:
%  "The offline tuning has complexity O(N*kmax) fitness evaluations; with the
%   Table-2 settings this is 3000 transient simulations, an ONE-TIME design
%   cost. The resulting controller is O(1) per sample (a fixed Park transform,
%   one PI update and one hysteresis comparison), needing ~<F> flops per Ts and
%   thus running comfortably in real time."

function complexity_analysis(quick)
if nargin<1, quick=false; end
mdl = 'EVCS_APF_V2G';
if ~exist('results','dir'), mkdir('results'); end
if ~bdIsLoaded(mdl), load_system(mdl); end
evalin('base','model_params');                  % reset base to defaults (N, kmax, Ts...)

%% ---------- (A) offline PSO complexity ----------
pso = evalin('base','pso');  Ts = evalin('base','Ts');  Tstop = evalin('base','Tstop');

% time a single fitness evaluation (one transient simulation)
m1 = apf_metrics(mdl, struct());                % proposed case, timed
t_eval = m1.simtime;
fprintf('\n=== COMPLEXITY (A) offline PSO ===\n');
fprintf('  single fitness sim wall-clock : %.2f s\n', t_eval);
fprintf('  evaluations (Table 2 N*kmax)  : %d x %d = %d\n', pso.N, pso.kmax, pso.N*pso.kmax);
fprintf('  projected full-tuning time    : %.1f min\n', pso.N*pso.kmax*t_eval/60);

% scaling: total time vs population size (fixed short horizon = 1 iteration)
if quick
    Nlist = pso.N; Tmeas = t_eval*pso.N;
else
    Nlist = [5 10 20 30];
    Tmeas = zeros(size(Nlist));
    for j = 1:numel(Nlist)
        tt = 0;
        for p = 1:Nlist(j)                      % one iteration = N sims
            mm = apf_metrics(mdl, struct('Kp_dc', pso.lb(1)+rand*(pso.ub(1)-pso.lb(1))));
            tt = tt + mm.simtime;
        end
        Tmeas(j) = tt;
        fprintf('  N=%2d : one PSO iteration measured %.1f s\n', Nlist(j), tt);
    end
end

%% ---------- (B) online controller complexity ----------
% per control step (executed every Ts): operation budget (order-of-magnitude)
ops = { 'PLL / angle update'          , 8 ;
        'Park transform abc->dq (Eq.8)', 18;
        'LPF DC extraction (i_d)'      , 4 ;
        'DC-link PI (Eq.11)'           , 6 ;
        'Inverse transform / ref i_c'  , 18;
        'Hysteresis compare x3 (Eq.12)', 6 };
flops_step = sum(cell2mat(ops(:,2)));
fs_ctrl = 1/Ts;
flops_per_s = flops_step*fs_ctrl;
fprintf('\n=== COMPLEXITY (B) online controller ===\n');
fprintf('  flops / control step          : %d\n', flops_step);
fprintf('  control rate 1/Ts             : %.0f kHz\n', fs_ctrl/1e3);
fprintf('  online load                   : %.2f Mflops/s  (O(1) per sample)\n', flops_per_s/1e6);

%% ---------- table ----------
rowNames = [ops(:,1); {'TOTAL flops/step';'control rate [kHz]';'online [Mflops/s]'; ...
            'PSO evals (N*kmax)';'single sim [s]';'full tuning [min]'}];
vals = [cell2mat(ops(:,2)); flops_step; fs_ctrl/1e3; flops_per_s/1e6; ...
        pso.N*pso.kmax; t_eval; pso.N*pso.kmax*t_eval/60];
Tc = table(rowNames, round(vals,3), 'VariableNames',{'Metric','Value'});
writetable(Tc,'results\Table_complexity.csv');
disp(Tc);

%% ---------- figure: PSO time scales linearly with N ----------
fig = figure('Color','w','Position',[100 100 760 470]);
plot(Nlist, Tmeas,'-o','LineWidth',1.7,'Color',[0 0.45 0.74],'MarkerFaceColor',[0 0.45 0.74]);
grid on; hold on;
if numel(Nlist)>1
    p = polyfit(Nlist,Tmeas,1); xf=[0 max(Nlist)*1.05];
    plot(xf, polyval(p,xf),'--','Color',[0.5 0.5 0.5]);
    legend('measured','linear fit  O(N)','Location','northwest');
end
xlabel('Population size  N'); ylabel('Time for one PSO iteration  [s]');
title('Computational cost of the offline PSO tuning scales linearly with N','FontWeight','bold');
exportgraphics(fig,'results\complexity_scaling.png','Resolution',300);
try, exportgraphics(fig,'results\complexity_scaling.pdf','ContentType','vector'); catch, end
fprintf('Saved results\\complexity_scaling.png and results\\Table_complexity.csv\n');
end
