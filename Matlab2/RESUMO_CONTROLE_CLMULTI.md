# RESUMO — Projeto e Ensaios CLMULTI (Controle Indireto de Pressão via Posição)

Data: 2026-09-13

## Objetivo
Projetar e validar o CLMULTI: controle indireto de pressão (Pw) por deslocamento do LAC (posição), com LQR e observador de Luenberger, conforme a monografia e a Apostila PTC5611.

## O que foi feito
- Implementado ensaio PLID (3 degraus: 100/200/300 psi) para mapear Pw = g(x) e obter pontos para a LUT inversa g⁻¹(Pref).
- Corrigido script MATLAB (serial) para evitar timeouts e gerar gráficos com as 3 curvas.
- Atualizada LUT do CLMULTI com dados do PLID (região alta, curva íngreme).
- Vários ensaios CLMULTI (perfis 0/100/200/50/0 psi) com logs serial e buffer 1 kHz.
- Criado script MATLAB para identificar τ e K do atuador a partir dos CSVs: `identify_tau_gain_from_csv.m`.
- Regras salvas (VIO rules): PRESSÃO NÃO FECHA A MALHA — controle é **exclusivamente** por posição (indireto), Pw apenas para log/segurança/identificação.

## O que deu certo
- PLID: atingimos 100/200/300 psi de forma reprodutível; extraímos posições de cruzamento e de hold.
- Subida a 100 psi no CLMULTI: desempenho consistente após ajuste da LUT (melhor resposta).
- Exportação de gráficos/CSVs e logs auxiliaram a depuração.

## O que deu errado (e por quê)
1) LUT estática vs. planta dinâmica: a relação Pw=g(x) tem histerese; posições de cruzamento e de hold são diferentes — LUT foi incorreta na região alta inicialmente.
2) Observador não era Luenberger: implementado apenas como filtro `x̂ += L*(posReal - x̂)`; faltou modelo Φ, Γ para predição + correção.
3) LQR sem projeto formal: KP/KI ajustados manualmente; faltou cálculo de K, Ki por alocação de polos no sistema aumentado (servossistema com integrador).
4) Válvulas por banda de posição estreita: causou ciclo limite (Apply/Hold alternando), levando a recuos do pistão e overshoot.
5) Descidas (200→50→0 psi): com banda ampliada, o sistema ficava em Hold e não despressurizava.

## Correções definidas
- Arquitetura correta (Apostila PTC5611, Seção 9.6.2):
  - Servossistema com integrador: v[n+1] = v[n] + (xRef - posReal)
  - Lei de controle: u = -K·x̂ + Ki·v (K,Ki por acker no sistema aumentado)
  - Observador de Luenberger real: x̂[n+1] = Φ·x̂ + Γ·u + L·(y - C·x̂)
  - LUT g⁻¹(Pref) apenas para xRef (referência), calibrada por PLID
- Válvulas: Apply contínuo enquanto Pref>0 (PWM do motor controla posição); Release apenas quando Pref=0 ou quando pos > xRef + banda (descida).
- Identificação: usar CSVs PWMSWEEP/OLSTEP/CLMULTI para estimar τ (constante de tempo) e K_vel (mm/s por %PWM) do atuador — script `identify_tau_gain_from_csv.m`.

## Estado atual (2026-09-13)
- PLID funcionando; 3 curvas e resultados impressos.
- CLMULTI com LQR pos + observador simplificado; precisa migrar para Luenberger real (com Φ, Γ) e K,Ki projetados.
- Script `identify_tau_gain_from_csv.m` pronto; corrigido para não depender de bwlabel.

## Próximos passos (em ordem)
1) Rodar `identify_tau_gain_from_csv.m` (já lendo Matlab/dados) e registrar τ e K_vel.
2) Montar Φ, Γ do modelo G(s)=K/(s(τs+1)), discretizar com ZOH (Ts=1ms).
3) Projetar K,Ki no sistema aumentado (acker/place) e L (polos 2–5× mais rápidos).
4) Atualizar CLMULTI com Φ,Γ,K,Ki,L; manter LUT g⁻¹(Pref) para xRef.
5) Ensaios CLMULTI: 0/100/200/50/0 psi; validar que 50/0 psi descem corretamente.
6) Atualizar gráficos e inserir na monografia.

## Regras (fixas)
- PRESSÃO NÃO FECHA MALHA — Pw não entra na realimentação; apenas monitoração/segurança/identificação.
- Controle é indireto por posição (xRef=g⁻¹(Pref)); observador+LQR em posição.
- Evitar Apply/Hold com banda estreita — usar Apply contínuo na subida/manutenção.

---
Autor: VIO — CLMULTI
