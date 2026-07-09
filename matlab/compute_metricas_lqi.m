function [metrics, meta] = compute_metricas_lqi(simOut, varargin)
%compute_metricas_lqi Calcula métricas de desempenho a partir de logs Simulink.
%
% Retorna um struct com métricas numéricas (sem exportar arquivos).
%
% Uso típico:
%   simOut = sim(model);
%   [m, meta] = compute_metricas_lqi(simOut);
%
% Parâmetros (Name-Value):
%   'PrefTS'        : timeseries com a referência (bar gauge). Se vazio,
%                     busca Pref_ts/Pref_ws_struct/Pref_ws_array no base.
%   'SettlingBand'  : banda relativa para t_s (default 0.02 = 2%).
%   'PwCandidates'  : cellstr com nomes candidatos do sinal de pressão.
%
% Observação:
% - Não inventa números: calcula exclusivamente a partir dos sinais.

p = inputParser;
p.addParameter('PrefTS', [], @(x) isempty(x) || isa(x,'timeseries'));
p.addParameter('SettlingBand', 0.02, @(x) isnumeric(x) && isscalar(x) && x>0);
p.addParameter('PwCandidates', {'Pw_bar_g','Pw_g_bar','Pw'}, @(x) iscell(x) && ~isempty(x));
p.addParameter('OmegaCandidates', {'omega_p','omega_p_rad_s','omega'}, @(x) iscell(x) && ~isempty(x));
p.addParameter('UinCandidates', {'u_in','u_in_cmd'}, @(x) iscell(x) && ~isempty(x));
p.addParameter('UoutCandidates', {'u_out','u_out_cmd'}, @(x) iscell(x) && ~isempty(x));
p.parse(varargin{:});

prefTS = p.Results.PrefTS;
settlingBand = p.Results.SettlingBand;

meta = struct();

% ---------------------------
% Recupera sinais: Pw (bar gauge), e (opcional) comandos
% ---------------------------
[Pw_ts, foundPwName] = local_get_timeseries(simOut, p.Results.PwCandidates);
if isempty(Pw_ts)
    error('Nao foi possivel localizar o sinal de pressao Pw.');
end
meta.PwSignalName = foundPwName;

% Referência: tenta usar argumento; caso vazio, busca no base workspace
if isempty(prefTS)
    prefTS = local_get_reference_from_base();
end
if isempty(prefTS)
    error(['Nao foi possivel localizar a referencia de pressao. ' ...
           'Passe PrefTS (timeseries) ou defina Pref_ts/Pref_ws_struct/Pref_ws_array no workspace.']);
end

t = Pw_ts.Time(:);
y = Pw_ts.Data(:);
r = interp1(prefTS.Time(:), prefTS.Data(:), t, 'previous', 'extrap');

aomega_ts = local_get_timeseries(simOut, p.Results.OmegaCandidates);
uin_ts   = local_get_timeseries(simOut, p.Results.UinCandidates);
uout_ts  = local_get_timeseries(simOut, p.Results.UoutCandidates);

% ---------------------------
% Segmentação por patamares
% ---------------------------
dr = [0; diff(r)];
stepIdx = find(abs(dr) > 1e-9);

segments = {};
if isempty(stepIdx)
    segments{1} = struct('t0', t(1), 'tf', t(end), 'r0', r(1), 'rf', r(end));
else
    edges = [1; stepIdx; numel(t)+1];
    for i = 1:(numel(edges)-1)
        k0 = edges(i);
        kf = edges(i+1)-1;
        segments{end+1} = struct(
            't0', t(k0), 'tf', t(kf), ...
            'r0', r(k0), 'rf', r(kf), ...
            'k0', k0, 'kf', kf);
    end
end

% ---------------------------
% Métricas globais e do degrau mais exigente
% ---------------------------
e = r - y;

metrics = struct();
metrics.RMS_e_bar = sqrt(mean(e.^2));
metrics.e_inf_bar = mean(e(max(1,end-100):end));

