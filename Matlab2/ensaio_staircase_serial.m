% ensaio_staircase_serial.m — Curva estática Pos×Pressão (degraus com hold)
% Estrutura de comunicação copiada do ensaio_ramp5c_serial.m (validado)

clear; close all; clc;

% Configuração
portName     = "COM18";
baudRate     = 460800;
% ~25 degraus ida × (move 3s + hold 0.5s) + volta = ~175s + margem
Tstop        = 250.0;
readTimeoutS = Tstop + 5.0;

% Abre serial
s = serialport(portName, baudRate);
configureTerminator(s, "CR/LF");
s.Timeout = 0.2;
flush(s);
cleanupObj = onCleanup(@() clear('s')); %#ok<NASGU>

% Buffers
log.t_ms = []; log.step = []; log.dir = [];
log.target = []; log.pos = []; log.pw = []; log.phase = [];

fprintf("Disparando STAIRCASE...\n");
writeline(s, "STAIRCASE");

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
    p = parseStairLine(line);
    if ~isempty(p)
        log.t_ms(end+1)   = p.t_ms; %#ok<*SAGROW>
        log.step(end+1)   = p.step;
        log.dir(end+1)    = p.dir;
        log.target(end+1) = p.target;
        log.pos(end+1)    = p.pos;
        log.pw(end+1)     = p.pw;
        log.phase(end+1)  = p.phase;
    else
        fprintf("%s\n", line);
        if contains(line, "STAIRCASE concluido") || contains(line, "STAIRCASE falha")
            finished = true;
            break;
        end
    end
end
clear s cleanupObj;

if ~finished
    warning("STAIRCASE nao confirmou conclusao em %.1fs; plotando assim mesmo.", readTimeoutS);
end
fprintf("Amostras recebidas: %d\n", numel(log.t_ms));

printAndExportSamples(log);
plotResults(log);

% ---------------------------- Funções locais -----------------------------

function p = parseStairLine(line)
% Aceita: [STAIR],t_ms,step,dir,target_mm,pos_mm,pw_psi,phase
    p = [];
    if ~startsWith(line, "[STAIR],")
        return;
    end
    parts = strsplit(strtrim(extractAfter(line, "[STAIR],")), ",");
    if numel(parts) < 7, return; end
    toF = @(s) sscanf(strtrim(s), '%f', 1);
    p.t_ms   = toF(parts{1});
    p.step   = toF(parts{2});
    p.dir    = toF(parts{3});
    p.target = toF(parts{4});
    p.pos    = toF(parts{5});
    p.pw     = toF(parts{6});
    p.phase  = toF(parts{7});
end

function printAndExportSamples(log)
    T = table(log.t_ms', log.step', log.dir', log.target', log.pos', log.pw', log.phase', ...
              'VariableNames', {'t_ms','step','dir','target_mm','pos_mm','pw_psi','phase'});

    fprintf("\n--- Amostras (primeiras 50) ---\n");
    disp(T(1:min(50,height(T)),:));
    fprintf("... total: %d amostras\n", height(T));

    scriptDir = fileparts(mfilename('fullpath'));
    dataDir = fullfile(scriptDir, 'dados');
    if ~exist(dataDir, 'dir'), mkdir(dataDir); end
    ts = datestr(now, 'yyyymmdd_HHMMSS');
    csvPath = fullfile(dataDir, sprintf('ensaio_staircase_serial_%s.csv', ts));
    writetable(T, csvPath);
    fprintf("Amostras exportadas em: %s\n", csvPath);

    % Extrair pontos de regime (fase==2 = Holding, últimos 100ms de cada hold)
    idxHold = (log.phase == 2);
    if any(idxHold)
        holdPos = log.pos(idxHold);
        holdPw  = log.pw(idxHold);
        holdDir = log.dir(idxHold);
        holdTgt = log.target(idxHold);

        % Média por degrau (target arredondado)
        targets = unique(round(holdTgt, 2));
        fprintf("\n--- Pontos em regime (hold) ---\n");
        fprintf("  target_mm   pos_mm    pw_psi   dir\n");
        for k = 1:numel(targets)
            idxT = (abs(holdTgt - targets(k)) < 0.01);
            fprintf("  %7.2f   %7.2f   %7.2f   %s\n", ...
                    targets(k), mean(holdPos(idxT)), mean(holdPw(idxT)), ...
                    ternDir(holdDir(find(idxT,1))));
        end
    end
end

function s = ternDir(d)
    if d == 0, s = 'ida'; else, s = 'volta'; end
