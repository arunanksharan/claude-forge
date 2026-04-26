# SSH + Remote Server Bootstrap

> Take a fresh Ubuntu 22.04/24.04 VPS from "just SSH'd in as root" to "production-ready" in ~30 minutes.

## Pick a host

| Host | When |
|------|------|
| **Hetzner Cloud** | Best price/performance for EU users. Solid Berlin/Helsinki data centers. |
| **DigitalOcean** | Beginner-friendly, good docs, premium pricing. |
| **Vultr / Linode** | Similar to DO. |
| **AWS EC2** | When you need other AWS services. Otherwise overkill. |
| **Fly.io / Railway** | Managed Docker, no SSH bootstrap needed. Pay more, learn less. |
| **Bare metal (OVH, Hetzner Robot)** | Cheaper at scale, more ops work. |

Recommended: **Hetzner CCX13** (~€7/mo) for small projects, **CCX23** (~€14/mo) for production. Pick Ubuntu 24.04 LTS image.

## Step 0 — initial SSH

You'll have:
- IP address
- Root password (or SSH key, if you provided one at provisioning)

```bash
ssh root@<ip>
```

Add the IP to `~/.ssh/config` for convenience:

```
# ~/.ssh/config (on your laptop)
Host {{your-domain}}
    HostName <ip>
    User deploy             # we'll create this user
    Port 22
    IdentityFile ~/.ssh/id_ed25519
    IdentitiesOnly yes
    ServerAliveInterval 60
```

## Step 1 — non-root user

Never run apps as root.

```bash
# as root, on the server
adduser deploy
usermod -aG sudo deploy

# copy your authorized_keys to the new user
mkdir -p /home/deploy/.ssh
cp ~/.ssh/authorized_keys /home/deploy/.ssh/
chown -R deploy:deploy /home/deploy/.ssh
chmod 700 /home/deploy/.ssh
chmod 600 /home/deploy/.ssh/authorized_keys

# test from your laptop in a NEW window — don't close root yet
ssh deploy@<ip>
sudo whoami    # should print "root"
```

If it works, proceed.

## Step 2 — disable root SSH + password auth

```bash
# as deploy, with sudo
sudo nano /etc/ssh/sshd_config

# set / verify:
PermitRootLogin no
PasswordAuthentication no
PubkeyAuthentication yes
ChallengeResponseAuthentication no
UsePAM yes
X11Forwarding no
ClientAliveInterval 300
ClientAliveCountMax 2
MaxAuthTries 3

# reload
sudo systemctl reload ssh
```

**Test from a new window** before closing the current one. If you can't connect, you can fix from the old window.

### (Optional) move SSH off port 22

Reduces noise from random scanners. Slight obscurity benefit. Set `Port 2222` in sshd_config + UFW + your `~/.ssh/config`. **Or skip it** — fail2ban + key-only is enough.

## Step 3 — UFW (firewall)

```bash
sudo ufw default deny incoming
sudo ufw default allow outgoing
sudo ufw allow OpenSSH                  # port 22 (or your custom port)
sudo ufw allow 'Nginx Full'             # 80 + 443
sudo ufw enable
sudo ufw status verbose
```

Anything not explicitly allowed is blocked. Re-enable carefully if you change SSH port.

## Step 4 — fail2ban

Bans IPs that fail SSH auth repeatedly.

```bash
sudo apt install -y fail2ban
sudo cp /etc/fail2ban/jail.conf /etc/fail2ban/jail.local
sudo nano /etc/fail2ban/jail.local

# verify these in [DEFAULT]:
bantime  = 1h
findtime = 10m
maxretry = 5

# under [sshd], make sure:
enabled = true

# restart
sudo systemctl restart fail2ban
sudo fail2ban-client status sshd
```

## Step 5 — automatic security updates

```bash
sudo apt install -y unattended-upgrades
sudo dpkg-reconfigure -plow unattended-upgrades

# also configure to reboot if needed:
sudo nano /etc/apt/apt.conf.d/50unattended-upgrades
# uncomment + set:
# Unattended-Upgrade::Automatic-Reboot "true";
# Unattended-Upgrade::Automatic-Reboot-Time "04:00";
```

