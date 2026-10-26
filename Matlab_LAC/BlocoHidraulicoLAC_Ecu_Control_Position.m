function [duty_cycle_lac, x_est_mm, v_est_mms] = ...
    ecu_controle_posicao_lac_lqi(x_ref_mm, x_med_mm, Phi, Gamma, K_lqr, K_i, L_obs, dt)
%#codegen
% =========================================================================
% ECU AUTOMOTIVA: CONTROLE DE POSIÇÃO DO LAC VIA LQI + LUENBERGER
% Equivalente funcional do firmware em linguagem C (AURIX TC375)
% =========================================================================
% Entradas:
%   x_ref_mm       : Referência de deslocamento linear do êmbolo [mm]
%   x_med_mm       : Deslocamento medido pelo sensor/encoder da planta [mm]
%   Phi            : Matriz de estados do modelo discreto (2x2)
%   Gamma          : Vetor de entrada do modelo discreto (2x1)
%   K_lqr          : Ganhos dos estados proporcionais [K_pos, K_vel] (1x2)
%   K_i            : Ganho da ação integral de posição (escalar)
%   L_obs          : Vetor de ganhos do Observador de Luenberger (2x1)
%   dt             : Passo de amostragem numérico da ECU [s]
%
% Saídas:
%   duty_cycle_lac : Comando PWM de acionamento do motor [-100% a +100%]
%   x_est_mm       : Posição estimada pelo observador [mm]
%   v_est_mms      : Velocidade estimada pelo observador [mm/s]
% =========================================================================

%% 1. LIMITES MECÂNICOS DO ATUADOR FÍSICO
X_MIN_MM = 0.0;    % Batente mecânico traseiro (repouso) [mm]
X_MAX_MM = 53.7;   % Batente mecânico dianteiro (curso total) [mm]

%% 2. MEMÓRIA INTERNA DE ESTADOS (PERSISTENT / ESTÁTICAS DE FIRMWARE)
persistent xhat vhat integral_pos last_u
if isempty(xhat)
    xhat         = 0.0; % Posição estimada [mm]
    vhat         = 0.0; % Velocidade estimada [mm/s]
    integral_pos = 0.0; % Acumulador integral do erro [mm*s]
    last_u       = 0.0; % Último comando PWM efetivamente aplicado [-100 a +100]
end

%% 3. CONDICIONAMENTO DA REFERÊNCIA
% Garante que a referência nunca demande posição além dos fins de curso
x_ref_clamped = max(X_MIN_MM, min(X_MAX_MM, double(x_ref_mm)));
pos_real      = double(x_med_mm);

%% 4. OBSERVADOR DE LUENBERGER DISCRETO (PREDITOR-CORRETOR)
% Cálculo da inovação (erro de observação da saída de posição)
innov = pos_real - xhat;

% Atualização temporal dos estados estimados
xhat_new = Phi(1,1)*xhat + Phi(1,2)*vhat + Gamma(1)*last_u + L_obs(1)*innov;
vhat_new = Phi(2,1)*xhat + Phi(2,2)*vhat + Gamma(2)*last_u + L_obs(2)*innov;

xhat = xhat_new;
vhat = vhat_new;

%% 5. LEI DE CONTROLE LQI DE POSIÇÃO
erro_pos = x_ref_clamped - xhat;

% Candidato à integração do erro
integral_cand = integral_pos + erro_pos * dt;

% Lei de controle ótima não saturada
u_unclamped = (K_lqr(1) * erro_pos) - (K_lqr(2) * vhat) + (K_i * integral_cand);

%% 6. ANTI-WINDUP CONDICIONAL IDÊNTICO AO FIRMWARE AURIX
% Clamping rígido da ação integral quando satura na mesma direção do esforço
if (u_unclamped > 100.0 && erro_pos > 0.0)
    u_cmd = 100.0;
    % Congela a integração (não atualiza integral_pos)
elseif (u_unclamped < -100.0 && erro_pos < 0.0)
    u_cmd = -100.0;
    % Congela a integração (não atualiza integral_pos)
else
    integral_pos = integral_cand;
    u_cmd = u_unclamped;
    if u_cmd > 100.0
        u_cmd = 100.0;
    elseif u_cmd < -100.0
        u_cmd = -100.0;
    end
end

%% 7. ATUALIZAÇÃO DAS SAÍDAS E REGISTRADOR DE RETORNO
duty_cycle_lac = u_cmd;
last_u         = u_cmd;

x_est_mm  = xhat;
v_est_mms = vhat;

end