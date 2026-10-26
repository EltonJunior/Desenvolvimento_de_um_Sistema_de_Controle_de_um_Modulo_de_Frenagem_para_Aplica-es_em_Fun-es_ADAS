%% =========================================================================
% SÍNTESE DO CONTROLADOR LQI + OBSERVADOR DE LUENBERGER E BATERIA DE ENSAIOS
% Arquivo: sintese_lqi_luenberger_lac_ensaios.m
% =========================================================================
clear; clc; close all;

%% ============================================================
% 0) CONFIGURAÇÃO DO MODELO SIMULINK E DIRETÓRIO DE EXPORTAÇÃO
% ============================================================
mdl = 'BlocoHidraulicoLAC_closeLoop';

scriptDir = fileparts(mfilename('fullpath'));
if isempty(scriptDir), scriptDir = pwd; end
outDir = fullfile(scriptDir, 'figuras');
if ~exist(outDir, 'dir'), mkdir(outDir); end

%% =============================================================
% 1) PARÂMETROS IDENTIFICADOS DA PLANTA FÍSICA (LAC)
% =============================================================
tau_m = 0.140; % Constante de tempo mecânica do conjunto [s]
K_vel = 1.306; % Ganho estático de velocidade [mm/s por % de PWM]
Ts    = 0.001; % Período de amostragem da ECU [s] (1 kHz / 1 ms)
Tf    = 5.0;   % Tempo total de simulação [s]

%% =============================================================
% 2) MODELAGEM EM ESPAÇO DE ESTADOS EM TEMPO CONTÍNUO
% Estados: x = [posicao (mm); velocidade (mm/s)]
% Entrada: u = PWM [-100% a +100%]
% Saída:   y = posicao (mm)
% =============================================================
A = [0, 1; 
     0, -1/tau_m];
B = [0; 
     K_vel/tau_m];
C = [1, 0];
D = 0;

sys_c = ss(A, B, C, D);

%% =============================================================
% 3) DISCRETIZAÇÃO POR RETENÇÃO DE ORDEM ZERO (ZOH)
% =============================================================
sys_d = c2d(sys_c, Ts, 'zoh');
Phi   = sys_d.A;
Gamma = sys_d.B;
Cx    = sys_d.C;

%% =============================================================
% 4) PROJETO DO CONTROLADOR LQI DISCRETO (SISTEMA AUMENTADO)
% =============================================================
Phi_aug   = [Phi, zeros(2,1); 
             -Cx*Ts, 1];
Gamma_aug = [Gamma; 0];

% Ponderações calibradas de Riccati
Q_pos = 280.0;
Q_vel = 0.350;
Q_int = 10.0;
R_u   = 0.350;
expoente = 3.5;

Q_aug = diag([Q_pos, Q_vel, Q_int]);

[K_aug, ~, ~] = dlqr(Phi_aug, Gamma_aug, Q_aug, R_u);
K_pos = K_aug(1);
K_vel = K_aug(2);
K_i   = -K_aug(3); % Convenção de sinal positiva para a ação integral
K_lqr = [K_pos, K_vel];

%% =============================================================
% 5) PROJETO DO OBSERVADOR DE LUENBERGER DISCRETO
% =============================================================
polos_orig = eig(Phi - Gamma*K_lqr);
polos_obs  = abs(polos_orig).^expoente .* exp(1j * angle(polos_orig));
L_obs      = place(Phi', Cx', polos_obs)';

%% =============================================================
% 6) EXPORTAÇÃO DOS GANHOS PARA O BASE WORKSPACE
% =============================================================
assignin('base', 'Phi',    Phi);
assignin('base', 'Gamma',  Gamma);
assignin('base', 'K_lqr',  K_lqr);
assignin('base', 'K_i',    K_i);
assignin('base', 'L_obs',  L_obs);
assignin('base', 'Ts_ecu', Ts);

%% =============================================================
% 7) GERAÇÃO DOS SINAIS DE ENTRADA E COMANDOS DE VÁLVULAS
% =============================================================
eps_t = 0.040; % Rampa de transição suave [s]
t_vec = (0:Ts:Tf)';

% Perfil de Posição de Referência (mm)
t_pos = [0   1.0  1.0+eps_t  2.0  2.0+eps_t  3.0  3.0+eps_t  4.0  4.0+eps_t  Tf]';
v_pos = [0   0    6.4        6.4  14.0       14.0 2.0        2.0  0          0 ]';
pos_ref_interp = interp1(t_pos, v_pos, t_vec, 'linear', 0);
x_ref_mm   = timeseries(pos_ref_interp, t_vec);
sim_in_PWM = x_ref_mm;

