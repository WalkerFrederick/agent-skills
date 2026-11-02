# agent-skills

My personal skills for AI agents — the canonical home for skills I author, kept
dotfiles-style. Public for reference and reuse.

Skills follow the cross-agent `.agents/skills` convention: each skill is a
directory with a `SKILL.md`, so any tool that reads that directory (Hermes,
Codex, etc.) picks them up automatically.

## Bootstrap on a new machine

```bash
git clone git@github.com:WalkerFrederick/agent-skills.git ~/.agents/skills
cd ~/.agents/skills && ./scripts/install-hooks.sh
```

Requires [gitleaks](https://github.com/gitleaks/gitleaks) for the pre-commit
secret scan (`brew install gitleaks`).

## Security

Since this repo is public:

- **Pre-commit** — gitleaks scans staged changes (fail-open if gitleaks isn't installed).
- **Push protection + secret scanning** — GitHub-side, blocks known secret patterns.
- **CI** (`.github/workflows/security-check.yml`) — gitleaks plus an LLM
  sensitivity check on PRs, re-run post-merge on `main`, plus a weekly
  full-history scan.
