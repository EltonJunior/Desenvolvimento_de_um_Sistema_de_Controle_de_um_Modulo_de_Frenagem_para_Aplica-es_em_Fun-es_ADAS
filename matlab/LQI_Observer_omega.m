function omega_p = LQI_Observer_omega(Pw, Pref)
%LQI_Observer_omega MATLAB Function block code (LQI + Luenberger) with omega saturation.
%
% Drop-in controller to prevent Psup runaway after reducing Klb.
%
% Inputs (Pa): Pw, Pref
% Output (rad/s): omega_p

%#codegen

Ad = coder.const(Ad);
Bd = coder.const(Bd);
Cd = coder.const(Cd);
Kx = coder.const(Kx);
Ki = coder.const(Ki);
Ld = coder.const(Ld);
Ts = coder.const(Ts);
Kb = coder.const(Kb);
Klb = coder.const(Klb);
Pret = coder.const(Pret);

% Optional (but recommended): define P_sup_max_bar in base workspace.
P_sup_max_bar = coder.const(P_sup_max_bar);

persistent xhat xi u_prev

if isempty(xhat)
    xhat = zeros(2,1);
end

if isempty(xi)
    xi = 0;
end

if isempty(u_prev)
    u_prev = 0;
end

% ===== Discrete observer =====
% In real implementation, u_prev is the previously applied command.
xhat = Ad*xhat + Bd*u_prev + Ld*(Pw - Cd*xhat);

% ===== Tracking + anti-windup =====
erro = Pref - Pw; % Pa

% Physical limit coherent with supply pressure cap
P_sup_max = Pret + P_sup_max_bar*1e5;
omega_p_max = (P_sup_max - Pret) * (Klb / max(Kb, eps));

% Candidate integration
xi_cand = xi + erro*Ts;

% LQI law (unsaturated)
omega_unsat = -Kx*xhat - Ki*xi_cand;

% Saturation (non-reversible pump: omega >= 0)
omega_sat = omega_unsat;
if omega_sat < 0
    omega_sat = 0;
end
if omega_sat > omega_p_max
    omega_sat = omega_p_max;
end

% Conditional integration anti-windup
is_saturated = (omega_sat ~= omega_unsat);
if is_saturated
    if (omega_sat <= 0 && erro < 0) || (omega_sat >= omega_p_max && erro > 0)
        % hold xi
    else
        xi = xi_cand;
    end
else
    xi = xi_cand;
end

omega_p = omega_sat;
u_prev = omega_p;
end
