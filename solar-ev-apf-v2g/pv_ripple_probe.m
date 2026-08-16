%% pv_ripple_probe.m
%  The PSO study showed the gains do NOT move the THD (flat J landscape) and the
%  ablation showed the PV boost stage is the dominant harmonic source (PV off ->
%  THD ~4.5%, PV on -> ~9%). This probe tests whether enlarging the PV-side
%  filtering / DC-link decoupling brings the source-current THD below the
%  IEEE-519 5% limit -- using PARAMETER overrides only (no structural change).
%
%  It keeps the Table-3 gains fixed and sweeps: boost inductor Lboost, PV input
%  capacitor Cpv, DC-link capacitor Cdc, and the PCC ripple-filter cap Crf.
%
%  Output: results\Table_pv_ripple.csv  + a printed ranked summary.
%
%  Usage:  >> pv_ripple_probe

mdl = 'EVCS_APF_V2G';
if ~exist('results','dir'), mkdir('results'); end
if ~bdIsLoaded(mdl), load_system(mdl); end

trials = {
 'Nominal (baseline)'                 , struct() ;
 'Lboost 1.5->5 mH'                   , struct('Lboost',5e-3) ;
 'Lboost 1.5->8 mH'                   , struct('Lboost',8e-3) ;
 'Cpv 0.5->2 mF'                      , struct('Cpv',2000e-6) ;
 'Cdc 3->6 mF'                        , struct('Cdc',6000e-6) ;
 'Crf 20->60 uF'                      , struct('Crf',60e-6) ;
 'Lboost 5mH + Cpv 2mF'               , struct('Lboost',5e-3,'Cpv',2000e-6) ;
 'Lboost 8mH + Cpv 2mF + Cdc 6mF'     , struct('Lboost',8e-3,'Cpv',2000e-6,'Cdc',6000e-6) ;
 'Lboost 8mH + Cpv 2mF + Crf 60uF'    , struct('Lboost',8e-3,'Cpv',2000e-6,'Crf',60e-6) ;
 'Full: Lboost 8mH+Cpv 2mF+Cdc 6mF+Crf 60uF', struct('Lboost',8e-3,'Cpv',2000e-6,'Cdc',6000e-6,'Crf',60e-6) ;
};

n = size(trials,1);
THD = zeros(n,1); Verr = zeros(n,1); Vm = zeros(n,1);
fprintf('\n=== PV-RIPPLE PROBE (Table-3 gains fixed) ===\n');
for i = 1:n
    m = apf_metrics(mdl, trials{i,2});
    THD(i) = m.THD_worst; Verr(i) = m.Vdc_err; Vm(i) = m.Vdc_mean;
    fprintf('  %-42s  THD = %6.2f %%   %s\n', trials{i,1}, THD(i), ...
            ternary(THD(i)<5,'<-- PASS (<5%)',''));
end

T = table(string(trials(:,1)), round(THD,2), round(Vm,1), round(Verr,2), ...
    string(arrayfun(@(x) ternary(x<5,'PASS','fail'), THD, 'uni',0)), ...
    'VariableNames',{'Trial','THD_pct','Vdc_mean_V','Vdc_err_pct','IEEE519'});
writetable(T,'results\Table_pv_ripple.csv');
disp(T);

[best,ib] = min(THD);
fprintf('\nBest configuration: "%s"  ->  THD = %.2f %%  (%s)\n', ...
    trials{ib,1}, best, ternary(best<5,'clears 5%','still above 5%'));
if best < 5
    fprintf(['If you adopt this, set the listed values in model_params.m and update\n' ...
             'Table 1 accordingly, then re-run export_paper_figures and the analyses.\n']);
else
    fprintf(['Parameter changes alone did not reach 5%%. The next step is a structural\n' ...
             'fix (LC output filter on the boost + slower P&O perturbation). Ask for it.\n']);
end
fprintf('Saved results\\Table_pv_ripple.csv\n');

function s = ternary(c,a,b), if c, s=a; else, s=b; end, end
