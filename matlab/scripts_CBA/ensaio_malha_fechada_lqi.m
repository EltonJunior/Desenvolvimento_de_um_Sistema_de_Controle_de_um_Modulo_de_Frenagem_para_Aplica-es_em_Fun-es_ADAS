%% artigo_ensaio_malha_fechada_lqi.m
% CONTROLE LQI DISCRETO + OBSERVADOR DE LUENBERGER
% Sistema hidráulico de freio não linear (modelo no Simulink).
%
% Observação importante (consistência com o artigo):
% - As válvulas são tratadas como comandos binários u_in,u_out ∈ {0,1}.

clear; clc; close all;

%% ============================================================
% 0) NOME DO MODELO SIMULINK
% ============================================================
% Ajuste este nome para o seu arquivo .slx (ou modelo no path do MATLAB).
MODEL_NAME = 'Freio_LQR_Model';

%% =============================================================
% 1) PARÂMETROS FÍSICOS (iguais ao modelo não linear)
% =============================================================
beta = 1.5e9;
rho  = 850;
Pret = 1e5;

Vsup = 6.0e-5;
Vw   = 1.0e-5;

Dp_rev = 5e-7;
Nv     = 0.85;
Kb     = Nv * (Dp_rev/(2*pi));
Klb    = 6.8e-13;

Cv_in   = 0.62;
Cv_out  = 0.62;
Ain_max = 3.0e-7;
Aout_max= 3.0e-7;

% Exportar parametros para o workspace do Simulink (necessario para varreduras)
assignin('base','beta',beta);
assignin('base','rho',rho);
assignin('base','Pret',Pret);
assignin('base','Vsup',Vsup);
assignin('base','Vw',Vw);
assignin('base','Kb',Kb);
assignin('base','Klb',Klb);
assignin('base','Cv_in',Cv_in);
assignin('base','Cv_out',Cv_out);
assignin('base','Ain_max',Ain_max);
assignin('base','Aout_max',Aout_max);

%% =============================================================
% 2) PONTO DE OPERAÇÃO (modo de pressurização)
% =============================================================
Pw_op   = 10e5;         % Pa  (100 bar)
Psup_op = Pw_op + 5e5;  % Pa  (pequeno diferencial)

% Válvulas binárias no escopo do trabalho
u_in_op  = 1.0;
u_out_op = 0.0;

% vazão necessária para manter equilíbrio (aproximação local)
dPin = Psup_op - Pw_op;
Qin_op = Cv_in*(Ain_max*u_in_op)*sqrt(2*dPin/rho);

omega_op = Qin_op / Kb; %#ok<NASGU>

%% =============================================================
% 3) LINEARIZAÇÃO ANALÍTICA
% Estados: x = [Psup Pw]'
% Entrada: u = omega_p
% Saída: y = Pw
% =============================================================

% Qin = kq*sqrt(2*(Psup-Pw)/rho), com kq = Cv_in*Ain_max*u_in_op
kq  = Cv_in*Ain_max*u_in_op;
s   = sqrt(2*dPin/rho);
dQd = kq/(rho*s); % dQin/d(Psup-Pw)

% Psup_dot = (beta/Vsup)*(Kb*omega_p - Klb*(Psup-Pret) - Qin)
% Pw_dot   = (beta/Vw)  *(Qin)  (com u_out_op=0 no ponto)
a11 = -(beta/Vsup)*(Klb + dQd);
a12 =  (beta/Vsup)*(dQd);

a21 =  (beta/Vw)*(dQd);
a22 = -(beta/Vw)*(dQd);

A = [a11 a12;
     a21 a22];

B = [(beta/Vsup)*Kb;
      0];

C = [0 1];
D = 0;

sys_c = ss(A,B,C,D);

%% ============================================================
% PROJETO LQI DISCRETO
% ============================================================

Ts = 1e-4;

sys_d = c2d(sys_c,Ts);

Ad = sys_d.A;
Bd = sys_d.B;
Cd = sys_d.C;

% Sistema aumentado para LQI
Ad_aug = [Ad zeros(2,1);
         -Cd*Ts 1];

Bd_aug = [Bd; 0];

Q_aug = diag([1e-12 1e-10 1e4]);
R = 1e-7;

K_aug = dlqr(Ad_aug,Bd_aug,Q_aug,R);

Kx = K_aug(1:2);
Ki = K_aug(3);

% Observador discreto
Ld = place(Ad',Cd',0.4*eig(Ad))';

assignin('base','Ad',Ad);
assignin('base','Bd',Bd);
assignin('base','Cd',Cd);
assignin('base','Kx',Kx);
assignin('base','Ki',Ki);
assignin('base','Ld',Ld);
assignin('base','Ts',Ts);

%% ============================================================
% EXECUÇÃO DO CONTROLADOR - Freio_LQR_Model
% ============================================================

%% Tempo de simulação
Tf = 3;
t  = (0:Ts:Tf)';

%% ============================================================
% SINAL DE REFERÊNCIA (bar): 0-50-30-80-20-100
% ============================================================

Pref_bar = zeros(size(t));
Pref_bar(t>=0.5) = 50;
Pref_bar(t>=1.0) = 30;
Pref_bar(t>=1.5) = 80;
Pref_bar(t>=2.0) = 20;
Pref_bar(t>=2.5) = 100;

Pref = Pref_bar * 1e5;   % converter para Pa (entrada no modelo)
Pref_ts = timeseries(Pref,t);
assignin('base','Pref_ts',Pref_ts);

%% Configurar modelo
model = 'Freio_LQR_Model';
model = MODEL_NAME;

% Checagem para mensagem mais clara quando o modelo nao estiver disponivel
if exist(model,'file') ~= 4 && exist([model '.slx'],'file') ~= 2
      error(['Nao foi possivel localizar o modelo Simulink `%s` (arquivo .slx nao encontrado no path).\n' ...
               'Ajuste `MODEL_NAME` no topo deste script OU coloque o arquivo `%s.slx` neste workspace.'], model, model);
