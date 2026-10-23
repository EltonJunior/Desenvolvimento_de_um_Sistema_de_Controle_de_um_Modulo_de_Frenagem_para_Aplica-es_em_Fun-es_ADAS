% ensaio_ramp5_serial.m — Executa 5 rampas com velocidades diferentes e plota
% Baseado no ensaio_oltest_serial e ensaio_ramptest_serial

clear; close all; clc;

% Configuração
portName     = "COM18";   % ajuste
baudRate     = 115200;
numRuns      = 5;
Tstop        = 6.0;       % por run; ajuste se mudar no firmware
readTimeoutS = Tstop + 3.0;

% Perfis de rampa (frações do intervalo 0.5–3.5 s)
% O firmware atual usa 0.5s idle + 3.0s rampa. Para "outras velocidades",
% enviaremos comandos dedicados via UART (RAMP5SPEED n). Até termos isso,
% este script roda 5 vezes o RAMPTEST padrão e anota a curva por run.

s = serialport(portName, baudRate);
configureTerminator(s, "CR/LF");
s.Timeout = 0.2;
flush(s);
cleanupObj = onCleanup(@() clear('s')); %#ok<NASGU>

allLogs = cell(numRuns,1);

for k = 1:numRuns
    fprintf("Disparando RAMPTEST (%d/%d)...\n", k, numRuns);
    writeline(s, "RAMPTEST");

    log = collectRampLog(s, readTimeoutS);
    allLogs{k} = log;

    pause(1.0); % espaçamento entre runs
end

clear s cleanupObj;

% Export e gráficos
scriptDir = fileparts(mfilename('fullpath'));
dataDir = fullfile(scriptDir, 'dados'); if ~exist(dataDir,'dir'), mkdir(dataDir); end
outDir  = fullfile(scriptDir, 'figuras'); if ~exist(outDir,'dir'), mkdir(outDir); end

% Exportar CSVs
for k = 1:numRuns
    log = allLogs{k};
    T = table(log.t_ms', log.posCmd', log.uIn', log.uOut', log.pw', log.pos', log.status', ...
        'VariableNames', {'t_ms','pos_cmd','u_in','u_out','pw_psi','pos_mm','status'});
    writetable(T, fullfile(dataDir, sprintf('ensaio_ramp5_serial_run%d_%s.csv', k, datestr(now,'yyyymmdd_HHMMSS'))));
end

% Figura: sobrepor P vs Pos por run (fase de rampa)
fig = figure('Color','w','Position',[100 100 1200 800]);
hold on; grid on;
colors = lines(numRuns);
for k = 1:numRuns
    log = allLogs{k};
    t = log.t_ms/1000;
    idxRamp = (t >= 0.5) & (t <= 3.5) & (log.uIn == 1);
    plot(log.pos(idxRamp), log.pw(idxRamp), '.-', 'Color', colors(k,:), 'DisplayName', sprintf('Run %d', k));
end
xlabel('Pos (mm)'); ylabel('P_w (psi)'); title('RAMP5: Curvas P vs Pos (5 runs)'); legend('Location','best');
exportgraphics(fig, fullfile(outDir, sprintf('ensaio_ramp5_%s.png', datestr(now,'yyyymmdd_HHMMSS'))), 'Resolution', 1200);

% --- Funções locais ---
function log = collectRampLog(s, readTimeoutS)
    log.t_ms = []; log.posCmd = []; log.uIn = []; log.uOut = [];
    log.pw = []; log.pos = []; log.status = []; log.valveMode = [];
    deadline = tic; finished = false;
    while toc(deadline) < readTimeoutS
        try
            line = readline(s);
        catch
            continue;
        end
        p = parseRampLine(line);
        if ~isempty(p)
            log.t_ms(end+1)      = p.t_ms; %#ok<*AGROW>
            log.posCmd(end+1)    = p.posCmd;
            log.uIn(end+1)       = p.uIn;
            log.uOut(end+1)      = p.uOut;
            log.pw(end+1)        = p.pw;
            log.pos(end+1)       = p.pos;
            log.status(end+1)    = p.status;
            log.valveMode(end+1) = p.valveMode;
        else
            if contains(line, "RAMPTEST concluido") || contains(line, "RAMPTEST falha")
                finished = true; break;
            end
        end
    end
    if ~finished
        warning("RAMPTEST nao confirmou conclusao em %.1fs; utilizando dados coletados.", readTimeoutS);
    end
end

function p = parseRampLine(line)
    p = [];
    if ~startsWith(line, "[RAMP],")
        return;
    end
    parts = strsplit(strtrim(extractAfter(line, "[RAMP],")), ",");
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
        vm = toU(parts{8}); if ~isempty(vm), p.valveMode = vm; end
    end
end