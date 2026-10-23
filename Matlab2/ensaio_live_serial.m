%% ensaio_live_serial.m
% Abre a serial da AURIX (COM18), dispara o modo LIVE, envia o perfil
% omega_p/u_in/u_out (mesma forma do artigo/gerar_sinais_malha_aberta_placa.m)
% e plota Pw/posicao a partir da telemetria [LIVE] recebida de volta.
%
% Pre-requisito: firmware ja gravado, com "LIVE START"/"OMEGA_P=..." aceitos
% (brake_uart_test.c). Nao depende de Simulink.

clear; clc;

portName   = "COM18";
baudRate   = 115200;
Tstop      = 4.0;

% Mesmo perfil de Matlab/gerar_sinais_malha_aberta_placa.m
tRampa = 0.5; tPlato = 1.0; tAEnd = 2.0; tBEnd = 3.0;
omegaRampa = 80; omegaPlato = 100;

s = serialport(portName, baudRate);
configureTerminator(s, "CR/LF");
s.Timeout = 0.05; % readline() must never block longer than this on a partial line
flush(s);
cleanupObj = onCleanup(@() localStop(s));

log.t = []; log.omega = []; log.uIn = []; log.uOut = [];
log.pw = []; log.pos = []; log.status = [];

fprintf("Iniciando LIVE...\n");
writeline(s, "LIVE START");
pause(0.2);
drainLines(s);

% Envia um comando, espera a resposta do firmware refletir esse comando (ou
% estoura o timeout do passo) antes de mandar o proximo - sincrono, sem laco
% livre disputando tempo com a leitura serial.
stepPeriodS   = 0.10;  % passo do perfil enviado (>= tempo de log do firmware)
stepTimeoutS  = 0.30;  % quanto esperar a resposta bater com o que foi mandado
tSteps = 0:stepPeriodS:Tstop;

for t = tSteps
    [omega, uIn, uOut] = referenceProfile(t, tRampa, tPlato, tAEnd, tBEnd, omegaRampa, omegaPlato);
    txLine = sprintf("OMEGA_P=%.2f,U_IN=%u,U_OUT=%u", omega, uIn, uOut);
    fprintf("TX t=%.2f: %s\n", t, txLine);
    writeline(s, txLine);

    stepStart = tic;
    matched = false;
    while toc(stepStart) < stepTimeoutS
        while s.NumBytesAvailable > 0
            try
                line = readline(s);
            catch
                break;
            end
            parsed = parseLiveLine(line);
            if ~isempty(parsed)
                fprintf("RX t=%.2f: %s\n", t, line);
                log.t(end+1)      = t; %#ok<*SAGROW>
                log.omega(end+1)  = parsed.omega;
                log.uIn(end+1)    = parsed.uIn;
                log.uOut(end+1)   = parsed.uOut;
                log.pw(end+1)     = parsed.pw;
                log.pos(end+1)    = parsed.pos;
                log.status(end+1) = parsed.status;
                if (parsed.uIn == uIn) && (parsed.uOut == uOut)
                    matched = true;
                end
            else
                fprintf("%s\n", line);
            end
        end
        if matched
            break;
        end
        pause(0.005);
    end

    if ~matched
        fprintf("t=%.2f: firmware nao confirmou U_IN=%u,U_OUT=%u dentro de %.2fs\n", ...
                t, uIn, uOut, stepTimeoutS);
    end
end

fprintf("Enviando LIVE STOP...\n");
writeline(s, "LIVE STOP");
pause(0.2);
drainLines(s);
clear s cleanupObj;

plotResults(log);

%% ------------------------------------------------------------------
function localStop(s)
    try
        writeline(s, "LIVE STOP");
    catch
    end
end

function drainLines(s)
    while s.NumBytesAvailable > 0
        try
            fprintf("%s\n", readline(s));
        catch
            break;
        end
    end
end

function [omega, uIn, uOut] = referenceProfile(t, tRampa, tPlato, tAEnd, tBEnd, omegaRampa, omegaPlato)
    if t < tRampa
        omega = 0;
    elseif t < tPlato
        omega = omegaRampa;
    elseif t < tAEnd
        omega = omegaPlato;
    else
        omega = 0;
    end

    if t < tAEnd
        uIn = 1; uOut = 0;
    elseif t < tBEnd
        uIn = 0; uOut = 0;
    else
        uIn = 0; uOut = 1;
    end
end

function parsed = parseLiveLine(line)
    parsed = [];
    prefix = "[LIVE],";
    if ~startsWith(line, prefix)
        return;
    end

    payload = extractAfter(line, prefix);
    tokens = sscanf(payload, '%f,%f,%f,%f,%f,%f');
    if numel(tokens) ~= 6
        return;
    end

    parsed.omega  = tokens(1);
    parsed.uIn    = tokens(2);
    parsed.uOut   = tokens(3);
    parsed.pw     = tokens(4);
    parsed.pos    = tokens(5);
    parsed.status = tokens(6);
end

function plotResults(log)
    figure('Name', 'Ensaio LIVE - malha aberta');

    subplot(3,1,1);
    plot(log.t, log.pw, '-o');
    ylabel('Pw [psi]'); grid on;

    subplot(3,1,2);
    plot(log.t, log.omega, '-o'); hold on;
    stairs(log.t, double(log.uIn) * 50, 'r');
    stairs(log.t, double(log.uOut) * 50, 'g');
    ylabel('omega_p / u\_in,u\_out (esc.)');
    legend('omega_p', 'u_{in} x50', 'u_{out} x50');
    grid on;

    subplot(3,1,3);
    plot(log.t, log.pos, '-o');
    ylabel('pos [mm]'); xlabel('t [s]'); grid on;
end