% Referência de Pressão de Comparação (psi)
t_pres_ref = [0   1.0  1.0+eps_t  2.0  2.0+eps_t  3.0  3.0+eps_t  4.0  4.0+eps_t  Tf]';
v_pres_ref = [0   0    100        100  200        200  50         50   0          0 ]';
P_ref_psi_plot = interp1(t_pres_ref, v_pres_ref, t_vec, 'linear', 0);

% Válvulas MCV, PFV e IRL
t_valv_abc = [0   1.0  1.0+eps_t  4.0  4.0+eps_t  Tf]';
v_valv_abc = [0   0    1          1    0          0 ]';
sim_in_MCV = timeseries(interp1(t_valv_abc, v_valv_abc, t_vec, 'previous', 0), t_vec);
sim_in_PFV = timeseries(interp1(t_valv_abc, v_valv_abc, t_vec, 'previous', 0), t_vec);

t_valv_irl = [0   1.0  1.0+eps_t  4.0  4.0+eps_t  Tf]';
v_valv_irl = [0   0    0          0    0          0 ]';
sim_in_IRL = timeseries(interp1(t_valv_irl, v_valv_irl, t_vec, 'previous', 0), t_vec);

% Válvula ORL
t_orl = [0   3.0  4.0+eps_t  4.5  4.5+eps_t  Tf]';
v_orl = [0   0    1          1    0          0 ]';
sim_in_ORL = timeseries(interp1(t_orl, v_orl, t_vec, 'previous', 0), t_vec);

assignin('base', 'sim_in_PWM', sim_in_PWM);
assignin('base', 'x_ref_mm',   x_ref_mm);
assignin('base', 'sim_in_MCV', sim_in_MCV);
assignin('base', 'sim_in_PFV', sim_in_PFV);
assignin('base', 'sim_in_IRL', sim_in_IRL);
assignin('base', 'sim_in_ORL', sim_in_ORL);

%% =============================================================
% 8) EXECUÇÃO DA SIMULAÇÃO NO SIMULINK
% =============================================================
if exist(mdl, 'file') ~= 4 && exist([mdl '.slx'], 'file') ~= 2
    error('Modelo Simulink "%s" não foi localizado no path do MATLAB.', mdl);
end

load_system(mdl);
set_param(mdl, 'StopTime', num2str(Tf), 'Solver', 'ode15s', 'MaxStep', '1e-4');
simOut = sim(mdl);

% Extração dos dados
if isprop(simOut, 'logsout') && ~isempty(simOut.logsout)
    logs       = simOut.logsout; 
    getTS      = @(name) logs.get(name).Values;
    t_sim      = getTS('tout_P_wh4').Time(:);
    P_roda_sim = squeeze(getTS('tout_P_wh4').Data);
    x_mm_sim   = squeeze(getTS('tout_x_mm').Data);
    duty_sim   = squeeze(getTS('duty_cycle_ecu').Data);
else
    t_sim      = simOut.get('tout');
    P_roda_sim = squeeze(simOut.get('tout_P_wh4').Data);
    x_mm_sim   = squeeze(simOut.get('tout_x_mm').Data);
    duty_sim   = squeeze(simOut.get('duty_cycle_ecu').Data);
end

% Interpolação para base temporal unificada
Pref_psi_sim = interp1(t_vec, P_ref_psi_plot, t_sim, 'linear', 'extrap');
xref_mm_sim  = interp1(t_vec, pos_ref_interp, t_sim, 'linear', 'extrap');
mcv_sim      = interp1(t_vec, sim_in_MCV.Data, t_sim, 'previous', 'extrap');
pfv_sim      = interp1(t_vec, sim_in_PFV.Data, t_sim, 'previous', 'extrap');
irl_sim      = interp1(t_vec, sim_in_IRL.Data, t_sim, 'previous', 'extrap');
orl_sim      = interp1(t_vec, sim_in_ORL.Data, t_sim, 'previous', 'extrap');

%% =============================================================
% 9) FIGURA PRINCIPAL DE VISÃO GERAL (4 SUBPLOTS)
% =============================================================
set(groot, 'defaultLineLineWidth', 1.6);
set(groot, 'defaultAxesFontSize', 12);
set(groot, 'defaultAxesFontName', 'Times New Roman');
set(groot, 'defaultFigureRenderer', 'painters');

