#!/bin/bash
# bashrc.sh — Shared shell enhancements for ctrl-plane nodes.
#
# Configures history settings, kubectl alias, and bash-completion.
# Called from master_common.sh and worker_common.sh.

set -euo pipefail

setup_common_bashrc() {
  grep -qxF 'export HISTTIMEFORMAT="%d/%m/%y %T "' ~/.bashrc || echo 'export HISTTIMEFORMAT="%d/%m/%y %T "' >> ~/.bashrc
  grep -qxF 'export HISTSIZE=10000' ~/.bashrc || echo 'export HISTSIZE=10000' >> ~/.bashrc
  grep -qxF 'export HISTFILESIZE=10000' ~/.bashrc || echo 'export HISTFILESIZE=10000' >> ~/.bashrc
  grep -qxF 'export HISTCONTROL=ignoreboth' ~/.bashrc || echo 'export HISTCONTROL=ignoreboth' >> ~/.bashrc
  grep -qxF 'shopt -s histappend' ~/.bashrc || echo 'shopt -s histappend' >> ~/.bashrc
  grep -qxF 'alias k=kubectl' ~/.bashrc || echo 'alias k=kubectl' >> ~/.bashrc

  if ! type _init_completion >/dev/null 2>&1; then
    echo "Installing bash-completion..."
    if ! install_bash_completion_pkg; then
      echo "WARNING: Failed to install bash-completion; continuing."
    fi
  fi

  if [ -f /etc/bash_completion ]; then
    . /etc/bash_completion
  elif [ -f /usr/share/bash-completion/bash_completion ]; then
    . /usr/share/bash-completion/bash_completion
  fi

  if command -v kubectl >/dev/null 2>&1; then
    source <(kubectl completion bash)
  else
    echo "kubectl not found in PATH. Autocomplete not enabled."
  fi

  alias k=kubectl
  complete -o default -F __start_kubectl k
}