end
load_system(model);

set_param(model,'Solver','FixedStepDiscrete');
set_param(model,'FixedStep',num2str(Ts));
set_param(model,'StopTime',num2str(Tf));

%% Rodar simulação
simOut = sim(model);

%% Captura dos sinais do Simulink (logsout)
logs = simOut.logsout;
getTS = @(name) logs.get(name).Values;

omega_p = getTS('omega_p');
u_in    = getTS('u_in');
u_out   = getTS('u_out');
Psup    = getTS('Psup_bar');
Pw      = getTS('Pw_bar');
Pref    = getTS('Pref_bar');

Tstop = max(Psup.Time);

%% Configuração de plots
set(groot,'defaultLineLineWidth',1.6);
set(groot,'defaultAxesFontSize',11);
set(groot,'defaultAxesFontName','Times New Roman');
set(groot,'defaultFigureRenderer','painters');

fig = figure('Color','w','Position',[100 100 1200 850]);
tiledlayout(2,1,'TileSpacing','compact','Padding','compact');

% 1) Entradas / Comandos
nexttile;
plot(omega_p.Time, squeeze(omega_p.Data),'k'); hold on;
plot(u_in.Time,  squeeze(u_in.Data)*max(squeeze(omega_p.Data)),'b--');
plot(u_out.Time, squeeze(u_out.Data)*max(squeeze(omega_p.Data)),'r--');
grid on; ylabel('\\omega_p (rad/s)','FontSize',18);
title('Sinais de comando','FontSize',18);
legend('\\omega_p','u_{in} (esc.)','u_{out} (esc.)','Location','best','FontSize',16);
ylim([-0.1*max(squeeze(omega_p.Data)), 1.1*max(squeeze(omega_p.Data))]);
xlim([0 Tstop]);

% 2) Pressões
nexttile;
plot(Psup.Time, squeeze(Psup.Data),'b'); hold on;
plot(Pw.Time,   squeeze(Pw.Data),'r');
plot(Pref.Time, squeeze(Pref.Data),'k--');
grid on; ylabel('Pressão (bar)','FontSize',18); title('Pressões e referência','FontSize',18);
legend('P_{sup}','P_w','P_{ref}','Location','best','FontSize',16);
ymin = min([squeeze(Psup.Data); squeeze(Pw.Data); squeeze(Pref.Data)]);
ymax = max([squeeze(Psup.Data); squeeze(Pw.Data); squeeze(Pref.Data)]);
ylim([ymin-5, ymax+5]);
xlim([0 Tstop]);

%% Exportar figuras
scriptDir = fileparts(mfilename('fullpath'));
outDir = fullfile(scriptDir,'figuras');
if ~exist(outDir,'dir'), mkdir(outDir); end

pdfPath = fullfile(outDir,'simulacao_comandos_e_pressao.pdf');
pngPath = fullfile(outDir,'simulacao_comandos_e_pressao.png');
exportgraphics(fig, pdfPath, 'ContentType','vector');
exportgraphics(fig, pngPath, 'Resolution', 1200);

disp('OK: figuras exportadas em:');
disp(outDir);

%% ============================================================
% ANALISES (itens 1--12) + robustez de discretizacao
% Cada item gera uma figura e salva em `figuras/` e no diretorio do artigo.
% ============================================================

% Vetores base (bar)
[t_vec, Pw_bar]   = ts_to_vec(Pw);
[~,    Psup_bar] = ts_to_vec(Psup);
[~,    Pref_bar] = ts_to_vec(Pref);
[~,    omega]    = ts_to_vec(omega_p);
[~,    uin]      = ts_to_vec(u_in);
[~,    uout]     = ts_to_vec(u_out);

e_bar = Pref_bar - Pw_bar;

% Detectar degraus da referencia (indices e tempos)
idx_steps = find(diff(Pref_bar) ~= 0) + 1;
idx_steps = idx_steps(:);
idx_all = [idx_steps; numel(t_vec)+1];

% Computar metricas por degrau
alpha_rise = [0.1 0.9];
tol_frac   = 0.02;
stepTbl = compute_step_metrics(t_vec, Pref_bar, Pw_bar, alpha_rise, tol_frac);

% Item 1) Metricas de rastreamento por trecho
fig1 = figure('Color','w','Position',[80 80 1200 850]);
tiledlayout(3,1,'TileSpacing','compact','Padding','compact');

nexttile;
plot(t_vec, Pw_bar,'r','LineWidth',1.4); hold on;
plot(t_vec, Pref_bar,'k--','LineWidth',1.2);
grid on; ylabel('Pressao (bar)','FontSize',18);
title('Item 1: Resposta e referencia','FontSize',18);
legend('P_w','P_{ref}','Location','best','FontSize',16);

nexttile;
plot(t_vec, e_bar,'b','LineWidth',1.2);
grid on; ylabel('Erro (bar)','FontSize',18);
title('Erro de seguimento e(t) = P_{ref}(t) - P_w(t)','FontSize',18);

nexttile;
if ~isempty(stepTbl)
      k = (1:height(stepTbl))';
      yyaxis left;
      bar(k, stepTbl.RMSE_seg,'FaceColor',[0.3 0.3 0.8],'EdgeColor','none');
      ylabel('RMSE por degrau (bar)','FontSize',18);
      yyaxis right;
      plot(k, abs(stepTbl.e_inf),'ko-','LineWidth',1.2,'MarkerSize',4);
      ylabel('|e_{inf}| (bar)','FontSize',18);
      grid on;
      xlabel('Indice do degrau','FontSize',18);
      title('Resumo por degrau (RMSE e erro estacionario)','FontSize',18);
else
      axis off;
      text(0,0.5,'Nao foi possivel extrair degraus de P_{ref}.','FontSize',16);
end

export_figure(fig1, outDir, 'artigo_item01_metricas_tracking');

% Figura adicional (template ja usado) com anotacao de metricas em texto
fig1b = figure('Color','w','Position',[80 80 1200 850]);
tiledlayout(3,1,'TileSpacing','compact','Padding','compact');