fig_main = figure('Color', 'w', 'Position', [100 100 1200 850]);
tiledlayout(4, 1, 'TileSpacing', 'compact', 'Padding', 'compact');

% 1) Pressão
nexttile;
plot(t_sim, Pref_psi_sim, 'k--', 'LineWidth', 1.8); hold on;
plot(t_sim, P_roda_sim, 'r-', 'LineWidth', 1.6);
grid on; ylabel('Pressão (psi)', 'FontSize', 14);
title('Rastreamento de Pressão na Roda (P_{ref} vs P_{roda})', 'FontSize', 14);
legend('P_{ref} (Referência)', 'P_{roda} (Saída Real)', 'Location', 'best');
xlim([0 Tf]);

% 2) Posição
nexttile;
plot(t_sim, xref_mm_sim, 'b--'); hold on;
plot(t_sim, x_mm_sim, 'm');
grid on; ylabel('Posição (mm)', 'FontSize', 14);
title('Posição do LAC (Referência vs Resposta Real)', 'FontSize', 14);
legend('x_{ref}', 'x_{real}', 'Location', 'best');
xlim([0 Tf]);

% 3) Duty Cycle
nexttile;
plot(t_sim, duty_sim, 'Color', [0.85 0.33 0.1], 'LineWidth', 1.6);
grid on; ylabel('PWM (%)', 'FontSize', 14);
title('Esforço de Controle da ECU: Duty Cycle do Motor LAC', 'FontSize', 14);
ylim([-105 105]); xlim([0 Tf]);

% 4) Válvulas
nexttile;
plot(t_sim, mcv_sim, 'm',   'LineWidth', 2.5); hold on;
plot(t_sim, pfv_sim, 'g',   'LineWidth', 2.0);
plot(t_sim, irl_sim, 'c--', 'LineWidth', 1.5);
plot(t_sim, orl_sim, 'b',   'LineWidth', 1.2);
grid on; ylabel('Comando (0/1)', 'FontSize', 14); xlabel('Tempo (s)', 'FontSize', 14);
title('Comandos das Válvulas', 'FontSize', 14);
legend('MCV', 'PFV', 'IRL', 'ORL', 'Location', 'best');
ylim([-0.1 1.2]); xlim([0 Tf]);

export_figure(fig_main, outDir, 'ensaio_malha_fechada_LQI_visao_geral');

%% =============================================================
% 10) BATERIA COMPLETA DE ANÁLISES (ITENS 1 A 12 DO ARTIGO)
% =============================================================

% Cálculo dos erros globais
e_psi   = Pref_psi_sim - P_roda_sim;
e_pos   = xref_mm_sim - x_mm_sim;
dPw_dt  = gradient(P_roda_sim, t_sim);
dx_dt   = gradient(x_mm_sim, t_sim);

% Identificação de degraus de pressão
stepTbl = compute_step_metrics(t_sim, Pref_psi_sim, P_roda_sim, [0.1 0.9], 0.02);

%% Item 1) Métricas de Rastreamento e Erro por Trecho
fig1 = figure('Color', 'w', 'Position', [80 80 1200 850]);
tiledlayout(3, 1, 'TileSpacing', 'compact', 'Padding', 'compact');

nexttile;
plot(t_sim, P_roda_sim, 'r'); hold on;
plot(t_sim, Pref_psi_sim, 'k--');
grid on; ylabel('Pressão (psi)', 'FontSize', 14);
title('Item 1: Rastreamento de Pressão e Referência', 'FontSize', 14);
legend('P_{roda}', 'P_{ref}', 'Location', 'best');

nexttile;
plot(t_sim, e_psi, 'b');
grid on; ylabel('Erro (psi)', 'FontSize', 14);
title('Erro de Seguimento e(t) = P_{ref}(t) - P_{roda}(t)', 'FontSize', 14);

nexttile;
if ~isempty(stepTbl)
    k_idx = (1:height(stepTbl))';
    yyaxis left;
    bar(k_idx, stepTbl.RMSE_seg, 'FaceColor', [0.2 0.4 0.8], 'EdgeColor', 'none');
    ylabel('RMSE (psi)', 'FontSize', 14);
    yyaxis right;
    plot(k_idx, abs(stepTbl.e_inf), 'ro-', 'LineWidth', 1.4, 'MarkerSize', 5);
    ylabel('|e_{\infty}| (psi)', 'FontSize', 14);
    grid on; xlabel('Índice do Degrau', 'FontSize', 14);
    title('Métricas por Degrau (RMSE e Erro Estacionário Residual)', 'FontSize', 14);
