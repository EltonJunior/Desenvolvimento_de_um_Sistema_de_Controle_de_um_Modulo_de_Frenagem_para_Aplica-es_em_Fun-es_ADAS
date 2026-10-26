function [ P_supply, P_roda, x_mm] = fcn(duty_cycle_lac,u_mcv, u_pfv, u_irl, u_orl,  dt)
%#codegen
% BLOCO DE PLANTA FÍSICA HIDRO-MECÂNICA ATUALIZADO (CINEMÁTICA DO FUSO REAL)
% Inputs:
%   u_mcv, u_pfv, u_irl, u_orl : Sinais ON/OFF (0 ou 1)
%   duty_cycle_lac             : Sinal de comando do LAC (-1.0 a 1.0 ou 0 a 1)
%   dt                         : Passo de amostragem (ex: 0.001)
% Outputs:
%   x_ponto                    : Velocidade instantânea do êmbolo [m/s]
%   P_supply                   : Pressão de suprimento (Nó p1) [Pa]
%   P_roda                     : Pressão na roda (Nó p3) [Pa]
%   x_mm                       : DESLOCAMENTO DO LAC EM MILÍMETROS [mm]

%% 1. PARAMETROS FIXOS DO SISTEMA (Valores validados pelo usuário)
rho     = 850;          % Densidade do fluido [kg/m^3]
beta    = 1.5e9;        % Módulo volumétrico [Pa]
A_lac   = 2.85e-4;      % Área do êmbolo do LAC [m^2]
V10     = 2.0e-5;       % Volume morto inicial [m^3]
%Valor sugerido para teste: Mude de V10 = 2.0e-5 para V10 = 1.0e-5 (\(10\text{ mL}\)).

% % Parâmetro Mecânico Real do Motor/Fuso
% K_drv   = 0.7e-4;      % Ganho real: m/s por unidade de comando (Velocidade máx: 0.269 mm/s)
% tau_m   = 0.020;        % Constante de tempo elétrica/mecânica do motor (ex: 20 ms)

% Parâmetros Reais Extraídos da Bancada (Escala 0-100)
K_drv   = 0.085;    % Média calibrada para a zona útil de controle (10% a 30%)
tau_m   = 0.140;      % Constante de aceleração real do motor (140 ms)

% Válvulas (Orifícios)
Cd      = 0.62;         %1.0;          % Coeficiente de descarga uniforme
A_max   = 3.5e-6;      %8.47e-7;      % Área máxima de passagem das válvulas [m^2]
tau_v   = 0.005;        % Constante de tempo do carretel [s]
pr      = 0.0;          % Pressão do reservatório [Pa]

% Volumes e Compliances dos Nós 2 e 3
C2      = 5.0e-12;      % Compliance da linha principal [m^3/Pa]
% C2      = 2.0e-12;      % REDUZIDO: Linha principal do bloco mais rígida
C3      = 4.5e-12; %2.5e-11;      % Compliance total do caliper [m^3/Pa]
% Valor sugerido para teste: Experimente testar C3 = 1.2e-12 ou C3 = 8.5e-13.


%% 2. INICIALIZAÇÃO DOS ESTADOS INTERNOS (PERSISTENT)
persistent p1 p2 p3 x x_dot a_mcv a_pfv a_irl a_orl

if isempty(p1)
    p1     = 0.0;  p2    = 0.0;  p3    = 0.0;
    x      = 0.0;  x_dot = 0.0;
    a_mcv  = 0.0;  a_pfv = 0.0;  a_irl = 0.0;  a_orl = 0.0;
end

%% 3. DINÂMICA DOS CARRETÉIS DAS VÁLVULAS
a_mcv = a_mcv + (dt / tau_v) * (-a_mcv + double(u_mcv));
a_pfv = a_pfv + (dt / tau_v) * (-a_pfv + double(u_pfv));
a_irl = a_irl + (dt / tau_v) * (-a_irl + double(u_irl));
a_orl = a_orl + (dt / tau_v) * (-a_orl + double(u_orl));

a_mcv = max(0.0, min(1.0, a_mcv));
a_pfv = max(0.0, min(1.0, a_pfv));
a_irl = max(0.0, min(1.0, a_irl));
a_orl = max(0.0, min(1.0, a_orl));

%% 4. CÁLCULO DAS VAZÕES INSTANTÂNEAS
A_eff_mcv = a_mcv * A_max;
A_eff_pfv = a_pfv * A_max;
A_eff_irl = a_irl * A_max; % Acoplamento IRL/ORL conforme lógica
A_eff_orl = a_orl * A_max;

dp_pfv = p1 - p2;
dp_mcv = p2 - pr;
dp_irl = p2 - p3;
dp_orl = p3 - pr;

Q_pfv = Cd * A_eff_pfv * sign(dp_pfv) * sqrt(2 * abs(dp_pfv) / rho);
Q_mcv = Cd * A_eff_mcv * sign(dp_mcv) * sqrt(2 * abs(dp_mcv) / rho);
Q_irl = Cd * A_eff_irl * sign(dp_irl) * sqrt(2 * abs(dp_irl) / rho);
Q_orl = Cd * A_eff_orl * sign(dp_orl) * sqrt(2 * abs(dp_orl) / rho);

%% 5. EQUAÇÕES DIFERENCIAIS DA PLANTA (EDOs)

% --- Mecânica Cinemática Real do Atuador do LAC ---
% Em vez de força, o comando de PWM gera uma velocidade alvo ditada pelo fuso.
% O motor possui um pequeno atraso físico de resposta (atraso de primeira ordem tau_m)
%x_dot_alvo = double(duty_cycle_lac) * K_drv;
x_dot_alvo = (double(duty_cycle_lac) / 100) * K_drv; % Garante que 50 vire 0.5

x_ddot     = (1 / tau_m) * (-x_dot + x_dot_alvo);

% --- Dinâmica Hidráulica ---
V1 = V10 - A_lac * x;
if V1 < 1.0e-7
    V1 = 1.0e-7;
end
p1_dot = (beta / V1) * (A_lac * x_dot - Q_pfv);
p2_dot = (1 / C2) * (Q_pfv - Q_mcv - Q_irl);
p3_dot = (1 / C3) * (Q_irl - Q_orl);

%% 6. INTEGRAÇÃO NUMÉRICA (Método de Euler)
x_dot = x_dot + x_ddot * dt;
x     = x + x_dot * dt;

% [ADICIONE ESTA LINHA AQUI]: Proteção de Fim de Curso Máximo do LAC
if x >= 0.0537
    x = 0.0537;
    x_dot = max(0.0, x_dot); % Impede o pistão de continuar avançando se bater no fundo
end

p1    = p1 + p1_dot * dt;
p2    = p2 + p2_dot * dt;
p3    = p3 + p3_dot * dt;

% Saturações físicas de fim de curso e cavitação
p1 = max(0.0, p1);
p2 = max(0.0, p2);
p3 = max(0.0, p3);
x  = max(0.0, x); % Impede deslocamento negativo na parede inicial

%% 7. ATRIBUIÇÃO DAS SAÍDAS DO BLOCO
%x_ponto  = x_dot;
P_supply = p1/6894.757;
P_roda   = p3/6894.757;
x_mm     = x * 1000; % Converte de metros [m] para milímetros [mm] para leitura real

end