% ensaio_clmulti_serial.m — Ensaio multi-referência (LQR pos + observador)
% Perfil: 0→100→200→50→0 psi com transições em 1s, 2s, 3s, 4s; total 6s
% Estrutura copiada do ensaio_clstep_serial.m (validado)

clear; close all; clc;

% Configuracao
portName     = "COM18";
baudRate     = 460800;
Tstop        = 40.0;
readTimeoutS = Tstop + 5.0;

% Abre serial
s = serialport(portName, baudRate);
configureTerminator(s, "CR/LF");
s.Timeout = 0.2;
flush(s);
cleanupObj = onCleanup(@() clear('s')); %#ok<NASGU>

% Buffers serial: [CLMULTI],t,pw,pwHat,pos,pwRef,u
slog.t_ms = []; slog.pw = []; slog.pwHat = [];
slog.pos = []; slog.pwRef = []; slog.u = [];

% Buffers 1kHz: [CM],t,pw_x100,pwHat_x100,pos_x100,pwRef_x100,u_x100
buf.t_ms = []; buf.pw = []; buf.pwHat = [];
buf.pos = []; buf.pwRef = []; buf.u = [];

fprintf("Disparando CLMULTI...\n");
writeline(s, "CLMULTI");

% Leitura
deadline = tic; finished = false;
while toc(deadline) < readTimeoutS
    try
        line = readline(s);
    catch
        continue;
    end
    if ~ischar(line) && ~isstring(line), continue; end
    if ismissing(line), continue; end

    % Parser serial [CLMULTI],t,pw,pwHat,pos,pwRef,u
    if startsWith(line, "[CLMULTI],")
        parts = strsplit(strtrim(extractAfter(line, "[CLMULTI],")), ",");
        if numel(parts) >= 6
            toF = @(s) sscanf(strtrim(s), '%f', 1);
            slog.t_ms(end+1)  = toF(parts{1}); %#ok<*SAGROW>
            slog.pw(end+1)    = toF(parts{2});
            slog.pwHat(end+1) = toF(parts{3});
            slog.pos(end+1)   = toF(parts{4});
            slog.pwRef(end+1) = toF(parts{5});
            slog.u(end+1)     = toF(parts{6});
        end
        continue;
    end

    % Parser buffer [CM],t,pw_x100,pwHat_x100,pos_x100,pwRef_x100,u_x100
    if startsWith(line, "[CM],")
        parts = strsplit(strtrim(extractAfter(line, "[CM],")), ",");
        if numel(parts) >= 6
            toF = @(s) sscanf(strtrim(s), '%f', 1);
            buf.t_ms(end+1)  = toF(parts{1});
            buf.pw(end+1)    = toF(parts{2}) / 100.0;
            buf.pwHat(end+1) = toF(parts{3}) / 100.0;
            buf.pos(end+1)   = toF(parts{4}) / 100.0;
            buf.pwRef(end+1) = toF(parts{5}) / 100.0;
            buf.u(end+1)     = toF(parts{6}) / 100.0;
        end
        continue;
    end

    if startsWith(line, "[CLMULTI_BUF]") || startsWith(line, "[CLMULTI_BUF_END]")
        continue;
    end

    fprintf("%s\n", line);
    if contains(line, "CLMULTI concluido") || contains(line, "CLMULTI falha")
        finished = true;
        break;
    end
end
clear s cleanupObj;

if ~finished
    warning("CLMULTI nao confirmou conclusao.");
end

fprintf("Amostras serial (5ms): %d\n", numel(slog.t_ms));
fprintf("Amostras buffer (1kHz): %d\n", numel(buf.t_ms));

% Exporta CSV
scriptDir = fileparts(mfilename('fullpath'));
dataDir = fullfile(scriptDir, 'dados');
if ~exist(dataDir, 'dir'), mkdir(dataDir); end
ts = datestr(now, 'yyyymmdd_HHMMSS');

if numel(buf.t_ms) > 0
    Tbuf = table(buf.t_ms', buf.pw', buf.pwHat', buf.pos', buf.pwRef', buf.u', ...
                 'VariableNames', {'t_ms','pw_psi','pwHat_psi','pos_mm','pwRef_psi','u_pct'});
    csvBuf = fullfile(dataDir, sprintf('ensaio_clmulti_buf1khz_%s.csv', ts));
    writetable(Tbuf, csvBuf);
    fprintf("Buffer exportado em: %s\n", csvBuf);
end

if numel(slog.t_ms) > 0
    Tser = table(slog.t_ms', slog.pw', slog.pwHat', slog.pos', slog.pwRef', slog.u', ...
                 'VariableNames', {'t_ms','pw_psi','pwHat_psi','pos_mm','pwRef_psi','u_pct'});
    csvSer = fullfile(dataDir, sprintf('ensaio_clmulti_serial_%s.csv', ts));
    writetable(Tser, csvSer);
    fprintf("Serial exportado em: %s\n", csvSer);
end

% Escolher dados: buffer > serial
if numel(buf.t_ms) > 10
    t = buf.t_ms / 1000; pw = buf.pw; pwHat = buf.pwHat;
    pos = buf.pos; pwRef = buf.pwRef; u_pct = buf.u;
    srcLabel = '1 kHz (buffer)';