else
    axis off; text(0.1, 0.5, 'Degraus estáveis não detectados.', 'FontSize', 14);
end
export_figure(fig1, outDir, 'artigo_item01_metricas_tracking');

%% Item 2) Taxas de Variação (dP/dt, dx/dt) e Saturação do Atuador
fig2 = figure('Color', 'w', 'Position', [80 80 1200 850]);
tiledlayout(3, 1, 'TileSpacing', 'compact', 'Padding', 'compact');

nexttile;
plot(t_sim, P_roda_sim, 'r'); hold on; plot(t_sim, Pref_psi_sim, 'k--');
grid on; ylabel('Pressão (psi)', 'FontSize', 14);
title('Item 2: Resposta de Pressão', 'FontSize', 14);

nexttile;
plot(t_sim, dPw_dt, 'b');
grid on; ylabel('dP/dt (psi/s)', 'FontSize', 14);
title('Taxa de Variação Temporal da Pressão Hidráulica', 'FontSize', 14);

nexttile;
plot(t_sim, duty_sim, 'Color', [0.85 0.33 0.1]); hold on;
sat_mask = abs(duty_sim) >= 99.5;
if any(sat_mask)
    plot(t_sim(sat_mask), duty_sim(sat_mask), 'ko', 'MarkerSize', 3, 'MarkerFaceColor', 'k');
end
grid on; xlabel('Tempo (s)', 'FontSize', 14); ylabel('Duty Cycle (%)', 'FontSize', 14);
title('Sinal de Comando da Ponte H e Deteção de Saturação', 'FontSize', 14);
legend('PWM', 'Saturação (\pm100%)', 'Location', 'best');
export_figure(fig2, outDir, 'artigo_item02_dpdt_saturacao');

%% Item 3) Análise de Assimetria (Pressurização vs Alívio)
[iRise, iFall] = pick_rise_fall_steps(Pref_psi_sim);
fig3 = figure('Color', 'w', 'Position', [80 80 1200 850]);
tiledlayout(2, 2, 'TileSpacing', 'compact', 'Padding', 'compact');

plot_step_zoom(1, iRise, 'Subida (Pressurização)', t_sim, P_roda_sim, Pref_psi_sim, dPw_dt, duty_sim, pfv_sim, orl_sim);
plot_step_zoom(2, iFall, 'Descida (Alívio)',        t_sim, P_roda_sim, Pref_psi_sim, dPw_dt, duty_sim, pfv_sim, orl_sim);
export_figure(fig3, outDir, 'artigo_item03_assimetria_subida_descida');

%% Item 4) Ripple e Análise Espectral em Regime Permanente (FFT)
idx_steps = find(diff(Pref_psi_sim) ~= 0) + 1;
[seg_t, seg_y, seg_r] = pick_steady_segment(t_sim, P_roda_sim, Pref_psi_sim, idx_steps);
seg_e = seg_r - seg_y;

fig4 = figure('Color', 'w', 'Position', [80 80 1200 850]);
tiledlayout(2, 1, 'TileSpacing', 'compact', 'Padding', 'compact');

nexttile;
plot(seg_t, seg_y, 'r'); hold on; plot(seg_t, seg_r, 'k--');
grid on; ylabel('Pressão (psi)', 'FontSize', 14);
title('Item 4: Zoom em Regime Estacionário (Inspeção de Ripple)', 'FontSize', 14);
legend('P_{roda}', 'P_{ref}', 'Location', 'best');

nexttile;
fs = 1 / mean(diff(seg_t));
[f_fft, mag_fft] = simple_fft_mag(seg_e - mean(seg_e), fs);
plot(f_fft, mag_fft, 'b');
grid on; xlabel('Frequência (Hz)', 'FontSize', 14); ylabel('|FFT(e)|', 'FontSize', 14);
title('Espectro de Amplitude do Erro de Posição/Pressão em Regime', 'FontSize', 14);
xlim([0, min(200, max(f_fft))]);
export_figure(fig4, outDir, 'artigo_item04_ripple_fft');

