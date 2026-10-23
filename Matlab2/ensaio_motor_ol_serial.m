% ensaio_motor_ol_serial.m — Coleta e plot do PWMSWEEP (malha aberta, varios PWMs)
% Estrutura de comunicacao copiada do ensaio_ramp5c_serial.m (validado)

clear; close all; clc;

% Configuração
portName     = "COM18";
baudRate     = 460800;
% 6 corridas × (Release 3s + HOME ~3s + Settle ~2s + RUN ate 10s) = ~108s + margem
Tstop        = 180.0;
readTimeoutS = Tstop + 5.0;

% Cores para cada corrida
curveColors = {'b','r','k','m',[0 0.6 0],[0.8 0.4 0]};
curveLabels = {'8%','15%','25%','50%','75%','100%'};

% Abre serial
s = serialport(portName, baudRate);
configureTerminator(s, "CR/LF");
s.Timeout = 0.2;
flush(s);
cleanupObj = onCleanup(@() clear('s')); %#ok<NASGU>

% Buffers — serial em tempo real (5ms)
log.t_ms = []; log.step = []; log.pwm = [];
log.pw = []; log.pos = [];

% Buffers — dump 1kHz do buffer RAM
buf.run_ms = []; buf.step = []; buf.pwm = [];
buf.pos = []; buf.pw = [];
curBufStep = 0;
curBufPwm = 0;

fprintf("Disparando PWMSWEEP...\n");
writeline(s, "PWMSWEEP");

% Leitura
% NOTA: diferente do RAMP5C, o PWMSWEEP fica em silencio durante o homing
% (3-5 segundos). Nesse intervalo readline retorna <missing> e qualquer
% funcao de texto (startsWith, contains, fprintf) falha. Por isso o bloco
% abaixo testa ischar/isstring antes de processar — unica diferenca em
% relacao ao loop do ensaio_ramp5c_serial.m.
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
    % Parse serial 5ms
    p = parsePwmSwLine(line);
    if ~isempty(p)
        log.t_ms(end+1) = p.t_ms; %#ok<*SAGROW>
        log.step(end+1) = p.step;
        log.pwm(end+1)  = p.pwm;
        log.pw(end+1)   = p.pw;
        log.pos(end+1)  = p.pos;
    % Parse buffer header [BUF] count,step,pwm
    elseif startsWith(line, '[BUF] ')
        parts = strsplit(strtrim(extractAfter(line, '[BUF] ')), ',');
        if numel(parts) >= 3
            curBufStep = sscanf(parts{2}, '%f', 1);
            curBufPwm  = sscanf(parts{3}, '%f', 1);
        end
    % Parse buffer sample [B],run_ms,pos_x100,pw_x100
    elseif startsWith(line, '[B],')
        parts = strsplit(strtrim(extractAfter(line, '[B],')), ',');
        if numel(parts) >= 3
            buf.run_ms(end+1) = sscanf(parts{1}, '%f', 1);
            buf.step(end+1)   = curBufStep;
            buf.pwm(end+1)    = curBufPwm;
            buf.pos(end+1)    = sscanf(parts{2}, '%f', 1) / 100.0;
            buf.pw(end+1)     = sscanf(parts{3}, '%f', 1) / 100.0;
        end
    else
        fprintf("%s\n", line);
        if contains(line, "PWMSWEEP concluido") || contains(line, "PWMSWEEP falha")
            finished = true;
            break;
        end
    end
end
clear s cleanupObj;

if ~finished
    warning("PWMSWEEP nao confirmou conclusao em %.1fs; plotando assim mesmo.", readTimeoutS);
end
fprintf("Amostras serial (5ms): %d\n", numel(log.t_ms));
fprintf("Amostras buffer (1kHz): %d\n", numel(buf.run_ms));

printAndExportSamples(log, buf);
plotResults(log, buf, curveColors, curveLabels);

% ---------------------------- Funções locais -----------------------------

function p = parsePwmSwLine(line)
% Aceita: [PWMSW],t_ms,step,pwm_pct,pw_psi,pos_mm
% Estrutura copiada do parseR5CLine (ensaio_ramp5c_serial.m)
    p = [];
    try
        if ~startsWith(line, "[PWMSW],")
            return;
        end
    catch
        return;
    end
    parts = strsplit(strtrim(extractAfter(line, "[PWMSW],")), ",");
    if numel(parts) < 5, return; end
    toF = @(s) sscanf(strtrim(s), '%f', 1);
    p.t_ms = toF(parts{1});
    p.step = toF(parts{2});
    p.pwm  = toF(parts{3});
    p.pw   = toF(parts{4});
    p.pos  = toF(parts{5});
end