nexttile;
plot(t_vec, Pw_bar,'r','LineWidth',1.4); hold on;
plot(t_vec, Pref_bar,'k--','LineWidth',1.2);
grid on; ylabel('Pressao (bar)','FontSize',18);
title('Resposta e referencia (P_w)','FontSize',18);
legend('P_w','P_{ref}','Location','best','FontSize',16);

nexttile;
plot(t_vec, e_bar,'b','LineWidth',1.2);
grid on; ylabel('Erro (bar)','FontSize',18); xlabel('Tempo (s)','FontSize',18);
title('Erro de seguimento','FontSize',18);

txt = build_metrics_text(t_vec, Pref_bar, Pw_bar, omega, uin, uout, stepTbl);
annotation(fig1b,'textbox',[0.04 0.01 0.92 0.26], ...
      'String',txt,'FitBoxToText','off','Interpreter','tex', ...
      'EdgeColor',[0.2 0.2 0.2],'BackgroundColor',[1 1 1]);

export_figure(fig1b, outDir, 'artigo_item01_metricas_desempenho');

% Item 2) dP/dt e saturacoes
dPw_dt = gradient(Pw_bar, t_vec);   % bar/s
dPs_dt = gradient(Psup_bar, t_vec); % bar/s
omega_max = max(omega);

fig2 = figure('Color','w','Position',[80 80 1200 850]);
tiledlayout(3,1,'TileSpacing','compact','Padding','compact');

nexttile;
plot(t_vec, Pw_bar,'r'); hold on;
plot(t_vec, Pref_bar,'k--');
grid on; ylabel('Pressao (bar)','FontSize',18);
title('Item 2: Pressao e referencia','FontSize',18);

nexttile;
plot(t_vec, dPw_dt,'b'); hold on;
plot(t_vec, dPs_dt,'c');
grid on; ylabel('dP/dt (bar/s)','FontSize',18);
legend('dP_w/dt','dP_{sup}/dt','Location','best','FontSize',16);
title('Taxas de variacao de pressao','FontSize',18);

nexttile;
plot(t_vec, omega,'k'); hold on;
plot(t_vec, uin*omega_max,'b--');
plot(t_vec, uout*omega_max,'r--');
satMask = omega >= 0.99*omega_max;
if any(satMask)
      plot(t_vec(satMask), omega(satMask),'mo','MarkerSize',3,'MarkerFaceColor','m');
end
grid on; xlabel('Tempo (s)','FontSize',18); ylabel('omega_p (rad/s)','FontSize',18);
legend('omega_p','u_{in} (esc.)','u_{out} (esc.)','omega_p ~ sat','Location','best','FontSize',18);
title('Comandos e indicacao de saturacao (proxima ao maximo observado)','FontSize',18);

export_figure(fig2, outDir, 'artigo_item02_dpdt_saturacao');

% Item 3) Assimetria: subida vs descida
[iRise, iFall] = pick_rise_fall_steps(Pref_bar);
fig3 = figure('Color','w','Position',[80 80 1200 850]);
tiledlayout(2,2,'TileSpacing','compact','Padding','compact');

plot_step_zoom(1, iRise, 'Subida (pressurizacao)', t_vec, Pw_bar, Pref_bar, dPw_dt, omega, uin, uout);
plot_step_zoom(2, iFall, 'Descida (alivio)',        t_vec, Pw_bar, Pref_bar, dPw_dt, omega, uin, uout);

export_figure(fig3, outDir, 'artigo_item03_assimetria_subida_descida');

% Item 4) Ripple / oscilacoes em regime + espectro simples (FFT)
[seg_t, seg_y, seg_r] = pick_steady_segment(t_vec, Pw_bar, Pref_bar, idx_steps);
seg_e = seg_r - seg_y;

fig4 = figure('Color','w','Position',[80 80 1200 850]);
tiledlayout(2,1,'TileSpacing','compact','Padding','compact');

nexttile;
plot(seg_t, seg_y,'r','LineWidth',1.4); hold on;
plot(seg_t, seg_r,'k--','LineWidth',1.2);
grid on; ylabel('Pressao (bar)','FontSize',18);
title('Item 4: Zoom em regime (possivel ripple)','FontSize',18);
legend('P_w','P_{ref}','Location','best','FontSize',16);

nexttile;
fs = 1/mean(diff(seg_t));
[f, mag] = simple_fft_mag(seg_e - mean(seg_e), fs);
plot(f, mag,'b','LineWidth',1.2);
grid on; xlabel('Frequencia (Hz)','FontSize',18); ylabel('|FFT(e)| (a.u.)','FontSize',18);
title('Espectro do erro no trecho em regime (FFT, sem janela)','FontSize',18);
xlim([0, min(500, max(f))]);

export_figure(fig4, outDir, 'artigo_item04_ripple_fft');

% Item 5) Validade local: nao linear vs linear (janela com u_in=1, u_out=0)
[t_win, u_win, x0] = pick_linear_validation_window(t_vec, omega, Psup_bar, Pw_bar, uin, uout, Psup_op/1e5, Pw_op/1e5);
if ~isempty(t_win)
      % Simular modelo linear discreto em tempo continuo equivalente via lsim
      % Usar sys_d (ZOH) como aproximacao com step-invariant (interp por amostragem)
      % Converter omega para incremental (rad/s)
      u_delta = u_win - mean(u_win);
      % Reamostrar para Ts nominal
      t0 = t_win(1);
      t1 = t_win(end);
      tS = (t0:Ts:t1)';
      uS = interp1(t_win, u_delta, tS, 'previous','extrap');
      % Estados incrementais em Pa (a partir do inicio da janela)
      x0_pa = x0(:) * 1e5;
      y_lin = lsim(sys_d, uS, tS, x0_pa);
      Pw_lin_bar = y_lin/1e5 + Pw_op/1e5;
      Pw_nl_bar  = interp1(t_vec, Pw_bar, tS, 'linear','extrap');
      fig5 = figure('Color','w','Position',[80 80 1200 850]);
      plot(tS, Pw_nl_bar,'r','LineWidth',1.4); hold on;
      plot(tS, Pw_lin_bar,'k--','LineWidth',1.2);
      grid on; xlabel('Tempo (s)','FontSize',18); ylabel('P_w (bar)','FontSize',18);
      title('Item 5: Comparacao local (nao linear vs linearizado) em janela de operacao','FontSize',18);
      legend('Planta nao linear (Simulink)','Modelo linear (local)','Location','best','FontSize',16);
      export_figure(fig5, outDir, 'artigo_item05_validacao_linearizacao');
