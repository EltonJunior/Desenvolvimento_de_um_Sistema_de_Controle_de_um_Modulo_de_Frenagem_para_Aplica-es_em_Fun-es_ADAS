%% ensaio_oltest_serial.m
% Dispara o OLTEST embarcado (perfil fixo em brake_uart_test.c) via COM18,
% aguarda o firmware rodar sozinho e so entao plota, no mesmo layout de
% ensaio_integrado_malha_aberta_real.m. Psup/Qpump/Qin/Qout nao existem no
% hardware (sem sensor de vazao/pressao de suprimento); so Pw e as entradas
% sao reais.

clear; close all; clc;

portName  = "COM18";
baudRate  = 115200;
Tstop     = 4.0;   % s, deve bater com BRAKE_OL_TSTOP_MS no firmware
readTimeoutS = Tstop + 2.0; % folga para a mensagem final de conclusao chegar

s = serialport(portName, baudRate);
configureTerminator(s, "CR/LF");
s.Timeout = 0.2;
flush(s);
cleanupObj = onCleanup(@() clear('s')); %#ok<NASGU>

log.t_ms = []; log.omega = []; log.uIn = []; log.uOut = [];
log.pw = []; log.pos = []; log.status = [];

fprintf("Disparando OLTEST...\n");
writeline(s, "OLTEST");

deadline = tic;
finished = false;
while toc(deadline) < readTimeoutS
    try
        line = readline(s);
    catch
        continue;
    end

    parsed = parseOlLine(line);
    if ~isempty(parsed)
        log.t_ms(end+1)   = parsed.t_ms; %#ok<*SAGROW>
        log.omega(end+1)  = parsed.omega;
        log.uIn(end+1)    = parsed.uIn;
        log.uOut(end+1)   = parsed.uOut;
        log.pw(end+1)     = parsed.pw;
        log.pos(end+1)    = parsed.pos;
        log.status(end+1) = parsed.status;
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
    warning("OLTEST nao confirmou conclusao dentro de %.1fs; plotando o que chegou.", readTimeoutS);
end
fprintf("Amostras recebidas: %d\n", numel(log.t_ms));

printAndExportSamples(log);
plotResults(log, Tstop);

%% ------------------------------------------------------------------
function printAndExportSamples(log)
    T = table(log.t_ms', log.omega', log.uIn', log.uOut', log.pw', log.pos', log.status', ...
              'VariableNames', {'t_ms','omega_p','u_in','u_out','pw_psi','pos_mm','status'});

    fprintf("\n--- Amostras (todas) ---\n");
    disp(T);

    scriptDir = fileparts(mfilename('fullpath'));
    dataDir = fullfile(scriptDir, 'dados');
    if ~exist(dataDir, 'dir'), mkdir(dataDir); end
    csvPath = fullfile(dataDir, 'ensaio_oltest_serial.csv');
    writetable(T, csvPath);
    fprintf("Amostras exportadas em: %s\n", csvPath);

    % Ponto de "tomada de folga": primeira amostra com pressao > 1 PSI.
    idx = find(log.pw > 1.0, 1, 'first');
    if ~isempty(idx)
        fprintf("\nInicio real da subida de pressao (Pw>1 PSI): t=%.0f ms, pos=%.2f mm, Pw=%.2f PSI\n", ...
                log.t_ms(idx), log.pos(idx), log.pw(idx));
    end

    [maxPw, idxMax] = max(log.pw);
    fprintf("Pressao maxima: %.2f PSI em pos=%.2f mm (t=%.0f ms)\n", ...
            maxPw, log.pos(idxMax), log.t_ms(idxMax));
end

%% ------------------------------------------------------------------
function parsed = parseOlLine(line)
    parsed = [];
    prefix = "[OL],";
    if ~startsWith(line, prefix)
        return;
    end

    payload = extractAfter(line, prefix);
    tokens = sscanf(payload, '%f,%f,%f,%f,%f,%f,%f');
    if numel(tokens) ~= 7
        return;
    end

    parsed.t_ms   = tokens(1);
    parsed.omega  = tokens(2);
    parsed.uIn    = tokens(3);
    parsed.uOut   = tokens(4);
    parsed.pw     = tokens(5);
    parsed.pos    = tokens(6);
    parsed.status = tokens(7);
end

function plotResults(log, Tstop)
    t = log.t_ms / 1000;

    set(groot,'defaultLineLineWidth',1.6);
    set(groot,'defaultAxesFontSize',12);
    set(groot,'defaultAxesFontName','Times New Roman');
    set(groot,'defaultFigureRenderer','painters');

    fig = figure('Color','w','Position',[100 100 1200 850]);
    tiledlayout(3,1,'TileSpacing','compact','Padding','compact');

    nexttile;
    plot(t, log.omega, 'k'); hold on;
    ymax = max([max(log.omega), 1]);
    plot(t, double(log.uIn) * ymax, 'b--');
    plot(t, double(log.uOut) * ymax, 'r--');
    grid on; ylabel('\omega_p (rad/s)', 'FontSize', 18);
    title('Entradas', 'FontSize', 18);
    legend('\omega_p', 'u_{in} (esc.)', 'u_{out} (esc.)', 'Location', 'best', 'FontSize', 16);
    xlim([0 Tstop]);

    nexttile;
    plot(t, log.pw, 'r');
    grid on; ylabel('P_w (psi)', 'FontSize', 18); title('Pressao (hardware real)', 'FontSize', 18);
    xlim([0 Tstop]);

    nexttile;
    plot(t, log.pos, 'k');
    grid on; ylabel('Posicao LAC (mm)', 'FontSize', 18); xlabel('Tempo (s)', 'FontSize', 18);
    title('Posicao do atuador', 'FontSize', 18);
    xlim([0 Tstop]);

    scriptDir = fileparts(mfilename('fullpath'));
    outDir = fullfile(scriptDir, 'figuras');
    if ~exist(outDir, 'dir'), mkdir(outDir); end

    pdfPath = fullfile(outDir, 'ensaio_oltest_serial.pdf');
    pngPath = fullfile(outDir, 'ensaio_oltest_serial.png');
    exportgraphics(fig, pdfPath, 'ContentType', 'vector');
    exportgraphics(fig, pngPath, 'Resolution', 1200);

    disp('OK: figuras exportadas em:');
    disp(outDir);
end
