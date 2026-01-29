# Server Setup for Session Persistence

This folder contains server-side configuration for enabling session persistence in the mobile terminal.

## The Problem

Without session persistence, every time you refresh or reconnect to the terminal, you start a fresh session and lose all context (command history, running processes, Claude conversations).

## The Solution

Use tmux as a session wrapper. When you connect:
- If a tmux session exists → attach to it (preserves everything)
- If no session exists → create a new one

## Installation Steps

### 1. Install tmux (if not already installed)

```bash
# Ubuntu/Debian
sudo apt install tmux

# CentOS/RHEL
sudo yum install tmux

# macOS
brew install tmux
```

### 2. Install the wrapper script

```bash
# Copy the wrapper script
sudo cp ttyd-tmux.sh /usr/local/bin/
sudo chmod +x /usr/local/bin/ttyd-tmux.sh
```

### 3. Update the systemd service

```bash
# Backup existing service
sudo cp /etc/systemd/system/mobileterminal.service /etc/systemd/system/mobileterminal.service.bak

# Install new service
sudo cp mobileterminal.service /etc/systemd/system/

# Reload and restart
sudo systemctl daemon-reload
sudo systemctl restart mobileterminal
```

### 4. Verify

```bash
# Check service status
sudo systemctl status mobileterminal

# View logs
sudo journalctl -u mobileterminal -f
```

## Usage

After setup, reconnecting to the terminal will automatically reattach to your existing tmux session.

### Tmux Basics

| Key Combo | Action |
|-----------|--------|
| `Ctrl+B, D` | Detach from session (keeps it running) |
| `Ctrl+B, C` | Create new window |
| `Ctrl+B, N` | Next window |
| `Ctrl+B, P` | Previous window |
| `Ctrl+B, [` | Enter scroll/copy mode |
| `Ctrl+B, ?` | Show all key bindings |

### Manual Session Management

```bash
# List sessions
tmux ls

# Kill a session
tmux kill-session -t claude_mobile

# Create a new session (replaces current)
tmux new-session -s claude_mobile
```

## Customization

Edit `/usr/local/bin/ttyd-tmux.sh` to change the session name:

```bash
SESSION="my_custom_session_name"
```

## Troubleshooting

### Session not persisting
1. Check if tmux is installed: `which tmux`
2. Check service logs: `sudo journalctl -u mobileterminal -f`
3. Verify the wrapper script is executable: `ls -la /usr/local/bin/ttyd-tmux.sh`

### Multiple users
For multiple users, modify the script to use user-specific session names:
```bash
SESSION="claude_${USER}"
```
