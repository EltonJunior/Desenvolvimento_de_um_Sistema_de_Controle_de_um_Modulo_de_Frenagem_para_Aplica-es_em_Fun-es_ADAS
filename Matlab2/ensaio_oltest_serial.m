% ensaio_oltest_serial.m — Coleta e plot do OLTEST com log de válvulas (limpo)

clear; close all; clc;

% Configuração
portName     = "COM18";
baudRate     = 115200;
Tstop        = 5.0;                 % deve bater com BRAKE_OL_TSTOP_MS
readTimeoutS = Tstop + 2.0;


% Abre serial
s = serialport(portName, baudRate);
configureTerminator(s, "CR/LF");
s.Timeout = 0.2;
flush(s);
cleanupObj = onCleanup(@() clear('s')); %#ok<NASGU>

% Buffers
log.t_ms = []; log.posCmd = []; log.uIn = []; log.uOut = [];
log.pw = []; log.pos = []; log.status = []; log.valveMode = [];

fprintf("Disparando OLTEST...\n");
writeline(s, "OLTEST");

% Leitura
deadline = tic; finished = false;
while toc(deadline) < readTimeoutS
    try
        line = readline(s);
    catch
        continue;
    end
    p = parseOlLine(line);
    if ~isempty(p)
        log.t_ms(end+1)      = p.t_ms; %#ok<*SAGROW>
        log.posCmd(end+1)    = p.posCmd;
        log.uIn(end+1)       = p.uIn;
        log.uOut(end+1)      = p.uOut;
        log.pw(end+1)        = p.pw;
        log.pos(end+1)       = p.pos;
        log.status(end+1)    = p.status;
        log.valveMode(end+1) = p.valveMode;   % 255 = ausente
    else
        fprintf("%s\n", line);
        if contains(line, "OLTEST concluido") || contains(line, "OLTEST falha")
            finished = true;
            break;
        end
    end
end
clear s cleanupObj;

if ~finished
    warning("OLTEST nao confirmou conclusao em %.1fs; plotando assim mesmo.", readTimeoutS);
end
fprintf("Amostras recebidas: %d\n", numel(log.t_ms));


printAndExportSamples(log);
plotResults(log, Tstop);

% ---------------------------- Funções locais -----------------------------

function p = parseOlLine(line)
% Aceita: [OL],t_ms,pos_cmd,u_in,u_out,pw_psi,pos_mm,status[,valve_mode]
    p = [];
    if ~startsWith(line, "[OL],")
        return;
    end
    parts = strsplit(strtrim(extractAfter(line, "[OL],")), ",");
    if numel(parts) < 7, return; end
    toF = @(s) sscanf(strtrim(s), '%f', 1);
    toU = @(s) uint8(sscanf(strtrim(s), '%u', 1));
    p.t_ms   = toF(parts{1});
    p.posCmd = toF(parts{2});
    p.uIn    = toU(parts{3});
    p.uOut   = toU(parts{4});
    p.pw     = toF(parts{5});
    p.pos    = toF(parts{6});
    p.status = toU(parts{7});
    p.valveMode = uint8(255);
    if numel(parts) >= 8
        vm = toU(parts{8});
        if ~isempty(vm), p.valveMode = vm; end
    end
end

function printAndExportSamples(log)
    haveVM = ~isempty(log.valveMode) && any(log.valveMode ~= 255);
    if haveVM
        T = table(log.t_ms', log.posCmd', log.uIn', log.uOut', ...
                  log.pw', log.pos', log.status', log.valveMode', ...
            'VariableNames', {'t_ms','pos_cmd','u_in','u_out','pw_psi','pos_mm','status','valve_mode'});
    else
        T = table(log.t_ms', log.posCmd', log.uIn', log.uOut', ...
                  log.pw', log.pos', log.status', ...
            'VariableNames', {'t_ms','pos_cmd','u_in','u_out','pw_psi','pos_mm','status'});
    end

    fprintf("\n--- Amostras (todas) ---\n");
    disp(T);

    scriptDir = fileparts(mfilename('fullpath'));
    dataDir = fullfile(scriptDir, 'dados');
    if ~exist(dataDir, 'dir'), mkdir(dataDir); end
    csvPath = fullfile(dataDir, sprintf('ensaio_oltest_serial_%s.csv', datestr(now, 'yyyymmdd_HHMMSS')));
    writetable(T, csvPath);
    fprintf("Amostras exportadas em: %s\n", csvPath);

    idx = find(log.pw > 1.0, 1, 'first');
    if ~isempty(idx)
        fprintf("\nInicio real da subida de pressao (Pw>1 PSI): t=%.0f ms, pos=%.2f mm, Pw=%.2f PSI\n", ...
                log.t_ms(idx), log.pos(idx), log.pw(idx));
    end
    [maxPw, idxMax] = max(log.pw);
    fprintf("Pressao maxima: %.2f PSI em pos=%.2f mm (t=%.0f ms)\n", ...
            maxPw, log.pos(idxMax), log.t_ms(idxMax));
