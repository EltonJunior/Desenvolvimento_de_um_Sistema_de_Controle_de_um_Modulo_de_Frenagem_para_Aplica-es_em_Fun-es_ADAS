%% =========================================================================
% SÍNTESE DO CONTROLADOR LQI, OBSERVADOR DE LUENBERGER E SIMULAÇÃO DO LAC
% Arquivo: sintese_lqi_luenberger_lac.m
% =========================================================================
clear; clc; close all;

%% 1. PARÂMETROS IDENTIFICADOS DA PLANTA FÍSICA (LAC)
% Conforme Capítulo 4 e ensaios experimentais com o AURIX TC375
tau_m = 0.140; % Constante de tempo mecânica do conjunto [s]
K_vel = 1.306; % Ganho estático de velocidade [mm/s por % de PWM]
Ts = 0.001;    % Período de amostragem da ECU [s] (1 kHz / 1 ms)
Tf = 5.0;      % Tempo total de simulação [s]
mdl = 'BlocoHidraulicoLAC_closeLoop'; % Nome do seu modelo Simulink

%% 2. MODELAGEM EM ESPAÇO DE ESTADOS EM TEMPO CONTÍNUO
% Estados: x = [posicao (mm); velocidade (mm/s)]
% Entrada: u = PWM [-100% a +100%]
% Saída: y = posicao (mm)
A = [0, 1; 0, -1/tau_m];
B = [0; K_vel/tau_m];
C = [1, 0];
D = 0;

sys_c = ss(A, B, C, D);

%% 3. DISCRETIZAÇÃO POR RETENÇÃO DE ORDEM ZERO (ZOH)
sys_d = c2d(sys_c, Ts, 'zoh');
Phi = sys_d.A;
Gamma = sys_d.B;
Cx = sys_d.C;

%% 4. PROJETO DO CONTROLADOR LQI DISCRETO (SISTEMA AUMENTADO)
% Vetor aumentado: x_aug = [posicao; velocidade; erro_integral]
% Dinâmica do integrador: z[k+1] = z[k] + Ts*(x_ref - y)
Phi_aug = [Phi, zeros(2,1); -Cx*Ts, 1];
Gamma_aug = [Gamma; 0];

% % Parâmetros de ajuste (Ponderação de Riccati)
% % Q_pos = 25.0;      % Aumentado de 10.0 para 25.0: resposta mais rápida ao erro de posição
% % Q_vel = 1.20;      % Aumentado de 0.05 para 1.20: introduz forte amortecimento ativo (elimina o overshoot)
% % Q_int = 15.0;      % Reduzido de 35.0 para 15.0: previne acúmulo excessivo da ação integral
% % R_u   = 0.02;      % Reduzido de 0.08 para 0.02: confere mais autoridade de torque ao motor contra a carga
Q_pos = 280.0;
Q_vel = 0.350;
Q_int = 10.0;
R_u   = 0.350;
expoente = 3.5;
% Q_pos = 40.0;       % Rapidez de resposta de posição
% Q_vel = 0.85;       % AMORTECIMENTO ATIVO: elimina a saturação reversa de -100% e suaviza a chegada
% Q_int = 25.0;       % AUMENTADO: anula a cauda de acomodação em menos de 50 ms
% R_u   = 0.035;      % CUSTO DO ESFORÇO: evita saturação espúria da ponte H
% 
% expoente = 2.0;     % Observador: polos rápidos o suficiente sem introduzir ruído

Q_aug = diag([Q_pos, Q_vel, Q_int]);

% Resolução da Equação Algébrica de Riccati Discreta
[K_aug, ~, ~] = dlqr(Phi_aug, Gamma_aug, Q_aug, R_u);

K_pos = K_aug(1);
K_vel = K_aug(2);
K_i = -K_aug(3); % Convenção de sinal positiva para a ação integral
K_lqr = [K_pos, K_vel];

%% 5. PROJETO DO OBSERVADOR DE LUENBERGER DISCRETO
% Alocação de polos: 3 a 4 vezes mais rápidos que a malha fechada do LQI
polos_orig = eig(Phi - Gamma*K_lqr);
%polos_obs = abs(polos_orig).^3.5 .* exp(1j * angle(polos_orig));
polos_obs  = abs(polos_orig).^expoente .* exp(1j * angle(polos_orig)); % Expoente ajustado para 2.5

