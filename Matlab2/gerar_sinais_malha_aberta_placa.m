%% gerar_sinais_malha_aberta_placa.m
% Gera os sinais de referencia do ensaio em malha aberta e publica no base
% workspace para o modelo Simulink que roda NA PLACA (Monitor & Tune).
%
% Fases (mesma estrutura do ensaio do artigo):
%   A pressurizacao : u_in=1, u_out=0, comando de vazao ativo
%   B retencao      : u_in=0, u_out=0, comando de vazao nulo
%   C alivio        : u_in=0, u_out=1, comando de vazao nulo
%
% Diferencas em relacao ao ensaio puramente simulado:
% - Nao se chama sim(). Quem executa a planta e o AURIX.
% - A unica saida medida e Pw, em PSI.
% - Psup, Qpump, Qin e Qout nao existem no hardware (nao ha medicao de vazao).
%
% Execute este script ANTES de Build/Monitor & Tune: os blocos From Workspace
% precisam das variaveis existindo no base workspace no momento da compilacao.

clear; clc;

%% ---------------------------------------------------------------------
% 1) Parametros do ensaio
% ----------------------------------------------------------------------
Ts    = 1e-3;   % [s] sample time do bloco HydraulicBlock na placa
Tstop = 4.0;    % [s] duracao total do ensaio

tA_end = 2.0;   % [s] fim da pressurizacao
tB_end = 3.0;   % [s] fim da retencao
tC_end = Tstop; % [s] fim do alivio

omega_rampa = 80;    % [rad/s] primeiro patamar de omega_p
omega_plato = 100;   % [rad/s] patamar principal de omega_p

t_rampa = 0.5;  % [s] instante em que omega_p sai de zero
t_plato = 1.0;  % [s] instante em que omega_p atinge o patamar principal

% Escala usada no firmware para converter omega_p em velocidade do LAC.
% Deve espelhar HydraulicBlock_SetOmegaScale(); serve so para estimar curso.
escala_mm_s_por_rad_s = 0.01;

%% ---------------------------------------------------------------------
% 2) Base de tempo discreta
% ----------------------------------------------------------------------
% Amostrar em Ts evita depender da interpolacao do From Workspace no codigo
% gerado e mantem o ensaio deterministico na placa.
t = (0:Ts:Tstop)';

%% ---------------------------------------------------------------------
% 3) omega_p(t)
% ----------------------------------------------------------------------
v_omega = zeros(size(t));
v_omega(t >= t_rampa & t < t_plato) = omega_rampa;
v_omega(t >= t_plato & t < tA_end)  = omega_plato;
v_omega(t >= tA_end)                = 0;

%% ---------------------------------------------------------------------
% 4) u_in(t) e u_out(t)
% ----------------------------------------------------------------------
% O bloco aceita apenas 1/0 (APPLY), 0/0 (HOLD) e 0/1 (RELEASE).
% A combinacao 1/1 e invalida e para a planta.
v_uin  = zeros(size(t));
v_uout = zeros(size(t));

v_uin(t < tA_end)   = 1;   % fase A
v_uout(t >= tB_end) = 1;   % fase C

v_uin  = uint8(v_uin);
v_uout = uint8(v_uout);

% Guarda de consistencia: nenhuma amostra pode ter u_in=1 e u_out=1.
if any(v_uin == 1 & v_uout == 1)
    error('Combinacao invalida u_in=1 e u_out=1 encontrada nos sinais gerados.');
end

%% ---------------------------------------------------------------------
% 5) Timeseries para os blocos From Workspace
% ----------------------------------------------------------------------
omega_p_ts = timeseries(v_omega, t);
u_in_ts    = timeseries(v_uin,  t);
u_out_ts   = timeseries(v_uout, t);

assignin('base','Ts',Ts);
assignin('base','Tstop',Tstop);
assignin('base','omega_p_ts',omega_p_ts);
assignin('base','u_in_ts',u_in_ts);
assignin('base','u_out_ts',u_out_ts);

%% ---------------------------------------------------------------------
% 6) Estimativa do curso do LAC na fase de pressurizacao
% ----------------------------------------------------------------------
mask_apply   = (v_uin == 1) & (v_uout == 0);
desloc_mm    = sum(double(v_omega(mask_apply))) * escala_mm_s_por_rad_s * Ts;

%% ---------------------------------------------------------------------
% 7) Salvar referencia para o script de plot
% ----------------------------------------------------------------------
scriptDir = fileparts(mfilename('fullpath'));
dataDir   = fullfile(scriptDir,'dados');
if ~exist(dataDir,'dir'), mkdir(dataDir); end

refFile = fullfile(dataDir,'referencia_malha_aberta.mat');
save(refFile,'t','v_omega','v_uin','v_uout','Ts','Tstop', ...
             'tA_end','tB_end','tC_end','escala_mm_s_por_rad_s');

%% ---------------------------------------------------------------------
% 8) Resumo
% ----------------------------------------------------------------------
fprintf('Sinais publicados no base workspace:\n');
fprintf('  omega_p_ts  %d amostras, max = %.1f rad/s\n', numel(t), max(v_omega));
fprintf('  u_in_ts     uint8\n');
fprintf('  u_out_ts    uint8\n');
fprintf('  Ts = %.4f s, Tstop = %.2f s\n', Ts, Tstop);
fprintf('Curso estimado do LAC na fase A: %.2f mm (escala %.4f mm/s por rad/s)\n', ...
        desloc_mm, escala_mm_s_por_rad_s);
fprintf('Referencia salva em: %s\n', refFile);
fprintf('\nProximos passos:\n');
fprintf('  1. Abrir o modelo com o bloco HydraulicBlock.\n');
fprintf('  2. Conferir sample time do bloco = %.4f s.\n', Ts);
fprintf('  3. Logar o sinal de saida com o nome Pw_psi.\n');
fprintf('  4. Executar Monitor & Tune (Hardware > Monitor & Tune).\n');
fprintf('  5. Ao terminar, rodar plotar_ensaio_malha_aberta_placa.m\n');