else
      warning('Item 5: janela de validacao linear nao encontrada (u_in/u_out nao permitem).');
end

% Item 6) Sensibilidade parametrica focada (varredura simples)
sensParams = { ...
      struct('name','beta','nom',beta,'scale',[0.8 1.0 1.2]), ...
      struct('name','Vw',  'nom',Vw,  'scale',[0.8 1.0 1.2]), ...
      struct('name','Ain_max','nom',Ain_max,'scale',[0.8 1.0 1.2]) ...
};

try
      sensRes = run_param_sensitivity(model, sensParams, Ts, Tf, Pref_ts);
      fig6 = plot_sensitivity_results(sensRes);
      export_figure(fig6, outDir, 'artigo_item06_sensibilidade_parametrica');
catch me
      warning('Item 6: falha na varredura de sensibilidade: %s', me.message);
end

% Item 7) Atrasos efetivos e tempos caracteristicos por degrau
fig7 = figure('Color','w','Position',[80 80 1200 850]);
if ~isempty(stepTbl)
      k = (1:height(stepTbl))';
      yyaxis left;
      stem(k, stepTbl.t_delay10,'filled','LineWidth',1.2); hold on;
      ylabel('Atraso ate 10% (s)','FontSize',18);
      yyaxis right;
      plot(k, stepTbl.tr_10_90,'ko-','LineWidth',1.2,'MarkerSize',4);
      ylabel('t_r (10-90%) (s)','FontSize',18);
      grid on; xlabel('Indice do degrau','FontSize',18);
      title('Item 7: Atraso efetivo e tempo de subida por degrau','FontSize',18);
      legend('Atraso (10%)','t_r (10-90%)','Location','best','FontSize',16);
else
      axis off;
      text(0,0.5,'Tabela de degraus vazia - nao ha atrasos para plotar.','FontSize',18);
end
export_figure(fig7, outDir, 'artigo_item07_atrasos_tempos');

% Item 8) Relacao comando -> pressao (mapas)
fig8 = figure('Color','w','Position',[80 80 1200 850]);
tiledlayout(2,2,'TileSpacing','compact','Padding','compact');

nexttile;
scatter(omega, dPs_dt, 8, (Psup_bar - Pw_bar), 'filled');
grid on; xlabel('omega_p (rad/s)','FontSize',18); ylabel('dP_{sup}/dt (bar/s)','FontSize',18);
title('omega_p -> dP_{sup}/dt (cor = \DeltaP)','FontSize',18);
cb = colorbar; cb.Label.String = '\DeltaP (bar)';

nexttile;
scatter(omega, dPw_dt, 8, (Psup_bar - Pw_bar), 'filled');
grid on; xlabel('omega_p (rad/s)','FontSize',18); ylabel('dP_w/dt (bar/s)','FontSize',18);
title('omega_p -> dP_w/dt (cor = \DeltaP)','FontSize',18);
cb = colorbar; cb.Label.String = '\DeltaP (bar)';

nexttile;
scatter(uout, dPw_dt, 8, Pw_bar, 'filled');
grid on; xlabel('u_{out}','FontSize',18); ylabel('dP_w/dt (bar/s)','FontSize',18);
title('u_{out} -> dP_w/dt (cor = P_w)','FontSize',18);
cb = colorbar; cb.Label.String = 'P_w (bar)';

nexttile;
scatter(uin, dPw_dt, 8, (Psup_bar - Pw_bar), 'filled');
grid on; xlabel('u_{in}','FontSize',18); ylabel('dP_w/dt (bar/s)','FontSize',18);
title('u_{in} -> dP_w/dt (cor = \DeltaP)','FontSize',18);
cb = colorbar; cb.Label.String = '\DeltaP (bar)';

export_figure(fig8, outDir, 'artigo_item08_mapa_comando_pressao');

% Item 9) Trade-off erro vs esforco (varrer R do LQI)
try
      tradeRes = run_tradeoff_sweep(model, A, B, C, Ts, Tf);
      fig9 = figure('Color','w','Position',[80 80 1200 850]);
      plot(tradeRes.e_rms, tradeRes.omega_rms,'ko-','LineWidth',1.3,'MarkerSize',5); hold on;
      grid on; xlabel('e_{RMS} (bar)','FontSize',18); ylabel('RMS(\omega_p) (rad/s)','FontSize',18);
      title('Item 9: Trade-off (erro vs esforco de controle)','FontSize',18);
      export_figure(fig9, outDir, 'artigo_item09_tradeoff_erro_esforco');
catch me
      warning('Item 9: falha no sweep de trade-off: %s', me.message);
end

% Item 10) Robustez a ruido de medicao (se o modelo suportar)
try
      noiseRes = run_noise_sweep(model, Ts, Tf, Pref_ts);
      fig10 = plot_noise_results(noiseRes);
      export_figure(fig10, outDir, 'artigo_item10_robustez_ruido');
catch me
      warning('Item 10: ensaio de ruido nao concluido: %s', me.message);
end

% Item 11) Transicoes/mudancas de patamar (marcacao dos degraus)
fig11 = figure('Color','w','Position',[80 80 1200 850]);
plot(t_vec, Pw_bar,'r','LineWidth',1.4); hold on;
plot(t_vec, Pref_bar,'k--','LineWidth',1.2);
for k = 1:numel(idx_steps)
      xline(t_vec(idx_steps(k)),'Color',[0.6 0.6 0.6],'LineStyle',':');
