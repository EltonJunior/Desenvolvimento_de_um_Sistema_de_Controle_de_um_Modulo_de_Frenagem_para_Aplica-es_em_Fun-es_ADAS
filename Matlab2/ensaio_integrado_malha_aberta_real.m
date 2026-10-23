%% artigo_ensaio_integrado_malha_aberta_real.m
% Ensaio integrado em malha aberta (configuração realista)
%
% Fases:
% A: pressurização (0–2 s): bomba ligada, inlet aberta, outlet fechada
% B: retenção     (2–3 s): bomba desligada, válvulas fechadas
% C: alívio       (3–4 s): bomba desligada, inlet fechada, outlet aberta
%
% Observação importante (consistência com o artigo):
% - As válvulas são tratadas como comandos binários u_in,u_out ∈ {0,1}.

clear; close all; clc;

mdl = 'BlocoHidraulico';   % modelo Simulink que chama Bloco_Hidraulico_2P
load_system(mdl);

% Tempo total e condições iniciais
Tstop = 4.0;   % s
Pret  = 1e5;   % Pa
Psup0 = Pret;
Pw0   = Pret;
assignin('base','Pret',Pret);
assignin('base','Psup0',Psup0);
assignin('base','Pw0',Pw0);

% Fases
tA_end = 2.0;
tB_end = 3.0;
tC_end = Tstop;

%% Sinal da bomba: omega_p(t)
% Valores de referência:
% - MotorParametricDesign2023 usa ~1000 rpm (≈104.7 rad/s) para AEB com motor elétrico.
% - Aqui utiliza-se ~100 rad/s (≈955 rpm) no platô, para obter transientes coerentes.

t_omega = [0   0.5 0.5  1  1  tA_end ...
           tA_end tB_end tB_end tC_end]';
v_omega = [0   0    80   80  100  100  ...
           0     0    0    0   ]';
omega_p_ts = timeseries(v_omega, t_omega);

%% Sinal da válvula de entrada: u_in(t)
% Fase A: aberta; Fases B e C: fechada.

t_uin = [0    tA_end tA_end tC_end]';
v_uin = [1       1      0      0 ]';
u_in_ts = timeseries(v_uin, t_uin);

%% Sinal da válvula de saída: u_out(t)
% Fases A e B: fechada; Fase C: aberta.

t_uout = [0    tB_end tB_end tC_end]';
v_uout = [0       0      1.0   1.0 ]';
u_out_ts = timeseries(v_uout, t_uout);

%% Enviar sinais para o workspace do modelo
assignin('base','omega_p_ts',omega_p_ts);
assignin('base','u_in_ts',u_in_ts);
assignin('base','u_out_ts',u_out_ts);

%% Configuração do modelo e simulação
set_param(mdl, 'StopTime', num2str(Tstop), ...
               'Solver',   'ode15s',      ...
               'MaxStep',  '1e-4');

simOut = sim(mdl);

%% Leitura de sinais
if isprop(simOut,'logsout') && ~isempty(simOut.logsout)
    logs = simOut.logsout;
    getTS = @(name) logs.get(name).Values;
    Psup    = getTS('Psup_bar_g');
    Pw      = getTS('Pw_bar_g');
    Qpump   = getTS('Qpump_mLs');
    Qin     = getTS('Qin_mLs');
    Qout    = getTS('Qout_mLs');
    omega_p = getTS('omega_p');
    u_in    = getTS('u_in');
    u_out   = getTS('u_out');
else
    Psup    = simOut.get('Psup_bar_g');
    Pw      = simOut.get('Pw_bar_g');
    Qpump   = simOut.get('Qpump_mLs');
    Qin     = simOut.get('Qin_mLs');
    Qout    = simOut.get('Qout_mLs');
    omega_p = simOut.get('omega_p');
    u_in    = simOut.get('u_in');
    u_out   = simOut.get('u_out');
end

Psup_g_bar = Psup.Data;   % bar (gauge)
Pw_g_bar   = Pw.Data;     % bar (gauge)
Qpump_ml_s = Qpump.Data;  % mL/s
Qin_ml_s   = Qin.Data;
Qout_ml_s  = Qout.Data;

%% Configuração de plots
set(groot,'defaultLineLineWidth',1.6);
set(groot,'defaultAxesFontSize',12);
set(groot,'defaultAxesFontName','Times New Roman');
set(groot,'defaultFigureRenderer','painters');

fig = figure('Color','w','Position',[100 100 1200 850]);
tiledlayout(3,1,'TileSpacing','compact','Padding','compact');

% Entradas
nexttile;
plot(omega_p.Time, omega_p.Data,'k'); hold on;
plot(u_in.Time,  u_in.Data*max(omega_p.Data),'b--');
plot(u_out.Time, u_out.Data*max(omega_p.Data),'r--');
grid on; ylabel('\omega_p (rad/s)','FontSize',18);
title('Entradas','FontSize',18);
legend('\omega_p','u_{in} (esc.)','u_{out} (esc.)','Location','best','FontSize',16);
ymax = max(omega_p.Data); margem = 0.1*ymax;
ylim([-max(2,margem), ymax + max(2,margem)]);
xlim([0 Tstop]);

% Pressões
nexttile;
plot(Psup.Time, Psup_g_bar,'b'); hold on;
plot(Pw.Time,   Pw_g_bar,'r');
grid on; ylabel('Pressão (bar)','FontSize',18); title('Pressões','FontSize',18);
legend('P_{sup}','P_w','Location','best','FontSize',16);
ymin = min([Psup_g_bar(:); Pw_g_bar(:)]);
ymax = max([Psup_g_bar(:); Pw_g_bar(:)]);
ylim([min(ymin,0) ymax + 5]);
xlim([0 Tstop]);

% Vazões
nexttile;
plot(Qpump.Time, Qpump_ml_s,'k'); hold on;
plot(Qin.Time,   Qin_ml_s,'b');
plot(Qout.Time,  Qout_ml_s,'r');
grid on; ylabel('Vazão (mL/s)','FontSize',18); xlabel('Tempo (s)','FontSize',18);
title('Vazões','FontSize',18);
legend('Q_{pump}','Q_{in}','Q_{out}','Location','best','FontSize',16);
ylim([-20 40]);
xlim([0 Tstop]);

%% Exportar figuras
scriptDir = fileparts(mfilename('fullpath'));
outDir = fullfile(scriptDir,'figuras');
if ~exist(outDir,'dir'), mkdir(outDir); end

pdfPath = fullfile(outDir,'artigo_ensaio_malha_aberta_integrado_real.pdf');
pngPath = fullfile(outDir,'artigo_ensaio_malha_aberta_integrado_real.png');
exportgraphics(fig, pdfPath, 'ContentType','vector');
exportgraphics(fig, pngPath, 'Resolution', 1200);

disp('OK: figuras exportadas em:');
disp(outDir);