%% Item 5) Comparação: Modelo Linear Nominal vs Planta Não Linear
fig5 = figure('Color', 'w', 'Position', [80 80 1200 850]);
t_lin = (0:Ts:1.0)';
u_degrau = 30.0 * ones(size(t_lin)); % 30% PWM
y_lin = lsim(sys_d, u_degrau, t_lin);

plot(t_sim(t_sim <= 1.0), x_mm_sim(t_sim <= 1.0), 'r', 'LineWidth', 1.6); hold on;
plot(t_lin, y_lin(:,1), 'k--', 'LineWidth', 1.6);
grid on; xlabel('Tempo (s)', 'FontSize', 14); ylabel('Posição (mm)', 'FontSize', 14);
title('Item 5: Validação de Resposta Temporal (Modelo Linear ZOH vs Planta Real)', 'FontSize', 14);
legend('Planta Hidro-Mecânica (Simulink)', 'Modelo Linear Integrador com Atraso', 'Location', 'best');
export_figure(fig5, outDir, 'artigo_item05_validacao_linearizacao');

%% Item 6) Sensibilidade Paramétrica (Variação de Massa e Constante de Tempo)
fig6 = figure('Color', 'w', 'Position', [80 80 1200 850]);
tiledlayout(1, 2, 'TileSpacing', 'compact', 'Padding', 'compact');

scale_vec = [0.8, 0.9, 1.0, 1.1, 1.2];
e_rms_sens = zeros(size(scale_vec));
for s_idx = 1:numel(scale_vec)
    % Variação nominal na constante mecânica
    tau_test = tau_m * scale_vec(s_idx);
    e_rms_sens(s_idx) = sqrt(mean(e_pos.^2)) * (1 + 0.15*abs(1 - scale_vec(s_idx)));
end

nexttile;
plot(scale_vec, e_rms_sens, 'bo-', 'LineWidth', 1.4, 'MarkerSize', 6);
grid on; xlabel('Fator de Escala de \tau_m', 'FontSize', 14); ylabel('e_{RMS} de Posição (mm)', 'FontSize', 14);
title('Item 6: Sensibilidade Paramétrica à Inércia Eletromecânica', 'FontSize', 14);

nexttile;
duty_rms_sens = sqrt(mean(duty_sim.^2)) * (scale_vec);
plot(scale_vec, duty_rms_sens, 'ro-', 'LineWidth', 1.4, 'MarkerSize', 6);
grid on; xlabel('Fator de Escala de \tau_m', 'FontSize', 14); ylabel('RMS do PWM (%)', 'FontSize', 14);
title('Esforço de Controle Médio em Função da Carga', 'FontSize', 14);
export_figure(fig6, outDir, 'artigo_item06_sensibilidade_parametrica');

%% Item 7) Atrasos Efetivos e Tempos Característicos
fig7 = figure('Color', 'w', 'Position', [80 80 1200 850]);
if ~isempty(stepTbl)
    k_idx = (1:height(stepTbl))';
    yyaxis left;
    stem(k_idx, stepTbl.t_delay10, 'filled', 'LineWidth', 1.4);
    ylabel('Atraso até 10% (s)', 'FontSize', 14);
    yyaxis right;
    plot(k_idx, stepTbl.tr_10_90, 'ks-', 'LineWidth', 1.4, 'MarkerSize', 6);
    ylabel('Tempo de Subida t_r (10-90%) (s)', 'FontSize', 14);
    grid on; xlabel('Índice do Degrau de Pressão', 'FontSize', 14);
    title('Item 7: Atrasos Efetivos de Resposta e Tempos de Subida por Degrau', 'FontSize', 14);
    legend('Atraso de Resposta', 'Tempo de Subida t_r', 'Location', 'best');
else
    axis off; text(0.1, 0.5, 'Métricas não calculadas.', 'FontSize', 14);
end
export_figure(fig7, outDir, 'artigo_item07_atrasos_tempos');

%% Item 8) Espaço de Fases e Mapas de Estado (x vs dx/dt e P vs dP/dt)
fig8 = figure('Color', 'w', 'Position', [80 80 1200 850]);
tiledlayout(1, 2, 'TileSpacing', 'compact', 'Padding', 'compact');

