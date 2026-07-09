%% run_varredura_robustez_lqi_export_artigo.m
% Wrapper para exportar robustez para o artigo IFAC.
% Usa variavel de ambiente para nao interferir no script original.

clear; clc;

thisFile = mfilename('fullpath');
thisDir  = fileparts(thisFile);
projRoot = fileparts(thisDir);

outTex = fullfile(projRoot,'artigo','tabelas','metricas_robustez.tex');
setenv('LQI_ROBUSTEZ_OUTTEX', outTex);

run(fullfile(thisDir,'run_varredura_robustez_lqi_export.m'));

setenv('LQI_ROBUSTEZ_OUTTEX','');
