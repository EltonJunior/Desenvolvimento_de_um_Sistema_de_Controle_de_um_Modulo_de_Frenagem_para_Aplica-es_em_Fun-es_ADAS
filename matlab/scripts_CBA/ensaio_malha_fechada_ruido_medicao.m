%% ensaio_malha_fechada_ruido_medicao.m
% Ensaio em malha fechada com ruído de medição em P_w.
%
% Este script pressupõe que o modelo Simulink (Freio_LQR_Model) tenha:
% - um ponto de soma na medição de pressão usada pelo observador;
% - ruído branco habilitável via variável ENABLE_MEAS_NOISE;
% - amplitude controlável via MEAS_NOISE_STD_BAR (em bar);
% - sinal medido logado (ex.: Pw_meas_bar) em logsout.
%
% Se o modelo ainda não tiver esses elementos, o script roda a simulação
% nominal, mas vai falhar ao tentar coletar Pw_meas_bar.

%clear; clc; close all;

%% Reusar o ensaio nominal para projeto/ganhos e referência
% (mantém coerência com os resultados já apresentados)
%run(fullfile(fileparts(mfilename('fullpath')),'ensaio_malha_fechada_lqi.m'));

%% Parâmetros do ruído (ajuste conforme necessário)
ENABLE_MEAS_NOISE = true;
MEAS_NOISE_STD_BAR = 0.5e6; % desvio-padrão em bar

assignin('base','ENABLE_MEAS_NOISE',ENABLE_MEAS_NOISE);
assignin('base','MEAS_NOISE_STD_BAR',MEAS_NOISE_STD_BAR);

% O script chamado acima já gerou e exportou `simulacao_comandos_e_pressao.png`.
% Agora, rodamos de novo o modelo e geramos a figura com o sinal medido.

model = 'Freio_LQR_Model';
load_system(model);

% Recuperar Ts/Tf e Pref_ts do workspace base (criados no script nominal)
Ts = evalin('base','Ts');
Tf = 3;
set_param(model,'Solver','FixedStepDiscrete');
set_param(model,'FixedStep',num2str(Ts));
set_param(model,'StopTime',num2str(Tf));

simOut = sim(model);
logs = simOut.logsout;
getTS = @(name) logs.get(name).Values;

% Sinais básicos
Pw      = getTS('Pw_bar');
Pref    = getTS('Pref_bar');
omega_p = getTS('omega_p');
u_in    = getTS('u_in');
u_out   = getTS('u_out');

% Sinal medido (deve existir quando o ruído estiver implementado)
Pw_meas = getTS('Pw_meas_bar');

Tstop = max(Pw.Time);

%% Figura: referência vs pressão verdadeira vs pressão medida
set(groot,'defaultLineLineWidth',1.6);
set(groot,'defaultAxesFontSize',13);
set(groot,'defaultAxesFontName','Times New Roman');
set(groot,'defaultFigureRenderer','painters');

fig = figure('Color','w','Position',[100 100 1200 850]);
tiledlayout(2,1,'TileSpacing','compact','Padding','compact');

nexttile;
plot(Pref.Time, squeeze(Pref.Data),'k--','LineWidth',1.2); hold on;
plot(Pw.Time,   squeeze(Pw.Data),'b','LineWidth',1.4);
plot(Pw_meas.Time, squeeze(Pw_meas.Data),'r','LineWidth',1.0);
grid on;
ylabel('Pressão (bar)','FontSize',18);
legend('P_{ref}','P_w (verdadeira)','y = P_w + n','Location','best','FontSize',16);

nexttile;
plot(omega_p.Time, squeeze(omega_p.Data),'k'); hold on;
plot(u_in.Time,  squeeze(u_in.Data)*max(squeeze(omega_p.Data)),'b--');
plot(u_out.Time, squeeze(u_out.Data)*max(squeeze(omega_p.Data)),'r--');
grid on; 
xlabel('Tempo (s)','FontSize',18); 
ylabel('Comandos','FontSize',18);
legend('\omega_p','u_{in} (esc.)','u_{out} (esc.)','Location','best','FontSize',16);
xlim([0 Tstop]);

%% Exportar PNG e PDF vetoriais onde o LaTeX espera
scriptDir = fileparts(mfilename('fullpath'));
outDir = fullfile(scriptDir,'figuras');
if ~exist(outDir,'dir'), mkdir(outDir); end
outPng = fullfile(outDir,'artigo_simulacao_ruido_medicao.png');
outPdf = fullfile(outDir,'artigo_simulacao_ruido_medicao.pdf');
exportgraphics(fig, outPng, 'Resolution', 1200);
exportgraphics(fig, outPdf, 'ContentType','vector');

fprintf('OK: figura exportada: %s\n', outPng);
fprintf('OK: figura vetorial exportada: %s\n', outPdf);