Now security patches install nightly. Monthly reboots happen at 4am if needed.

## Step 6 — swap (if VPS has < 4GB RAM)

```bash
sudo fallocate -l 2G /swapfile
sudo chmod 600 /swapfile
sudo mkswap /swapfile
sudo swapon /swapfile

# persist across reboots
echo '/swapfile none swap sw 0 0' | sudo tee -a /etc/fstab

# tune for server use (less aggressive swapping)
echo 'vm.swappiness=10' | sudo tee -a /etc/sysctl.conf
sudo sysctl -p
```

Even 2GB swap saves you from OOM kills when memory spikes briefly.

## Step 7 — timezone + NTP

```bash
sudo timedatectl set-timezone UTC       # always UTC on servers
timedatectl status                      # verify
```

`systemd-timesyncd` is enabled by default — sync should be `active`.

## Step 8 — install runtime deps

### For a Node app

```bash
# Node via fnm or nvm
curl -fsSL https://fnm.vercel.app/install | bash
source ~/.bashrc
fnm install 22
fnm default 22

# pnpm
corepack enable
corepack prepare pnpm@latest --activate

# verify
node -v && pnpm -v
```

### For a Python (FastAPI) app

```bash
# install uv
curl -LsSf https://astral.sh/uv/install.sh | sh
source ~/.bashrc

# verify
uv --version

# Python 3.12
uv python install 3.12
```

### Common to both

```bash
# nginx
sudo apt install -y nginx
sudo systemctl enable --now nginx

# certbot (for SSL)
sudo apt install -y certbot python3-certbot-nginx

# basic tools
sudo apt install -y git curl wget htop net-tools jq make build-essential
```

## Step 9 — Docker (if using compose)

```bash
# install Docker per the official docs (changes often — check docs.docker.com)
# Ubuntu 24.04 example:
curl -fsSL https://get.docker.com | sudo sh

# add deploy to docker group (no sudo needed)
sudo usermod -aG docker deploy
# log out and back in for group change to take effect

# verify
docker --version
docker compose version
```

## Step 10 — clone + deploy your app

```bash
# create app directory
sudo mkdir -p /var/www/{{project-slug}}
sudo chown deploy:deploy /var/www/{{project-slug}}

# clone (use a deploy key — see below)
cd /var/www
git clone git@github.com:YOUR/{{project-slug}}.git

# create .env on the server
cd {{project-slug}}
cp .env.example .env
nano .env       # fill in real secrets

# protect it
chmod 600 .env
```

### Deploy keys (read-only repo access from server)

On the server:

```bash
ssh-keygen -t ed25519 -C "deploy@{{your-domain}}" -f ~/.ssh/id_ed25519_deploy -N ""
cat ~/.ssh/id_ed25519_deploy.pub
```

Add the public key to GitHub: **Repo → Settings → Deploy keys → Add deploy key** (read-only is enough).

Configure SSH:

```bash
nano ~/.ssh/config
```

```
Host github-deploy
    HostName github.com
    User git
    IdentityFile ~/.ssh/id_ed25519_deploy
    IdentitiesOnly yes
```

Now clone with: `git clone git@github-deploy:YOUR/{{project-slug}}.git`.

## Step 11 — reverse proxy + SSL

See `nginx-reverse-proxy.md` and `lets-encrypt-ssl.md`.

## Step 12 — process management

For Node: `pm2-process-management.md`.
For Python: gunicorn behind nginx, managed by systemd:

```ini
# /etc/systemd/system/{{project-slug}}.service
[Unit]
Description={{project-name}}
After=network.target postgresql.service redis.service

[Service]
Type=simple
User=deploy
Group=deploy
WorkingDirectory=/var/www/{{project-slug}}
EnvironmentFile=/var/www/{{project-slug}}/.env
ExecStart=/var/www/{{project-slug}}/.venv/bin/gunicorn src.{{project-slug}}.main:app -k uvicorn.workers.UvicornWorker -w 4 -b 127.0.0.1:8000 --timeout 60
ExecReload=/bin/kill -HUP $MAINPID
KillMode=mixed
TimeoutStopSec=30
Restart=on-failure
RestartSec=5s

# resource limits
LimitNOFILE=65536

[Install]
WantedBy=multi-user.target
```

