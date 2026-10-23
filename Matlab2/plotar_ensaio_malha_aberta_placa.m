%% plotar_ensaio_malha_aberta_placa.m
% Pos-processamento do ensaio em malha aberta executado NA PLACA.
%
% Este script nao executa simulacao. Ele coleta o sinal de pressao medido
% que voltou do AURIX durante o Monitor & Tune e gera as figuras.
%
% Fontes de dados tentadas, nesta ordem:
%   1. base workspace: logsout, rt_logsout ou out
%   2. Simulation Data Inspector (ultima run)
%   3. arquivo .mat indicado em ARQUIVO_DADOS
%
% As entradas (omega_p, u_in, u_out) vem do .mat gravado por
% gerar_sinais_malha_aberta_placa.m, pois sao conhecidas no MATLAB.

clear; close all; clc;

%% ---------------------------------------------------------------------
% 1) Configuracao
% ----------------------------------------------------------------------
NOME_SINAL_PW = 'pwPsi';   % nome do sinal logado no modelo
ARQUIVO_DADOS = '';         % opcional: caminho de um .mat com o sinal Pw

scriptDir = fileparts(mfilename('fullpath'));
dataDir   = fullfile(scriptDir,'dados');
outDir    = fullfile(scriptDir,'figuras');
if ~exist(outDir,'dir'), mkdir(outDir); end

%% ---------------------------------------------------------------------
% 2) Carregar as referencias geradas para o ensaio
% ----------------------------------------------------------------------
refFile = fullfile(dataDir,'referencia_malha_aberta.mat');
if ~exist(refFile,'file')
    error(['Referencia nao encontrada: %s\n' ...
           'Rode gerar_sinais_malha_aberta_placa.m antes deste script.'], refFile);
end
ref = load(refFile);

%% ---------------------------------------------------------------------
% 3) Coletar Pw medido na placa
% ----------------------------------------------------------------------
pw_ts = local_coletarSinal(NOME_SINAL_PW, ARQUIVO_DADOS);

if isempty(pw_ts)
    error(['Nao foi possivel obter o sinal "%s".\n' ...
           'Verifique se o sinal esta logado no modelo e se o Monitor & Tune ' ...
           'foi executado, ou informe ARQUIVO_DADOS.'], NOME_SINAL_PW);
end

t_pw  = pw_ts.Time(:);
pw_psi = double(squeeze(pw_ts.Data));
pw_psi = pw_psi(:);

Tstop = max([ref.Tstop; t_pw(end)]);

%% ---------------------------------------------------------------------
% 4) Metricas do ensaio
% ----------------------------------------------------------------------
pw_max = max(pw_psi);

% Pressao ao final de cada fase, usando a amostra medida mais proxima.
pw_fimA = local_valorEm(t_pw, pw_psi, ref.tA_end);
pw_fimB = local_valorEm(t_pw, pw_psi, ref.tB_end);
pw_fimC = pw_psi(end);

% Deriva durante a retencao (fase B): quanto o HOLD perdeu de pressao.
maskB = (t_pw >= ref.tA_end) & (t_pw <= ref.tB_end);
if any(maskB)
    deriva_hold = max(pw_psi(maskB)) - min(pw_psi(maskB));
else
    deriva_hold = NaN;
end

fprintf('Pressao maxima        : %.2f PSI\n', pw_max);
fprintf('Fim da pressurizacao  : %.2f PSI (t = %.2f s)\n', pw_fimA, ref.tA_end);
fprintf('Fim da retencao       : %.2f PSI (t = %.2f s)\n', pw_fimB, ref.tB_end);
fprintf('Fim do alivio         : %.2f PSI\n', pw_fimC);
fprintf('Variacao durante HOLD : %.2f PSI\n', deriva_hold);

%% ---------------------------------------------------------------------
% 5) Figuras
% ----------------------------------------------------------------------
set(groot,'defaultLineLineWidth',1.6);
set(groot,'defaultAxesFontSize',12);
set(groot,'defaultAxesFontName','Times New Roman');
set(groot,'defaultFigureRenderer','painters');

fig = figure('Color','w','Position',[100 100 1200 700]);
tiledlayout(2,1,'TileSpacing','compact','Padding','compact');

