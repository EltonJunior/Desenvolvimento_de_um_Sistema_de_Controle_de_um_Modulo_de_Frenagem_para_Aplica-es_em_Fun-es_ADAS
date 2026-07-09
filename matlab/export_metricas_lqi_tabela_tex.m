function outTex = export_metricas_lqi_tabela_tex(simOut, varargin)
%export_metricas_lqi_tabela_tex Exporta métricas de desempenho em um .tex.
%
% Gera um arquivo LaTeX com um tabular (booktabs) para ser incluído via \input.
%
% Uso típico:
%   simOut = sim(model);
%   export_metricas_lqi_tabela_tex(simOut);
%
% Parâmetros (Name-Value):
%   'OutTex'        : caminho do .tex de saída.
%   'PrefTS'        : timeseries com a referência (Pa ou bar, conforme seu log).
%   'SettlingBand'  : banda relativa para t_s (default 0.02 = 2%).
%
% Observação de rigor:
% - Não inventa números: calcula exclusivamente a partir dos sinais logados.

p = inputParser;
p.addParameter('OutTex', '', @(x) ischar(x) || isstring(x));
p.addParameter('PrefTS', [], @(x) isempty(x) || isa(x,'timeseries'));
p.addParameter('SettlingBand', 0.02, @(x) isnumeric(x) && isscalar(x) && x>0);
p.parse(varargin{:});

outTex = char(p.Results.OutTex);
if isempty(outTex)
    % Mantém compatibilidade com a tese: saída padrão nas tabelas do capítulo.
    thisFile = mfilename('fullpath');
    thisDir  = fileparts(thisFile);
    projRoot = fileparts(thisDir);
    outTex = fullfile(projRoot,'elementos-textuais','tabelas','metricas_lqi.tex');
end

prefTS = p.Results.PrefTS;

[metrics, meta] = compute_metricas_lqi(simOut, 'PrefTS', prefTS, 'SettlingBand', p.Results.SettlingBand);

foundPwName = '';
if isfield(meta,'PwSignalName')
    foundPwName = meta.PwSignalName;
end

outDir = fileparts(outTex);
if ~exist(outDir,'dir')
    mkdir(outDir);
end

fid = fopen(outTex,'w');
if fid < 0
    error('Nao foi possivel criar o arquivo: %s', outTex);
end

fprintf(fid, '%% Arquivo gerado automaticamente por export_metricas_lqi_tabela_tex.m\n');
fprintf(fid, '%% Sinal Pw encontrado como: %s\n', foundPwName);
fprintf(fid, '\\begin{tabular}{l c}\n');
fprintf(fid, '\\toprule\n');
fprintf(fid, 'Metrica & Valor \\\\ \\midrule\n');
fprintf(fid, 'Erro RMS (bar) & %.3f \\\\ \n', metrics.RMS_e_bar);
fprintf(fid, 'Erro estacionario $e_\\infty$ (bar) & %.3f \\\\ \n', metrics.e_inf_bar);
fprintf(fid, 'Sobressinal/undershoot $M_p$ do maior degrau (\\%%) & %.2f \\\\ \n', metrics.Mp_pct);
fprintf(fid, 'Tempo de subida/queda $t_r$ do maior degrau (s) & %.4f \\\\ \n', metrics.tr_s);
fprintf(fid, 'Tempo de acomodacao $t_s$ do maior degrau (s) & %.4f \\\\ \n', metrics.ts_s);

if ~isnan(metrics.omega_max)
    fprintf(fid, '$\\max\\,\\omega_p$ (rad/s) & %.2f \\\\ \n', metrics.omega_max);
end
if ~isnan(metrics.uin_max)
    fprintf(fid, '$\\max\\,u_{in}$ & %.3f \\\\ \n', metrics.uin_max);
end
if ~isnan(metrics.uout_max)
    fprintf(fid, '$\\max\\,u_{out}$ & %.3f \\\\ \n', metrics.uout_max);
end

fprintf(fid, '\\bottomrule\n');
fprintf(fid, '\\end{tabular}\n');
fclose(fid);

fprintf('Tabela LaTeX exportada: %s\n', outTex);
end
