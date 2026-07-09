%% run_varredura_robustez_lqi_export.m
% Varredura de sensibilidade paramétrica (robustez) + exportação LaTeX.
%
% Objetivo:
% - Rodar múltiplas simulações com variações percentuais em parâmetros
%   selecionados e sintetizar o "pior caso" das métricas em uma tabela
%   diretamente incluível no LaTeX.
%
% Saída principal:
% - elementos-textuais/tabelas/metricas_robustez.tex
%
% Pré-requisitos:
% - O modelo Simulink (Freio_LQR_Model ou Freio_LQR_Model_v2) deve estar
%   acessível no MATLAB path.
% - O modelo deve registrar o sinal de pressão do canal/roda em bar gauge
%   como 'Pw_bar_g' (recomendado) via logsout.
% - O modelo deve utilizar parâmetros do workspace base (p.ex. beta, Vsup,
%   Vw, Kb, Klb, Ain_max, omega_p_max) para que as variações afetem a planta
%   e/ou as saturações. Caso o bloco hidráulico use constantes internas,
%   as variações podem não alterar a dinâmica da planta (apenas os limites
%   do atuador/saturação, quando aplicável).
%
% Como usar:
% 1) Execute o script de síntese e geração da referência:
%      run('script_controle_lqi_luenberger_run.m');
%    (Ele também roda uma simulação nominal e cria Pref_ts no workspace.)
% 2) Em seguida execute este script:
%      run('run_varredura_robustez_lqi_export.m');
%
% Observação de rigor:
% - Este script não insere números manualmente: todos os valores vêm de simulações.

clear; clc;

thisFile = mfilename('fullpath');
thisDir  = fileparts(thisFile);
projRoot = fileparts(thisDir);

outTexEnv = getenv('LQI_ROBUSTEZ_OUTTEX');
if ~isempty(outTexEnv)
    outTex = outTexEnv;
else
    outTex = fullfile(projRoot,'elementos-textuais','tabelas','metricas_robustez.tex');
end

% -----------------------------
% 0) Garante que a referência exista (Pref_ts)
% -----------------------------
if evalin('base','exist(''Pref_ts'',''var'')') == 0
    fprintf('Pref_ts nao encontrado. Rodando script_controle_lqi_luenberger_run.m...\n');
    run(fullfile(thisDir,'script_controle_lqi_luenberger_run.m'));
end

prefTS = evalin('base','Pref_ts');

% -----------------------------
% 1) Seleção do modelo
% -----------------------------
if ~isempty(which('Freio_LQR_Model_v2.slx')) || ~isempty(which('Freio_LQR_Model_v2.mdl'))
    model = 'Freio_LQR_Model_v2';
else
    model = 'Freio_LQR_Model';
end

load_system(model);

% -----------------------------
% 2) Define parâmetros a varrer
% -----------------------------
% Percentuais de variação (ex.: 0.20 = +-20%)
variationPct = 0.20;

% Parâmetros (baseline tomado do workspace base)
paramNames = {'beta','Vsup','Vw','Kb','Klb','Ain_max'};

baseVals = struct();
for i = 1:numel(paramNames)
    nm = paramNames{i};
    if evalin('base', sprintf('exist(''%s'',''var'')', nm)) ~= 0
        baseVals.(nm) = evalin('base', nm);
    else
        error('Parametro %s nao encontrado no workspace base. Rode o script de sintese primeiro.', nm);
    end
end

% Também usados no cálculo de omega_p_max
Pret = evalin('base','Pret');
P_sup_max_bar = evalin('base','P_sup_max_bar');
P_sup_max = Pret + P_sup_max_bar*1e5;

% -----------------------------
% 3) Gera casos: nominal + cantos do hipercubo (+/-)
% -----------------------------
nP = numel(paramNames);
cornerCount = 2^nP;

cases = struct('id',{},'mult',{},'vals',{});

% Caso 0 (nominal)
cases(end+1).id = 0;
cases(end).mult = ones(1,nP);
cases(end).vals = baseVals;

for c = 0:(cornerCount-1)
    bits = dec2bin(c,nP) - '0';
    mult = ones(1,nP);
    for k = 1:nP
        if bits(k) == 1
            mult(k) = 1 + variationPct;
        else
            mult(k) = 1 - variationPct;
        end
    end

    vals = struct();
    for k = 1:nP
        nm = paramNames{k};
        vals.(nm) = baseVals.(nm) * mult(k);
    end

    cases(end+1).id = c + 1;
    cases(end).mult = mult;
    cases(end).vals = vals;
end

fprintf('Varredura: %d casos (nominal + %d cantos) com +-%.0f%%.\n', numel(cases), cornerCount, variationPct*100);

% -----------------------------
% 4) Executa simulações e calcula métricas
% -----------------------------
results = struct('caseId',{},'metrics',{},'meta',{},'mult',{});
failed = [];

Ts = evalin('base','Ts');
Tf = prefTS.Time(end);

