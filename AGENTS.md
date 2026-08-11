# AGENTS.md

This file provides guidance to AI agents when working with code in this repository.

## What this repo is

Docker Compose deployment config for [Paseo](https://paseo.sh) (a meta-agent orchestrator with a bundled web UI) extended with four agent CLIs: Claude Code, OpenCode, Pi, and Hermes Agent. Single-service stack, no application source code — this repo is purely the image/compose definition and is tracked so the setup is reproducible.

## Commands

```bash
# Rebuild the image after editing Dockerfile
docker build -t paseo-with-agents .

# Bring the stack up / down
docker compose up -d
docker compose down

# Recreate the container after a rebuild (compose won't auto-pick-up a locally rebuilt image tag)
docker compose up -d --force-recreate

# Shell into the running container
docker exec -it paseo sh
docker exec --user paseo -it paseo sh   # as the app user instead of root

# Tail logs
docker logs -f paseo
```

There is no test suite or linter in this repo — it's infra config. Validate changes by rebuilding the image and execing in to confirm the expected file/behavior, as done for the hermes patch below.

## Architecture

- `Dockerfile` builds `paseo-with-agents` from `ghcr.io/getpaseo/paseo:latest`, switches to `USER root` to `npm install -g` the three npm-based CLIs (`@anthropic-ai/claude-code`, `opencode-ai`, `@mariozechner/pi-coding-agent`) and to run Hermes's own install script (no npm package exists for Hermes). Paseo itself continues running as the non-root `paseo` user (uid/gid 1000) after image build.
- `docker-compose.yml` runs the single `paseo` service, publishing `6767/tcp` (Paseo's web UI/daemon port).
- Volumes:
  - `./paseo-home:/home/paseo` — all persistent state: Paseo's own config/DB, and each agent CLI's per-user config/credentials (e.g. `/home/paseo/.hermes/config.yaml` + `/home/paseo/.hermes/.env`, `/home/paseo/.claude`, etc.). Gitignored; this is the actual runtime state, not tracked.
  - `/home/lance/git:/home/paseo/git` — host git checkouts, mounted **under** `/home/paseo` (Paseo's `$HOME` inside the container) rather than at a sibling path like `/workspace`. This matters: Paseo's "search for directory" (Projects > new project) is rooted at `process.env.HOME` server-side with strict path-containment, so anything mounted outside `$HOME` is invisible to that picker regardless of query.
- Networking: `extra_hosts: host.docker.internal:host-gateway` lets the container reach host-bound services (e.g. a local Lemonade LLM server on `13305`) without hardcoding the docker bridge gateway IP. No firewalld changes are needed for Tailscale reachability on this host — `tailscale0` is already in the `trusted` zone.
- Secrets split across two different env files with different scopes:
  - Repo-level `.env` (gitignored, templated by `.env.example`) only holds `PASEO_PASSWORD`, which `docker-compose.yml` interpolates via `${PASEO_PASSWORD}`.
  - Agent-level secrets (`FIREWORKS_API_KEY`, `LEMONADE_API_KEY`, etc.) live inside the container at `/home/paseo/.hermes/.env`, edited via `hermes config set` / direct `printf` into that file — not read by compose at all. `.env.example` documents this split with commented-out placeholders rather than real compose entries.
  - Lemonade requires no real auth, but Hermes's ACP model-discovery path (`acp_adapter/server.py:_named_custom_provider_catalogs`) only live-probes a custom provider's `/models` endpoint when `key_env` resolves to a **non-empty** value — so `LEMONADE_API_KEY` is set to an arbitrary non-empty placeholder purely to satisfy that truthiness check, not for real authentication.
- The Dockerfile's final `sed` step patches a real upstream Hermes bug: `acp_adapter/tools.py`'s `_tool_result_failed()` marks any nonzero `exit_code` as ACP `status: "failed"`, even when `tools/terminal_tool.py` already annotated that same result with `exit_code_meaning` (e.g. `grep`/`diff` exiting 1 as "not an error"). The two checks are disconnected upstream; the sed patch makes `_tool_result_failed` respect `exit_code_meaning`. Re-verify this patch still applies (the sed pattern is a literal string match) whenever the Hermes install script/version changes — a silent no-op sed won't fail the build.
- After any config change made via `docker exec` (e.g. `hermes config set`, editing `/home/paseo/.hermes/.env`), the running `hermes acp` process must be restarted (`docker restart paseo`, or kill the specific pid) to pick it up — it's a long-running process, not re-read per request.