end
grid on; xlabel('Tempo (s)','FontSize',18); ylabel('Pressao (bar)','FontSize',18);
title('Item 11: Transicoes de referencia (patamares)','FontSize',18);
legend('P_w','P_{ref}','Location','best','FontSize',16);
export_figure(fig11, outDir, 'artigo_item11_transicoes_referencia');

% Item 12) Plausibilidade: resumo de ordens de grandeza extraidas da simulacao
fig12 = figure('Color','w','Position',[80 80 1200 850]);
tiledlayout(2,1,'TileSpacing','compact','Padding','compact');

nexttile;
plot(t_vec, Pw_bar,'r','LineWidth',1.4); hold on;
plot(t_vec, Pref_bar,'k--','LineWidth',1.2);
grid on; ylabel('Pressao (bar)','FontSize',18);
title('Item 12: Curva base (contexto)','FontSize',18);

nexttile;
axis off;
txt12 = build_plausibility_text(t_vec, Pw_bar, Psup_bar, dPw_dt, dPs_dt, stepTbl, omega, uin, uout);
text(0.01, 0.98, txt12, 'VerticalAlignment','top','Interpreter','tex','FontSize',11);
export_figure(fig12, outDir, 'artigo_item12_plausibilidade_resumo');

% Extra) Robustez da discretizacao (Ts sweep) - opcional, pode demorar
try
      Ts_list = [5e-5 1e-4 2e-4 5e-4];
      discRes = run_discretization_sweep(model, A, B, C, Ts_list, Tf);
      figD = plot_discretization_results(discRes);
      export_figure(figD, outDir, 'artigo_extra_discretizacao');
catch me
      warning('Extra discretizacao: falha no sweep de Ts: %s', me.message);
end

disp('OK: analises concluida(s). Figuras exportadas no diretorio do artigo e em ./figuras');

%% ============================================================
% Funcoes locais
% ============================================================

function [t, y] = ts_to_vec(ts)
      t = ts.Time(:);
      y = squeeze(ts.Data);
      if isrow(y)
            y = y(:);
      end
end

function export_figure(figHandle, outDir, baseName)
      if ~exist(outDir,'dir')
            mkdir(outDir);
      end
      pdfPath = fullfile(outDir, [baseName '.pdf']);
      pngPath = fullfile(outDir, [baseName '.png']);
      exportgraphics(figHandle, pdfPath, 'ContentType','vector');
      exportgraphics(figHandle, pngPath, 'Resolution', 300);
end

function stepTbl = compute_step_metrics(t, r, y, alpha_rise, tol_frac)
      idx_steps = find(diff(r) ~= 0) + 1;
      idx_steps = idx_steps(:);
      idx_all = [idx_steps; numel(t)+1];
      rows = [];
      for k = 1:numel(idx_steps)
            i0 = idx_steps(k);
            i1 = idx_all(k+1) - 1;
            if i1 <= i0
                  continue;
            end
            t0 = t(i0);
            r0 = r(i0-1);
            r1 = r(i0);
            y0 = y(i0-1);
            dt = r1 - r0;
            if abs(dt) < 1e-12
                  continue;
            end
            ts = t(i0:i1);
            ys = y(i0:i1);
            es = r(i0:i1) - y(i0:i1);

            % RMSE do segmento
            Tseg = ts(end) - ts(1);
            RMSE_seg = sqrt(trapz(ts, es.^2) / max(Tseg, eps));

            % Overshoot
            if dt > 0
                  peak = max(ys);
                  Mp = 100 * max(0, peak - r1) / abs(dt);
            else
                  peak = min(ys);
                  Mp = 100 * max(0, r1 - peak) / abs(dt);
            end

            % Rise time (10%-90%)
            y10 = y0 + alpha_rise(1)*dt;
            y90 = y0 + alpha_rise(2)*dt;
            if dt > 0
                  i10 = find(ys >= y10, 1, 'first');
                  i90 = find(ys >= y90, 1, 'first');
            else
                  i10 = find(ys <= y10, 1, 'first');
                  i90 = find(ys <= y90, 1, 'first');
            end
            if isempty(i10) || isempty(i90)
                  tr_10_90 = NaN;
                  t_delay10 = NaN;
            else
                  tr_10_90 = ts(i90) - ts(i10);
                  t_delay10 = ts(i10) - t0;
            end

            % Settling time (2%)
            band = tol_frac * abs(dt);
            outside = find(abs(ys - r1) > band);
            if isempty(outside)
                  ts_settle = 0;
            else
                  last_out = outside(end);
                  if last_out == numel(ts)
                        ts_settle = NaN;
                  else
                        ts_settle = ts(last_out) - t0;
                  end
            end

            % Erro estacionario (media do ultimo 10%)
            n_tail = max(5, round(0.1*numel(ts)));
            e_inf = mean((r(i1-n_tail+1:i1) - y(i1-n_tail+1:i1)));

            rows = [rows; {k, t0, r0, r1, Mp, tr_10_90, ts_settle, t_delay10, e_inf, RMSE_seg}]; %#ok<AGROW>
      end
      if isempty(rows)
            stepTbl = table();
            return;
      end
      stepTbl = cell2table(rows, 'VariableNames', { ...
            'k','t0','r0','r1','Mp_pct','tr_10_90','ts_2pct','t_delay10','e_inf','RMSE_seg' ...
      });
end

