% ensaio_clstep_serial.m — Ensaio malha fechada comparativo A(Pw) vs B(pos+obs)
% Uso: setar modeCmd = "CLSTEP A" ou "CLSTEP B" abaixo
% Estrutura de comunicacao copiada do ensaio_olstep_serial.m (validado)

clear; close all; clc;

% ====== CONFIGURAR MODO AQUI ======
modeCmd = "CLSTEP B";   % "CLSTEP A" = feedback Pw | "CLSTEP B" = feedback pos+obs
% ===================================

% Configuracao
portName     = "COM18";
baudRate     = 460800;
Tstop        = 30.0;
readTimeoutS = Tstop + 5.0;

% Abre serial
s = serialport(portName, baudRate);
configureTerminator(s, "CR/LF");
s.Timeout = 0.2;
flush(s);
cleanupObj = onCleanup(@() clear('s')); %#ok<NASGU>

% Buffers serial: [CLSTEP],t,mode,phase,pw,pwHat,pos,xRef,u
slog.t_ms = []; slog.mode = []; slog.phase = [];
slog.pw = []; slog.pwHat = []; slog.pos = [];
slog.xRef = []; slog.u = [];

% Buffers 1kHz: [CB],t,mode,phase,pw_x100,pwHat_x100,pos_x100,pwRef_x100,u_x100
buf.t_ms = []; buf.mode = []; buf.phase = [];
buf.pw = []; buf.pwHat = []; buf.pos = [];
buf.pwRef = []; buf.u = [];

fprintf("Disparando %s...\n", modeCmd);
writeline(s, modeCmd);

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

    % Parser serial [CLSTEP],t,mode,phase,pw,pwHat,pos,xRef,u
    if startsWith(line, "[CLSTEP],")
        parts = strsplit(strtrim(extractAfter(line, "[CLSTEP],")), ",");
        if numel(parts) >= 8
            toF = @(s) sscanf(strtrim(s), '%f', 1);
            slog.t_ms(end+1)  = toF(parts{1}); %#ok<*SAGROW>
            slog.mode(end+1)  = toF(parts{2});
            slog.phase(end+1) = toF(parts{3});
            slog.pw(end+1)    = toF(parts{4});
            slog.pwHat(end+1) = toF(parts{5});
            slog.pos(end+1)   = toF(parts{6});
            slog.xRef(end+1)  = toF(parts{7});
            slog.u(end+1)     = toF(parts{8});
        end
        continue;
    end

    % Parser buffer [CB],t,mode,phase,pw_x100,pwHat_x100,pos_x100,pwRef_x100,u_x100
    if startsWith(line, "[CB],")
        parts = strsplit(strtrim(extractAfter(line, "[CB],")), ",");
        if numel(parts) >= 8
            toF = @(s) sscanf(strtrim(s), '%f', 1);
            buf.t_ms(end+1)  = toF(parts{1});
            buf.mode(end+1)  = toF(parts{2});
            buf.phase(end+1) = toF(parts{3});
            buf.pw(end+1)    = toF(parts{4}) / 100.0;
            buf.pwHat(end+1) = toF(parts{5}) / 100.0;
            buf.pos(end+1)   = toF(parts{6}) / 100.0;
            buf.pwRef(end+1) = toF(parts{7}) / 100.0;
            buf.u(end+1)     = toF(parts{8}) / 100.0;
        end
        continue;
    end

    if startsWith(line, "[CLSTEP_BUF]"), continue; end
    if startsWith(line, "[CLSTEP_BUF_END]"), continue; end

    % Mensagens gerais
    fprintf("%s\n", line);
    if contains(line, "CLSTEP concluido") || contains(line, "CLSTEP falha")
        finished = true;
        break;
    end
end
clear s cleanupObj;

if ~finished
    warning("CLSTEP nao confirmou conclusao em %.1fs.", readTimeoutS);
end

fprintf("Amostras serial (5ms): %d\n", numel(slog.t_ms));
fprintf("Amostras buffer (1kHz): %d\n", numel(buf.t_ms));

% Exporta CSV
scriptDir = fileparts(mfilename('fullpath'));
dataDir = fullfile(scriptDir, 'dados');
if ~exist(dataDir, 'dir'), mkdir(dataDir); end
ts = datestr(now, 'yyyymmdd_HHMMSS');

modeLabel = 'A';
if numel(buf.mode) > 0 && buf.mode(1) == 1, modeLabel = 'B'; end
if numel(slog.mode) > 0 && slog.mode(1) == 1, modeLabel = 'B'; end

if numel(buf.t_ms) > 0
    Tbuf = table(buf.t_ms', buf.mode', buf.phase', buf.pw', buf.pwHat', ...
                 buf.pos', buf.pwRef', buf.u', ...
                 'VariableNames', {'t_ms','mode','phase','pw_psi','pwHat_psi', ...
                                   'pos_mm','pwRef_psi','u_pct'});
    csvBuf = fullfile(dataDir, sprintf('ensaio_clstep%s_buf1khz_%s.csv', modeLabel, ts));
    writetable(Tbuf, csvBuf);
    fprintf("Buffer exportado em: %s\n", csvBuf);
