%% harmonic_diagnose.m
%  Diagnose WHERE the residual source-current THD comes from, by comparing the
%  harmonic spectra of:
%     (a) the load current            (uncompensated reference)
%     (b) the source current, PV ON   (proposed, full)
%     (c) the source current, PV OFF  (APF-only floor)
%  in the G2V steady-state window. Tells us whether the residual is a few
%  LOW-ORDER harmonics (=> SRF / reference-generation fix) or BROADBAND
%  (=> hysteresis / topology limit).
%
%  Output: results\harmonic_diagnose.png , results\Table_harmonics.csv
%
%  Usage:  >> harmonic_diagnose

mdl='EVCS_APF_V2G';
if ~exist('results','dir'), mkdir('results'); end
if ~bdIsLoaded(mdl), load_system(mdl); end

[isOn , iL] = runcase(mdl, struct());                 % PV on  (nominal)
[isOff, ~ ] = runcase(mdl, struct('Irr0',0,'Irr1',0));% PV off

f0 = evalin('base','fgrid'); Ts = evalin('base','Ts');
Hmax = 25;
[hL ,tL ] = spec(iL ,   f0, Ts, Hmax);
[hOn,tOn] = spec(isOn,   f0, Ts, Hmax);
[hOff,tOff]= spec(isOff, f0, Ts, Hmax);

fprintf('\n=== HARMONIC DIAGNOSIS (phase a, G2V window) ===\n');
fprintf('  THD load (uncompensated) : %5.2f %%\n', tL);
fprintf('  THD source, PV ON        : %5.2f %%\n', tOn);
fprintf('  THD source, PV OFF       : %5.2f %%\n', tOff);
fprintf('  dominant source harmonics (PV ON): ');
[~,ord] = sort(hOn(2:end),'descend'); ord = ord(1:5)+1;
fprintf('%dth ', sort(ord)); fprintf('\n');

% table of harmonic magnitudes (% of fundamental)
h = (1:Hmax)';
T = table(h, round(hL',2), round(hOn',2), round(hOff',2), ...
    'VariableNames',{'Harmonic','Load_pct','SourcePVon_pct','SourcePVoff_pct'});
writetable(T,'results\Table_harmonics.csv'); disp(T(2:min(20,Hmax),:));

% figure
fig=figure('Color','w','Position',[80 80 1000 520]);
b=bar(2:Hmax, [hL(2:end); hOff(2:end); hOn(2:end)]','grouped'); grid on;
b(1).FaceColor=[0.7 0.7 0.7]; b(2).FaceColor=[0.47 0.67 0.19]; b(3).FaceColor=[0.85 0.33 0.10];
legend(sprintf('Load (THD %.1f%%)',tL), sprintf('Source PV off (THD %.1f%%)',tOff), ...
       sprintf('Source PV on (THD %.1f%%)',tOn),'Location','northeast');
xlabel('Harmonic order  h'); ylabel('Magnitude  [% of fundamental]');
title('Harmonic signature of the residual source-current THD','FontWeight','bold');
exportgraphics(fig,'results\harmonic_diagnose.png','Resolution',300);
fprintf('Saved results\\harmonic_diagnose.png and results\\Table_harmonics.csv\n');

% ---------- helpers ----------
function [isa, iL] = runcase(mdl, ov)
    evalin('base','model_params');
    f=fieldnames(ov); for i=1:numel(f), assignin('base',f{i},ov.(f{i})); end
    evalin('base','Kpu=1/(VLL*sqrt(2/3));'); evalin('base','alpha_lpf=Ts/(tau_lpf+Ts);');
    ws=warning('off','all'); c=onCleanup(@() warning(ws)); %#ok<NASGU>
    so=sim(mdl,'StopTime',num2str(evalin('base','Tstop')));
    S=getf(so,'is_log'); L=getf(so,'iL_log');
    A=squeeze(S.Data); if size(A,1)~=numel(S.Time), A=A.'; end; isa=timeseries(A(:,1),S.Time);
    B=squeeze(L.Data); if size(B,1)~=numel(L.Time), B=B.'; end; iL =timeseries(B(:,1),L.Time);
end
function v=getf(so,n), try, v=so.(n); catch, v=evalin('base',n); end, end
function [Hpct,THD]=spec(ts,f0,Ts,Hmax)
    x=double(ts.Data(:)); t=ts.Time;
    Ncyc=6; N=round(Ncyc/f0/Ts); i0=find(t>=0.23,1,'first');
    if isempty(i0)||i0+N-1>numel(x), i0=max(1,numel(x)-N+1); end
    seg=x(i0:i0+N-1); seg=seg-mean(seg);
    X=abs(fft(seg))/N*2; df=1/(N*Ts); mags=zeros(1,Hmax);
    for hh=1:Hmax, k=round(hh*f0/df)+1; if k<=numel(X), mags(hh)=X(k); end, end
    Hpct=100*mags/max(mags(1),eps); THD=100*sqrt(sum(mags(2:end).^2))/max(mags(1),eps);
end
