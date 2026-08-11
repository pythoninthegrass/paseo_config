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

# Upstream bug: acp_adapter/tools.py's _tool_result_failed() flags any
# nonzero exit_code as an ACP "failed" status, even when terminal_tool.py
# already annotated it exit_code_meaning (e.g. grep/diff "not an error").
# Suppress the false-failed status until hermes-agent fixes this upstream.
RUN sed -i \
    's/if isinstance(exit_code, int) and exit_code != 0:/if isinstance(exit_code, int) and exit_code != 0 and not data.get("exit_code_meaning"):/' \
    /usr/local/lib/hermes-agent/acp_adapter/tools.py