% Alocação no sistema dual
L_obs = place(Phi', Cx', polos_obs)';

%% 6. EXPORTAÇÃO PARA O BASE WORKSPACE DO SIMULINK
assignin('base', 'Phi', Phi);
assignin('base', 'Gamma', Gamma);
assignin('base', 'K_lqr', K_lqr);
assignin('base', 'K_i', K_i);
assignin('base', 'L_obs', L_obs);
assignin('base', 'Ts_ecu', Ts);

%% 7. EXIBIÇÃO NO CONSOLE E GERAÇÃO DE CÓDIGO PARA FIRMWARE C
fprintf('===================================================================\n');
fprintf('       PARÂMETROS CALCULADOS PARA SIMULINK E FIRMWARE C (1 kHz)    \n');
fprintf('===================================================================\n');
fprintf('// Copie e cole no arquivo de header do firmware C (.h):\n\n');
fprintf('#define BRAKE_LAC_TS     (%.6ff)\n', Ts);
fprintf('#define BRAKE_LAC_PHI11  (%.12ff)\n', Phi(1,1));
fprintf('#define BRAKE_LAC_PHI12  (%.12ff)\n', Phi(1,2));
fprintf('#define BRAKE_LAC_PHI21  (%.12ff)\n', Phi(2,1));
fprintf('#define BRAKE_LAC_PHI22  (%.12ff)\n', Phi(2,2));
fprintf('#define BRAKE_LAC_GAMMA1 (%.12ff)\n', Gamma(1));
fprintf('#define BRAKE_LAC_GAMMA2 (%.12ff)\n', Gamma(2));
fprintf('#define BRAKE_LAC_LQR_K1 (%.8ff)\n', K_pos);
fprintf('#define BRAKE_LAC_LQR_K2 (%.8ff)\n', K_vel);
fprintf('#define BRAKE_LAC_LQR_KI (%.8ff)\n', K_i);
fprintf('#define BRAKE_LAC_OBS_L1 (%.8ff)\n', L_obs(1));
fprintf('#define BRAKE_LAC_OBS_L2 (%.8ff)\n', L_obs(2));
fprintf('===================================================================\n');

%% 8. GERAÇÃO DOS SINAIS DE ENTRADA MULTIFASE (VETORES COORDENADOS)
% Previne o erro de pontos repetidos gerando degraus limpos
eps_t = 0.040; %1e-5; 
t_vec = (0:Ts:Tf)';

% Perfil de Posição de Referência desejado para o LAC (em milímetros)
% Modifique os valores abaixo para alterar o formato do degrau em mm
t_pos = [0   1.0  1.0+eps_t  2.0  2.0+eps_t  3.0  3.0+eps_t  4.0  4.0+eps_t  Tf]';
v_pos = [0   0    6.4        6.4  14.0       14.0 2.0        2.0  0          0 ]'; % Curso em mm

% Interpolação e criação do timeseries da Posição
pos_ref_interp = interp1(t_pos, v_pos, t_vec, 'previous', 0);
x_ref_mm = timeseries(pos_ref_interp, t_vec);
sim_in_PWM = x_ref_mm;


%% --- NOVA ADIÇÃO: REFERÊNCIA DE PRESSÃO EM PSI ---
% Defina os pontos de tempo e pressão desejados em PSI para a referência visual
t_pres_ref = [0   1.0  1.0+eps_t  2.0  2.0+eps_t  3.0  3.0+eps_t  4.0  4.0+eps_t  Tf]';
v_pres_ref = [0   0    100        100  200        200  50         50   0          0 ]'; % Valores em PSI
P_ref_psi_plot = interp1(t_pres_ref, v_pres_ref, t_vec, 'previous', 0);

% Sinais das Válvulas MCV, PFV e IRL (Abertas de 1.0s a 2.0s como exemplo)
t_valv_abc = [0   1.0  1.0+eps_t  4.0  4.0+eps_t  Tf]';
v_valv_abc = [0   0    1          1    0          0 ]';
sim_in_MCV = timeseries(interp1(t_valv_abc, v_valv_abc, t_vec, 'previous', 0), t_vec);
sim_in_PFV = timeseries(interp1(t_valv_abc, v_valv_abc, t_vec, 'previous', 0), t_vec);