function printAndExportSamples(log, buf)
    scriptDir = fileparts(mfilename('fullpath'));
    dataDir = fullfile(scriptDir, 'dados');
    if ~exist(dataDir, 'dir'), mkdir(dataDir); end
    ts = datestr(now, 'yyyymmdd_HHMMSS');

    % Serial 5ms
    T = table(log.t_ms', log.step', log.pwm', log.pw', log.pos', ...
        'VariableNames', {'t_ms','step','pwm_pct','pw_psi','pos_mm'});
    fprintf("\n--- Amostras serial (primeiras 50) ---\n");
    disp(T(1:min(50,height(T)),:));
    fprintf("... total: %d amostras\n", height(T));
    csvPath = fullfile(dataDir, sprintf('ensaio_pwmsweep_serial_%s.csv', ts));
    writetable(T, csvPath);
    fprintf("Serial exportado em: %s\n", csvPath);

    % Buffer 1kHz
    if ~isempty(buf.run_ms)
        Tb = table(buf.run_ms', buf.step', buf.pwm', buf.pw', buf.pos', ...
            'VariableNames', {'run_ms','step','pwm_pct','pw_psi','pos_mm'});
        fprintf("\n--- Amostras buffer 1kHz (primeiras 50) ---\n");
        disp(Tb(1:min(50,height(Tb)),:));
        fprintf("... total: %d amostras\n", height(Tb));
        csvBuf = fullfile(dataDir, sprintf('ensaio_pwmsweep_buf1khz_%s.csv', ts));
        writetable(Tb, csvBuf);
        fprintf("Buffer exportado em: %s\n", csvBuf);
    end

    % Sumario por corrida (buffer 1kHz)
    src = buf; srcName = 'buf';
    if isempty(src.run_ms), src = log; srcName = 'serial'; end
    steps = unique(src.step);
    for k = 1:numel(steps)
        idxC = src.step == steps(k);
        if ~any(idxC), continue; end
        [maxPw, im] = max(src.pw(idxC));
        posC = src.pos(idxC);
        pwmC = src.pwm(idxC);
        fprintf("Corrida %d (PWM=%.0f%%, %s): Pmax=%.1f PSI @ pos=%.2f mm\n", ...
                steps(k), pwmC(1), srcName, maxPw, posC(im));
    end
end

function plotResults(log, buf, curveColors, curveLabels)
    % Usa buffer 1kHz se disponivel, senao serial
    if ~isempty(buf.run_ms)
        src = buf;
        srcLabel = '1 kHz';
        timeField = 'run_ms';
    else
        src = log;
        srcLabel = '5 ms';
        timeField = 't_ms';
    end

    set(groot,'defaultLineLineWidth',1.6);
    set(groot,'defaultAxesFontSize',12);
    set(groot,'defaultAxesFontName','Times New Roman');
    set(groot,'defaultFigureRenderer','painters');

    steps = unique(src.step);
    nSteps = numel(steps);
    tData = src.(timeField);

    % ── Figura 1: Temporal (pos + pressao), tempo relativo por corrida ──
    fig1 = figure('Color','w','Position',[50 50 1400 900]);
    tiledlayout(2,1,'TileSpacing','compact','Padding','compact');

    nexttile; hold on; grid on;
    for k = 1:nSteps
        idx = (src.step == steps(k));
        t_local = (tData(idx) - tData(find(idx,1))) / 1000;
        cc = curveColors{min(k,numel(curveColors))};
        plot(t_local, src.pos(idx), '-', 'Color', cc, 'LineWidth', 1.5);
    end
    ylabel('Posicao (mm)', 'FontSize', 16);
    title(sprintf('PWMSWEEP — Posicao x Tempo (%s)', srcLabel), 'FontSize', 18);
    legend(curveLabels(1:nSteps), 'Location', 'northwest', 'FontSize', 12);

    nexttile; hold on; grid on;
    for k = 1:nSteps
        idx = (src.step == steps(k));
        t_local = (tData(idx) - tData(find(idx,1))) / 1000;
        cc = curveColors{min(k,numel(curveColors))};
        plot(t_local, src.pw(idx), '-', 'Color', cc, 'LineWidth', 1.5);
    end
    xlabel('Tempo da corrida (s)', 'FontSize', 16);
    ylabel('P_w (psi)', 'FontSize', 16);
    title('Pressao x Tempo', 'FontSize', 18);
    legend(curveLabels(1:nSteps), 'Location', 'northwest', 'FontSize', 12);

    % ── Figura 2: Curva estatica Pos x Pressao (linhas, sobrepostas) ──
    fig2 = figure('Color','w','Position',[100 100 900 700]);
    hold on; grid on;
    legendEntries = {};
    for k = 1:nSteps
        idx = (src.step == steps(k));
        if ~any(idx), continue; end
        cc = curveColors{min(k,numel(curveColors))};
        plot(src.pos(idx), src.pw(idx), '-', 'Color', cc, 'LineWidth', 1.5);
        legendEntries{end+1} = sprintf('PWM %s', curveLabels{k}); %#ok<AGROW>
    end
    xlabel('Posicao LAC (mm)', 'FontSize', 18);
    ylabel('P_w (psi)', 'FontSize', 18);
    title(sprintf('Curva Estatica: Pos x Pressao (%s)', srcLabel), 'FontSize', 18);
    legend(legendEntries, 'Location', 'northwest', 'FontSize', 14);
    % Export
    scriptDir = fileparts(mfilename('fullpath'));
    outDir = fullfile(scriptDir, 'figuras');
    if ~exist(outDir, 'dir'), mkdir(outDir); end
    ts = datestr(now, 'yyyymmdd_HHMMSS');
    exportgraphics(fig1, fullfile(outDir, sprintf('ensaio_pwmsweep_temporal_%s.pdf', ts)), 'ContentType','vector');
    exportgraphics(fig1, fullfile(outDir, sprintf('ensaio_pwmsweep_temporal_%s.png', ts)), 'Resolution', 1200);
    exportgraphics(fig2, fullfile(outDir, sprintf('ensaio_pwmsweep_curvas_%s.pdf', ts)), 'ContentType','vector');
    exportgraphics(fig2, fullfile(outDir, sprintf('ensaio_pwmsweep_curvas_%s.png', ts)), 'Resolution', 1200);
    disp('OK: figuras exportadas em:'); disp(outDir);
end