end

if numel(slog.t_ms) > 0
    Tser = table(slog.t_ms', slog.mode', slog.phase', slog.pw', slog.pwHat', ...
                 slog.pos', slog.xRef', slog.u', ...
                 'VariableNames', {'t_ms','mode','phase','pw_psi','pwHat_psi', ...
                                   'pos_mm','xRef_mm','u_pct'});
    csvSer = fullfile(dataDir, sprintf('ensaio_clstep%s_serial_%s.csv', modeLabel, ts));
    writetable(Tser, csvSer);
    fprintf("Serial exportado em: %s\n", csvSer);
end

% Escolher dados: buffer > serial
if numel(buf.t_ms) > 10
    t     = buf.t_ms / 1000;
    pw    = buf.pw;
    pwHat = buf.pwHat;
    pos   = buf.pos;
    pwRef = buf.pwRef;
    u_pct = buf.u;
    ph    = buf.phase;
    srcLabel = '1 kHz (buffer)';
else
    t     = slog.t_ms / 1000;
    pw    = slog.pw;
    pwHat = slog.pwHat;
    pos   = slog.pos;
    pwRef = ones(size(slog.pw)) * 100;  % fallback
    u_pct = slog.u;
    ph    = slog.phase;
    srcLabel = '5 ms (serial)';
end

% ── Metricas ──
% Indices da fase de controle (phase==2)
idxCtrl = (ph == 2);
if any(idxCtrl)
    pwCtrl = pw(idxCtrl);
    tCtrl  = t(idxCtrl);
    refVal = pwRef(find(idxCtrl,1));

    errRMS = sqrt(mean((pwCtrl - refVal).^2));
    eSS    = abs(mean(pwCtrl(end-min(100,numel(pwCtrl)-1):end)) - refVal);
    Mp     = (max(pwCtrl) - refVal) / refVal * 100;

    % t_subida (10%->90% de refVal)
    i10 = find(pwCtrl >= 0.1*refVal, 1, 'first');
    i90 = find(pwCtrl >= 0.9*refVal, 1, 'first');
    if ~isempty(i10) && ~isempty(i90)
        tRise = tCtrl(i90) - tCtrl(i10);
    else
        tRise = NaN;
    end

    % t_acomodacao (5% band)
    band = 0.05 * refVal;
    iSettle = find(abs(pwCtrl - refVal) > band, 1, 'last');
    if ~isempty(iSettle) && iSettle < numel(tCtrl)
        tSettle = tCtrl(iSettle) - tCtrl(1);
    else
        tSettle = NaN;
    end

    fprintf("\n--- Metricas modo %s ---\n", modeLabel);
    fprintf("Erro RMS:          %.2f psi\n", errRMS);
    fprintf("Erro estacionario: %.2f psi\n", eSS);
    fprintf("Sobressinal Mp:    %.1f %%\n", Mp);
    fprintf("Tempo subida:      %.3f s\n", tRise);
    fprintf("Tempo acomodacao:  %.3f s\n", tSettle);
end

% ── Tabela de amostras (primeiras 80 da fase de controle) ──
fprintf("\n--- Amostras fase de controle (primeiras 80) ---\n");
fprintf("  %8s  %8s  %8s  %8s  %8s  %8s  %8s\n", ...
        "t(s)", "Pw_real", "Pw_est", "pos_mm", "xRef_mm", "u_pct", "erro_Pw");
fprintf("  %8s  %8s  %8s  %8s  %8s  %8s  %8s\n", ...
        "------", "------", "------", "------", "------", "------", "------");

idxCtrlAll = find(ph == 2);
nPrint = min(80, numel(idxCtrlAll));
for ii = 1:nPrint
    k = idxCtrlAll(ii);
    if numel(buf.t_ms) > 10
        xr = 0;  % buffer nao tem xRef diretamente, usa pwRef
    else
        xr = slog.xRef(k);
    end
    fprintf("  %8.3f  %8.2f  %8.2f  %8.2f  %8.2f  %8.1f  %8.2f\n", ...
            t(k), pw(k), pwHat(k), pos(k), xr, u_pct(k), pw(k)-pwRef(find(idxCtrl,1)));
end
fprintf("... total fase controle: %d amostras\n", numel(idxCtrlAll));

% ── Tabela resumo a cada 100ms durante controle ──
fprintf("\n--- Resumo a cada 100ms (fase controle) ---\n");
fprintf("  %8s  %8s  %8s  %8s  %8s  %8s\n", ...
        "t(s)", "Pw_real", "Pw_est", "pos_mm", "u_pct", "errPw");
