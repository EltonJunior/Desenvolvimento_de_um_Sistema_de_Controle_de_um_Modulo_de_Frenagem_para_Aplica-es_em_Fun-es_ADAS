# Copilot instructions (MSc thesis / LaTeX)

## Default mode
- Language: Portuguese for narrative text; English for commands/identifiers.
- Be conservative: do not invent results, citations, figures, or experimental claims.
- Keep edits surgical: preserve existing structure, style, and labels unless explicitly requested.

## LaTeX editing rules
- Preserve labels/refs: never delete or rename a `\label{...}` without updating all `\ref/\eqref` usages.
- Avoid Unicode inside `lstlisting` / verbatim blocks (e.g., “→”, “–”): prefer ASCII (`->`, `-`) to prevent `listings` encoding errors.
- Keep ABNT template conventions (UniforTeX2 / abntex2) intact.
- When adding figures:
  - Prefer `\IfFileExists{...}{...}{...}` placeholders (already used in the project).
  - Do not hardcode new colors/fonts/styles.

## Citations and bibliography
- Never fabricate bibliography entries or citation keys.
- If a citation key is missing, ask for the BibTeX entry or confirm which PDF/source it refers to.
- Primary bibliography file: `elementos-pos-textuais/referencias.bib`.

## Using PDFs in `references/`
- Treat PDFs as *background reading only* unless the user provides page numbers/quotes.
- Do not reproduce long copyrighted excerpts; paraphrase and cite the source (and page) when the user provides it.
- If the user wants a claim supported, ask for: (1) which PDF, (2) page(s), (3) the excerpt.

## Simulink/MATLAB workflow assumptions
- Simulations are executed in Simulink; MATLAB scripts should only:
  1) set parameters,
  2) run the model,
  3) collect logged signals,
  4) generate plots,
  5) export figures.
- Post-processing (metrics) is allowed **only** on signals logged from Simulink.

## Review checklist before finishing
- `get_errors` shows no new LaTeX errors in touched files.
- New content compiles with the existing template.
- No new undefined refs/labels introduced.
