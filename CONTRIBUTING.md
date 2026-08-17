# Contributing to ECSR

ECSR is the protected state-evolution protocol consumed by application repositories. The public fishing collaboration lives in `iiitaoge/ECSR-IceFishing-Demo`; do not use this repository for fishing features.

Framework changes are accepted only through a focused pull request. Before proposing one:

1. Read `AGENTS.md`, `ARCHITECTURE.md`, and `GIT_EVOLUTION.md` completely.
2. Describe the requested evolution as `X_t`, `S_i`, `⊗`, and `Φ`.
3. Preserve the `Components / Systems / Rules` ontology and the single State Update authority.
4. Run `./tests/Verify.ps1` locally and include the result in the pull request.
5. Do not mix framework evolution with application or platform code.

All framework paths are owned by `@iiitaoge`. A pull request cannot enter `main` without the owner's explicit approval.