% Entradas enviadas ao bloco hidraulico
nexttile;
plot(ref.t, ref.v_omega,'k'); hold on;
escala_valv = max(ref.v_omega);
if escala_valv <= 0, escala_valv = 1; end
stairs(ref.t, double(ref.v_uin)*escala_valv,'b--');
stairs(ref.t, double(ref.v_uout)*escala_valv,'r--');
grid on; ylabel('\omega_p (rad/s)','FontSize',18);
title('Entradas do bloco hidraulico','FontSize',18);
legend('\omega_p','u_{in} (esc.)','u_{out} (esc.)','Location','best','FontSize',16);
ylim([-0.1*escala_valv, 1.2*escala_valv]);
xlim([0 Tstop]);

% Pressao medida na placa
nexttile;
plot(t_pw, pw_psi,'r'); hold on;
xline(ref.tA_end,'k:','HandleVisibility','off');
xline(ref.tB_end,'k:','HandleVisibility','off');
grid on;
ylabel('Pressao (PSI)','FontSize',18);
xlabel('Tempo (s)','FontSize',18);
title('Pressao medida no canal da roda (P_w)','FontSize',18);
legend('P_w','Location','best','FontSize',16);
ylim([min(0,min(pw_psi)), max(pw_psi)*1.15 + 0.1]);
xlim([0 Tstop]);

%% ---------------------------------------------------------------------
% 6) Exportar figuras e dados coletados
% ----------------------------------------------------------------------
pdfPath = fullfile(outDir,'ensaio_malha_aberta_placa.pdf');
pngPath = fullfile(outDir,'ensaio_malha_aberta_placa.png');
exportgraphics(fig, pdfPath, 'ContentType','vector');
exportgraphics(fig, pngPath, 'Resolution', 1200);

if ~exist(dataDir,'dir'), mkdir(dataDir); end
medFile = fullfile(dataDir,'medicao_malha_aberta.mat');
save(medFile,'t_pw','pw_psi','pw_max','pw_fimA','pw_fimB','pw_fimC','deriva_hold');

fprintf('\nFiguras exportadas em: %s\n', outDir);
fprintf('Medicao salva em     : %s\n', medFile);

%% ---------------------------------------------------------------------
% Funcoes locais
% ----------------------------------------------------------------------
function ts = local_coletarSinal(nomeSinal, arquivoDados)
ts = local_doArquivo(arquivoDados, nomeSinal);
if ~isempty(ts), return; end

candidatos = {'logsout','rt_logsout','out'};
for k = 1:numel(candidatos)
    if evalin('base', sprintf('exist(''%s'',''var'')', candidatos{k})) == 1
        ts = local_doContainer(evalin('base', candidatos{k}), nomeSinal);
        if ~isempty(ts), return; end
    end
end

ts = local_doSdi(nomeSinal);
end

function ts = local_doArquivo(arquivo, nomeSinal)
ts = [];
if isempty(arquivo) || ~exist(arquivo,'file')
    return;
end
S = load(arquivo);
campos = fieldnames(S);
for k = 1:numel(campos)
    ts = local_doContainer(S.(campos{k}), nomeSinal);
    if ~isempty(ts), return; end
end
end

function ts = local_doContainer(obj, nomeSinal)
ts = [];
try
    if isa(obj,'Simulink.SimulationOutput')
        if ~isempty(obj.logsout)
            obj = obj.logsout;
        end
    end
    if isa(obj,'Simulink.SimulationData.Dataset')
        el = obj.getElement(nomeSinal);
        ts = el.Values;
    elseif isa(obj,'timeseries') && strcmp(obj.Name, nomeSinal)
        ts = obj;
    end
catch
    ts = [];
end
end

function ts = local_doSdi(nomeSinal)
ts = [];
try
    ids = Simulink.sdi.getAllRunIDs;
    if isempty(ids), return; end
    runObj = Simulink.sdi.getRun(ids(end));
    for i = 1:runObj.SignalCount
        sig = Simulink.sdi.getSignal(runObj.getSignalIDByIndex(i));
        if strcmp(sig.Name, nomeSinal)
            ts = sig.Values;
            return;
        end
    end
catch
    ts = [];
end
end

function v = local_valorEm(t, y, instante)
[~, idx] = min(abs(t - instante));
v = y(idx);
end
