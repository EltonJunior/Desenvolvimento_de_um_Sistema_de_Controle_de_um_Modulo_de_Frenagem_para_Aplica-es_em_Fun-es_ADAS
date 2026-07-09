%% script_controle_lqi_luenberger_run.m
% Synthesis + run helper with physical saturation parameters exported.
% This script matches the structure you posted, but additionally exports:
%   Pret, Kb, Klb, P_sup_max_bar, omega_p_max
% so the Simulink MATLAB Function controller can cap omega_p and prevent Psup runaway.

clear; clc; close all;

%% ============================================================
% 1) PHYSICAL PARAMETERS (consistent with 2P plant)
% ============================================================
beta = 1.5e9;
rho  = 850;
Pret = 1e5;

Vsup = 6.0e-5;
Vw   = 1.0e-5;

Dp_rev = 5e-7;
Nv     = 0.85;
Kb     = Nv * (Dp_rev/(2*pi));
Klb    = 6.8e-13;

Cv_in    = 0.62;
Ain_max  = 3.0e-7;

%% ============================================================
% 2) OPERATING POINT
% ============================================================
Pw_op   = 10e5;        % 100 bar
Psup_op = Pw_op + 5e5; % small differential

u_in_op = 0.5;

% Flow needed at op point
DeltaPin = Psup_op - Pw_op;
Qin_op   = Cv_in*(Ain_max*u_in_op)*sqrt(2*DeltaPin/rho);

omega_op = Qin_op / Kb;

%% ============================================================
% 3) ANALYTICAL LINEARIZATION
% States: x = [Psup Pw]'
% Input:  u = omega_p
% Output: y = Pw
% ============================================================

kq  = Cv_in*Ain_max*u_in_op;
s   = sqrt(2*DeltaPin/rho);
dQd = kq/(rho*s); % dQin/d(Psup-Pw)

% Psup_dot = (beta/Vsup)*(Kb*omega_p - Klb*(Psup-Pret) - Qin)
% Pw_dot   = (beta/Vw)  *(Qin)  (u_out=0 at op)
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
% 4) DISCRETE LQI (ZOH)
% ============================================================
Ts = 1e-4;

sys_d = c2d(sys_c,Ts);
Ad = sys_d.A;
Bd = sys_d.B;
Cd = sys_d.C;

% Augmented system for LQI
Ad_aug = [Ad zeros(2,1);
         -Cd*Ts 1];
Bd_aug = [Bd; 0];

Q_aug = diag([1e-12 1e-10 1e4]);
R     = 1e-7;

K_aug = dlqr(Ad_aug,Bd_aug,Q_aug,R);
Kx = K_aug(1:2);
Ki = K_aug(3);

%% ============================================================
% 5) DISCRETE LUENBERGER OBSERVER
% ============================================================
Ld = place(Ad',Cd',0.4*eig(Ad))';

%% ============================================================
% 6) PHYSICAL SATURATION (critical for Psup)
% ============================================================
% Define a physical upper bound for supply pressure (gauge) and derive omega_p_max
P_sup_max_bar = 130;                 % bar (gauge)
P_sup_max     = Pret + P_sup_max_bar*1e5;
omega_p_max   = (P_sup_max - Pret) * (Klb / max(Kb, eps));

%% Export to base workspace (used by Simulink MATLAB Function blocks)
assignin('base','Ad',Ad);
assignin('base','Bd',Bd);
assignin('base','Cd',Cd);
assignin('base','Kx',Kx);
assignin('base','Ki',Ki);
assignin('base','Ld',Ld);
assignin('base','Ts',Ts);

assignin('base','Pret',Pret);
assignin('base','Kb',Kb);
assignin('base','Klb',Klb);
assignin('base','P_sup_max_bar',P_sup_max_bar);
assignin('base','omega_p_max',omega_p_max);

%% ============================================================
% 7) RUN SIMULINK MODEL
% ============================================================
% Pick model name (use v2 if present)
if ~isempty(which('Freio_LQR_Model_v2.slx')) || ~isempty(which('Freio_LQR_Model_v2.mdl'))
      model = 'Freio_LQR_Model_v2';
else
      model = 'Freio_LQR_Model';
end

% Reference profile: 0-50-30-80-20-100 (bar gauge)
Tf = 3;
t  = (0:Ts:Tf)';
t  = t(:);

% Safety: enforce non-decreasing time (avoids From Workspace errors)
[t, sortIdx] = sort(t,'ascend');

Pref_bar = zeros(size(t));
Pref_bar(t>=0.5) = 50;
Pref_bar(t>=1.0) = 30;
Pref_bar(t>=1.5) = 80;
Pref_bar(t>=2.0) = 20;
Pref_bar(t>=2.5) = 100;

Pref = Pref_bar * 1e5;
Pref = Pref(sortIdx);

% Export reference in multiple formats; choose the one matching your From Workspace block.
Pref_ts = timeseries(Pref,t);
Pref_ws_array = [t Pref]; % Nx2 array [time  value]
Pref_ws_struct.time = t;
Pref_ws_struct.signals.values = Pref;
Pref_ws_struct.signals.dimensions = 1;

assignin('base','t_ref',t);
assignin('base','Pref',Pref);
assignin('base','Pref_ts',Pref_ts);
assignin('base','Pref_ws_array',Pref_ws_array);
assignin('base','Pref_ws_struct',Pref_ws_struct);

%% ============================================================
% 7.1) QUICK DIAGNOSTICS FOR From Workspace BLOCK
% ============================================================
% This helps identify which workspace variable the block is actually using.
try
      load_system(model);
      blk = [model '/Control/From Workspace'];
      varName = get_param(blk,'VariableName');
      fprintf('\nFrom Workspace block variable: %s\n', varName);
      try
            md = evalin('base', sprintf('min(diff(%s.Time))', varName));
            fprintf('min(diff(%s.Time)) = %.3g\n', varName, md);
      catch
            try
                  md = evalin('base', sprintf('min(diff(%s(:,1)))', varName));
                  fprintf('min(diff(%s(:,1))) = %.3g\n', varName, md);
            catch
                  % ignore
            end
      end
catch ME
      fprintf('\nDiagnostic skipped: %s\n', ME.message);
end

set_param(model,'Solver','FixedStepDiscrete');
set_param(model,'FixedStep',num2str(Ts));
set_param(model,'StopTime',num2str(Tf));

simOut = sim(model);

% NOTE: plotting/log parsing is intentionally omitted here;
% keep using your existing post-processing section.