end

function plotResults(log, Tstop)
    t = log.t_ms / 1000;

    set(groot,'defaultLineLineWidth',1.6);
    set(groot,'defaultAxesFontSize',12);
    set(groot,'defaultAxesFontName','Times New Roman');
    set(groot,'defaultFigureRenderer','painters');

    fig = figure('Color','w','Position',[100 100 1200 1100]);
    tiledlayout(4,1,'TileSpacing','compact','Padding','compact');

    % Entradas
    nexttile;
    plot(t, log.posCmd, 'k'); hold on;
    ymax = max([max(log.posCmd), 1]);
    plot(t, double(log.uIn) * ymax, 'b--');
    plot(t, double(log.uOut) * ymax, 'r--');
    grid on; ylabel('Pos. cmd (mm)', 'FontSize', 18);
    title('Entradas', 'FontSize', 18);
    legend('pos_{cmd}', 'u_{in} (esc.)', 'u_{out} (esc.)', 'Location', 'best', 'FontSize', 14);
    xlim([0 Tstop]);

    % Pressão
    nexttile;
    plot(t, log.pw, 'r');
    grid on; ylabel('P_w (psi)', 'FontSize', 18);
    title('Pressao (hardware real)', 'FontSize', 18);
    xlim([0 Tstop]);

    % Posição
    nexttile;
    plot(t, log.pos, 'k');
    grid on; ylabel('Posicao LAC (mm)', 'FontSize', 18);
    title('Posicao do atuador', 'FontSize', 18);
    xlim([0 Tstop]);

    % Válvulas
    nexttile;
    [pfv_on, irl_on, orl_on, csv_on] = deriveValveSignals(log);
    off = 0;
    stairs(t, pfv_on + off, 'b', 'LineWidth', 1.4); hold on; off = off + 1.5;
    stairs(t, irl_on + off, 'r', 'LineWidth', 1.4); off = off + 1.5;
    stairs(t, orl_on + off, 'g', 'LineWidth', 1.4); off = off + 1.5;
    stairs(t, csv_on + off, 'm', 'LineWidth', 1.4);
    grid on; ylabel('Estado', 'FontSize', 18); xlabel('Tempo (s)', 'FontSize', 18);
    title('Valvulas (0=off, 1=on)', 'FontSize', 18);
    yticks(0:0.5:6.5);
    yticklabels({'PFV off','PFV on','','IRL off','IRL on','', ...
                 'ORL off','ORL on','','CSV off','CSV on','','',''});
    ylim([-0.5 7]); xlim([0 Tstop]);

    % Export
    scriptDir = fileparts(mfilename('fullpath'));
    outDir = fullfile(scriptDir, 'figuras');
    if ~exist(outDir, 'dir'), mkdir(outDir); end
    exportgraphics(fig, fullfile(outDir, sprintf('ensaio_oltest_serial_%s.pdf', datestr(now, 'yyyymmdd_HHMMSS'))), 'ContentType','vector');
    exportgraphics(fig, fullfile(outDir, sprintf('ensaio_oltest_serial_%s.png', datestr(now, 'yyyymmdd_HHMMSS'))), 'Resolution', 1200);
    disp('OK: figuras exportadas em:'); disp(outDir);
end

function [pfv_on, irl_on, orl_on, csv_on] = deriveValveSignals(log)
% 0=Deenergized, 1=Release, 2=Apply, 3=Hold; 255=indisponível
% PFV (NC) energizada=aberta; IRL (NO) energizada=fechada;
% ORL (NC) energizada=aberta; CSV (NO) energizada=fechada.
    vm = log.valveMode;
    if isempty(vm) || all(vm == 255)
        st = log.status;         % 1=Applying, 2=Holding, 3=Releasing
        pfv_on = double(st == 1);
        irl_on = double(st == 2);
        orl_on = double(st == 3);
        csv_on = double(st == 1);
        return;
    end
    pfv_on = double(vm == 2);
    irl_on = double(vm == 3);
    orl_on = double(vm == 1);
    csv_on = double(vm == 2);
end