function txt = build_metrics_text(t, r, y, omega, uin, uout, stepTbl)
      e = r - y;
      Ttotal = t(end) - t(1);
      e_rms = sqrt(trapz(t, e.^2) / max(Ttotal, eps));
      omega_max = max(omega);
      txtLines = {};
      txtLines{end+1} = sprintf('e_{RMS} (global) = %.3f bar', e_rms);
      txtLines{end+1} = sprintf('max(\\omega_p) = %.1f rad/s', omega_max);
      txtLines{end+1} = sprintf('max(u_{in}) = %.2f, max(u_{out}) = %.2f', max(uin), max(uout));
      if ~isempty(stepTbl)
            for i = 1:height(stepTbl)
                  txtLines{end+1} = sprintf('Degrau #%d @ t=%.2fs: r %.0f->%.0f bar | Mp=%.1f%%%% | t_r=%.3fs | t_s=%.3fs | e_{inf}=%.3f bar | RMSE=%.3f bar', ...
                        stepTbl.k(i), stepTbl.t0(i), stepTbl.r0(i), stepTbl.r1(i), stepTbl.Mp_pct(i), ...
                        stepTbl.tr_10_90(i), stepTbl.ts_2pct(i), stepTbl.e_inf(i), stepTbl.RMSE_seg(i));
            end
      end
      txt = strjoin(txtLines, '\n');
end

function [iRise, iFall] = pick_rise_fall_steps(r)
      dr = diff(r);
      iRise = find(dr > 0, 1, 'first');
      iFall = find(dr < 0, 1, 'first');
      if isempty(iRise)
            iRise = 1;
      else
            iRise = iRise + 1;
      end
      if isempty(iFall)
            iFall = max(2, iRise);
      else
            iFall = iFall + 1;
      end
end

function plot_step_zoom(tileRow, idx0, ttl, t, y, r, dy, omega, uin, uout)
      if isempty(idx0) || idx0 < 2
            idx0 = 2;
      end
      % janela de zoom (0.25 s)
      t0 = t(idx0);
      t1 = min(t0 + 0.25, t(end));
      mask = (t >= t0) & (t <= t1);

      nexttile((tileRow-1)*2 + 1);
      plot(t(mask), y(mask),'r','LineWidth',1.4); hold on;
      plot(t(mask), r(mask),'k--','LineWidth',1.2);
      grid on; ylabel('Pressao (bar)','FontSize',18);
      title(['Item 3: ' ttl ' - pressao'],'FontSize',18);
      legend('P_w','P_{ref}','Location','best','FontSize',16);

      nexttile((tileRow-1)*2 + 2);
      omega_max = max(omega);
      plot(t(mask), dy(mask),'b','LineWidth',1.2); hold on;
      plot(t(mask), omega(mask)/max(omega_max,eps),'k');
      plot(t(mask), uin(mask),'b--');
      plot(t(mask), uout(mask),'r--');
      grid on; ylabel('Normalizado / bar/s','FontSize',18);
      title(['Item 3: ' ttl ' - taxa e comandos'],'FontSize',18);
      legend('dP_w/dt','\\omega_p (norm.)','u_{in}','u_{out}','Location','best','FontSize',16);
end

function [seg_t, seg_y, seg_r] = pick_steady_segment(t, y, r, idx_steps)
      % Escolhe o ultimo patamar apos o ultimo degrau, descartando um tempo de acomodacao
      if isempty(idx_steps)
            segMask = t >= 0.8*t(end);
      else
            last = idx_steps(end);
            t_start = min(t(end)-0.6, t(last) + 0.2);
            segMask = t >= t_start;
      end
      seg_t = t(segMask);
      seg_y = y(segMask);
      seg_r = r(segMask);
      if numel(seg_t) < 20
            seg_t = t(max(1,end-200):end);
            seg_y = y(max(1,end-200):end);
            seg_r = r(max(1,end-200):end);
      end
end

function [f, mag] = simple_fft_mag(x, fs)
      x = x(:);
      N = numel(x);
      Nfft = 2^nextpow2(N);
      X = fft(x, Nfft);
      P2 = abs(X)/max(N,1);
      P1 = P2(1:(Nfft/2+1));
      P1(2:end-1) = 2*P1(2:end-1);
      f = fs*(0:(Nfft/2))/Nfft;
      mag = P1;
end

function [t_win, u_win, x0] = pick_linear_validation_window(t, omega, Psup_bar, Pw_bar, uin, uout, Psup_op_bar, Pw_op_bar)
      % Busca uma janela onde uin=1 e uout=0 por tempo suficiente
      mask = (uin > 0.5) & (uout < 0.5);
      % encontrar o maior trecho continuo
      d = diff([0; mask; 0]);
      startIdx = find(d==1);
      endIdx = find(d==-1)-1;
      if isempty(startIdx)
            t_win = []; u_win = []; x0 = [];
            return;
      end
      segLens = endIdx - startIdx + 1;
      [~, j] = max(segLens);
      s = startIdx(j);
      e = endIdx(j);
      if (t(e) - t(s)) < 0.25
            t_win = []; u_win = []; x0 = [];
            return;
      end
      % usar sub-janela de 0.25 s a partir do inicio do trecho
      t0 = t(s);
      t1 = min(t0 + 0.25, t(e));
      sel = (t >= t0) & (t <= t1);
      t_win = t(sel);
      u_win = omega(sel);
      x0 = [Psup_bar(sel);
              Pw_bar(sel)];
      x0 = [x0(1,1) - Psup_op_bar; x0(2,1) - Pw_op_bar];
end

