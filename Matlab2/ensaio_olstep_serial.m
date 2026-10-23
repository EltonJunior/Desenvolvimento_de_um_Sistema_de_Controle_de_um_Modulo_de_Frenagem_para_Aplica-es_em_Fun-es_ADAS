% ensaio_olstep_serial.m — Ensaio malha aberta 3 fases (pressurizar/hold/alivio)
% Estrutura de comunicacao copiada do ensaio_ramp5c_serial.m (validado)

clear; close all; clc;

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

% Buffers serial
slog.t_ms = []; slog.phase = []; slog.uIn = []; slog.uOut = [];
slog.pw = []; slog.pos = [];

% Buffers 1kHz
buf.t_ms = []; buf.pw = []; buf.pos = [];
buf.phase = []; buf.uIn = []; buf.uOut = [];
curBufActive = false;

fprintf("Disparando OLSTEP...\n");
writeline(s, "OLSTEP");

% Leitura
deadline = tic; finished = false;
while toc(deadline) < readTimeoutS
    try
        line = readline(s);
    catch
        continue;
    end
    if ~ischar(line) && ~isstring(line)
        continue;
    end
    if ismissing(line)
        continue;
    end

    % Parser serial [OLSTEP],t,phase,uIn,uOut,pw,pos
    if startsWith(line, "[OLSTEP],")
        parts = strsplit(strtrim(extractAfter(line, "[OLSTEP],")), ",");
        if numel(parts) >= 6
            toF = @(s) sscanf(strtrim(s), '%f', 1);
            slog.t_ms(end+1)  = toF(parts{1}); %#ok<*SAGROW>
            slog.phase(end+1) = toF(parts{2});
            slog.uIn(end+1)   = toF(parts{3});
            slog.uOut(end+1)  = toF(parts{4});
            slog.pw(end+1)    = toF(parts{5});
            slog.pos(end+1)   = toF(parts{6});
        end
        continue;
    end

    % Parser buffer [B],t,pw_x100,pos_x100,phase,uIn,uOut
    if startsWith(line, "[B],")
        parts = strsplit(strtrim(extractAfter(line, "[B],")), ",");
        if numel(parts) >= 6
            toF = @(s) sscanf(strtrim(s), '%f', 1);
            buf.t_ms(end+1)  = toF(parts{1});
            buf.pw(end+1)    = toF(parts{2}) / 100.0;
            buf.pos(end+1)   = toF(parts{3}) / 100.0;
            buf.phase(end+1) = toF(parts{4});
            buf.uIn(end+1)   = toF(parts{5});
            buf.uOut(end+1)  = toF(parts{6});
        end
        continue;
    end

    if startsWith(line, "[OLSTEP_BUF]")
        curBufActive = true;
        continue;
    end
    if startsWith(line, "[OLSTEP_BUF_END]")
        curBufActive = false;
        continue;
    end

    % Mensagens gerais
    fprintf("%s\n", line);
    if contains(line, "OLSTEP concluido") || contains(line, "OLSTEP falha")
        finished = true;
        break;
    end
end
clear s cleanupObj;

if ~finished
    warning("OLSTEP nao confirmou conclusao em %.1fs; plotando assim mesmo.", readTimeoutS);
end

fprintf("Amostras serial (5ms): %d\n", numel(slog.t_ms));
fprintf("Amostras buffer (1kHz): %d\n", numel(buf.t_ms));

% Exporta CSV
scriptDir = fileparts(mfilename('fullpath'));
dataDir = fullfile(scriptDir, 'dados');
if ~exist(dataDir, 'dir'), mkdir(dataDir); end
ts = datestr(now, 'yyyymmdd_HHMMSS');

if numel(buf.t_ms) > 0
    Tbuf = table(buf.t_ms', buf.phase', buf.uIn', buf.uOut', buf.pw', buf.pos', ...
                 'VariableNames', {'t_ms','phase','u_in','u_out','pw_psi','pos_mm'});
    csvBuf = fullfile(dataDir, sprintf('ensaio_olstep_buf1khz_%s.csv', ts));
    writetable(Tbuf, csvBuf);
    fprintf("Buffer exportado em: %s\n", csvBuf);
end

if numel(slog.t_ms) > 0
    Tser = table(slog.t_ms', slog.phase', slog.uIn', slog.uOut', slog.pw', slog.pos', ...
                 'VariableNames', {'t_ms','phase','u_in','u_out','pw_psi','pos_mm'});
    csvSer = fullfile(dataDir, sprintf('ensaio_olstep_serial_%s.csv', ts));
    writetable(Tser, csvSer);
    fprintf("Serial exportado em: %s\n", csvSer);
end

% Escolher dados para plot: buffer se disponivel, senao serial
if numel(buf.t_ms) > 10
    t = buf.t_ms / 1000;
    pw = buf.pw;
    pos = buf.pos;
    ph = buf.phase;
    uIn = buf.uIn;
    uOut = buf.uOut;
    srcLabel = '1 kHz (buffer)';
else
    t = slog.t_ms / 1000;
    pw = slog.pw;
    pos = slog.pos;
    ph = slog.phase;
    uIn = slog.uIn;
    uOut = slog.uOut;
    srcLabel = '5 ms (serial)';
end

% ── Tabela de amostras (primeiras 50) ──
fprintf("\n--- Amostras (primeiras 50) ---\n");
fprintf("  %8s  %6s  %4s  %4s  %8s  %8s\n", ...
        "t(s)", "phase", "uIn", "uOut", "Pw_psi", "pos_mm");
