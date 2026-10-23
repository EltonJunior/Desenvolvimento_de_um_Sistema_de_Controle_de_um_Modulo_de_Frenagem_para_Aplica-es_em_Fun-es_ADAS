% ensaio_plid_serial.m — Plant IDentification: 3 degraus (100/200/300 psi)
% Mede posição do LAC quando Pw atinge cada alvo (Apply + PWM fixo)
% Estrutura de comunicacao baseada no ensaio_olstep_serial.m

clear; close all; clc;

% Configuracao
portName     = "COM18";
baudRate     = 460800;
Tstop        = 120.0;   % até 2min (3 degraus + homing entre eles)
readTimeoutS = Tstop + 5.0;

% Abre serial
s = serialport(portName, baudRate);
configureTerminator(s, "CR/LF");
s.Timeout = 0.05;  % menor timeout; evitamos bloqueio usando NumBytesAvailable
flush(s);
cleanupObj = onCleanup(@() clear('s')); %#ok<NASGU>

% Buffers serial: [PLID],t,step,phase,pw,pos
slog.t_ms = []; slog.step = []; slog.phase = [];
slog.pw = []; slog.pos = [];

% Buffers 1kHz: [PB],t,step,phase,pw_x100,pos_x100
buf.t_ms = []; buf.step = []; buf.phase = [];
buf.pw = []; buf.pos = [];

fprintf("Disparando PLID...\n");
writeline(s, "PLID");

% Leitura
deadline = tic; finished = false;
while toc(deadline) < readTimeoutS
    try
        % Evita warnings de timeout: só lê quando há bytes disponíveis
        if s.NumBytesAvailable == 0
            pause(0.02);
            continue;
        end
        line = readline(s);
    catch
        continue;
    end
    if ~ischar(line) && ~isstring(line), continue; end
    if ismissing(line), continue; end

    % Parser serial [PLID],t,step,phase,pw,pos
    if startsWith(line, "[PLID],")
        parts = strsplit(strtrim(extractAfter(line, "[PLID],")), ",");
        if numel(parts) >= 5
            toF = @(s) sscanf(strtrim(s), '%f', 1);
            slog.t_ms(end+1)  = toF(parts{1}); %#ok<*SAGROW>
            slog.step(end+1)  = toF(parts{2});
            slog.phase(end+1) = toF(parts{3});
            slog.pw(end+1)    = toF(parts{4});
            slog.pos(end+1)   = toF(parts{5});
        end
        continue;
    end

    % Parser buffer [PB],t,step,phase,pw_x100,pos_x100
    if startsWith(line, "[PB],")
        parts = strsplit(strtrim(extractAfter(line, "[PB],")), ",");
        if numel(parts) >= 5
            toF = @(s) sscanf(strtrim(s), '%f', 1);
            buf.t_ms(end+1)  = toF(parts{1});
            buf.step(end+1)  = toF(parts{2});
            buf.phase(end+1) = toF(parts{3});
            buf.pw(end+1)    = toF(parts{4}) / 100.0;
            buf.pos(end+1)   = toF(parts{5}) / 100.0;
        end
        continue;
    end

    % Concluído?
    if contains(line, "PLID concluido")
        fprintf("  %s\n", line);
        finished = true;
        % Drenar mensagens remanescentes sem bloquear
        tDrain = tic;
        while (s.NumBytesAvailable > 0) && (toc(tDrain) < 0.5)
            extra = readline(s);
            if ~ismissing(extra)
                fprintf("  %s\n", extra);
            end
        end
        break;
    end

    % Imprimir outros logs
    if strlength(strtrim(line)) > 0
        fprintf("  %s\n", line);
    end
end

if ~finished
    fprintf("AVISO: timeout sem concluir\n");
end

fprintf("Amostras serial: %d\n", numel(slog.t_ms));
fprintf("Amostras buffer: %d\n", numel(buf.t_ms));

