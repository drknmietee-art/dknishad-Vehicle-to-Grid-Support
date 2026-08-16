function m = apf_metrics(mdl, ov, opts)
%APF_METRICS  Run ONE case of the APF model and return power-quality metrics.
%
%  Shared engine for ablation_study / complexity_analysis / robustness_analysis
%  / sensitivity_analysis. It (1) resets the base workspace to the model_params
%  defaults, (2) applies the field/value overrides in struct OV, (3) re-derives
%  the dependent constants, (4) simulates, and (5) extracts metrics.
%
%  INPUTS
%     mdl   : model name (default 'EVCS_APF_V2G')
%     ov    : struct of base-workspace overrides, e.g. struct('Lf',2e-3,'HB',0.5)
%     opts  : struct, optional:
%               .Tstop   simulation stop time  (default = base Tstop)
%               .Hmax    harmonics for the load-current FFT (default 15)
%
%  OUTPUT struct m:
%     m.THD_g2v   source-current THD in the G2V window   [%]
%     m.THD_v2g   source-current THD in the V2G window   [%]
%     m.THD_worst max(THD_g2v, THD_v2g)                  [%]
%     m.THD_load  load-current THD (i.e. "without APF")  [%]
%     m.Vdc_mean  mean DC-link voltage (t>0.1 s)         [V]
%     m.Vdc_err   normalised DC-link error integral      [%]  (Eq. 19 term)
%     m.PF        distortion power factor  = 1/sqrt(1+(THD/100)^2)
%     m.J         fitness  w1*THD_worst + w2*Vdc_err      (Eq. 19)
%     m.simtime   wall-clock simulation time             [s]
%     m.ok        true if the run produced finite metrics
%
%  The model reads its parameters from the BASE workspace, so keep the model
%  LOADED across calls (this function assumes the caller did load_system once);
%  it will load it if necessary. FastRestart is left OFF so structural
%  parameters (Lf, Cdc, ...) recompile each run.

if nargin < 1 || isempty(mdl), mdl = 'EVCS_APF_V2G'; end
if nargin < 2 || isempty(ov),  ov  = struct();       end
if nargin < 3, opts = struct(); end
if ~isfield(opts,'Hmax'), opts.Hmax = 15; end

% ---- load model once, defaults into base ----
if ~bdIsLoaded(mdl)
    if exist([mdl '.slx'],'file'), load_system(mdl);
    else, error('%s.slx not found on the path (cd to MATLAB_Simulink_Model).', mdl);
    end
end
set_param(mdl,'FastRestart','off');
bumpTransportDelayBuffers(mdl);                % silence "buffer too small" warnings
evalin('base','model_params');                 % reset ALL params to defaults

% ---- apply overrides ----
f = fieldnames(ov);
for i = 1:numel(f), assignin('base', f{i}, ov.(f{i})); end

% ---- re-derive dependent constants (in case their inputs were overridden) ----
evalin('base', 'Kpu       = 1/(VLL*sqrt(2/3));');
evalin('base', 'alpha_lpf = Ts/(tau_lpf+Ts);');

% ---- stop time ----
if isfield(opts,'Tstop'), Tstop = opts.Tstop; else, Tstop = evalin('base','Tstop'); end