t_valv_irl = [0   1.0  1.0+eps_t  4.0  4.0+eps_t  Tf]';
v_valv_irl = [0   0    0         0    0          0 ]';
sim_in_IRL = timeseries(interp1(t_valv_irl, v_valv_irl, t_vec, 'previous', 0), t_vec);

% Sinal da Válvula ORL (Aberta de 3.0s a 4.0s)
t_orl = [0   1.0   1.0+eps_t    3.30    3.30+eps_t  3.335  3.335+eps_t  4.0  4.0+eps_t  4.5  4.5+eps_t  Tf]';
v_orl = [0   0      0           0      0          0    0          0    1          1    0          0 ]';
sim_in_ORL = timeseries(interp1(t_orl, v_orl, t_vec, 'previous', 0), t_vec);

%% 9. ENVIAR SINAIS PARA O WORKSPACE DO MODELO
assignin('base', 'sim_in_PWM', sim_in_PWM);
assignin('base', 'x_ref_mm', x_ref_mm);
assignin('base', 'sim_in_MCV', sim_in_MCV);
assignin('base', 'sim_in_PFV', sim_in_PFV);
assignin('base', 'sim_in_IRL', sim_in_IRL);
assignin('base', 'sim_in_ORL', sim_in_ORL);

%% 10. EXECUÇÃO DA SIMULAÇÃO
if exist(mdl, 'file') == 4 || exist([mdl '.slx'], 'file') == 2
    load_system(mdl);
    set_param(mdl, 'StopTime', num2str(Tf), 'Solver', 'ode15s', 'MaxStep', '1e-4');
    simOut = sim(mdl);
    
    % Coleta de dados via logsout ou chamada direta
    if isprop(simOut,'logsout') && ~isempty(simOut.logsout)
        logs = simOut.logsout; getTS = @(name) logs.get(name).Values;
        t_sim = getTS('tout_P_wh4').Time;
        P_roda_sim = getTS('tout_P_wh4').Data;
        x_mm_sim = getTS('tout_x_mm').Data;
        duty_sim = getTS('duty_cycle_ecu').Data;
    else
        t_sim = simOut.get('tout');
        P_roda_sim = simOut.get('tout_P_wh4').Data;
        x_mm_sim = simOut.get('tout_x_mm').Data;
        duty_sim = simOut.get('duty_cycle_ecu').Data;
    end

    %% 11. GERAÇÃO DOS PLOTS (PADRÃO TIMES NEW ROMAN)
    set(groot,'defaultLineLineWidth',1.6);
    set(groot,'defaultAxesFontSize',12);
    set(groot,'defaultAxesFontName','Times New Roman');
    set(groot,'defaultFigureRenderer','painters');

    fig = figure('Color','w','Position',[100 100 1200 850]);
    tiledlayout(4,1,'TileSpacing','compact','Padding','compact');

    % Linha 1: Pressão da Roda x Tempo
    nexttile;
    plot(t_vec, P_ref_psi_plot, 'k--', 'LineWidth', 1.8); hold on; % Linha de Referência
    plot(t_sim, P_roda_sim, 'r-', 'LineWidth', 1.6);              % Resposta Real da Planta
    grid on; 
    ylabel('Pressão (psi)', 'FontSize', 14);
    title('Rastreamento de Pressão na Roda (P_{ref} vs P_{roda})', 'FontSize', 14);
    legend('P_{ref} (Referência)', 'P_{roda} (Saída Real)', 'Location', 'best');
    xlim([0 Tf]);

    % Linha 2: Resposta de Posição Real vs Referência
    nexttile;
    plot(t_vec, pos_ref_interp, 'b--'); hold on;
    plot(t_sim, x_mm_sim, 'm');
    grid on; ylabel('Posição do LAC (mm)', 'FontSize', 14);
    title('Posição do LAC (Referência vs Resposta Real)', 'FontSize', 14);
    legend('x_{ref}', 'x_{real}', 'Location', 'best');
    xlim([0 Tf]);

    % Linha 3: Sinal de Esforço de Controle Duty Cycle ECU ---
    nexttile;
    plot(t_sim, duty_sim, 'Color', [0.85 0.33 0.1], 'LineWidth', 1.6); % Cor Laranja
    grid on; ylabel('Sinal PWM (%)', 'FontSize', 14);
    title('Esforço de Controle da ECU: Duty Cycle do Motor LAC', 'FontSize', 14);
    ylim([-105 105]); % Limite físico padrão da ponte H (-100% a +100%)
    xlim([0 Tf]);

    % Linha 3: Comandos das Válvulas
    nexttile;
    plot(t_vec, sim_in_MCV.Data, 'm',  'LineWidth', 3.5); hold on;
    plot(t_vec, sim_in_PFV.Data, 'g',  'LineWidth', 2.0);
    plot(t_vec, sim_in_IRL.Data, 'c--',  'LineWidth', 1.5);
    plot(t_vec, sim_in_ORL.Data, 'b',  'LineWidth', 1.0);
    grid on; ylabel('Comando (0/1)', 'FontSize', 14); xlabel('Tempo (s)', 'FontSize', 14);
    title('Comandos das Válvulas', 'FontSize', 14);
    legend('MCV', 'PFV', 'IRL', 'ORL', 'Location', 'best');
    ylim([-0.1 1.2]); xlim([0 Tf]);

    %% 12. EXPORTAÇÃO DA FIGURA COM TIMESTAMP
    scriptDir = fileparts(mfilename('fullpath'));
    outDir = fullfile(scriptDir, 'figuras');
    if ~exist(outDir, 'dir'), mkdir(outDir); end

    timestamp = datestr(now, 'yyyymmdd_HHMMSS');
    pngPath = fullfile(outDir, sprintf('ensaio_malha_fechada_LQI_%s.png', timestamp));
    exportgraphics(fig, pngPath, 'Resolution', 300);
    disp('OK: Gráfico de controle salvo em:'); disp(pngPath);
