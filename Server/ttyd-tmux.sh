#!/bin/bash
#
# ttyd-tmux.sh
# Wrapper script for ttyd to provide session persistence via tmux
#
# Install location: /usr/local/bin/ttyd-tmux.sh
# Make executable: chmod +x /usr/local/bin/ttyd-tmux.sh
#

# Session name - can be customized per user/device
SESSION="claude_mobile"

# Check if tmux session exists
if tmux has-session -t "$SESSION" 2>/dev/null; then
    # Attach to existing session
    exec tmux attach-session -t "$SESSION"
else
    # Create new session
    exec tmux new-session -s "$SESSION"
fi