fprintf("  %8s  %6s  %4s  %4s  %8s  %8s\n", ...
        "------", "-----", "----", "----", "------", "------");
nPrint = min(50, numel(t));
for ii = 1:nPrint
    fprintf("  %8.3f  %6.0f  %4.0f  %4.0f  %8.2f  %8.2f\n", ...
            t(ii), ph(ii), uIn(ii), uOut(ii), pw(ii), pos(ii));
end
fprintf("... total: %d amostras\n", numel(t));

% ── Resumo a cada 100ms ──
fprintf("\n--- Resumo a cada 100ms ---\n");
fprintf("  %8s  %6s  %8s  %8s\n", "t(s)", "phase", "Pw_psi", "pos_mm");
fprintf("  %8s  %6s  %8s  %8s\n", "------", "-----", "------", "------");
tSample = t(1):0.1:t(end);
for jj = 1:numel(tSample)
    [~, idx] = min(abs(t - tSample(jj)));
    fprintf("  %8.3f  %6.0f  %8.2f  %8.2f\n", t(idx), ph(idx), pw(idx), pos(idx));
end

% ── Estatísticas por fase ──
phaseNamesLog = {'Idle','Pressurizar','Hold','Release','IdleFinal'};
fprintf("\n--- Estatisticas por fase ---\n");
for pp = 0:4
    idxP = (ph == pp);
    if any(idxP)
        [pwMaxV, pwMaxI] = max(pw(idxP));
        tP = t(idxP);
        fprintf("Fase %d (%s): Pw max=%.2f psi, Pw media=%.2f psi, pos media=%.2f mm, duracao=%.3f s\n", ...
                pp, phaseNamesLog{min(pp+1,5)}, pwMaxV, mean(pw(idxP)), mean(pos(idxP)), tP(end)-tP(1));
    end
end

% ── Pw max, Pw final, overshoot ──
idxHold = (ph == 2);
if any(idxHold)
    pwHold = pw(idxHold);
    fprintf("\n--- Hold ---\n");
    fprintf("Pw media hold:  %.2f psi\n", mean(pwHold));
    fprintf("Pw std hold:    %.2f psi\n", std(pwHold));
    fprintf("Pw max hold:    %.2f psi\n", max(pwHold));
    fprintf("Pw min hold:    %.2f psi\n", min(pwHold));
end

idxPress = (ph == 1);
if any(idxPress)
    pwPress = pw(idxPress);
    [pwPeakV, ~] = max(pwPress);
    fprintf("\nPw pico pressurizar: %.2f psi\n", pwPeakV);
    fprintf("Overshoot vs 100psi: %.1f %%\n", (pwPeakV - 100)/100*100);
end

fprintf("Pw final (ultimo ponto): %.2f psi @ pos=%.2f mm\n", pw(end), pos(end));

% ── Plot ──
set(groot,'defaultLineLineWidth',1.6);
set(groot,'defaultAxesFontSize',12);
set(groot,'defaultAxesFontName','Times New Roman');
set(groot,'defaultFigureRenderer','painters');

phaseNames = {'Idle','Pressurizar','Hold','Release','Idle'};
phaseColors = {[0.7 0.7 0.7],[1 0.3 0],[0 0.5 0],[0 0.3 0.8],[0.7 0.7 0.7]};

fig1 = figure('Color','w','Position',[50 50 1400 900]);
tiledlayout(3,1,'TileSpacing','compact','Padding','compact');

% Pressao x Tempo
nexttile; hold on; grid on;
% Fundo colorido por fase
uniquePhases = unique(ph);
for k = 1:numel(uniquePhases)
    idx = (ph == uniquePhases(k));
    pidx = min(uniquePhases(k)+1, numel(phaseColors));
    scatter(t(idx), pw(idx), 2, phaseColors{pidx}, 'filled');
end
plot(t, pw, '-k', 'LineWidth', 1.2);
ylabel('P_w (psi)', 'FontSize', 16);
title(sprintf('Pressao x Tempo'), 'FontSize', 18);
yline(100, '--r', 'P_{ref} = 100 psi', 'LineWidth', 1, 'FontSize', 11);
ylim([-10 (max(pw)+10)]);

% Posicao x Tempo
nexttile; hold on; grid on;
plot(t, pos, '-b', 'LineWidth', 1.5);
ylabel('Posicao LAC (mm)', 'FontSize', 16);
title('Posicao do LAC x Tempo', 'FontSize', 16);

% Valvulas x Tempo
nexttile; hold on; grid on;
stairs(t, uIn, '-r', 'LineWidth', 1.5);
stairs(t, uOut, '-b', 'LineWidth', 1.5);
% stairs(t, ph, '-k', 'LineWidth', 1.0);
ylabel('Comando', 'FontSize', 16);
xlabel('Tempo (s)', 'FontSize', 16);
% legend('u_{in} (Apply)', 'u_{out} (Release)', 'Fase', 'Location', 'northeast');
legend('u_{in}', 'u_{out}', 'Location', 'northeast', 'FontSize', 16);
% title('Comandos de Valvulas e Fase', 'FontSize', 16);
title('Comandos de Valvulas', 'FontSize', 16);
ylim([-0.3 1.5]);

% Export
figDir = fullfile(scriptDir, 'figuras');
if ~exist(figDir, 'dir'), mkdir(figDir); end
exportgraphics(fig1, fullfile(figDir, sprintf('ensaio_olstep_%s.pdf', ts)), 'ContentType','vector');
exportgraphics(fig1, fullfile(figDir, sprintf('ensaio_olstep_%s.png', ts)), 'Resolution', 1200);
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