% ── Selecionar fonte ──
% Buffer 1kHz só guarda as últimas N amostras e pode não cobrir os 3
% degraus. Usar serial (que captura tudo) quando o buffer não tiver os 3.
useBuf = false;
if numel(buf.t_ms) > 10
    nStepsBuf = numel(unique(buf.step(~isnan(buf.step))));
    if nStepsBuf >= 3
        useBuf = true;
    end
end
if useBuf
    t    = buf.t_ms / 1000.0;
    pw   = buf.pw;
    pos  = buf.pos;
    stepV = buf.step;
    ph   = buf.phase;
    srcLabel = 'buffer 1kHz';
else
    t    = slog.t_ms / 1000.0;
    pw   = slog.pw;
    pos  = slog.pos;
    stepV = slog.step;
    ph   = slog.phase;
    srcLabel = 'serial 5ms';
end

% ── Export CSV ──
scriptDir = fileparts(mfilename('fullpath'));
dadosDir  = fullfile(scriptDir, 'dados');
if ~exist(dadosDir, 'dir'), mkdir(dadosDir); end
ts = datestr(now, 'yyyymmdd_HHMMSS');

if numel(buf.t_ms) > 10
    Tbuf = table(buf.t_ms', buf.step', buf.phase', buf.pw', buf.pos', ...
                 'VariableNames', {'t_ms','step','phase','pw_psi','pos_mm'});
    bufFile = fullfile(dadosDir, sprintf('ensaio_plid_buf1khz_%s.csv', ts));
    writetable(Tbuf, bufFile);
    fprintf("Buffer exportado em: %s\n", bufFile);
end

Tser = table(slog.t_ms', slog.step', slog.phase', slog.pw', slog.pos', ...
             'VariableNames', {'t_ms','step','phase','pw_psi','pos_mm'});
serFile = fullfile(dadosDir, sprintf('ensaio_plid_serial_%s.csv', ts));
writetable(Tser, serFile);
fprintf("Serial exportado em: %s\n", serFile);

% ── Análise por degrau ──
targetPsi = [100, 200, 300];
fprintf("\n══════ RESULTADOS POR DEGRAU ══════\n");
fprintf("  %6s  %8s  %10s  %10s  %10s  %10s\n", ...
        "Degrau", "Alvo_psi", "Pw_cruzam", "Pos_cruzam", "Pw_hold", "Pos_hold");
fprintf("  %6s  %8s  %10s  %10s  %10s  %10s\n", ...
        "------", "--------", "---------", "----------", "-------", "--------");

% Descobrir steps reais presentes nos dados
uSteps = sort(unique(stepV(~isnan(stepV))));
uSteps = uSteps(:)';
if numel(uSteps) > 3, uSteps = uSteps(1:3); end

for k = 1:numel(uSteps)
    ddVal = uSteps(k);
    idxStep = (stepV == ddVal);
    if ~any(idxStep), continue; end

    % Fase 2 = Pressurize, fase 3 = Hold
    idxPress = idxStep & (ph == 2);
    idxHold  = idxStep & (ph == 3);

    % Posição de cruzamento: primeira amostra em Pressurize com Pw >= alvo
    alvo = targetPsi(min(k, numel(targetPsi)));
    posCross = NaN; pwCross = NaN;
    if any(idxPress)
        pwP = pw(idxPress);
        posP = pos(idxPress);
        iCross = find(pwP >= alvo, 1, 'first');
        if ~isempty(iCross)
            posCross = posP(iCross);
            pwCross = pwP(iCross);
        end
    end

    % Médias durante Hold
    pwHoldMean = NaN; posHoldMean = NaN;
    if any(idxHold)
        pwHoldMean = mean(pw(idxHold));
        posHoldMean = mean(pos(idxHold));
    end

    fprintf("  %6d  %8.0f  %10.1f  %10.2f  %10.1f  %10.2f\n", ...
            k, alvo, pwCross, posCross, pwHoldMean, posHoldMean);
end
fprintf("═══════════════════════════════════\n");