if ~isempty(aomega_ts)
    metrics.omega_max = max(aomega_ts.Data(:));
else
    metrics.omega_max = NaN;
end
if ~isempty(uin_ts)
    metrics.uin_max = max(uin_ts.Data(:));
else
    metrics.uin_max = NaN;
end
if ~isempty(uout_ts)
    metrics.uout_max = max(uout_ts.Data(:));
else
    metrics.uout_max = NaN;
end

bestStep = struct('amp', -Inf, 'Mp_pct', NaN, 'tr_s', NaN, 'ts_s', NaN);

for i = 1:numel(segments)
    seg = segments{i};
    if ~isfield(seg,'k0')
        continue
    end
    k0 = seg.k0; kf = seg.kf;
    yi = y(k0:kf);
    ti = t(k0:kf);

    r0 = seg.r0; rf = seg.rf;
    amp = rf - r0;
    if abs(amp) < 1e-9
        continue
    end

    if amp > 0
        Mp = (max(yi) - rf) / abs(amp) * 100;
    else
        Mp = (rf - min(yi)) / abs(amp) * 100;
    end

    tr = NaN;
    if amp > 0
        y10 = r0 + 0.1*amp;
        y90 = r0 + 0.9*amp;
        idx10 = find(yi >= y10, 1, 'first');
        idx90 = find(yi >= y90, 1, 'first');
    else
        y90 = r0 + 0.9*amp;
        y10 = r0 + 0.1*amp;
        idx90 = find(yi <= y90, 1, 'first');
        idx10 = find(yi <= y10, 1, 'first');
    end
    if ~isempty(idx10) && ~isempty(idx90)
        tr = ti(idx10) - ti(idx90);
        if tr < 0
            tr = -tr;
        end
    end

    band = max(settlingBand*abs(amp), 1.0);
    ts = local_settling_time(ti, yi, rf, band);

    if abs(amp) > bestStep.amp
        bestStep.amp = abs(amp);
        bestStep.Mp_pct = Mp;
        bestStep.tr_s = tr;
        bestStep.ts_s = ts;
    end
end

metrics.Mp_pct = bestStep.Mp_pct;
metrics.tr_s = bestStep.tr_s;
metrics.ts_s = bestStep.ts_s;
end

% ==========================
% Helpers locais
% ==========================
function [ts, nameFound] = local_get_timeseries(simOut, candidateNames)
ts = [];
nameFound = '';

% 1) logsout
try
    if isprop(simOut,'logsout') && ~isempty(simOut.logsout)
        logs = simOut.logsout;
        for i = 1:numel(candidateNames)
            nm = candidateNames{i};
            try
                el = logs.get(nm);
                if ~isempty(el)
                    ts = el.Values;
                    nameFound = nm;
                    return
                end
            catch
            end
        end
    end
catch
end

% 2) simOut.get
for i = 1:numel(candidateNames)
    nm = candidateNames{i};
    try
        v = simOut.get(nm);
        if isa(v,'timeseries')
            ts = v;
            nameFound = nm;
            return
        end
    catch
    end
end
end

function prefTS = local_get_reference_from_base()
prefTS = [];

try
    v = evalin('base','Pref_ts');
    if isa(v,'timeseries')
        prefTS = v;
        return
    end
catch
end

try
    s = evalin('base','Pref_ws_struct');
    if isstruct(s) && isfield(s,'time') && isfield(s,'signals')
        t = s.time(:);
        x = s.signals.values(:);
        prefTS = timeseries(x,t);
        return
    end
catch
end

try
    a = evalin('base','Pref_ws_array');
    if isnumeric(a) && size(a,2) >= 2
        prefTS = timeseries(a(:,2), a(:,1));
        return
    end
catch
end
end

function ts = local_settling_time(t, y, rFinal, band)
ts = NaN;
within = abs(y - rFinal) <= band;
if ~any(within)
    return
end

for i = 1:numel(within)
    if within(i)
        if all(within(i:end))
            ts = t(i) - t(1);
            return
        end
    end
end
end
