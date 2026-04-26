---
name: deploy-vps-bootstrap
description: Use when the user wants to take a fresh Linux VPS (Ubuntu 22.04/24.04) from "just SSH'd in as root" to production-ready — non-root user, SSH hardening, UFW firewall, fail2ban, automatic security updates, swap, runtime deps (Node or Python), Docker, deploy keys. Triggers on "set up new vps", "bootstrap server", "harden ubuntu server", "fresh server setup".
---

# Bootstrap a Fresh VPS (claudeforge)

Follow `deployment/ssh-and-remote-server-setup.md`. Walk the user through these steps, asking before destructive actions:

1. **Verify the user's setup**:
   - Domain pointing to the server's IP (A and AAAA records)?
   - SSH key on their laptop (`~/.ssh/id_ed25519.pub`)?
   - Username they want for the deploy user (default: `deploy`)?
   - Runtime: Node, Python, or both?
2. **Walk through the steps in order** from the deployment guide:
   - Step 1: create non-root user, copy SSH key, test login
   - Step 2: disable root SSH + password auth (test in a new window first!)
   - Step 3: UFW firewall (allow OpenSSH + Nginx Full)
   - Step 4: fail2ban
   - Step 5: automatic security updates
   - Step 6: swap (if RAM < 4GB)
   - Step 7: timezone (UTC)
   - Step 8: install runtime deps (Node via fnm/nvm, or uv for Python)
   - Step 9: Docker (if using compose)
   - Step 10: clone the project + create `.env`
3. **Each command should be run by the user** (you don't have SSH access to their server). Provide commands to copy-paste, ask for output if needed to verify.
4. **NEVER assume**: ask before disabling password auth, UFW enable, anything that could lock them out.
5. **After bootstrap**: point them to `deploy-docker-nginx-ssl` skill for the next stage (nginx + SSL + app deploy).

This skill is **interactive** — the user is doing the steps on their server. Be patient, confirm output at each gate.
