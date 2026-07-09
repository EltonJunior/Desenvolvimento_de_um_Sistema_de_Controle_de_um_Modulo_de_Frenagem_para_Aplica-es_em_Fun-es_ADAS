function [Psup_dot, Pw_dot, Qpump, Qin, Qout] = Bloco_Hidraulico_2P(omega_p, u_in, u_out, Psup, Pw)
%Bloco_Hidraulico_2P Nonlinear 2-pressure hydraulic plant (supply + wheel).
%
% Intended to be used inside a Simulink MATLAB Function block.
%
% Inputs:
%   omega_p: rad/s (>=0)
%   u_in, u_out: 0..1
%   Psup, Pw: Pa
% Outputs:
%   Psup_dot, Pw_dot: Pa/s
%   Qpump, Qin, Qout: m^3/s

% ---------- basic hydraulic parameters ----------
beta = 1.5e9;   % Pa
rho  = 850;     % kg/m^3
Pret = 1e5;     % Pa

% ---------- effective volumes ----------
Vsup = 6.0e-5;  % m^3
Vw   = 1.0e-5;  % m^3

% ---------- pump (simple linear model) ----------
Dp_rev = 5e-7;                  % m^3/rev
Nv     = 0.85;                  % volumetric efficiency
Kb     = Nv * (Dp_rev/(2*pi));  % m^3/rad
Klb    = 6.8e-13;               % (m^3/s)/Pa

% ---------- valves (orifice law) ----------
Cv_in    = 0.62;
Cv_out   = 0.62;
Ain_max  = 3.0e-7;              % m^2
Aout_max = 3.0e-7;              % m^2

% Optional leakages
Kleak_sup = 0;                  % (m^3/s)/Pa
Kleak_w   = 0;                  % (m^3/s)/Pa

% ---------- sanitize inputs ----------
if omega_p < 0
    omega_p = 0;
end
u_in  = min(max(u_in,  0), 1);
u_out = min(max(u_out, 0), 1);

% Avoid pressures below return
Psup = max(Psup, Pret);
Pw   = max(Pw,   Pret);

% ---------- pump -> supply ----------
Qpump = Kb*omega_p - Klb*(Psup - Pret);

% ---------- supply -> wheel (inlet valve) ----------
dPin = max(Psup - Pw, 0);
Qin  = Cv_in * (Ain_max * u_in) * sqrt(2*dPin/rho);

% ---------- wheel -> return (outlet valve) ----------
dPout = max(Pw - Pret, 0);
Qout  = Cv_out * (Aout_max * u_out) * sqrt(2*dPout/rho);

% ---------- pressure dynamics ----------
Psup_dot = (beta/Vsup) * ( Qpump - Qin - Kleak_sup*(Psup - Pret) );
Pw_dot   = (beta/Vw)   * ( Qin - Qout - Kleak_w*(Pw - Pret) );
end