% ── Resumo a cada 200ms ──
fprintf("\n--- Resumo a cada 200ms ---\n");
fprintf("  %8s  %6s  %6s  %8s  %8s\n", "t(s)", "step", "phase", "Pw_psi", "pos_mm");
tSample = t(1):0.2:t(end);
for jj = 1:numel(tSample)
    [~, idx] = min(abs(t - tSample(jj)));
    fprintf("  %8.3f  %6.0f  %6.0f  %8.2f  %8.2f\n", ...
            t(idx), stepV(idx), ph(idx), pw(idx), pos(idx));
end

% ── Plot ──
set(groot,'defaultLineLineWidth',1.6);
set(groot,'defaultAxesFontSize',12);
set(groot,'defaultAxesFontName','Times New Roman');
set(groot,'defaultFigureRenderer','painters');

fig1 = figure('Color','w','Position',[50 50 1400 900]);
tiledlayout(2,1,'TileSpacing','compact','Padding','compact');

% 1) Pw x Tempo — cada degrau com tempo relativo (sobrepostos)
nexttile; hold on; grid on;
colors = {'b','r','m'};
legLabels = {};
for k = 1:numel(uSteps)
    ddVal = uSteps(k);
    idx = (stepV == ddVal) & ((ph == 2) | (ph == 3));
    if any(idx)
        tRel = t(idx) - t(find(idx,1));  % tempo relativo ao início do degrau
        cc = colors{min(k, numel(colors))};
        plot(tRel, pw(idx), '-', 'Color', cc, 'LineWidth', 1.5);
        legLabels{end+1} = sprintf('Degrau %d (%d psi)', k, targetPsi(min(k,numel(targetPsi)))); %#ok<SAGROW>
    end
end
yline(100, '--k', '100 psi', 'FontSize', 10);
yline(200, '--k', '200 psi', 'FontSize', 10);
yline(300, '--k', '300 psi', 'FontSize', 10);
ylabel('P_w (psi)', 'FontSize', 16);
title(sprintf('3 Pressoes vs Tempo'), 'FontSize', 18);
if ~isempty(legLabels), legend(legLabels, 'Location', 'best'); end
ylim([-10 max(pw)+20]);
xlabel('Tempo relativo (s)', 'FontSize', 14);

% 2) Pos x Tempo — cada degrau com tempo relativo
nexttile; hold on; grid on;
for k = 1:numel(uSteps)
    ddVal = uSteps(k);
    idx = (stepV == ddVal) & ((ph == 2) | (ph == 3));
    if any(idx)
        tRel = t(idx) - t(find(idx,1));
        cc = colors{min(k, numel(colors))};
        plot(tRel, pos(idx), '-', 'Color', cc, 'LineWidth', 1.5);
    end
end
ylabel('Posicao LAC (mm)', 'FontSize', 16);
xlabel('Tempo relativo (s)', 'FontSize', 16);
title('Posicao do pistao', 'FontSize', 16);

% Export
figDir = fullfile(scriptDir, 'figuras');
if ~exist(figDir, 'dir'), mkdir(figDir); end
exportgraphics(fig1, fullfile(figDir, sprintf('ensaio_plid_%s.pdf', ts)), 'ContentType','vector');
exportgraphics(fig1, fullfile(figDir, sprintf('ensaio_plid_%s.png', ts)), 'Resolution', 1200);
disp('OK: figuras exportadas em:'); disp(figDir);

% ── HOME ──
clear s;
pause(1);
fprintf("\nEnviando HOME...\n");
sHome = serialport(portName, baudRate);
configureTerminator(sHome, "CR/LF");
sHome.Timeout = 0.5;
flush(sHome);
writeline(sHome, "HOME");
tHome = tic;
while toc(tHome) < 20
    try
        hl = readline(sHome);
        if ~ismissing(hl)
            fprintf("  %s\n", hl);
            if contains(hl, "HOME concluido"), break; end
        end
    catch
    end
end
clear sHome;
fprintf("HOME finalizado.\n");