else
    warning('Modelo Simulink "%s" não foi encontrado no caminho atual.', mdl);
end


% %% =========================================================================
% % SÍNTESE DO CONTROLADOR LQI E OBSERVADOR DE LUENBERGER PARA O LAC
% % Arquivo: sintese_lqi_luenberger_lac.m
% % =========================================================================
% clear; clc;
% 
% %% 1. PARÂMETROS IDENTIFICADOS DA PLANTA FÍSICA (LAC)
% % Conforme Capítulo 4 e ensaios experimentais com o AURIX TC375
% tau_m   = 0.053;         % Constante de tempo mecânica do conjunto [s]
% K_vel   = 1.306;         % Ganho estático de velocidade [mm/s por % de PWM]
% Ts      = 0.001;         % Período de amostragem da ECU [s] (1 kHz / 1 ms)
% 
% %% 2. MODELAGEM EM ESPAÇO DE ESTADOS EM TEMPO CONTÍNUO
% % Estados: x = [posicao (mm); velocidade (mm/s)]
% % Entrada: u = PWM [-100% a +100%]
% % Saída:   y = posicao (mm)
% A = [0,  1;
%     0, -1/tau_m];
% 
% B = [0;
%     K_vel/tau_m];
% 
% C = [1, 0];
% D = 0;
% 
% sys_c = ss(A, B, C, D);
% 
% %% 3. DISCRETIZAÇÃO POR RETENÇÃO DE ORDEM ZERO (ZOH)
% sys_d = c2d(sys_c, Ts, 'zoh');
% Phi   = sys_d.A
% Gamma = sys_d.B
% Cx    = sys_d.C;
% 
% %% 4. PROJETO DO CONTROLADOR LQI DISCRETO (SISTEMA AUMENTADO)
% % Vetor aumentado: x_aug = [posicao; velocidade; erro_integral]
% % Dinâmica do integrador: z[k+1] = z[k] + Ts*(x_ref - y)
% Phi_aug = [Phi,          zeros(2,1);
%     -Cx*Ts,        1];
% 
% Gamma_aug = [Gamma; 
%     0];
% 
% % =========================================================================
% % PARÂMETROS DE AJUSTE (PONDERAÇÃO DE RICCATI) - ALTERE AQUI PARA AJUSTAR
% % =========================================================================
% Q_pos = 10.0; %15.0;            % Penalização do erro de posição (aumente para acelerar)
% Q_vel = 0.05;            % Amortecimento de velocidade (aumente para frear oscilações)
% Q_int = 35.0;            % Penalização da ação integral (aumente para vencer atrito estático)
% Q_aug = diag([Q_pos, Q_vel, Q_int]);
% 
% R_u   = 0.08;            % Custo do esforço de controle PWM (diminua para mais torque)
% 
% % Resolução da Equação Algébrica de Riccati Discreta
% [K_aug, ~, polos_mf] = dlqr(Phi_aug, Gamma_aug, Q_aug, R_u);
% 
% K_pos = K_aug(1);
% K_vel = K_aug(2);
% K_i   = -K_aug(3)       % Convenção de sinal positiva para a ação integral
% 
% K_lqr = [K_pos, K_vel]
% 
% %% 5. PROJETO DO OBSERVADOR DE LUENBERGER DISCRETO
% % Alocação de polos: 3 a 4 vezes mais rápidos que a malha fechada do LQI
% polos_orig = eig(Phi - Gamma*K_lqr);
% polos_obs  = abs(polos_orig).^3.5 .* exp(1j * angle(polos_orig));
% 
% % Alocação no sistema dual
% L_obs = place(Phi', Cx', polos_obs)'
% 
% %% 6. EXPORTAÇÃO PARA O BASE WORKSPACE DO SIMULINK
% assignin('base', 'Phi',    Phi);
% assignin('base', 'Gamma',  Gamma);
% assignin('base', 'K_lqr',  K_lqr);
% assignin('base', 'K_i',    K_i);
% assignin('base', 'L_obs',  L_obs);
% assignin('base', 'Ts_ecu', Ts);
% 
% %% 7. EXIBIÇÃO NO CONSOLE E GERAÇÃO DE CÓDIGO PARA FIRMWARE C
% fprintf('===================================================================\n');
% fprintf('       PARÂMETROS CALCULADOS PARA SIMULINK E FIRMWARE C (1 kHz)    \n');
% fprintf('===================================================================\n');
% fprintf('// Copie e cole no arquivo de header do firmware C (.h):\n\n');
% fprintf('#define BRAKE_LAC_TS          (%.6ff)\n', Ts);
% fprintf('#define BRAKE_LAC_PHI11       (%.12ff)\n', Phi(1,1));
% fprintf('#define BRAKE_LAC_PHI12       (%.12ff)\n', Phi(1,2));
% fprintf('#define BRAKE_LAC_PHI21       (%.12ff)\n', Phi(2,1));
% fprintf('#define BRAKE_LAC_PHI22       (%.12ff)\n', Phi(2,2));
% fprintf('#define BRAKE_LAC_GAMMA1      (%.12ff)\n', Gamma(1));
% fprintf('#define BRAKE_LAC_GAMMA2      (%.12ff)\n', Gamma(2));
% fprintf('#define BRAKE_LAC_LQR_K1      (%.8ff)\n', K_pos);
% fprintf('#define BRAKE_LAC_LQR_K2      (%.8ff)\n', K_vel);
% fprintf('#define BRAKE_LAC_LQR_KI      (%.8ff)\n', K_i);
% fprintf('#define BRAKE_LAC_OBS_L1      (%.8ff)\n', L_obs(1));
% fprintf('#define BRAKE_LAC_OBS_L2      (%.8ff)\n', L_obs(2));
% fprintf('===================================================================\n');
% 
% 
% 
% % %% =========================================================================
% % % SÍNTESE DO CONTROLADOR LQI E OBSERVADOR DE LUENBERGER PARA O LAC
% % % Arquivo: sintese_lqi_luenberger_lac.m
% % % =========================================================================
% % clear; clc;
% % 
% % %% 1. PARÂMETROS IDENTIFICADOS DO ATUADOR LINEAR (LAC)
% % % Conforme Capítulo 4 da dissertação (modelo reduzido de 2ª ordem)
% % tau_m   = 0.053;         % Constante de tempo eletromecânica [s]
% % K_vel   = 1.306;         % Ganho de velocidade [mm/s por % de PWM]
% % Ts      = 1.0e-3;        % Passo de amostragem do controle da ECU [s] (1 kHz)
% % 
% % %% 2. MODELO EM ESPAÇO DE ESTADOS EM TEMPO CONTÍNUO
% % % Estados: x = [posicao (mm); velocidade (mm/s)]
% % % Entrada: u = PWM (-100 a +100 %)
% % % Saída:   y = posicao (mm)
% % A = [0,  1;
% %     0, -1/tau_m];
% % 
% % B = [0;
% %     K_vel/tau_m];
% % 
% % C = [1, 0];
% % D = 0;
% % 
% % sys_c = ss(A, B, C, D);
% % 
% % %% 3. DISCRETIZAÇÃO COM RETENÇÃO DE ORDEM ZERO (ZOH)
% % sys_d = c2d(sys_c, Ts, 'zoh');
% % Phi   = sys_d.A;
% % Gamma = sys_d.B;
% % Cx    = sys_d.C;
% % 
% % %% 4. PROJETO DO CONTROLADOR LQI DISCRETO (SISTEMA AUMENTADO)
% % % Vetor aumentado: x_aug = [x_pos; x_vel; z_int]
% % Phi_aug = [Phi,          zeros(2,1);
% %     -Cx*Ts,       1];
% % 
% % Gamma_aug = [Gamma; 
% %     0];
% % 
% % % Matrizes de ponderação do custo quadrático de Riccati
% % % Ajustadas para priorizar seguimento rápido sem saturação excessiva de tensão
% % Q_pos = 10.0;            % Penalização do erro de posição
% % Q_vel = 0.1;             % Amortecimento de velocidade
% % Q_int = 50.0;            % Ação integral para eliminação de erro estacionário
% % Q_aug = diag([Q_pos, Q_vel, Q_int]);
% % 
% % R_u   = 0.05;            % Penalização do esforço de controle (PWM)
% % 
% % % Resolução da Equação Algébrica de Riccati Discreta
% % [K_aug, S, e_mf] = dlqr(Phi_aug, Gamma_aug, Q_aug, R_u);
% % 
% % K_lqr = K_aug(1:2);      % [K_pos, K_vel]
% % K_i   = -K_aug(3);       % Ganho integral com convenção de sinal positiva
% % 
% % %% 5. PROJETO DO OBSERVADOR DE LUENBERGER DISCRETO
% % % Alocação de polos do observador: 3 a 5 vezes mais rápidos que a malha fechada
% % polos_mf = eig(Phi - Gamma*K_lqr);
% % polos_obs = abs(polos_mf).^3 .* exp(1j*angle(polos_mf)); % Desloca em direção à origem
% % 
% % % Alocação no sistema dual
% % L_obs = place(Phi', Cx', polos_obs)';
% % 
% % %% 6. EXPORTAÇÃO PARA O BASE WORKSPACE DO SIMULINK
% % assignin('base', 'Phi',    Phi);
% % assignin('base', 'Gamma',  Gamma);
% % assignin('base', 'K_lqr',  K_lqr);
% % assignin('base', 'K_i',    K_i);
% % assignin('base', 'L_obs',  L_obs);
% % assignin('base', 'dt_ecu', Ts);
% % 
% % fprintf('====================================================\n');
% % fprintf('  SÍNTESE LQI E LUENBERGER CONCLUÍDA COM SUCESSO    \n');
% % fprintf('====================================================\n');
% % fprintf('Matriz Phi:\n'); disp(Phi);
% % fprintf('Matriz Gamma:\n'); disp(Gamma);
% % fprintf('Ganhos K_lqr: [%.4f, %.4f]\n', K_lqr(1), K_lqr(2));
% % fprintf('Ganho K_i:    %.4f\n', K_i);
% % fprintf('Ganhos L_obs: [%.4f; %.4f]\n', L_obs(1), L_obs(2));
% % fprintf('Exportado para o Workspace com Ts = %.4f s\n', Ts);
