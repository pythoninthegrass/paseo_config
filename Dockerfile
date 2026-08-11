FROM ghcr.io/getpaseo/paseo:latest

USER root

RUN npm install -g \
    @anthropic-ai/claude-code \
    opencode-ai \
    @mariozechner/pi-coding-agent

RUN curl -fsSL https://hermes-agent.nousresearch.com/install.sh \
    | bash -s -- --non-interactive --skip-setup
