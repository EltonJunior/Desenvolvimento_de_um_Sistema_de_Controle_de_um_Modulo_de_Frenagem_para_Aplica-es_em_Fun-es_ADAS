# Repo

* [Overview](overview.md) - Visão geral do projeto de mestrado: controle digital e indireto de pressão hidráulica em atuador de frenagem para funções ADAS.

# Subdirectories

* [architecture](architecture/index.md) - Control Strategy — Estratégias de controle: controle indireto por posição (CLMULTI/LQR/Luenberger) versus controle direto LQI em pressão (2P); Data Flow & Telemetry — Fluxo de comunicação serial em tempo real entre PC/MATLAB e firmware embarcado AURIX (protocolo ECHO/LIVE/PLID/CLMULTI); Experimental Validation & Robustness — Metodologia de validação experimental, identificação paramétrica (tau e K_vel) e robustez paramétrica; and 1 more.
* [modules](modules/index.md) - Matlab Simulation & Synthesis — Scripts de modelagem analítica, linearização e síntese de controle em simulação (LQI discreto e observador 2P); Bench Testing & Identification — Suíte de ensaios experimentais em bancada real (PLID, CLMULTI, CLSTEP, sweep de PWM e identificação de parâmetros); Serial Communication & Codec — Módulos MATLAB System Object para codificação e decodificação do protocolo UART do AURIX.