set_param(model,'Solver','FixedStepDiscrete');
set_param(model,'FixedStep',num2str(Ts));
set_param(model,'StopTime',num2str(Tf));

for i = 1:numel(cases)
    cs = cases(i);

    for k = 1:nP
        nm = paramNames{k};
        assignin('base', nm, cs.vals.(nm));
    end

    omega_p_max = (P_sup_max - Pret) * (cs.vals.Klb / max(cs.vals.Kb, eps));
    assignin('base','omega_p_max', omega_p_max);

    try
        simOut = sim(model);
        [m, meta] = compute_metricas_lqi(simOut, 'PrefTS', prefTS);

        results(end+1).caseId = cs.id;
        results(end).metrics = m;
        results(end).meta = meta;
        results(end).mult = cs.mult;
    catch ME
        failed(end+1) = cs.id; %#ok<AGROW>
        fprintf('Caso %d falhou: %s\n', cs.id, ME.message);
    end
end

if isempty(results)
    error('Nenhuma simulacao foi concluida com sucesso; nao ha tabela para exportar.');
end

% -----------------------------
% 5) Sintetiza nominal e pior caso
% -----------------------------
nomIdx = find([results.caseId] == 0, 1, 'first');
if isempty(nomIdx)
    nomIdx = 1;
end

metricFields = {'RMS_e_bar','e_inf_bar','Mp_pct','tr_s','ts_s','omega_max','uin_max','uout_max'};
nominal = results(nomIdx).metrics;

worst = struct();
worstCase = struct();

for f = 1:numel(metricFields)
    fn = metricFields{f};
    vals = arrayfun(@(r) r.metrics.(fn), results);

    idxValid = find(~isnan(vals));
    if isempty(idxValid)
        worst.(fn) = NaN;
        worstCase.(fn) = NaN;
        continue
    end

    [mx, k] = max(vals(idxValid));
    worst.(fn) = mx;
    worstCase.(fn) = results(idxValid(k)).caseId;
end

% -----------------------------
% 6) Exporta tabela LaTeX (pior caso)
% -----------------------------
outDir = fileparts(outTex);
if ~exist(outDir,'dir')
    mkdir(outDir);
end

fid = fopen(outTex,'w');
if fid < 0
    error('Nao foi possivel criar o arquivo: %s', outTex);
end

fprintf(fid, '%% Arquivo gerado automaticamente por run_varredura_robustez_lqi_export.m\n');
fprintf(fid, '%% Numero de casos executados com sucesso: %d (falhas: %d)\n', numel(results), numel(failed));
fprintf(fid, '%% Variacao: +-%.0f%% nos parametros: %s\n', variationPct*100, strjoin(paramNames, ', '));
fprintf(fid, '\\begin{tabular}{l c c c}\n');
fprintf(fid, '\\toprule\n');
fprintf(fid, 'Metrica & Nominal & Pior caso & Caso \\\\ \\midrule\n');

fprintf(fid, 'Erro RMS (bar) & %.3f & %.3f & %d \\\\ \n', nominal.RMS_e_bar, worst.RMS_e_bar, worstCase.RMS_e_bar);
fprintf(fid, 'Erro estacionario $e_\\infty$ (bar) & %.3f & %.3f & %d \\\\ \n', nominal.e_inf_bar, worst.e_inf_bar, worstCase.e_inf_bar);
fprintf(fid, 'Sobressinal/undershoot $M_p$ (\\%%) & %.2f & %.2f & %d \\\\ \n', nominal.Mp_pct, worst.Mp_pct, worstCase.Mp_pct);
fprintf(fid, 'Tempo de subida/queda $t_r$ (s) & %.4f & %.4f & %d \\\\ \n', nominal.tr_s, worst.tr_s, worstCase.tr_s);
fprintf(fid, 'Tempo de acomodacao $t_s$ (s) & %.4f & %.4f & %d \\\\ \n', nominal.ts_s, worst.ts_s, worstCase.ts_s);

if ~isnan(nominal.omega_max) || ~isnan(worst.omega_max)
    fprintf(fid, '$\\max\\,\\omega_p$ (rad/s) & %.2f & %.2f & %d \\\\ \n', nominal.omega_max, worst.omega_max, worstCase.omega_max);
end
if ~isnan(nominal.uin_max) || ~isnan(worst.uin_max)
    fprintf(fid, '$\\max\\,u_{in}$ & %.3f & %.3f & %d \\\\ \n', nominal.uin_max, worst.uin_max, worstCase.uin_max);
end
if ~isnan(nominal.uout_max) || ~isnan(worst.uout_max)
    fprintf(fid, '$\\max\\,u_{out}$ & %.3f & %.3f & %d \\\\ \n', nominal.uout_max, worst.uout_max, worstCase.uout_max);
end

fprintf(fid, '\\bottomrule\n');
fprintf(fid, '\\end{tabular}\n');

fclose(fid);

fprintf('Tabela de robustez exportada: %s\n', outTex);
if ~isempty(failed)
    fprintf('Casos que falharam: %s\n', mat2str(failed));
end