else
    t = slog.t_ms / 1000; pw = slog.pw; pwHat = slog.pwHat;
    pos = slog.pos; pwRef = slog.pwRef; u_pct = slog.u;
    srcLabel = '5 ms (serial)';
end

% ── Métricas por segmento ──
segTimes = [0 1.0 2.0 3.0 4.0 5.0 6.0];
segRefs  = [0 100 200 50 0 0];
segNames = {'Idle (0 psi)', 'Degrau 100 psi', 'Degrau 200 psi', 'Descida 50 psi', 'Release (0 psi)', 'Idle final'};

fprintf("\n--- Metricas por segmento ---\n");
for ss = 1:6
    idxSeg = (t >= segTimes(ss)) & (t < segTimes(ss+1));
    if ~any(idxSeg), continue; end
    pwSeg = pw(idxSeg);
    tSeg  = t(idxSeg);
    refV  = segRefs(ss);

    errRMS = sqrt(mean((pwSeg - refV).^2));
    eSS = abs(mean(pwSeg(end-min(50,numel(pwSeg)-1):end)) - refV);
    if refV > 0
        Mp = (max(pwSeg) - refV) / refV * 100;
    else
        Mp = NaN;
    end

    fprintf("Seg %d (%s): Pref=%.0f | eRMS=%.2f | eSS=%.2f | Mp=%.1f%% | Pw_media=%.2f | Pw_max=%.2f\n", ...
            ss, segNames{ss}, refV, errRMS, eSS, Mp, mean(pwSeg), max(pwSeg));
end

% ── Resumo a cada 100ms ──
fprintf("\n--- Resumo a cada 100ms ---\n");
fprintf("  %8s  %8s  %8s  %8s  %8s  %8s\n", ...
        "t(s)", "Pw_real", "Pw_est", "pos_mm", "Pref", "u_pct");
fprintf("  %8s  %8s  %8s  %8s  %8s  %8s\n", ...
        "------", "------", "------", "------", "------", "------");
tSample = t(1):0.1:t(end);
for jj = 1:numel(tSample)
    [~, idx] = min(abs(t - tSample(jj)));
    fprintf("  %8.3f  %8.2f  %8.2f  %8.2f  %8.1f  %8.1f\n", ...
            t(idx), pw(idx), pwHat(idx), pos(idx), pwRef(idx), u_pct(idx));
end

% ── Plot ──
set(groot,'defaultLineLineWidth',1.6);
set(groot,'defaultAxesFontSize',12);
set(groot,'defaultAxesFontName','Times New Roman');
set(groot,'defaultFigureRenderer','painters');

fig1 = figure('Color','w','Position',[50 50 1400 1000]);
tiledlayout(3,1,'TileSpacing','compact','Padding','compact');

% 1) Pw real vs estimada vs referência
nexttile; hold on; grid on;
plot(t, pw, '-k', 'LineWidth', 1.5);
plot(t, pwHat, '--r', 'LineWidth', 1.2);
stairs(t, pwRef, ':b', 'LineWidth', 1.5);
ylabel('P_w (psi)', 'FontSize', 16);
title(sprintf('Pw real vs estimada'), 'FontSize', 18);
legend('P_w real', 'P_w estimada', 'P_{ref}', 'Location', 'best', 'FontSize', 12);
ylim([-10 max([max(pw) max(pwRef)])+20]);

% 2) Posição
nexttile; hold on; grid on;
plot(t, pos, '-b', 'LineWidth', 1.5);
ylabel('Posicao LAC (mm)', 'FontSize', 16);
title('Posicao do pistao', 'FontSize', 16);

% 3) Esforço de controle
nexttile; hold on; grid on;
plot(t, u_pct, '-', 'Color', [0.8 0.2 0], 'LineWidth', 1.2);
ylabel('u (%)', 'FontSize', 14);
xlabel('Tempo (s)', 'FontSize', 16);
title('Esforco de controle (PWM)', 'FontSize', 16);
ylim([-5 105]);

% Export
figDir = fullfile(scriptDir, 'figuras');
if ~exist(figDir, 'dir'), mkdir(figDir); end
exportgraphics(fig1, fullfile(figDir, sprintf('ensaio_clmulti_%s.pdf', ts)), 'ContentType','vector');
exportgraphics(fig1, fullfile(figDir, sprintf('ensaio_clmulti_%s.png', ts)), 'Resolution', 1200);
disp('OK: figuras exportadas em:'); disp(figDir);

% ── HOME ao final ──
fprintf("\nEnviando HOME...\n");
sHome = serialport(portName, baudRate);
configureTerminator(sHome, "CR/LF");
sHome.Timeout = 0.5;
flush(sHome);
writeline(sHome, "HOME");
tHome = tic;
while toc(tHome) < 20
    try
        lineH = readline(sHome);
    catch
        continue;
    end
    if ismissing(lineH), continue; end
    fprintf("  %s\n", lineH);
    if contains(lineH, "HOME concluido") || contains(lineH, "HOME ok")
        break;
    end
end
clear sHome;
fprintf("HOME finalizado.\n");
