function best = pso_tune_short(N, kmax)
%PSO_TUNE_SHORT  Short, GENUINE PSO tuning of the APF gains (Eq. 19-20).
%
%  Fixes the two issues that made the original run produce a FLAT convergence
%  curve:
%    * the swarm now starts fully RANDOM (particle 1 is no longer pre-seeded
%      with the Table-3 gains), so early iterations are genuinely worse and the
%      best-so-far actually decreases;
%    * the global best starts at +inf and is discovered from the swarm.
%
%  Optimises x = [Kp_dc, Ki_dc, HB] by minimising  J = w1*THD + w2*eVdc
%  (Eq. 19), with FastRestart ON for speed.
%
%  Usage:
%     best = pso_tune_short            % default N=8, kmax=12  (~96 sims)
%     best = pso_tune_short(10,15)     % custom budget
%
%  Writes the best gains to the base workspace + optimized_gains.mat, and saves
%  results\Fig09_pso_convergence.png (a real decreasing curve).
%
%  NOTE ON EXPECTATIONS: on this model the PV boost stage is the dominant
%  harmonic source (disabling PV drops THD from ~9% to ~4.5%). PSO only tunes
%  Kp/Ki/HB, so it will improve on the un-tuned result but may plateau ABOVE 5%.
%  If it does, the remaining gap is PV ripple, not the gains -- ask for the
%  ripple-filter / MPPT-damping fix to close it.

if nargin < 1 || isempty(N),    N = 8;   end
if nargin < 2 || isempty(kmax), kmax = 12; end

mdl = 'EVCS_APF_V2G';
if ~exist('results','dir'), mkdir('results'); end
if ~bdIsLoaded(mdl)
    if exist([mdl '.slx'],'file'), load_system(mdl); else, build_apf_v2g_model; end
end
evalin('base','model_params');
pso     = evalin('base','pso');
Vdc_ref = evalin('base','Vdc_ref');
Tpso    = evalin('base','Tstop');          % full horizon incl. the V2G phase

set_param(mdl,'FastRestart','on');
ws = warning('off','all'); cleaner = onCleanup(@() postClean(mdl,ws));

lb = pso.lb; ub = pso.ub; D = numel(lb);
wmax = pso.wmax; wmin = pso.wmin; c1 = pso.c1; c2 = pso.c2;

rng('shuffle');
X  = lb + rand(N,D).*(ub-lb);              % fully random swarm (no x0 seed)
V  = zeros(N,D);
Pb = X;  Pbf = inf(N,1);
Gb = X(1,:);  Gbf = inf;                   % discovered from the swarm
hist = nan(kmax,1);

fprintf('\n=== SHORT PSO (N=%d, kmax=%d, %d evals) ===\n', N, kmax, N*kmax);
for k = 1:kmax
    w = wmax - (wmax-wmin)*(k-1)/max(kmax-1,1);
    for i = 1:N
        J = fitness(X(i,:));
        if J < Pbf(i), Pbf(i)=J; Pb(i,:)=X(i,:); end
        if J < Gbf,    Gbf=J;    Gb=X(i,:);      end
    end
    r1 = rand(N,D); r2 = rand(N,D);
    V = w*V + c1*r1.*(Pb-X) + c2*r2.*(Gb-X);
    X = min(max(X+V, lb), ub);
    hist(k) = Gbf;
    fprintf('  iter %2d/%d :  J=%.4f   Kp=%.3f Ki=%.2f HB=%.3f\n', ...
            k, kmax, Gbf, Gb(1), Gb(2), Gb(3));
end

best.Kp_dc=Gb(1); best.Ki_dc=Gb(2); best.HB=Gb(3); best.J=Gbf; best.history=hist;
assignin('base','Kp_dc',Gb(1)); assignin('base','Ki_dc',Gb(2)); assignin('base','HB',Gb(3));
save('optimized_gains.mat','best');
fprintf('\nBest gains:  Kp=%.3f  Ki=%.2f  HB=%.3f   (J=%.4f)\n', Gb(1),Gb(2),Gb(3),Gbf);
fprintf('Saved to optimized_gains.mat.  Run  >> run_all  or  export_paper_figures  to use them.\n');

% ---- proper convergence figure ----
h = hist(isfinite(hist));
fig = figure('Color','w','Position',[120 120 760 460]);
plot(1:numel(h), h, '-o','LineWidth',1.7,'Color',[0 0.45 0.74],'MarkerFaceColor',[0 0.45 0.74]);
grid on; xlabel('Iteration  k'); ylabel('Best fitness  J  (Eq. 19)');
title('Figure 9.  Convergence characteristic of the metaheuristic optimization algorithm','FontWeight','bold');
exportgraphics(fig,'results\Fig09_pso_convergence.png','Resolution',300);
try, exportgraphics(fig,'results\Fig09_pso_convergence.pdf','ContentType','vector'); catch, end
try, savefig(fig,'results\Fig09_pso_convergence.fig'); catch, end
fprintf('Saved results\\Fig09_pso_convergence.*\n');

% ================= nested fitness (same as pso_tune.m) =================
    function J = fitness(x)
        assignin('base','Kp_dc',x(1)); assignin('base','Ki_dc',x(2)); assignin('base','HB',x(3));
        try
            so  = sim(mdl,'StopTime',num2str(Tpso));
            thd = getv(so,'THD_log'); vdc = getv(so,'Vdc_log');
            mG = thd.Time>0.20 & thd.Time<0.29;
            mV = thd.Time>0.40;
            THDpct = max(100*mean(thd.Data(mG)), 100*mean(thd.Data(mV)));
            m2 = vdc.Time>0.1;
            eV = trapz(vdc.Time(m2), abs(Vdc_ref - vdc.Data(m2)))/(Tpso*Vdc_ref)*100;
            J  = pso.w1*THDpct + pso.w2*eV;
            if ~isfinite(J), J = 1e6; end
        catch e
            J = 1e6;
        end
    end
    function v = getv(so,name)
        try, v = so.(name); catch, v = evalin('base',name); end
    end
end

function postClean(mdl, ws)
try, set_param(mdl,'FastRestart','off'); catch, end
warning(ws);
end