% ---- simulate (timed) ----
m = defaultMetrics();
try
    ws = warning('off','all');                 % suppress buffer/solver chatter
    cleaner = onCleanup(@() warning(ws));      % restored even on error
    t0 = tic;
    so = sim(mdl, 'StopTime', num2str(Tstop));
    m.simtime = toc(t0);

    vdc = getLog(so,'Vdc_log');
    is  = phaseA(getLog(so,'is_log'));         % source current, phase a
    iL  = phaseA(getLog(so,'iL_log'));         % load current, phase a
    Ts  = evalin('base','Ts');
    f0  = evalin('base','fgrid');
    Vref= evalin('base','Vdc_ref');

    % harmonic magnitudes (A) of the source current in each operating window
    [magS_g, m.THD_g2v] = harmWin(is, f0, Ts, [0.23 0.29]);   % G2V steady window
    [magS_v, m.THD_v2g] = harmWin(is, f0, Ts, [0.44 0.50]);   % V2G steady window
    [magL_g, m.THD_load]= harmWin(iL, f0, Ts, [0.23 0.29]);   % load = "without APF"
    m.THD_worst = max(m.THD_g2v, m.THD_v2g);

    % ---- TDD (IEEE-519 metric): harmonics referenced to the DEMAND current ----
    %  The load is ~constant, so its fundamental is the maximum demand current
    %  I_L. Referencing to I_L (not the shrinking source fundamental) keeps the
    %  V2G number meaningful instead of inflated by the small grid fundamental.
    IL_demand = magL_g(1);
    m.TDD_g2v = 100*sqrt(sum(magS_g(2:end).^2))/max(IL_demand,eps);
    m.TDD_v2g = 100*sqrt(sum(magS_v(2:end).^2))/max(IL_demand,eps);
    m.TDD_worst = max(m.TDD_g2v, m.TDD_v2g);

    % DC-link regulation
    m2 = vdc.Time > 0.1;
    m.Vdc_mean = mean(vdc.Data(m2));
    m.Vdc_err  = trapz(vdc.Time(m2), abs(Vref - vdc.Data(m2)))/(Tstop*Vref)*100;

    % power factor (distortion, at the G2V operating point) + fitness
    m.PF = 1/sqrt(1 + (m.THD_g2v/100)^2);
    w1 = evalin('base','pso.w1'); w2 = evalin('base','pso.w2');
    m.J  = w1*m.THD_worst + w2*m.Vdc_err;
    m.ok = all(isfinite([m.THD_worst m.Vdc_err]));
catch err
    warning('apf_metrics: run failed (%s)', err.message);
end
end

% ---------------------------------------------------------------- helpers
function m = defaultMetrics()
m = struct('THD_g2v',NaN,'THD_v2g',NaN,'THD_worst',NaN,'THD_load',NaN, ...
           'TDD_g2v',NaN,'TDD_v2g',NaN,'TDD_worst',NaN, ...
           'Vdc_mean',NaN,'Vdc_err',NaN,'PF',NaN,'J',NaN,'simtime',NaN,'ok',false);
end

function x = phaseA(ts)
% phase-a column as a timeseries-like struct with .Time/.Data
D = squeeze(ts.Data); if size(D,1)~=numel(ts.Time), D = D.'; end
x.Time = ts.Time; x.Data = D(:,1);
end

function [mags, THDpct] = harmWin(x, f0, Ts, win)
% harmonic magnitudes (1..25) over an integer number of cycles inside win=[t0 t1]
t = x.Time; d = double(x.Data(:));
i0 = find(t >= win(1), 1, 'first');
Navail = numel(d) - i0 + 1;
Ncyc = max(1, floor(min((win(2)-win(1)), Navail*Ts)*f0));   % whole cycles
N = round(Ncyc/f0/Ts);
if isempty(i0) || i0+N-1 > numel(d), i0 = max(1, numel(d)-N+1); end
seg = d(i0:i0+N-1); seg = seg - mean(seg);
X = abs(fft(seg))/N*2; df = 1/(N*Ts);
mags = zeros(1,25);
for h = 1:25, k = round(h*f0/df)+1; if k<=numel(X), mags(h)=X(k); end, end
THDpct = 100*sqrt(sum(mags(2:end).^2))/max(mags(1),eps);
end

function bumpTransportDelayBuffers(mdl)
% one-time: enlarge the Transport Delay buffers inside the Discrete-THD block so
% Simulink stops warning "buffer too small" every run.
persistent done
if ~isempty(done), return; end
ws = warning('off','all'); c = onCleanup(@() warning(ws));  %#ok<NASGU>
try
    td = find_system(mdl,'LookUnderMasks','all','FollowLinks','on','BlockType','TransportDelay');
    for i = 1:numel(td)
        try, set_param(td{i},'BufferSize','16384'); catch, end
    end
catch, end
done = true;
end

function ts = getLog(so, name)
try, ts = so.(name); return; catch, end
try, ts = so.get(name); return; catch, end
ts = evalin('base', name);
end