function sensRes = run_param_sensitivity(model, sensParams, Ts, Tf, Pref_ts)
      % Usa as variaveis do workspace base consumidas pelo modelo
      sensRes = struct();
      sensRes.params = sensParams;
      sensRes.points = [];
      baseVars = evalin('base','whos'); %#ok<NASGU>

      for p = 1:numel(sensParams)
            par = sensParams{p};
            for s = 1:numel(par.scale)
                  val = par.nom * par.scale(s);

                  assignin('base', par.name, val);
                  assignin('base','Ts',Ts);
                  assignin('base','Pref_ts',Pref_ts);

                  load_system(model);
                  set_param(model,'Solver','FixedStepDiscrete');
                  set_param(model,'FixedStep',num2str(Ts));
                  set_param(model,'StopTime',num2str(Tf));

                  simOut = sim(model);
                  logs = simOut.logsout;
                  getTS = @(name) logs.get(name).Values;
                  Pw = getTS('Pw_bar');
                  Pref = getTS('Pref_bar');
                  omega_p = getTS('omega_p');

                  [t, y] = ts_to_vec(Pw);
                  [~, r] = ts_to_vec(Pref);
                  [~, om] = ts_to_vec(omega_p);
                  e = r - y;
                  e_rms = sqrt(trapz(t, e.^2) / max((t(end)-t(1)), eps));
                  omega_rms = sqrt(trapz(t, om.^2) / max((t(end)-t(1)), eps));

                  sensRes.points = [sensRes.points; {par.name, par.scale(s), e_rms, omega_rms}]; %#ok<AGROW>
            end
            % restaurar nominal
            assignin('base', par.name, par.nom);
      end
      sensRes.points = cell2table(sensRes.points, 'VariableNames', {'param','scale','e_rms','omega_rms'});
end

function fig = plot_sensitivity_results(sensRes)
      fig = figure('Color','w','Position',[80 80 1200 850]);
      tiledlayout(1,2,'TileSpacing','compact','Padding','compact');
      pts = sensRes.points;
      params = unique(pts.param,'stable');

      nexttile;
      hold on;
      for i = 1:numel(params)
            p = params{i};
            sel = strcmp(pts.param,p);
            plot(pts.scale(sel), pts.e_rms(sel), 'o-','LineWidth',1.2,'MarkerSize',5);
      end
      grid on; xlabel('Escala do parametro','FontSize',18); ylabel('e_{RMS} (bar)','FontSize',18);
      title('Item 6: Sensibilidade (erro RMS)','FontSize',18);
      legend(params,'Location','best','FontSize',16);

      nexttile;
      hold on;
      for i = 1:numel(params)
            p = params{i};
            sel = strcmp(pts.param,p);
            plot(pts.scale(sel), pts.omega_rms(sel), 'o-','LineWidth',1.2,'MarkerSize',5);
      end
      grid on; xlabel('Escala do parametro','FontSize',18); ylabel('RMS(\omega_p) (rad/s)','FontSize',18);
      title('Item 6: Sensibilidade (esforco)','FontSize',18);
      legend(params,'Location','best','FontSize',16);
end

function tradeRes = run_tradeoff_sweep(model, A, B, C, Ts, Tf)
      % Varre R do LQI e registra (e_rms, omega_rms)
      R_list = [1e-8 3e-8 1e-7 3e-7 1e-6];
      tradeRes = struct('R',R_list(:),'e_rms',[],'omega_rms',[]);

      % Recriar sys_c e discretizar
      sys_c = ss(A,B,C,0);
      sys_d = c2d(sys_c, Ts);
      Ad = sys_d.A; Bd = sys_d.B; Cd = sys_d.C;
      Ad_aug = [Ad zeros(2,1);
                   -Cd*Ts 1];
      Bd_aug = [Bd; 0];

      Q_aug = diag([1e-12 1e-10 1e4]);

      for i = 1:numel(R_list)
            R = R_list(i);
            K_aug = dlqr(Ad_aug, Bd_aug, Q_aug, R);
            Kx = K_aug(1:2);
            Ki = K_aug(3);
            Ld = place(Ad', Cd', 0.4*eig(Ad))';
            assignin('base','Kx',Kx);
            assignin('base','Ki',Ki);
            assignin('base','Ld',Ld);
            assignin('base','Ts',Ts);

            % referencia padrao ja no workspace (Pref_ts)
            load_system(model);
            set_param(model,'Solver','FixedStepDiscrete');
            set_param(model,'FixedStep',num2str(Ts));
            set_param(model,'StopTime',num2str(Tf));
            simOut = sim(model);
            logs = simOut.logsout;
            getTS = @(name) logs.get(name).Values;
            Pw = getTS('Pw_bar');
            Pref = getTS('Pref_bar');
            omega_p = getTS('omega_p');

            [t, y] = ts_to_vec(Pw);
            [~, r] = ts_to_vec(Pref);
            [~, om] = ts_to_vec(omega_p);
            e = r - y;
            tradeRes.e_rms(i,1) = sqrt(trapz(t, e.^2) / max((t(end)-t(1)), eps));
            tradeRes.omega_rms(i,1) = sqrt(trapz(t, om.^2) / max((t(end)-t(1)), eps));
      end
end

function noiseRes = run_noise_sweep(model, Ts, Tf, Pref_ts)
      % Requer suporte no modelo: ENABLE_MEAS_NOISE, MEAS_NOISE_STD_BAR e Pw_meas_bar.
      std_list = [0 0.2 0.5 1.0]; % bar
      noiseRes = struct('std_bar',std_list(:),'e_rms',[],'omega_rms',[],'has_meas',false);

      for i = 1:numel(std_list)
            assignin('base','ENABLE_MEAS_NOISE', true);
            assignin('base','MEAS_NOISE_STD_BAR', std_list(i));
            assignin('base','Ts',Ts);
            assignin('base','Pref_ts',Pref_ts);

            load_system(model);
            set_param(model,'Solver','FixedStepDiscrete');
            set_param(model,'FixedStep',num2str(Ts));
            set_param(model,'StopTime',num2str(Tf));
            simOut = sim(model);
            logs = simOut.logsout;
            getTS = @(name) logs.get(name).Values;
            Pw = getTS('Pw_bar');
            Pref = getTS('Pref_bar');
            omega_p = getTS('omega_p');
            [t, y] = ts_to_vec(Pw);
            [~, r] = ts_to_vec(Pref);
            [~, om] = ts_to_vec(omega_p);
            e = r - y;
            noiseRes.e_rms(i,1) = sqrt(trapz(t, e.^2) / max((t(end)-t(1)), eps));
            noiseRes.omega_rms(i,1) = sqrt(trapz(t, om.^2) / max((t(end)-t(1)), eps));
            try
                  getTS('Pw_meas_bar');
                  noiseRes.has_meas = true;
            catch
            end
      end