fprintf("  %8s  %8s  %8s  %8s  %8s  %8s\n", ...
        "------", "------", "------", "------", "------", "------");

if any(idxCtrl)
    tCtrlFull  = t(idxCtrl);
    pwCtrlFull = pw(idxCtrl);
    phCtrlFull = pwHat(idxCtrl);
    posCtrlFull = pos(idxCtrl);
    uCtrlFull  = u_pct(idxCtrl);
    refV = pwRef(find(idxCtrl,1));

    tStart = tCtrlFull(1);
    tSample = tStart:0.1:tCtrlFull(end);
    for jj = 1:numel(tSample)
        [~, idx] = min(abs(tCtrlFull - tSample(jj)));
        fprintf("  %8.3f  %8.2f  %8.2f  %8.2f  %8.1f  %8.2f\n", ...
                tCtrlFull(idx), pwCtrlFull(idx), phCtrlFull(idx), ...
                posCtrlFull(idx), uCtrlFull(idx), pwCtrlFull(idx)-refV);
    end
end

% ── Pmax, Pmin, posição final ──
if any(idxCtrl)
    fprintf("\n--- Estatisticas fase controle ---\n");
    [pwMaxVal, pwMaxIdx] = max(pwCtrlFull);
    [pwMinVal, pwMinIdx] = min(pwCtrlFull);
    fprintf("Pw max:        %.2f psi @ t=%.3f s\n", pwMaxVal, tCtrlFull(pwMaxIdx(1)));
    fprintf("Pw min:        %.2f psi @ t=%.3f s\n", pwMinVal, tCtrlFull(pwMinIdx(1)));
    fprintf("Pw media:      %.2f psi\n", mean(pwCtrlFull));
    fprintf("Pw final:      %.2f psi\n", pwCtrlFull(end));
    fprintf("Pos final:     %.2f mm\n", posCtrlFull(end));
    fprintf("u medio:       %.1f %%\n", mean(uCtrlFull));
    fprintf("u max:         %.1f %%\n", max(uCtrlFull));
end

% ── Plot ──
set(groot,'defaultLineLineWidth',1.6);
set(groot,'defaultAxesFontSize',12);
set(groot,'defaultAxesFontName','Times New Roman');
set(groot,'defaultFigureRenderer','painters');

fig1 = figure('Color','w','Position',[50 50 1400 1000]);
tiledlayout(4,1,'TileSpacing','compact','Padding','compact');

% 1) Pw real vs Pw estimada vs Pw ref
nexttile; hold on; grid on;
plot(t, pw, '-k', 'LineWidth', 1.5);
plot(t, pwHat, '--r', 'LineWidth', 1.2);
yline(100, ':b', 'P_{ref}', 'LineWidth', 1, 'FontSize', 11);
ylabel('P_w (psi)', 'FontSize', 16);
title(sprintf('Pressao real vs estimada'), 'FontSize', 18);
legend('P_w real', '\hat{P}_w (observador)', 'P_{ref}', 'Location', 'best', 'FontSize', 12);
ylim([-10 max([max(pw) max(pwHat)])+15]);

% 2) Erro de estimacao
nexttile; hold on; grid on;
plot(t, pw - pwHat, '-m', 'LineWidth', 1.2);
ylabel('Erro Pw (psi)', 'FontSize', 14);
title('Erro de estimacao do observador', 'FontSize', 16);
yline(0, '--k');

% 3) Posicao
nexttile; hold on; grid on;
plot(t, pos, '-b', 'LineWidth', 1.5);
ylabel('Posicao LAC (mm)', 'FontSize', 16);
title('Posicao do pistao', 'FontSize', 16);

% 4) Comando u(%)
nexttile; hold on; grid on;
plot(t, u_pct, '-', 'Color', [0.8 0.4 0], 'LineWidth', 1.5);
ylabel('u (PWM %)', 'FontSize', 14);
xlabel('Tempo (s)', 'FontSize', 16);
title('Esforco de controle', 'FontSize', 16);
ylim([-5 105]);

% Export
figDir = fullfile(scriptDir, 'figuras');
if ~exist(figDir, 'dir'), mkdir(figDir); end
exportgraphics(fig1, fullfile(figDir, sprintf('ensaio_clstep%s_%s.pdf', modeLabel, ts)), 'ContentType','vector');
exportgraphics(fig1, fullfile(figDir, sprintf('ensaio_clstep%s_%s.png', modeLabel, ts)), 'Resolution', 1200);
disp('OK: figuras exportadas em:'); disp(figDir);

% ── HOME: retornar motor à posição inicial ──
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
    if ~ischar(lineH) && ~isstring(lineH), continue; end
    if ismissing(lineH), continue; end
    fprintf("  %s\n", lineH);
    if contains(lineH, "HOME ok") || contains(lineH, "HOME concluido") || contains(lineH, "HOME falha")
        break;
    end
end
clear sHome;
fprintf("HOME finalizado.\n");
