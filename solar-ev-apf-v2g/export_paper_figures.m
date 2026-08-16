%% export_paper_figures.m
%  ONE-SHOT RESULT EXPORTER for the paper
%  "Power Quality Improvement in Solar-Powered EV Charging Stations Using a
%   Metaheuristic-Tuned Active Power Filter with Vehicle-to-Grid Support".
%
%  Simulates  EVCS_APF_V2G.slx  and writes EVERY figure that is a
%  simulation / data RESULT (as named in the paper's figure captions) to the
%  .\results\ folder, each as a 300-dpi PNG, a vector PDF and a MATLAB .fig:
%
%     Fig. 3   PV array I-V and P-V characteristics under varying irradiance
%              and temperature.
%     Fig. 9   Convergence characteristic of the metaheuristic optimization
%              algorithm.
%     Fig. 10  Source and load current waveforms before and after compensation.
%     Fig. 11  Harmonic-spectrum (THD) comparison with and without the proposed
%              APF.
%     Fig. 12  DC-link voltage regulation and V2G active-power exchange profile.
%     Fig. 13  Comparative performance (THD) of the proposed method versus
%              state-of-the-art techniques.
%
%  (Figures 1, 2, 4, 5, 6, 7 and 8 are hand-drawn schematics / flowcharts, not
%   simulation output. The optional last section snapshots the Simulink canvas
%   so you have a model diagram alongside them.)
%
%  It also writes  results\Table4_THD.csv  and  results\metrics.txt.
%
%  USAGE (from the MATLAB_Simulink_Model folder, MATLAB R2024b + Simscape
%  Electrical):
%
%       >> export_paper_figures                    % simulate EVCS_APF_V2G, export all
%       >> export_paper_figures('nosim')           % reuse logs already in the base
%                                                  %   workspace (skip re-simulating)
%       >> export_paper_figures('sim','EVCS_APF_V2G')   % explicit model name
%
%  ---------------------------------------------------------------------------
function export_paper_figures(mode, mdlName)
if nargin < 1 || isempty(mode),    mode    = 'sim';           end
if nargin < 2 || isempty(mdlName), mdlName = 'EVCS_APF_V2G';  end   % correct model
runSim = ~strcmpi(mode,'nosim');

mdl    = mdlName;                            % <-- EVCS_APF_V2G by default
outdir = 'results';
if ~exist(outdir,'dir'), mkdir(outdir); end

model_params;                               % Table 1/2/3 parameters into scope

%% ---------------------------------------------------------------- 1. simulate
if runSim
    if ~bdIsLoaded(mdl)
        if exist([mdl '.slx'],'file'), load_system(mdl);
        else, error('%s.slx not found in %s', mdl, pwd);
        end
    end
    fprintf('Simulating %s for %g s (Ts = %g s)...\n', mdl, Tstop, Ts);
    simOut = sim(mdl,'StopTime',num2str(Tstop));
else
    simOut = [];                            % pull the logs from base workspace
    fprintf('nosim: reusing existing *_log timeseries from the base workspace.\n');
end

isL = getLog(simOut,'is_log');    % source currents  (after compensation)
iLL = getLog(simOut,'iL_log');    % load currents    (= source before comp.)
vdc = getLog(simOut,'Vdc_log');   % DC-link voltage
thd = getLog(simOut,'THD_log');   % on-line source-current THD (phase a)
iev = getLog(simOut,'Iev_log');   % EV battery current (+G2V / -V2G)

%% ============================================================================
%% Figure 10 : Source and load current waveforms before and after compensation
%% ============================================================================
tL = iLL.Time;  IL = orient(iLL.Data, numel(tL));
tS = isL.Time;  IS = orient(isL.Data, numel(tS));
win = [0.24 0.30];                          % 3 fundamental cycles, steady state
f10 = figure('Name','Fig.10','Color','w','Position',[60 60 940 560]);
subplot(2,1,1);
plot(tL, IL,'LineWidth',1); grid on; xlim(win);
ylabel('i_L  [A]');
title('Load currents  —  before compensation (nonlinear, distorted)');
subplot(2,1,2);
plot(tS, IS,'LineWidth',1); grid on; xlim(win);
ylabel('i_s  [A]'); xlabel('Time  [s]');
title('Source currents  —  after metaheuristic-tuned APF compensation');
sgtitle('Figure 10.  Source and load current waveforms before and after compensation','FontWeight','bold');
saveAll(f10, outdir, 'Fig10_source_load_currents');

%% ============================================================================
%% Figure 11 : Harmonic-spectrum (THD) comparison with and without the APF
%%   "without APF" = spectrum of the load current (what the source would carry)
%%   "with  APF"   = spectrum of the actual source current
%% ============================================================================
Hmax = 15;                                  % harmonics to display
[hno, THDno] = harmonicSpectrum(tL, IL(:,1), fgrid, Ts, Hmax);   % before
[hwi, THDwi] = harmonicSpectrum(tS, IS(:,1), fgrid, Ts, Hmax);   % after
f11 = figure('Name','Fig.11','Color','w','Position',[80 80 940 520]);
hb = bar(2:Hmax, [hno(2:end); hwi(2:end)]', 'grouped'); grid on;
hb(1).FaceColor = [0.85 0.33 0.10];  hb(2).FaceColor = [0.00 0.45 0.74];
legend(sprintf('Without APF  (THD = %.1f%%)',THDno), ...
       sprintf('With proposed APF  (THD = %.2f%%)',THDwi),'Location','northeast');
xlabel('Harmonic order  h'); ylabel('Magnitude  [% of fundamental]');
title('Figure 11.  Harmonic-spectrum (THD) comparison with and without the proposed APF','FontWeight','bold');
saveAll(f11, outdir, 'Fig11_harmonic_spectrum');

%% ============================================================================
%% Figure 12 : DC-link voltage regulation and V2G active-power exchange profile
%% ============================================================================
Pev = vdc.Data(:) .* resampleTo(iev, vdc.Time) / 1e3;    % EV DC power  [kW]
f12 = figure('Name','Fig.12','Color','w','Position',[100 100 940 560]);
subplot(2,1,1);
plot(vdc.Time, vdc.Data,'LineWidth',1.1); grid on; hold on;
yline(Vdc_ref,'--r',sprintf('V_{dc}^* = %g V',Vdc_ref));
ylabel('V_{dc}  [V]');
title('DC-link voltage regulation (Eq. 5, 11)');
subplot(2,1,2);
plot(vdc.Time, Pev,'LineWidth',1.1); grid on; hold on;
yline(0,'k-'); xline(t_v2g,'--k',sprintf('G2V \\rightarrow V2G  (t = %.2f s)',t_v2g));
ylabel('P_{ev}  [kW]'); xlabel('Time  [s]');
title('EV active-power exchange:  + charging (G2V),  - discharging (V2G)');
sgtitle('Figure 12.  DC-link voltage regulation and V2G active-power exchange profile','FontWeight','bold');
saveAll(f12, outdir, 'Fig12_dclink_v2g');

%% ============================================================================
%% Figure 3 : PV array I-V and P-V characteristics (single-diode model, Eq. 1-2)
%%   Generated analytically from the array configuration in model_params.m so it
%%   does not depend on the time-domain run.
%% ============================================================================
f3 = plotPVcharacteristics(Npar, Nser);
saveAll(f3, outdir, 'Fig03_PV_IV_PV_characteristics');

%% ============================================================================
%% Figure 9 : Convergence characteristic of the metaheuristic optimization
%%   Uses the J-history saved by pso_tune.m (optimized_gains.mat -> best.history).
%%   If none exists yet, a quick PSO run is offered to generate it.
%% ============================================================================
Jhist = [];
if exist('optimized_gains.mat','file')
    S = load('optimized_gains.mat');
    if isfield(S,'best') && isfield(S.best,'history'), Jhist = S.best.history(:); end
end
if isempty(Jhist)
    warning(['No PSO convergence history found (optimized_gains.mat / best.history). ', ...
             'Run  >> pso_tune  (or pso_tune(false) for the full Table-2 run) first, ', ...
             'then re-run this exporter. Skipping Figure 9.']);
else
    Jhist = Jhist(isfinite(Jhist));
    f9 = figure('Name','Fig.9','Color','w','Position',[120 120 760 460]);
    plot(1:numel(Jhist), Jhist,'-o','LineWidth',1.6,'MarkerSize',4); grid on;
    xlabel('Iteration  k'); ylabel('Best fitness  J  (Eq. 19)');
    title('Figure 9.  Convergence characteristic of the metaheuristic optimization algorithm','FontWeight','bold');
    saveAll(f9, outdir, 'Fig09_pso_convergence');
end

%% ============================================================================
%% Figure 13 : Comparative performance (THD) vs state-of-the-art techniques
%%   Proposed values come from Table 4 (worst-mode = 3.6%, best = 2.9%).
%%   Edit the SOTA list below with the reported source-current THDs of the
%%   comparison references to make this a full "versus SOTA" chart.
%% ============================================================================
% --- editable comparison data (method , reported THD %) ---------------------
sota = { 'Proposed (V2G, worst)', 3.6 ; ...
         'Proposed (balanced)',   2.9 ; ...
         'DVR ANN+fuzzy [14]',    4.94; ...   % documented in the paper's text
         'IEEE-519 limit',        5.0 };
% ---------------------------------------------------------------------------
names = sota(:,1);  vals = cell2mat(sota(:,2));
[vals, ix] = sort(vals); names = names(ix);
f13 = figure('Name','Fig.13','Color','w','Position',[140 140 900 500]);
b = barh(vals); grid on; b.FaceColor = 'flat';
for k = 1:numel(vals)
    if contains(names{k},'Proposed'), b.CData(k,:) = [0.00 0.45 0.74];
    elseif contains(names{k},'IEEE'), b.CData(k,:) = [0.85 0.33 0.10];
    else,                             b.CData(k,:) = [0.60 0.60 0.60];
    end
    text(vals(k)+0.05, k, sprintf('%.2f%%',vals(k)),'VerticalAlignment','middle');
end
set(gca,'YTick',1:numel(names),'YTickLabel',names);
xline(5,'--r'); xlabel('Source-current THD  [%]');
title('Figure 13.  Comparative performance (THD) of the proposed method versus state-of-the-art techniques','FontWeight','bold');
saveAll(f13, outdir, 'Fig13_comparative_THD');

%% ---------------------------------------------------- Table 4 + metrics files
mG2V = thd.Time > 0.20 & thd.Time < 0.29;   % G2V steady state
mV2G = thd.Time > 0.40;                      % V2G steady state
THDg2v = 100*mean(thd.Data(mG2V));
THDv2g = 100*mean(thd.Data(mV2G));
THDss  = max(THDg2v, THDv2g);
Vdc_mean = mean(vdc.Data(vdc.Time > 0.1));

T = cell2table({ 'G2V (charging)' , round(THDno,1) , round(THDg2v,2) ; ...
                 'V2G (discharging)', round(THDno,1) , round(THDv2g,2) }, ...
      'VariableNames',{'OperatingMode','THD_withoutAPF_pct','THD_withAPF_pct'});
writetable(T, fullfile(outdir,'Table4_THD.csv'));

fid = fopen(fullfile(outdir,'metrics.txt'),'w');
fprintf(fid,'Model                          : %s\n', mdl);
fprintf(fid,'Source-current THD, G2V mode   : %.2f %%\n', THDg2v);
fprintf(fid,'Source-current THD, V2G mode   : %.2f %%\n', THDv2g);
fprintf(fid,'Worst-mode THD (compliance)    : %.2f %%  (%s)\n', THDss, ...
        ternary(THDss<5,'IEEE-519 SATISFIED','IEEE-519 NOT met - run pso_tune'));
fprintf(fid,'Mean DC-link voltage (t>0.1s)  : %.1f V  (ref %g V)\n', Vdc_mean, Vdc_ref);
fclose(fid);

fprintf('\n================ RESULTS ================\n');
fprintf('THD  G2V / V2G / worst          : %.2f / %.2f / %.2f %%\n', THDg2v, THDv2g, THDss);
fprintf('IEEE-519 5%% limit               : %s\n', ternary(THDss<5,'SATISFIED','NOT met'));
fprintf('Mean DC-link voltage            : %.1f V (ref %g V)\n', Vdc_mean, Vdc_ref);
fprintf('All figures + tables written to : .\\%s\\\n', outdir);
fprintf('=========================================\n');

%% -------------------------------------------- OPTIONAL: schematic model canvas
%  Figs 1,2,4,5,6,7,8 are drawn schematics; this just snapshots the model.
try
    if ~bdIsLoaded(mdl), load_system(mdl); end
    print(['-s' mdl], '-dpng', '-r200', fullfile(outdir,'Model_canvas_snapshot.png'));
    fprintf('Model canvas snapshot        : .\\%s\\Model_canvas_snapshot.png\n', outdir);
catch e
    fprintf('(model canvas snapshot skipped: %s)\n', e.message);
end
end % ======================================================= end main function


%% =========================== local helper functions =========================
function ts = getLog(simOut, name)
% robust retrieval of a To-Workspace timeseries (from simOut or base workspace)
if ~isempty(simOut)
    try, ts = simOut.(name); return; catch, end
    try, ts = simOut.get(name); return; catch, end
end
ts = evalin('base', name);
end

function M = orient(D, n)
% squeeze To-Workspace data to an  n x nCh  matrix
D = squeeze(D);
if size(D,1) ~= n && size(D,2) == n, D = D.'; end
M = D;
end

function y = resampleTo(ts, t)
% linear resample of timeseries ts onto time vector t (column vector out)
y = interp1(ts.Time, double(ts.Data(:)), t, 'linear', 'extrap');
y = y(:);
end

function [Hpct, THDpct] = harmonicSpectrum(t, x, f0, Ts, Hmax)
% single-sided harmonic magnitudes (% of fundamental) over an integer number
% of fundamental cycles, plus the THD.
x = double(x(:));
% restrict to a steady-state window of whole cycles
i0 = find(t >= 0.24, 1, 'first');
Ncyc = 4; N = round(Ncyc/f0/Ts);
if isempty(i0) || i0+N-1 > numel(x), i0 = max(1, numel(x)-N+1); end
seg = x(i0:i0+N-1);
seg = seg - mean(seg);                       % drop DC
X = abs(fft(seg))/N * 2;                      % single-sided magnitude
df = 1/(N*Ts);
Hpct = zeros(1,Hmax);
mags = zeros(1,Hmax);
for h = 1:Hmax
    k = round(h*f0/df) + 1;                   % bin for harmonic h
    if k <= numel(X), mags(h) = X(k); end
end
fund = max(mags(1), eps);
Hpct = 100*mags/fund;
THDpct = 100*sqrt(sum(mags(2:end).^2))/fund;
end

function fig = plotPVcharacteristics(Npar, Nser)
% SunPower SPR-305E-WHT-D single-diode model (Eq. 1-2), array = Npar x Nser.
% Temperature-dependent saturation current so Voc (and power) drop with T.
q=1.602e-19; kB=1.381e-23; ncell=96; a=1.3; Eg=1.12; Tstc=298.15;
Iph_stc=6.14; I0_stc=9.8e-11; Rs=0.35; Rsh=270;
Vt  = @(T)(a*kB*T*ncell)/q;
Iph = @(G,T)(Iph_stc + 0.0032*(T-Tstc)).*G/1000;
I0  = @(T) I0_stc*(T/Tstc).^3 .* exp((q*Eg/(a*kB))*(1/Tstc - 1./T));

% sweep range from the array open-circuit voltage at STC
Voc_mod = pvModuleVoc(Iph(1000,Tstc), I0(Tstc), Rs, Rsh, Vt(Tstc));
V = linspace(0, 1.03*Nser*Voc_mod, 500);

cols = [0.00 0.45 0.74; 0.85 0.33 0.10; 0.47 0.67 0.19; 0.85 0.11 0.11];
cond = {1000,Tstc,'-'; 700,Tstc,'-'; 500,Tstc,'-'; 1000,323.15,'--'};
lg = {'1000 W/m^2, 25\circC','700 W/m^2, 25\circC','500 W/m^2, 25\circC','1000 W/m^2, 50\circC'};

fig = figure('Name','Fig.3','Color','w','Position',[100 100 980 460]);
ax1 = subplot(1,2,1); hold on; grid on;
ax2 = subplot(1,2,2); hold on; grid on;
Pmx = 0;
for j = 1:size(cond,1)
    [Ia,Pa] = pvArrayCurve(V, Iph(cond{j,1},cond{j,2}), I0(cond{j,2}), Rs, Rsh, Vt(cond{j,2}), Npar, Nser);
    plot(ax1, V, Ia,   cond{j,3},'LineWidth',1.7,'Color',cols(j,:));
    plot(ax2, V, Pa/1e3,cond{j,3},'LineWidth',1.7,'Color',cols(j,:));
    Pmx = max(Pmx, max(Pa)/1e3);
end
xlabel(ax1,'V_{pv}  [V]'); ylabel(ax1,'I_{pv}  [A]'); title(ax1,'I-V characteristics');
legend(ax1,lg,'Location','northeast'); xlim(ax1,[0 V(end)]); ylim(ax1,[0 inf]);
xlabel(ax2,'V_{pv}  [V]'); ylabel(ax2,'P_{pv}  [kW]'); title(ax2,'P-V characteristics');
legend(ax2,lg,'Location','northwest'); xlim(ax2,[0 V(end)]); ylim(ax2,[0 Pmx*1.12]);
sgtitle('Figure 3.  PV array I-V and P-V characteristics under varying irradiance and temperature','FontWeight','bold');
end

function Voc = pvModuleVoc(Iph, I0, Rs, Rsh, Vt)
% bisection for the module open-circuit voltage (module current -> 0)
lo = 0; hi = 200;
for k = 1:80
    mid = (lo+hi)/2;
    if pvModuleI(mid, Iph, I0, Rs, Rsh, Vt) > 0, lo = mid; else, hi = mid; end
end
Voc = lo;
end

function I = pvModuleI(v, Iph, I0, Rs, Rsh, Vt)
I = Iph;
for it = 1:100
    ex = exp(min(max((v+I*Rs)/Vt,-40),40));
    f  = Iph - I0*(ex-1) - (v+I*Rs)/Rsh - I;
    df = -I0*(Rs/Vt)*ex - Rs/Rsh - 1;
    I  = I - f/df;
end
I = max(I,0);
end

function [Iarr,Parr] = pvArrayCurve(Varr, Iph, I0, Rs, Rsh, Vt, Npar, Nser)
% array I-V by scaling a single-module implicit single-diode solve
Imod = zeros(size(Varr));
for i = 1:numel(Varr)
    Imod(i) = pvModuleI(Varr(i)/Nser, Iph, I0, Rs, Rsh, Vt);
end
Iarr = Imod*Npar;  Parr = Varr.*Iarr;
end

function saveAll(fig, outdir, tag)
% write PNG (300 dpi) + vector PDF + .fig
png = fullfile(outdir,[tag '.png']);
pdf = fullfile(outdir,[tag '.pdf']);
try
    exportgraphics(fig, png, 'Resolution', 300);
    exportgraphics(fig, pdf, 'ContentType','vector');
catch
    saveas(fig, png); saveas(fig, pdf);        % older releases
end
try, savefig(fig, fullfile(outdir,[tag '.fig'])); catch, end
fprintf('  saved  %s  (.png/.pdf/.fig)\n', tag);
end

function s = ternary(c,a,b), if c, s=a; else, s=b; end, end
