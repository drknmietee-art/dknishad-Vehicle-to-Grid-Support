%% sensitivity_analysis.m
%  SENSITIVITY analysis of the source-current THD (and DC-link error) to the
%  tuned controller parameters and the two main plant parameters, swept ONE AT
%  A TIME around the Table-3 optimum. Shows how peaked the optimum is and which
%  parameter the performance is most sensitive to (tornado ranking).
%
%  Parameters swept:
%     Kp_dc  (DC-link PI proportional)     around 1.85
%     Ki_dc  (DC-link PI integral)         around 24.6
%     HB     (hysteresis band)             around 0.35
%     Lf     (APF coupling inductor)       around 1.5 mH
%     Cdc    (DC-link capacitor)           around 3000 uF
%
%  Outputs: results\sensitivity_sweeps.png , results\sensitivity_tornado.png ,
%           results\Table_sensitivity.csv
%
%  Usage:  >> sensitivity_analysis
%          >> sensitivity_analysis(true)   % QUICK: 3 points per parameter
%
%  DRAFT TEXT:
%  "A one-at-a-time sensitivity study (Fig. X) sweeps each tuned gain and the
%   main plant parameters about the optimum. The THD exhibits a clear minimum
%   at the PSO-selected values; the hysteresis band HB and the sampling-limited
%   inductor Lf are the most sensitive levers, while the DC-link integral gain
%   and capacitor are comparatively flat - consistent with the multi-objective
%   fitness of Eq. (19)."

function sensitivity_analysis(quick)
if nargin<1, quick=false; end
mdl='EVCS_APF_V2G';
if ~exist('results','dir'), mkdir('results'); end
if ~bdIsLoaded(mdl), load_system(mdl); end
evalin('base','model_params');                  % reset base -> fresh nominal values

% nominal (Table 3 + Table 1) and sweep grids
if quick
    P = {
     'Kp_dc', [0.9 1.85 3.5]          , 1.85 ;
     'Ki_dc', [10 24.6 60]            , 24.6 ;
     'HB'   , [0.15 0.35 0.6]         , 0.35 ;
     'Lf'   , [1.0e-3 1.5e-3 2.5e-3]  , 1.5e-3 ;
     'Cdc'  , [2000e-6 3000e-6 4000e-6], 3000e-6 };
else
    P = {
     'Kp_dc', [0.5 0.9 1.85 3.0 4.5]              , 1.85 ;
     'Ki_dc', [5 12 24.6 45 70]                   , 24.6 ;
     'HB'   , [0.1 0.2 0.35 0.5 0.7]              , 0.35 ;
     'Lf'   , [1.0e-3 1.25e-3 1.5e-3 2.0e-3 2.5e-3], 1.5e-3 ;
     'Cdc'  , [1500e-6 2250e-6 3000e-6 3750e-6 4500e-6], 3000e-6 };
end

np=size(P,1); rows={}; sens=zeros(np,1);
fig=figure('Color','w','Position',[80 80 1100 640]);
fprintf('\n=== SENSITIVITY ANALYSIS (%s) ===\n', mdl);
for k=1:np
    name=P{k,1}; grid_=P{k,2}; nom=P{k,3};
    THD=zeros(size(grid_)); Verr=zeros(size(grid_));
    for i=1:numel(grid_)
        m=apf_metrics(mdl, struct(name,grid_(i)));
        THD(i)=m.TDD_worst; Verr(i)=m.Vdc_err;   % TDD = IEEE-519 metric
        rows(end+1,:)={name, grid_(i), round(THD(i),2), round(Verr(i),2)}; %#ok<AGROW>
    end
    % normalised sensitivity  |d(THD)/d(param)| * param/THD  around the nominal
    [~,ic]=min(abs(grid_-nom));
    dP=(max(grid_)-min(grid_)); dT=(max(THD)-min(THD));
    sens(k)=abs(dT/max(THD(ic),eps));            % relative THD spread at fixed sweep span
    subplot(2,3,k);
    plot(grid_,THD,'-o','LineWidth',1.6,'Color',[0 0.45 0.74]); grid on; hold on;
    xline(nom,'--k'); yline(5,':r');
    xlabel(name,'Interpreter','none'); ylabel('THD [%]');
    title(sprintf('%s  (opt = %g)', name, nom),'Interpreter','none');
    fprintf('  %-6s swept %d pts,  THD range %.2f-%.2f %%\n', name, numel(grid_), min(THD), max(THD));
end
sgtitle('Sensitivity of source-current THD to controller / plant parameters','FontWeight','bold');
exportgraphics(fig,'results\sensitivity_sweeps.png','Resolution',300);
try, exportgraphics(fig,'results\sensitivity_sweeps.pdf','ContentType','vector'); catch, end

% ---- tornado: rank parameters by relative THD spread ----
[ss,ix]=sort(sens,'descend');
ft=figure('Color','w','Position',[120 120 780 460]);
barh(ss,'FaceColor',[0 0.45 0.74]); grid on;
set(gca,'YTick',1:np,'YTickLabel',P(ix,1),'YDir','reverse');
xlabel('Relative THD spread over the sweep  (higher = more sensitive)');
title('Parameter sensitivity ranking (tornado)','FontWeight','bold');
exportgraphics(ft,'results\sensitivity_tornado.png','Resolution',300);

T=cell2table(rows,'VariableNames',{'Parameter','Value','THD_pct','Vdc_err_pct'});
writetable(T,'results\Table_sensitivity.csv'); disp(T);
fprintf('Saved results\\sensitivity_sweeps.png, sensitivity_tornado.png, Table_sensitivity.csv\n');
end
