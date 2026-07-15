%% gerar_fig_ruido_medicao.m
% Gera a figura `simulacao_ruido_medicao.png` para o ensaio com ruído de medição
% descrito em sbaconf.tex (Eq. y(k)=P_w(k)+n(k)).
%
% Como o modelo Simulink não está versionado neste repositório, este script é
% um TEMPLATE: você só precisa ajustar (i) o nome do modelo e (ii) os nomes dos
% sinais registrados em logsout.

clear; close all; clc;

%% 1) Configure aqui
MODEL_NAME = 'SEU_MODELO_AQUI';   % ex.: 'modulador_pressao_lqi'
STOP_TIME  = '2.0';              % [s] string, para compatibilidade com Simulink
scriptDir = fileparts(mfilename('fullpath'));
outDir = fullfile(scriptDir,'figuras');
if ~exist(outDir,'dir'), mkdir(outDir); end

% Parâmetros do ensaio de ruído (devem ser consumidos pelo modelo)
ENABLE_MEAS_NOISE = true;
MEAS_NOISE_STD_PA = 5e4;          % desvio-padrão [Pa] (ex.: 0.5 bar)

% Se o seu modelo usa pressão manométrica relativa a P_ret, defina abaixo.
% Caso contrário, deixe 0.
P_RET_PA = 0;

OUT_PNG = fullfile(outDir, 'simulacao_ruido_medicao.png');
OUT_PDF = fullfile(outDir, 'simulacao_ruido_medicao.pdf');

%% 2) Rodar simulação
assert(exist('sim', 'file') == 2, 'Simulink não disponível no caminho do MATLAB.');

try
    load_system(MODEL_NAME);
catch
    error('Não foi possível abrir o modelo `%s`. Ajuste MODEL_NAME no topo do script.', MODEL_NAME);
end

simIn = Simulink.SimulationInput(MODEL_NAME);
simIn = simIn.setModelParameter('StopTime', STOP_TIME);

% Variáveis em workspace (o modelo deve referenciar essas variáveis para habilitar o ruído)
simIn = simIn.setVariable('ENABLE_MEAS_NOISE', ENABLE_MEAS_NOISE);
simIn = simIn.setVariable('MEAS_NOISE_STD_PA', MEAS_NOISE_STD_PA);
simIn = simIn.setVariable('P_RET_PA', P_RET_PA);

simOut = sim(simIn);

%% 3) Coletar sinais
% Espera-se que o modelo registre sinais em logsout (Simulink > Data Import/Export > Signal logging).
if ~isprop(simOut, 'logsout') || isempty(simOut.logsout)
    error('`logsout` não encontrado. Habilite Signal logging no modelo e registre os sinais necessários.');
end

logs = simOut.logsout;

% Ajuste os nomes abaixo para coincidir com os nomes no seu modelo
sigNames = struct( ...
    't',        '', ...
    'p_ref',    'P_ref', ...
    'p_w',      'P_w', ...
    'p_w_meas', 'P_w_meas', ...
    'omega_p',  'omega_p', ...
    'u_in',     'u_in', ...
    'u_out',    'u_out' ...
);

getTs = @(name) logs.get(name).Values; %#ok<NASGU>

missing = {};
fields = fieldnames(sigNames);
for k = 1:numel(fields)
    f = fields{k};
    n = sigNames.(f);
    if isempty(n)
        continue;
    end
    try
        tmp = logs.get(n);
        if isempty(tmp)
            missing{end+1} = n; %#ok<AGROW>
        end
    catch
        missing{end+1} = n; %#ok<AGROW>
    end
end
if ~isempty(missing)
    error(['Sinais ausentes em logsout: %s\n' ...
           'Edite `sigNames` neste script OU renomeie os sinais no modelo para bater.'], strjoin(unique(missing), ', '));
end

P_ref_ts  = logs.get(sigNames.p_ref).Values;
P_w_ts    = logs.get(sigNames.p_w).Values;
P_meas_ts = logs.get(sigNames.p_w_meas).Values;
omega_ts  = logs.get(sigNames.omega_p).Values;
uin_ts    = logs.get(sigNames.u_in).Values;
uout_ts   = logs.get(sigNames.u_out).Values;

t = P_w_ts.Time;

% Converter para bar manométrico (se aplicável)
Pg_ref  = (P_ref_ts.Data  - P_RET_PA) / 1e5;
Pg_w    = (P_w_ts.Data    - P_RET_PA) / 1e5;
Pg_meas = (P_meas_ts.Data - P_RET_PA) / 1e5;

%% 4) Plot e export
fig = figure('Color', 'w', 'Position', [100, 100, 1000, 600]);

tiledlayout(2,1,'TileSpacing','compact','Padding','compact');

nexttile;
plot(t, Pg_ref, 'k--', 'LineWidth', 1.2); hold on;
plot(t, Pg_w, 'b-', 'LineWidth', 1.5);
plot(t, Pg_meas, 'r-', 'LineWidth', 1.0);
grid on;
ylabel('Press\~ao [bar]');
legend('P_{ref}', 'P_w (verdadeira)', 'y = P_w + n', 'Location','best');

nexttile;
plot(t, omega_ts.Data, 'LineWidth', 1.2); hold on;
stairs(t, uin_ts.Data, 'LineWidth', 1.2);
stairs(t, uout_ts.Data, 'LineWidth', 1.2);
grid on;
xlabel('Tempo [s]');
ylabel('Comandos');
legend('\omega_p', 'u_{in}', 'u_{out}', 'Location','best');

exportgraphics(fig, OUT_PNG, 'Resolution', 600);
exportgraphics(fig, OUT_PDF, 'ContentType','vector');
fprintf('Figura exportada: %s\n', OUT_PNG);
fprintf('Figura vetorial exportada: %s\n', OUT_PDF);