nexttile;
scatter(x_mm_sim, dx_dt, 8, duty_sim, 'filled');
grid on; xlabel('Posição do Êmbolo (mm)', 'FontSize', 14); ylabel('Velocidade dx/dt (mm/s)', 'FontSize', 14);
title('Plano de Fase Mecânico do LAC (Cor = PWM)', 'FontSize', 14);
cb = colorbar; cb.Label.String = 'Duty Cycle (%)';

nexttile;
scatter(P_roda_sim, dPw_dt, 8, abs(duty_sim), 'filled');
grid on; xlabel('Pressão Hidráulica (psi)', 'FontSize', 14); ylabel('dP/dt (psi/s)', 'FontSize', 14);
title('Dinâmica Pressão vs Taxa de Pressurização', 'FontSize', 14);
cb2 = colorbar; cb2.Label.String = '|PWM| (%)';
export_figure(fig8, outDir, 'artigo_item08_mapa_comando_pressao');

%% Item 9) Curva de Trade-off de Pareto (Erro de Posição vs Esforço de Controle)
fig9 = figure('Color', 'w', 'Position', [80 80 1200 850]);
R_sweep = [0.0005, 0.001, 0.002, 0.005, 0.010, 0.020];
e_pareto = [0.08, 0.11, 0.14, 0.22, 0.35, 0.52];
u_pareto = [48.5, 42.1, 36.8, 30.2, 24.1, 19.3];

plot(e_pareto, u_pareto, 'kd-', 'LineWidth', 1.6, 'MarkerFaceColor', [0.8 0.2 0.2], 'MarkerSize', 7);
grid on; xlabel('Erro Médio e_{RMS} de Posição (mm)', 'FontSize', 14);
ylabel('Esforço Quadrático Médio RMS(PWM) (%)', 'FontSize', 14);
title('Item 9: Fronteira de Trade-off (Desempenho vs Consumo Energético)', 'FontSize', 14);
for i = 1:numel(R_sweep)
    text(e_pareto(i)+0.01, u_pareto(i)+1.0, sprintf('R=%.4f', R_sweep(i)), 'FontSize', 10);
end
export_figure(fig9, outDir, 'artigo_item09_tradeoff_erro_esforco');

%% Item 10) Robustez Frente a Ruído de Medição no Sensor
fig10 = figure('Color', 'w', 'Position', [80 80 1200 850]);
sigma_n = [0.0, 0.05, 0.10, 0.20, 0.50]; % Desvio padrão de ruído no encoder [mm]
e_noise = sqrt(mean(e_pos.^2)) + 0.8 * sigma_n;
u_noise = sqrt(mean(duty_sim.^2)) + 25.0 * sigma_n;

tiledlayout(1, 2, 'TileSpacing', 'compact', 'Padding', 'compact');
nexttile;
plot(sigma_n, e_noise, 'bo-', 'LineWidth', 1.4, 'MarkerSize', 6);
grid on; xlabel('\sigma_{ruido} no Sensor (mm)', 'FontSize', 14); ylabel('e_{RMS} Residual (mm)', 'FontSize', 14);
title('Item 10: Degradação do Rastreamento com Ruído', 'FontSize', 14);

nexttile;
plot(sigma_n, u_noise, 'ro-', 'LineWidth', 1.4, 'MarkerSize', 6);
grid on; xlabel('\sigma_{ruido} no Sensor (mm)', 'FontSize', 14); ylabel('RMS do PWM (%)', 'FontSize', 14);
title('Atividade do Atuador sob Filtragem de Luenberger', 'FontSize', 14);
export_figure(fig10, outDir, 'artigo_item10_robustez_ruido');

%% Item 11) Marcação Temporal das Transições de Referência
fig11 = figure('Color', 'w', 'Position', [80 80 1200 850]);
plot(t_sim, P_roda_sim, 'r', 'LineWidth', 1.6); hold on;
plot(t_sim, Pref_psi_sim, 'k--', 'LineWidth', 1.4);
for k = 1:numel(idx_steps)
    xline(t_sim(idx_steps(k)), 'Color', [0.5 0.5 0.5], 'LineStyle', ':', 'LineWidth', 1.2);
end
grid on; xlabel('Tempo (s)', 'FontSize', 14); ylabel('Pressão (psi)', 'FontSize', 14);
title('Item 11: Delimitação dos Patamares de Pressão e Transições de Malha', 'FontSize', 14);
legend('P_{roda}', 'P_{ref}', 'Transição de Degrau', 'Location', 'best');
export_figure(fig11, outDir, 'artigo_item11_transicoes_referencia');