```bash
sudo systemctl daemon-reload
sudo systemctl enable --now {{project-slug}}
sudo systemctl status {{project-slug}}
journalctl -u {{project-slug}} -f
```

For Docker compose: just `docker compose -f docker-compose.prod.yml up -d` — compose handles restart.

## Step 13 — backups

If you have a managed DB, backups are usually automatic. For self-hosted:

```bash
# /usr/local/bin/pg-backup.sh
#!/usr/bin/env bash
set -euo pipefail
BACKUP_DIR=/var/backups/postgres
mkdir -p "$BACKUP_DIR"
TS=$(date -u +%Y%m%dT%H%M%SZ)
pg_dump -U postgres -d {{db-name}} | gzip > "$BACKUP_DIR/{{db-name}}-$TS.sql.gz"
# keep last 14 days
find "$BACKUP_DIR" -type f -mtime +14 -delete
# upload to S3 / B2 / wherever
aws s3 cp "$BACKUP_DIR/{{db-name}}-$TS.sql.gz" s3://your-backups/{{project-slug}}/ || true
```

Schedule via cron:

```bash
sudo crontab -e
0 3 * * * /usr/local/bin/pg-backup.sh
```

**Test restoring from backup at least once.** A backup that's never been restored is a hope, not a backup.

## Step 14 — monitoring (light)

Even without a full observability stack, install:

- **netdata** (single binary, web dashboard) — `bash <(curl -Ss https://my-netdata.io/kickstart.sh)` — for live system metrics
- Or **Prometheus node-exporter** if you have a Prom server somewhere
- A simple uptime check from outside (Uptime Robot, Better Uptime, free tier)

For real production, see the `observability/` folder.

## Deploy script (simple)

```bash
# /var/www/{{project-slug}}/deploy.sh
#!/usr/bin/env bash
set -euo pipefail

cd /var/www/{{project-slug}}

git fetch --tags
git reset --hard origin/main

# Node
pnpm install --frozen-lockfile
pnpm build
pm2 reload ecosystem.config.cjs --update-env

# Python
# uv sync --frozen
# uv run alembic upgrade head
# sudo systemctl reload {{project-slug}}

echo "deployed: $(git rev-parse --short HEAD)"
```

```bash
chmod +x deploy.sh
```

Trigger manually (`./deploy.sh`) or via GitHub Actions over SSH.

For real CI/CD, see `cicd-automation/` (not in this repo yet — coming).

## Common pitfalls

| Pitfall | Fix |
|---------|-----|
| Locked yourself out (key + password disabled) | Use the host's web console / KVM to fix sshd_config |
| sudo asks for password every time | Add `deploy ALL=(ALL) NOPASSWD:ALL` to `/etc/sudoers.d/deploy` (security tradeoff — be deliberate) |
| Disk fills up unexpectedly | `du -sh /var/log/* /var/lib/docker/* | sort -h` to find culprit |
| App OOMs at night | Check `dmesg | grep -i kill`, configure `max_memory_restart`, add swap |
| `systemctl status` says "exit-code" | Always `journalctl -u <service>` for the actual error |
| New SSH session hangs at "looking up host" | Likely `UseDNS yes` + slow reverse DNS — set `UseDNS no` in sshd_config |
| nginx 502 right after deploy | App not yet listening; restart order matters |
| Permissions wrong on cloned repo | `sudo chown -R deploy:deploy /var/www/{{project-slug}}` |
| `.env` readable by everyone | `chmod 600 .env` and `chown deploy:deploy .env` |
| Deploy script doesn't reload nginx | Reload only when nginx config changed; otherwise just `pm2 reload` / `systemctl reload <app>` |
