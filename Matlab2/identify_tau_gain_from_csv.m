% identify_tau_gain_from_csv.m
% Estima tau (constante de tempo) e K (ganho velocidade/%PWM) do atuador
% a partir de um CSV de ensaio (recomendado: PWMSWEEP, OLSTEP, ou
% CLMULTI serial com coluna u_x100). Plota gráficos para monografia.
%
% Uso:
%   identify_tau_gain_from_csv()               % auto-detecta último CSV em Matlab/dados
%   identify_tau_gain_from_csv('caminho.csv')  % usa CSV específico
%
function identify_tau_gain_from_csv(csvPath)
    close all; clc;
    if nargin < 1 || isempty(csvPath)
        % auto-detecta último CSV em Matlab/dados
        baseDir = fullfile(fileparts(mfilename('fullpath')), 'dados');
        if ~exist(baseDir, 'dir'), baseDir = pwd; end
        files = dir(fullfile(baseDir, '**', '*.csv'));
        if isempty(files), error('Nenhum CSV encontrado em %s', baseDir); end
        [~, idx] = max([files.datenum]);
        csvPath = fullfile(files(idx).folder, files(idx).name);
    end
    fprintf('Arquivo: %s\n', csvPath);

    % Leitura robusta
    raw = fileread(csvPath);
    lines = regexp(raw, '\r?\n', 'split');
    % Extrai linhas numéricas (CLMULTI: prefixo [CM], PLID: [PB] ou similar)
    data = [];
    for i = 1:numel(lines)
        s = strtrim(lines{i});
        if isempty(s), continue; end
        % Remove prefixos como [CM], [PB]
        if startsWith(s, '[')
            k = strfind(s, ']'); if ~isempty(k), s = strtrim(s(k(1)+1:end)); end
        end
        % Aceita linhas CSV com 5-8 campos numéricos
        parts = strsplit(s, ',');
        nums = nan(1, numel(parts)); ok = true;
        for j = 1:numel(parts)
            v = str2double(strtrim(parts{j}));
            if isnan(v), ok = false; break; end
            nums(j) = v;
        end
        if ok && numel(nums) >= 5
            data(end+1,1:numel(nums)) = nums; %#ok<AGROW>
        end
    end
    if isempty(data)
        % fallback: readtable
        T = readtable(csvPath, 'FileType','text');
        data = table2array(T);
    end

    % Heurística de colunas:
    % t_ms, pw_x100, pwHat_x100, pos_x100, pwRef_x100, u_x100 (CLMULTI)
    % ou t_ms, step, phase, pw_psi, pos_mm (PLID/PB)
    t_ms = data(:,1);
    % pos: tenta coluna 4 (pos_x100) senão 5 (pos_mm)
    if size(data,2) >= 4 && all(abs(data(:,4)) < 2e4)
        pos = data(:,4) / 100.0; % x100 → mm
    elseif size(data,2) >= 5
        pos = data(:,5); % já em mm
    else
        error('Não foi possível identificar coluna de posição.');
    end
    % u (%PWM): tenta última coluna (u_x100) se presente
    if size(data,2) >= 6
        u = data(:,end) / 100.0; % x100 → %
    else
        % sem u: assume PWM constante 10% (PLID típico)
        u = 10.0 * ones(size(pos));
    end
    t = (t_ms - t_ms(1)) / 1000.0; % s

    % Seleciona janelas com PWM ~constante e > 5%
    winLen = 0.8; % s
    minU = 5.0;   % %
    dt = median(diff(t));
    Nw = max(8, round(winLen/dt));
    idxConst = movstd(u, Nw, 'omitnan') < 0.7 & (u > minU);

    % Segmentar regiões
    % Segmentar regiões TRUE em idxConst sem depender de bwlabel (Image Toolbox)
    results = struct('t0',{},'t1',{},'uPct',{},'tau',{},'Kvel',{},'rmse',{});
    dIdx = diff([false; idxConst(:); false]);
    segStarts = find(dIdx == 1);
    segEnds   = find(dIdx == -1) - 1;

    % Derivada suavizada (velocidade)
    v = deriv_sgolay(t, pos);

    kseg = 0;
    for sId = 1:numel(segStarts)
        mask = false(size(t));
        mask(segStarts(sId):segEnds(sId)) = true;
        if nnz(mask) < Nw, continue; end
        ti = t(segStarts(sId)); tf = t(segEnds(sId));
        % recorta 0.6s iniciais da janela para pegar a subida
        tmask = t >= ti & t <= min(tf, ti + 0.6);
        if nnz(tmask) < max(10, Nw/2), continue; end
        tloc = t(tmask) - t(find(tmask,1,'first'));
        vloc = v(tmask);
        uloc = median(u(tmask));
        % Fitting: v(t) = Vss * (1 - exp(-(t)/tau))
        % Chutes iniciais
        Vss0 = max(1e-3, prctile(vloc, 90));
        tau0 = max(0.05, min(0.8, 0.2));
        p0 = [Vss0, tau0];
        obj = @(p) vloc - (max(0,p(1))*(1 - exp(-tloc/max(1e-3,p(2)))));
        p = fminsearch(@(pp) rms(obj(pp)), p0, optimset('Display','off'));
        Vss = max(0, p(1)); tau = max(1e-3, p(2));
        vhat = Vss * (1 - exp(-tloc/tau));
        rmse = sqrt(mean((vloc - vhat).^2));
        Kvel = Vss / max(1e-3, uloc); % mm/s por %PWM

        kseg = kseg + 1;
        results(kseg) = struct('t0',ti,'t1',tf,'uPct',uloc,'tau',tau,'Kvel',Kvel,'rmse',rmse); %#ok<SAGROW>

        % Plot por segmento (sobrepostos no mesmo figure)
        if kseg == 1
            figure('Color','w','Position',[100 100 1100 800]); tlo = tiledlayout(3,1,'TileSpacing','compact');
        end
        nexttile(1); hold on; grid on;
        plot(t, pos, 'Color',[0.7 0.7 0.7]);
        area([ti min(tf,ti+0.6)], [max(pos) max(pos)], min(pos), 'FaceColor',[0.8 0.9 1], 'EdgeColor','none', 'FaceAlpha',0.25);
        ylabel('Posição (mm)'); title('Janela usada para identificação');

        nexttile(2); hold on; grid on;
        plot(t, u, 'k-');
        yline(uloc, '--r', sprintf('u=%.1f%%', uloc)); ylabel('PWM (%)');

        nexttile(3); hold on; grid on;
        plot(tloc + ti, vloc, 'b-', 'LineWidth',1.2);
        plot(tloc + ti, vhat, 'r--', 'LineWidth',1.5);
        xlabel('Tempo (s)'); ylabel('Vel (mm/s)');
        legend('v medida','ajuste v̂','Location','best');
    end

    if isempty(results)
        error('Nenhuma janela com PWM ~constante encontrada > %.1f%%.', minU);
    end

    % Consolida estimativas (média ponderada por 1/rmse)
    w = 1./max(1e-6, [results.rmse]); w = w / sum(w);
    tau_est = sum(w .* [results.tau]);
    Kvel_est = sum(w .* [results.Kvel]);

    fprintf('\n===== Identificação: tau e K (velocidade/%PWM) =====\n');
    fprintf('Tau (s):        %.4f\n', tau_est);
    fprintf('K_vel (mm/s%%): %.4f\n', Kvel_est);
    fprintf('Janelas usadas: %d\n', numel(results));

    % Salva figura
    figDir = fullfile(fileparts(mfilename('fullpath')), 'figuras');
    if ~exist(figDir,'dir'), mkdir(figDir); end
    ts = datestr(now,'yyyymmdd_HHMMSS');
    outPng = fullfile(figDir, ['id_tauK_' ts '.png']);
    outPdf = fullfile(figDir, ['id_tauK_' ts '.pdf']);
    exportgraphics(gcf, outPng, 'Resolution', 200);
    exportgraphics(gcf, outPdf);
    fprintf('Figuras exportadas em:\n  %s\n  %s\n', outPng, outPdf);

    % Próximo passo sugerido
    fprintf('\nProximo passo:\n');
    fprintf('- Montar Φ,Γ de G(s)=K/(s*(tau*s+1)) com Ts=1ms (c2d com ZOH).\n');
    fprintf('- Projetar K,Ki por acker() no sistema aumentado (servossistema).\n');
    fprintf('- Projetar L por place() com polos 2-5x mais rapidos que MF.\n');
end

function v = deriv_sgolay(t, x)
    % Derivada robusta via Savitzky-Golay + diferenças
    x = x(:); t = t(:);
    dt = median(diff(t));
    try
        x_s = sgolayfilt(x, 3, max(5, 2*floor(0.05/dt)+1));
    catch
        x_s = x;
    end
    v = [0; diff(x_s)] ./ [dt; diff(t)];
    % Suaviza a derivada
    try
        v = sgolayfilt(v, 3, max(5, 2*floor(0.05/dt)+1));
    catch
    end
end