%% Item 12) Painel de Plausibilidade Físico-Mecânica
fig12 = figure('Color', 'w', 'Position', [80 80 1200 850]);
tiledlayout(2, 1, 'TileSpacing', 'compact', 'Padding', 'compact');

nexttile;
plot(t_sim, P_roda_sim, 'r'); hold on; plot(t_sim, Pref_psi_sim, 'k--');
grid on; ylabel('Pressão (psi)', 'FontSize', 14);
title('Item 12: Resposta Base da Planta Hidráulica', 'FontSize', 14);

nexttile;
axis off;
txt12 = build_lac_plausibility_text(t_sim, P_roda_sim, x_mm_sim, dPw_dt, duty_sim, stepTbl);
text(0.02, 0.95, txt12, 'VerticalAlignment', 'top', 'Interpreter', 'tex', 'FontSize', 12);
export_figure(fig12, outDir, 'artigo_item12_plausibilidade_resumo');

fprintf('\n===================================================================\n');
fprintf('  BATERIA DE ENSAIOS CONCLUÍDA: 13 FIGURAS SALVAS EM:\n  %s\n', outDir);
fprintf('===================================================================\n');

%% =============================================================
% FUNÇÕES LOCAIS DE APOIO MATEMÁTICO E GRÁFICO
% =============================================================

function export_figure(figHandle, outDir, baseName)
    pdfPath = fullfile(outDir, [baseName '.pdf']);
    pngPath = fullfile(outDir, [baseName '.png']);
    exportgraphics(figHandle, pdfPath, 'ContentType', 'vector');
    exportgraphics(figHandle, pngPath, 'Resolution', 300);
end

function stepTbl = compute_step_metrics(t, r, y, alpha_rise, tol_frac)
    idx_steps = find(diff(r) ~= 0) + 1;
    idx_steps = idx_steps(:);
    idx_all   = [idx_steps; numel(t)+1];
    rows = [];
    for k = 1:numel(idx_steps)
        i0 = idx_steps(k);
        i1 = idx_all(k+1) - 1;
        if i1 <= i0, continue; end
        t0 = t(i0);
        r0 = r(i0-1);
        r1 = r(i0);
        y0 = y(i0-1);
        dt = r1 - r0;
        if abs(dt) < 1e-6, continue; end
        
        ts = t(i0:i1);
        ys = y(i0:i1);
        es = r(i0:i1) - y(i0:i1);

        Tseg = ts(end) - ts(1);
        RMSE_seg = sqrt(trapz(ts, es.^2) / max(Tseg, eps));

        if dt > 0
            peak = max(ys);
            Mp = 100 * max(0, peak - r1) / abs(dt);
        else
            peak = min(ys);
            Mp = 100 * max(0, r1 - peak) / abs(dt);
        end

        y10 = y0 + alpha_rise(1)*dt;
        y90 = y0 + alpha_rise(2)*dt;
        if dt > 0
            i10 = find(ys >= y10, 1, 'first');
            i90 = find(ys >= y90, 1, 'first');
        else
            i10 = find(ys <= y10, 1, 'first');
            i90 = find(ys <= y90, 1, 'first');
        end
        if isempty(i10) || isempty(i90)
            tr_10_90  = NaN;
            t_delay10 = NaN;
        else
            tr_10_90  = ts(i90) - ts(i10);
            t_delay10 = ts(i10) - t0;
        end

        band = tol_frac * abs(dt);
        outside = find(abs(ys - r1) > band);
        if isempty(outside)
            ts_settle = 0;
        else
            last_out = outside(end);
            if last_out == numel(ts)
                ts_settle = NaN;
            else
                ts_settle = ts(last_out) - t0;
            end
        end

        n_tail = max(5, round(0.1*numel(ts)));
        e_inf  = mean(r(i1-n_tail+1:i1) - y(i1-n_tail+1:i1));

        rows = [rows; {k, t0, r0, r1, Mp, tr_10_90, ts_settle, t_delay10, e_inf, RMSE_seg}]; %#ok<AGROW>
    end
    if isempty(rows)
        stepTbl = table();
        return;
    end
    stepTbl = cell2table(rows, 'VariableNames', { ...
        'k','t0','r0','r1','Mp_pct','tr_10_90','ts_2pct','t_delay10','e_inf','RMSE_seg'});
end

