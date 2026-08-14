FROM ghcr.io/getpaseo/paseo:latest

USER root

RUN npm install -g \
    @anthropic-ai/claude-code \
    opencode-ai \
    @mariozechner/pi-coding-agent

# Paseo's terminal feature spawns env.SHELL || "/bin/sh"; SHELL is unset by
# default, so without this every in-browser terminal session lands in dash.
RUN <<EOF
  set -ex
  apt-get update
  apt-get install -y bash
  rm -fr /var/lib/apt/lists/*
EOF
ENV SHELL=/bin/bash

# node-pty (a hermes-agent npm dep) needs these to compile its native addon via node-gyp.
RUN <<EOF
  set -ex
  apt-get update
  apt-get install -y --no-install-recommends python3 make g++
  rm -fr /var/lib/apt/lists/*
EOF

RUN curl -fsSL https://hermes-agent.nousresearch.com/install.sh \
    | bash -s -- --non-interactive --skip-setup

# Default every new user to the shared self-hosted Lemonade endpoint so
# fresh $HOME volumes work without a manual `hermes config set` pass.
RUN <<EOF
  set -ex
  chown -R paseo:paseo /home/paseo/.hermes
  su - paseo -c '
    hermes config set model.provider custom:lemonade
    hermes config set model.default Qwen3.8-27B-UD-Q8_K_XL
    hermes config set providers.lemonade.base_url http://host.docker.internal:13305/api/v1
    hermes config set providers.lemonade.key_env LEMONADE_API_KEY
    hermes config unset model.base_url || true
    grep -q "^LEMONADE_API_KEY=" ~/.hermes/.env || printf "LEMONADE_API_KEY=lemonade-local\n" >> ~/.hermes/.env
  '
EOF

RUN <<EOF
  set -ex
  apt-get update
  apt-get install -y extrepo
  extrepo enable mise
  apt-get remove -y --auto-remove extrepo
  apt-get update
  apt-get install -y mise
  rm -fr /var/lib/apt/lists/*
EOF

# GitHub CLI: https://github.com/cli/cli/blob/trunk/docs/install_linux.md
RUN <<EOF
  set -ex
  apt-get update
  apt-get install -y curl
  install -d -m 755 /etc/apt/keyrings
  curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg -o /etc/apt/keyrings/githubcli-archive-keyring.gpg
  chmod go+r /etc/apt/keyrings/githubcli-archive-keyring.gpg
  echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" > /etc/apt/sources.list.d/github-cli.list
  apt-get update
  apt-get install -y gh
  rm -fr /var/lib/apt/lists/*
EOF

# Container is the isolation boundary, so passwordless sudo here is fine.
# Keyed by uid, not name, since DISPLAY_USER below aliases uid 1000 to a second name.
RUN <<EOF
  set -ex
  apt-get update
  apt-get install -y sudo
  rm -fr /var/lib/apt/lists/*
  echo '#1000 ALL=(ALL) NOPASSWD:ALL' > /etc/sudoers.d/paseo
  chmod 0440 /etc/sudoers.d/paseo
EOF

# Cosmetic per-user alias: the daemon always runs as gosu'd uid 1000 ("paseo"
# in the base image's entrypoint), but glibc's getpwuid() resolves to whichever
# /etc/passwd entry for that uid comes first, so prepending DISPLAY_USER here
# makes whoami/id/ps show the human name without touching the entrypoint.
ARG DISPLAY_USER
RUN <<EOF
  set -ex
  if [ -n "$DISPLAY_USER" ] && [ "$DISPLAY_USER" != "paseo" ]; then
    sed -i "1i ${DISPLAY_USER}:x:1000:1000::/home/paseo:/bin/bash" /etc/passwd
    sed -i "1i ${DISPLAY_USER}:!:20670:0:99999:7:::" /etc/shadow
  fi
EOF

# build deps
RUN <<EOF
  set -ex
  apt-get update
  apt-get install -y libsdl2-dev
  rm -fr /var/lib/apt/lists/*
EOF

# Upstream bug: acp_adapter/tools.py's _tool_result_failed() flags any
# nonzero exit_code as an ACP "failed" status, even when terminal_tool.py
# already annotated it exit_code_meaning (e.g. grep/diff "not an error").
# Suppress the false-failed status until hermes-agent fixes this upstream.
RUN sed -i \
    's/if isinstance(exit_code, int) and exit_code != 0:/if isinstance(exit_code, int) and exit_code != 0 and not data.get("exit_code_meaning"):/' \
    /usr/local/lib/hermes-agent/acp_adapter/tools.py
