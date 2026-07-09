%% export_metricas_lqi_tabela_tex_artigo.m
% Wrapper para exportar a tabela de metricas (nominal) para o artigo IFAC.
% Nao inventa numeros: calcula apenas a partir do simOut e da referencia.

clear; clc;

thisFile = mfilename('fullpath');
thisDir  = fileparts(thisFile);
projRoot = fileparts(thisDir);

outTex = fullfile(projRoot,'artigo','tabelas','metricas_lqi.tex');

% Garante que a referencia exista (Pref_ts)
if evalin('base','exist(''Pref_ts'',''var'')') == 0
    fprintf('Pref_ts nao encontrado. Rodando script_controle_lqi_luenberger_run.m...\n');
    run(fullfile(thisDir,'script_controle_lqi_luenberger_run.m'));
end

prefTS = evalin('base','Pref_ts');

% Roda uma simulacao nominal se simOut nao existir
if evalin('base','exist(''simOut'',''var'')') == 0
    fprintf('simOut nao encontrado. Rodando simulacao nominal via script_controle_lqi_luenberger_run.m...\n');
    run(fullfile(thisDir,'script_controle_lqi_luenberger_run.m'));
end

simOut = evalin('base','simOut');

export_metricas_lqi_tabela_tex(simOut, 'OutTex', outTex, 'PrefTS', prefTS);