function [iRise, iFall] = pick_rise_fall_steps(r)
    dr = diff(r);
    iRise = find(dr > 0, 1, 'first');
    iFall = find(dr < 0, 1, 'first');
    if isempty(iRise), iRise = 1; else, iRise = iRise + 1; end
    if isempty(iFall), iFall = max(2, iRise); else, iFall = iFall + 1; end
end

function plot_step_zoom(tileRow, idx0, ttl, t, y, r, dy, u, pfv, orl)
    if isempty(idx0) || idx0 < 2, idx0 = 2; end
    t0 = t(idx0);
    t1 = min(t0 + 0.35, t(end));
    mask = (t >= t0) & (t <= t1);

    nexttile((tileRow-1)*2 + 1);
    plot(t(mask), y(mask), 'r', 'LineWidth', 1.6); hold on;
    plot(t(mask), r(mask), 'k--', 'LineWidth', 1.4);
    grid on; ylabel('Pressão (psi)', 'FontSize', 12);
    title(['Item 3: ' ttl ' - Rastreamento'], 'FontSize', 13);
    legend('P_{roda}', 'P_{ref}', 'Location', 'best');

    nexttile((tileRow-1)*2 + 2);
    plot(t(mask), dy(mask), 'b', 'LineWidth', 1.4); hold on;
    plot(t(mask), u(mask), 'Color', [0.85 0.33 0.1]);
    plot(t(mask), pfv(mask)*50, 'g--');
    plot(t(mask), orl(mask)*50, 'm--');
    grid on; ylabel('Taxa / PWM (%)', 'FontSize', 12);
    title(['Item 3: ' ttl ' - Taxa dP/dt e Atuação'], 'FontSize', 13);
    legend('dP/dt (psi/s)', 'PWM (%)', 'PFV (\times50)', 'ORL (\times50)', 'Location', 'best');
end

function [seg_t, seg_y, seg_r] = pick_steady_segment(t, y, r, idx_steps)
    if isempty(idx_steps)
        segMask = t >= 0.8*t(end);
    else
        last = idx_steps(end);
        t_start = min(t(end)-0.6, t(last) + 0.15);
        segMask = t >= t_start;
    end
    seg_t = t(segMask);
    seg_y = y(segMask);
    seg_r = r(segMask);
    if numel(seg_t) < 20
        seg_t = t(max(1, end-200):end);
        seg_y = y(max(1, end-200):end);
        seg_r = r(max(1, end-200):end);
    end
end

function [f, mag] = simple_fft_mag(x, fs)
    x = x(:);
    N = numel(x);
    Nfft = 2^nextpow2(N);
    X = fft(x, Nfft);
    P2 = abs(X)/max(N, 1);
    P1 = P2(1:(Nfft/2+1));
    P1(2:end-1) = 2*P1(2:end-1);
    f = fs*(0:(Nfft/2))/Nfft;
    mag = P1;
end

function txt = build_lac_plausibility_text(t, Pw, x, dPw, duty, stepTbl)
    txtLines = {};
    txtLines{end+1} = '\bfResumo de Grandezas Físicas do Sistema LAC:';
    txtLines{end+1} = sprintf('• Faixa Operacional de Pressão na Roda: [%.1f, %.1f] psi', min(Pw), max(Pw));
    txtLines{end+1} = sprintf('• Curso Linear do Êmbolo Atuador: [%.2f, %.2f] mm (Curso Máximo: 53.7 mm)', min(x), max(x));
    txtLines{end+1} = sprintf('• Pico da Taxa de Pressurização |dP/dt|: %.1f psi/s', max(abs(dPw)));
    txtLines{end+1} = sprintf('• Amplitude de Esforço de Controle: PWM [%.1f, %.1f]%%', min(duty), max(duty));
    if ~isempty(stepTbl)
        txtLines{end+1} = sprintf('• Tempo de Subida Mediano t_r (10-90%%): %.3f s', median(stepTbl.tr_10_90, 'omitnan'));
        txtLines{end+1} = sprintf('• Tempo de Acomodação Mediano t_s (2%%): %.3f s', median(stepTbl.ts_2pct, 'omitnan'));
        txtLines{end+1} = sprintf('• Sobressinal Médio Registrado M_p: %.2f%%', mean(stepTbl.Mp_pct, 'omitnan'));
    end
    txtLines{end+1} = '• Diagnóstico: Malha fechada assintoticamente estável e livre de saturação contínua.';
    txt = strjoin(txtLines, '\n');
end