end

function fig = plot_noise_results(noiseRes)
      fig = figure('Color','w','Position',[80 80 1200 850]);
      tiledlayout(1,2,'TileSpacing','compact','Padding','compact');

      nexttile;
      plot(noiseRes.std_bar, noiseRes.e_rms,'ko-','LineWidth',1.2,'MarkerSize',5);
      grid on; xlabel('\sigma_n (bar)','FontSize',18); ylabel('e_{RMS} (bar)','FontSize',18);
      title('Item 10: Degradacao do erro com ruido','FontSize',18);

      nexttile;
      plot(noiseRes.std_bar, noiseRes.omega_rms,'ko-','LineWidth',1.2,'MarkerSize',5);
      grid on; xlabel('\sigma_n (bar)','FontSize',18); ylabel('RMS(\omega_p) (rad/s)','FontSize',18);
      title('Item 10: Esforco vs ruido','FontSize',18);
end

function txt = build_plausibility_text(t, Pw_bar, Psup_bar, dPw_dt, dPs_dt, stepTbl, omega, uin, uout)
      txtLines = {};
      txtLines{end+1} = sprintf('Resumo (extraido das curvas simuladas):');
      txtLines{end+1} = sprintf('Faixa P_w: [%.1f, %.1f] bar', min(Pw_bar), max(Pw_bar));
      txtLines{end+1} = sprintf('Faixa P_{sup}: [%.1f, %.1f] bar', min(Psup_bar), max(Psup_bar));
      txtLines{end+1} = sprintf('Pico |dP_w/dt|: %.1f bar/s', max(abs(dPw_dt)));
      txtLines{end+1} = sprintf('Pico |dP_{sup}/dt|: %.1f bar/s', max(abs(dPs_dt)));
      txtLines{end+1} = sprintf('max(\\omega_p): %.1f rad/s', max(omega));
      txtLines{end+1} = sprintf('Comandos binarios: max(u_{in})=%.0f, max(u_{out})=%.0f', max(uin), max(uout));
      if ~isempty(stepTbl)
            txtLines{end+1} = sprintf('t_r (mediana, 10-90%%): %.3f s', median(stepTbl.tr_10_90,'omitnan'));
            txtLines{end+1} = sprintf('t_s (mediana, 2%%): %.3f s', median(stepTbl.ts_2pct,'omitnan'));
      end
      txtLines{end+1} = sprintf('Obs.: esta figura e usada para checagem de ordem de grandeza e leitura objetiva de dinamica.');
      txt = strjoin(txtLines, '\n');
end

function discRes = run_discretization_sweep(model, A, B, C, Ts_list, Tf)
      discRes = struct();
      discRes.Ts = Ts_list(:);
      discRes.e_rms = zeros(numel(Ts_list),1);
      discRes.omega_rms = zeros(numel(Ts_list),1);

      for i = 1:numel(Ts_list)
            Ts = Ts_list(i);
            t = (0:Ts:Tf)';
            Pref_bar = zeros(size(t));
            Pref_bar(t>=0.5) = 50;
            Pref_bar(t>=1.0) = 30;
            Pref_bar(t>=1.5) = 80;
            Pref_bar(t>=2.0) = 20;
            Pref_bar(t>=2.5) = 100;
            Pref = Pref_bar * 1e5;
            Pref_ts = timeseries(Pref,t);

            % Redesenhar o controlador para o novo Ts
            sys_c = ss(A,B,C,0);
            sys_d = c2d(sys_c,Ts);
            Ad = sys_d.A; Bd = sys_d.B; Cd = sys_d.C;
            Ad_aug = [Ad zeros(2,1);
                         -Cd*Ts 1];
            Bd_aug = [Bd; 0];
            Q_aug = diag([1e-12 1e-10 1e4]);
            R = 1e-7;
            K_aug = dlqr(Ad_aug,Bd_aug,Q_aug,R);
            Kx = K_aug(1:2);
            Ki = K_aug(3);
            Ld = place(Ad',Cd',0.4*eig(Ad))';

            assignin('base','Kx',Kx);
            assignin('base','Ki',Ki);
            assignin('base','Ld',Ld);
            assignin('base','Ts',Ts);
            assignin('base','Pref_ts',Pref_ts);

            load_system(model);
            set_param(model,'Solver','FixedStepDiscrete');
            set_param(model,'FixedStep',num2str(Ts));
            set_param(model,'StopTime',num2str(Tf));

            simOut = sim(model);
            logs = simOut.logsout;
            getTS = @(name) logs.get(name).Values;
            Pw = getTS('Pw_bar');
            Pref = getTS('Pref_bar');
            omega_p = getTS('omega_p');
            [t2, y] = ts_to_vec(Pw);
            [~, r] = ts_to_vec(Pref);
            [~, om] = ts_to_vec(omega_p);
            e = r - y;
            discRes.e_rms(i) = sqrt(trapz(t2, e.^2) / max((t2(end)-t2(1)), eps));
            discRes.omega_rms(i) = sqrt(trapz(t2, om.^2) / max((t2(end)-t2(1)), eps));
      end
end

function fig = plot_discretization_results(discRes)
      fig = figure('Color','w','Position',[80 80 1200 850]);
      tiledlayout(1,2,'TileSpacing','compact','Padding','compact');
      nexttile;
      semilogx(discRes.Ts, discRes.e_rms,'ko-','LineWidth',1.2,'MarkerSize',5);
      grid on; xlabel('T_s (s)','FontSize',18); ylabel('e_{RMS} (bar)','FontSize',18);
      title('Extra: Sensibilidade a discretizacao (erro)','FontSize',18);

      nexttile;
      semilogx(discRes.Ts, discRes.omega_rms,'ko-','LineWidth',1.2,'MarkerSize',5);
      grid on; xlabel('T_s (s)','FontSize',18); ylabel('RMS(\omega_p) (rad/s)','FontSize',18);
      title('Extra: Sensibilidade a discretizacao (esforco)','FontSize',18);
end