end

function plotResults(log)
    set(groot,'defaultLineLineWidth',1.6);
    set(groot,'defaultAxesFontSize',12);
    set(groot,'defaultAxesFontName','Times New Roman');
    set(groot,'defaultFigureRenderer','painters');

    t = log.t_ms / 1000;
    idxIda   = (log.dir == 0);
    idxVolta = (log.dir == 1);
    idxHold  = (log.phase == 2);

    % ── Figura 1: Temporal (target + pos + pressão) ──
    fig1 = figure('Color','w','Position',[50 50 1400 900]);
    tiledlayout(3,1,'TileSpacing','compact','Padding','compact');

    nexttile; hold on; grid on;
    plot(t, log.target, '-', 'Color', [0.7 0.7 0.7], 'LineWidth', 1.0);
    plot(t, log.pos, '-b', 'LineWidth', 1.5);
    ylabel('Posição (mm)', 'FontSize', 16);
    title('STAIRCASE — Posição x Tempo', 'FontSize', 18);
    legend('Referência','Real','Location','northwest');

    nexttile; hold on; grid on;
    plot(t, log.pw, '-k', 'LineWidth', 1.5);
    ylabel('P_w (psi)', 'FontSize', 16);
    title('Pressão x Tempo', 'FontSize', 18);

    nexttile; hold on; grid on;
    plot(t, log.phase, '-r', 'LineWidth', 1.0);
    ylabel('Fase', 'FontSize', 16);
    xlabel('Tempo (s)', 'FontSize', 16);
    title('Fase (1=Moving, 2=Holding, 3=Release)', 'FontSize', 14);

    % ── Figura 2: Curva estática Pos×Pressão (ida + volta) ──
    fig2 = figure('Color','w','Position',[100 100 900 700]);
    hold on; grid on;

    % Pontos em regime (Hold) — média por degrau
    idxHoldIda   = idxHold & idxIda;
    idxHoldVolta = idxHold & idxVolta;

    if any(idxHoldIda)
        [posIda, pwIda] = avgByTarget(log.target(idxHoldIda), log.pos(idxHoldIda), log.pw(idxHoldIda));
        plot(posIda, pwIda, '-ob', 'LineWidth', 2, 'MarkerSize', 6, 'MarkerFaceColor', 'b');
    end
    if any(idxHoldVolta)
        [posVolta, pwVolta] = avgByTarget(log.target(idxHoldVolta), log.pos(idxHoldVolta), log.pw(idxHoldVolta));
        plot(posVolta, pwVolta, '-sr', 'LineWidth', 2, 'MarkerSize', 6, 'MarkerFaceColor', 'r');
    end

    xlabel('Posição LAC (mm)', 'FontSize', 18);
    ylabel('P_w (psi)', 'FontSize', 18);
    title('Curva Estática: Posição x Pressão (regime)', 'FontSize', 18);
    if any(idxHoldIda) && any(idxHoldVolta)
        legend('Ida','Volta','Location','northwest','FontSize',14);
    elseif any(idxHoldIda)
        legend('Ida','Location','northwest','FontSize',14);
    end

    % Export
    scriptDir = fileparts(mfilename('fullpath'));
    outDir = fullfile(scriptDir, 'figuras');
    if ~exist(outDir, 'dir'), mkdir(outDir); end
    ts = datestr(now, 'yyyymmdd_HHMMSS');
    exportgraphics(fig1, fullfile(outDir, sprintf('ensaio_staircase_temporal_%s.pdf', ts)), 'ContentType','vector');
    exportgraphics(fig1, fullfile(outDir, sprintf('ensaio_staircase_temporal_%s.png', ts)), 'Resolution', 1200);
    exportgraphics(fig2, fullfile(outDir, sprintf('ensaio_staircase_curva_%s.pdf', ts)), 'ContentType','vector');
    exportgraphics(fig2, fullfile(outDir, sprintf('ensaio_staircase_curva_%s.png', ts)), 'Resolution', 1200);
    disp('OK: figuras exportadas em:'); disp(outDir);
end

function [posAvg, pwAvg] = avgByTarget(targets, pos, pw)
    uTargets = unique(round(targets, 2));
    posAvg = zeros(size(uTargets));
    pwAvg  = zeros(size(uTargets));
    for k = 1:numel(uTargets)
        idx = (abs(targets - uTargets(k)) < 0.01);
        posAvg(k) = mean(pos(idx));
        pwAvg(k)  = mean(pw(idx));
    end
end
