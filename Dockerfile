FROM ghcr.io/getpaseo/paseo:latest

USER root

RUN npm install -g \
    @anthropic-ai/claude-code \
    opencode-ai \
    @mariozechner/pi-coding-agent

RUN curl -fsSL https://hermes-agent.nousresearch.com/install.sh \
    | bash -s -- --non-interactive --skip-setup

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
RUN <<EOF
  set -ex
  apt-get update
  apt-get install -y sudo
  rm -fr /var/lib/apt/lists/*
  echo 'paseo ALL=(ALL) NOPASSWD:ALL' > /etc/sudoers.d/paseo
  chmod 0440 /etc/sudoers.d/paseo
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
