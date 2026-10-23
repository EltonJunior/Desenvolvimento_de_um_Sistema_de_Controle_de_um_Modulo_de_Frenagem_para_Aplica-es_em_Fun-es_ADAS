%% ensaio_echo_serial.m
% Teste de comunicacao/protocolo (sem hardware real): manda [ECHO]<omega,u_in,u_out>
% seguindo o mesmo perfil do ensaio, le a resposta [ECHO],... e plota, so para
% validar porta serial, parsing e escala dos graficos antes do ensaio LIVE real.

clear; clc;

portName    = "COM18";
baudRate    = 115200;
sendPeriodS = 0.05;
Tstop       = 4.0;
replyTimeoutS = 0.2;

tRampa = 0.5; tPlato = 1.0; tAEnd = 2.0; tBEnd = 3.0;
omegaRampa = 80; omegaPlato = 100;

s = serialport(portName, baudRate);
configureTerminator(s, "CR/LF");
s.Timeout = replyTimeoutS;
flush(s);
cleanupObj = onCleanup(@() clear('s')); %#ok<NASGU>

log.t = []; log.omega = []; log.uIn = []; log.uOut = [];
log.pw = []; log.pos = []; log.status = [];

fprintf("Iniciando ECHO...\n");

tSteps = 0:sendPeriodS:Tstop;
for t = tSteps
    [omega, uIn, uOut] = referenceProfile(t, tRampa, tPlato, tAEnd, tBEnd, omegaRampa, omegaPlato);

    writeline(s, sprintf("[ECHO]<%.2f,%u,%u>", omega, uIn, uOut));

    line = "";
    try
        line = readline(s);
    catch
        fprintf("t=%.2f: sem resposta (timeout)\n", t);
        continue;
    end

    parsed = parseEchoLine(line);
    if isempty(parsed)
        fprintf("t=%.2f: linha inesperada: %s\n", t, line);
        continue;
    end

    log.t(end+1)      = t; %#ok<*SAGROW>
    log.omega(end+1)  = parsed.omega;
    log.uIn(end+1)    = parsed.uIn;
    log.uOut(end+1)   = parsed.uOut;
    log.pw(end+1)     = parsed.pw;
    log.pos(end+1)    = parsed.pos;
    log.status(end+1) = parsed.status;
end

clear s cleanupObj;

fprintf("Recebidas %d respostas de %d envios.\n", numel(log.t), numel(tSteps));
plotResults(log);

%% ------------------------------------------------------------------
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

function parsed = parseEchoLine(line)
    parsed = [];
    prefix = "[ECHO],";
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
    figure('Name', 'Ensaio ECHO - validacao de protocolo');

    subplot(3,1,1);
    plot(log.t, log.pw, '-o');
    ylabel('Pw [psi] (aleatorio)'); grid on;

    subplot(3,1,2);
    plot(log.t, log.omega, '-o'); hold on;
    stairs(log.t, double(log.uIn) * 50, 'r');
    stairs(log.t, double(log.uOut) * 50, 'g');
    ylabel('omega_p / u\_in,u\_out (esc.)');
    legend('omega_p', 'u_{in} x50', 'u_{out} x50');
    grid on;

    subplot(3,1,3);
    plot(log.t, log.pos, '-o');
    ylabel('pos [mm] (aleatorio)'); xlabel('t [s]'); grid on;
end
