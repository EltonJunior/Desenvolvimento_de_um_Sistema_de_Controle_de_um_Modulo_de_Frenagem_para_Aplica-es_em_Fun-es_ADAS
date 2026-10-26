% Ajustado para refletir a complacência do sistema real
% Ensaio integrado em malha aberta para o atuador linear LAC
% ensaio_integrado_malha_aberta_real_LAC.m
clear; close all; clc;

mdl = 'BlocoHidraulicoLAC_OpenLoop';
load_system(mdl);

% Tempo total de simulação
Tstop = 5.0; % s

%% --- 1. CONFIGURAÇÃO DOS SINAIS DE ENTRADA (ESTRUTURA DE VETORES) ---

% Sinal PWM: Degrau de 50% de 1.0s a 2.0s
t_pwm = [0   1.0  1.0  2.0  2.0  Tstop]';
v_pwm = [0   0    0.75   0.75   0    0    ]';
sim_in_PWM = timeseries(v_pwm, t_pwm);

% Sinal MCV, PFV e IRL: Abertos de 1.0s a 2.0s
t_valv_abc = [0   1.0  1.0  2.5  2.5  Tstop]';
v_valv_abc = [0   0    1    1    0    0    ]';
sim_in_MCV = timeseries(v_valv_abc, t_valv_abc);
sim_in_PFV = timeseries(v_valv_abc, t_valv_abc);
sim_in_IRL = timeseries(v_valv_abc, t_valv_abc);

% Sinal ORL: Aberto de 3.0s a 4.0s
t_orl = [0   3.0  3.0  4.0  4.0  Tstop]';
v_orl = [0   0    1    1    0    0    ]';
sim_in_ORL = timeseries(v_orl, t_orl);

%% --- 2. ENVIAR SINAIS PARA O WORKSPACE DO MODELO ---
assignin('base', 'sim_in_PWM', sim_in_PWM);
assignin('base', 'sim_in_MCV', sim_in_MCV);
assignin('base', 'sim_in_PFV', sim_in_PFV);
assignin('base', 'sim_in_IRL', sim_in_IRL);
assignin('base', 'sim_in_ORL', sim_in_ORL);

%% --- 3. CONFIGURAÇÃO DO MODELO E SIMULAÇÃO ---
set_param(mdl, 'StopTime', num2str(Tstop), ...
               'Solver',   'ode15s',      ...
               'MaxStep',  '1e-4');

simOut = sim(mdl);

%% --- 4. LEITURA ROBUSTA DE SINAIS DE SAÍDA ---
if isprop(simOut,'logsout') && ~isempty(simOut.logsout)
    logs = simOut.logsout;
    getTS = @(name) logs.get(name).Values;
    tout_P_wh4_ts = getTS('tout_P_wh4');
    tout_x_mm_ts  = getTS('tout_x_mm');
else
    tout_P_wh4_ts = simOut.get('tout_P_wh4');
    tout_x_mm_ts  = simOut.get('tout_x_mm');
end

% Extração dos dados nativos dos timeseries de saída
t_plot_P = tout_P_wh4_ts.Time;
P_data   = tout_P_wh4_ts.Data;

t_plot_x = tout_x_mm_ts.Time;
x_data   = tout_x_mm_ts.Data;

%% --- 5. CONFIGURAÇÃO E GERAÇÃO DOS PLOTS ---
set(groot,'defaultLineLineWidth',1.6);
set(groot,'defaultAxesFontSize',12);
set(groot,'defaultAxesFontName','Times New Roman');
set(groot,'defaultFigureRenderer','painters');

fig = figure('Color','w','Position',[100 100 1200 850]);
tiledlayout(3,1,'TileSpacing','compact','Padding','compact');

% Linha 1: Pressão x Tempo
nexttile;
plot(t_plot_P, P_data, 'r');
grid on; 
ylabel('Pressão (psi)', 'FontSize', 16);
title('Pressão x Tempo', 'FontSize', 16);
xlim([0 Tstop]);

% Linha 2: Posição do LAC x Tempo
nexttile;
plot(t_plot_x, x_data, 'b');
grid on; 
ylabel('Posição do LAC (mm)', 'FontSize', 16);
title('Posição do LAC x Tempo', 'FontSize', 16);
xlim([0 Tstop]);

% Linha 3: Comandos das Válvulas
nexttile;
plot(sim_in_MCV.Time, sim_in_MCV.Data, 'm'); hold on;
plot(sim_in_PFV.Time, sim_in_PFV.Data, 'g');
plot(sim_in_IRL.Time, sim_in_IRL.Data, 'c--');
plot(sim_in_ORL.Time, sim_in_ORL.Data, 'b');
grid on; 
ylabel('Comando (0/1)', 'FontSize', 16);
xlabel('Tempo (s)', 'FontSize', 16);
title('Comandos das Válvulas', 'FontSize', 16);
legend('MCV', 'PFV', 'IRL', 'ORL', 'Location', 'best', 'FontSize', 12);
ylim([-0.1 1.2]);
xlim([0 Tstop]);

%% --- 6. EXPORTAÇÃO COM TIMESTAMP ---
scriptDir = fileparts(mfilename('fullpath'));
outDir = fullfile(scriptDir, 'figuras');
if ~exist(outDir, 'dir'), mkdir(outDir); end

% Geração dinâmica do timestamp
timestamp = datestr(now, 'yyyymmdd_HHMMSS');
filename_base = sprintf('ensaio_malha_aberta_LAC_psi_%s', timestamp);

pdfPath = fullfile(outDir, [filename_base '.pdf']);
pngPath = fullfile(outDir, [filename_base '.png']);

exportgraphics(fig, pdfPath, 'ContentType', 'vector');
exportgraphics(fig, pngPath, 'Resolution', 300); % 300 DPI para agilizar execução

disp('OK: Figuras exportadas com sucesso em:');
disp(pngPath);

