# Let's Encrypt SSL with certbot

> Free, auto-renewing TLS certs via certbot's nginx plugin. Plus DNS challenge for wildcards.

## Prerequisites

- Domain pointing to your server (`A` record for `your-domain.com` and `www.your-domain.com` → server IP)
- Port 80 reachable from the internet (Let's Encrypt validates by hitting `/.well-known/acme-challenge/`)
- nginx installed and running

## Install

```bash
sudo apt install -y certbot python3-certbot-nginx
```

For Caddy users: skip this entire file. Caddy handles SSL automatically with no config.

## First cert (HTTP-01 challenge via nginx plugin)

```bash
sudo certbot --nginx -d {{your-domain}} -d www.{{your-domain}} \
  --email you@example.com \
  --agree-tos \
  --no-eff-email \
  --redirect
```

What happens:

1. certbot reads your nginx config
2. Modifies the relevant server block to serve the ACME challenge from `/.well-known/acme-challenge/`
3. Asks Let's Encrypt to validate the domain (LE hits `http://your-domain/.well-known/acme-challenge/...`)
4. On success, fetches the cert + key into `/etc/letsencrypt/live/{{your-domain}}/`
5. Modifies the nginx config to use the cert (HTTPS server block + redirect from HTTP)
6. Reloads nginx

Verify:

```bash
curl -I https://{{your-domain}}
# should be 200 OK with valid cert
```

Test the cert grade: https://www.ssllabs.com/ssltest/analyze.html?d={{your-domain}}

Aim for **A or A+**. The certbot defaults are usually A; A+ requires HSTS preload.

## Auto-renewal

Certbot installs a systemd timer that renews automatically:

```bash
sudo systemctl status certbot.timer
# Active: active (waiting)
```

Test the renewal in dry-run mode:

```bash
sudo certbot renew --dry-run
```

If the dry run fails, fix it now — at renewal time you'll have ~30 days before expiry, but the timer is silent on failure.

## Renewal hooks

Run a script after renewal (e.g., reload nginx, copy cert to a different service):

```bash
sudo nano /etc/letsencrypt/renewal-hooks/deploy/reload-nginx.sh
```

```bash
#!/usr/bin/env bash
systemctl reload nginx
```

```bash
sudo chmod +x /etc/letsencrypt/renewal-hooks/deploy/reload-nginx.sh
```

certbot already reloads nginx after renewal via the `--nginx` plugin's auto-config. The hook is for non-nginx services that also need the cert (e.g., a separate websocket gateway, mail server).

## Wildcard cert (DNS-01 challenge)

For `*.{{your-domain}}`, you need DNS-01 (Let's Encrypt requires DNS validation for wildcards):

```bash
sudo certbot certonly --manual --preferred-challenges=dns \
  -d {{your-domain}} -d *.{{your-domain}} \
  --email you@example.com \
  --agree-tos
```

certbot prompts you to add a TXT record `_acme-challenge.{{your-domain}}` with a specific value. Add it to your DNS, wait ~30 sec for propagation, hit Enter.

For **automated** wildcard renewals, use a DNS provider plugin (Cloudflare, Route53, etc.):

```bash
sudo apt install -y python3-certbot-dns-cloudflare

# create credentials file
sudo nano /etc/letsencrypt/cloudflare.ini
```

```
dns_cloudflare_api_token = YOUR_CLOUDFLARE_API_TOKEN
```

```bash
sudo chmod 600 /etc/letsencrypt/cloudflare.ini

sudo certbot certonly \
  --dns-cloudflare \
  --dns-cloudflare-credentials /etc/letsencrypt/cloudflare.ini \
  --dns-cloudflare-propagation-seconds 30 \
  -d {{your-domain}} -d *.{{your-domain}}
```

Now `certbot renew` handles wildcards automatically.

## Multiple domains, one cert

```bash
sudo certbot --nginx \
  -d {{your-domain}} \
  -d www.{{your-domain}} \
  -d api.{{your-domain}} \
  -d admin.{{your-domain}}
```

All four go in one cert. Easier to manage.

## Multiple separate certs

For unrelated domains, use separate runs:

```bash
sudo certbot --nginx -d domain-one.com -d www.domain-one.com
sudo certbot --nginx -d domain-two.com
```

Each gets its own cert in `/etc/letsencrypt/live/<domain>/`.

## Manual cert install (when not using --nginx plugin)

If you have nginx config you don't want certbot rewriting, use `certonly`:

```bash
sudo certbot certonly --webroot -w /var/www/certbot \
  -d {{your-domain}} -d www.{{your-domain}}
```

Pre-create the webroot and add to nginx:

```bash
sudo mkdir -p /var/www/certbot
```

```nginx
# in your HTTP server block
location /.well-known/acme-challenge/ {
    root /var/www/certbot;
}
```

Then in your HTTPS server block, reference the cert files manually:

```nginx
ssl_certificate     /etc/letsencrypt/live/{{your-domain}}/fullchain.pem;
ssl_certificate_key /etc/letsencrypt/live/{{your-domain}}/privkey.pem;
```

## A+ rating

certbot's defaults give you A. For A+:

### 1. HSTS with preload

```nginx
add_header Strict-Transport-Security "max-age=63072000; includeSubDomains; preload" always;
```

`max-age=63072000` = 2 years. `preload` is required for the browser preload list. Submit at https://hstspreload.org/.

**Be careful**: once preloaded, removing HTTPS for that domain breaks for all users until they update their browser. Don't preload subdomains you might want to use as plain HTTP.

### 2. Strong DH params

certbot generates these automatically (`/etc/letsencrypt/ssl-dhparams.pem`). Reference in nginx:

```nginx
ssl_dhparam /etc/letsencrypt/ssl-dhparams.pem;
```

### 3. OCSP stapling

```nginx
ssl_stapling on;
ssl_stapling_verify on;
ssl_trusted_certificate /etc/letsencrypt/live/{{your-domain}}/chain.pem;
resolver 1.1.1.1 8.8.8.8 valid=300s;
resolver_timeout 5s;
```

### 4. Modern cipher suite

certbot's `options-ssl-nginx.conf` is good. If you customize:

```nginx
ssl_protocols TLSv1.2 TLSv1.3;
ssl_ciphers 'ECDHE-ECDSA-AES128-GCM-SHA256:ECDHE-RSA-AES128-GCM-SHA256:ECDHE-ECDSA-CHACHA20-POLY1305:ECDHE-RSA-CHACHA20-POLY1305:ECDHE-ECDSA-AES256-GCM-SHA384:ECDHE-RSA-AES256-GCM-SHA384';
ssl_prefer_server_ciphers on;
ssl_session_cache shared:SSL:10m;
ssl_session_timeout 1d;
ssl_session_tickets off;
```

## Caddy alternative

If you want zero SSL config:

```caddyfile
# /etc/caddy/Caddyfile
{{your-domain}}, www.{{your-domain}} {
    reverse_proxy localhost:8000
}
```

Run `sudo systemctl reload caddy`. Caddy:

- Gets a cert from Let's Encrypt automatically
- Renews automatically
- Handles HSTS, gzip, HTTP/2 by default
- Redirects HTTP to HTTPS

For complex configs (rate limit, rewrites, multiple upstreams), nginx still wins on flexibility. For simple proxy + SSL, **Caddy is genuinely simpler**.

## Renewal monitoring

Auto-renewal can silently fail. Add monitoring:

```bash
# /usr/local/bin/check-cert-expiry.sh
#!/usr/bin/env bash
DOMAIN={{your-domain}}
EXPIRY=$(echo | openssl s_client -servername $DOMAIN -connect $DOMAIN:443 2>/dev/null | openssl x509 -noout -enddate | cut -d= -f2)
EXPIRY_TS=$(date -d "$EXPIRY" +%s)
NOW_TS=$(date +%s)
DAYS_LEFT=$(( (EXPIRY_TS - NOW_TS) / 86400 ))

if [ "$DAYS_LEFT" -lt 14 ]; then
    echo "WARNING: $DOMAIN cert expires in $DAYS_LEFT days" | mail -s "cert expiry warning" you@example.com
fi
```

```bash
sudo crontab -e
0 9 * * * /usr/local/bin/check-cert-expiry.sh
```

Or use an external monitor (Uptime Robot, ssl-checker.io) that emails you when expiry < 14 days.

## Common pitfalls

| Pitfall | Fix |
|---------|-----|
| `Failed authorization procedure` | Domain doesn't resolve to this server, or port 80 blocked. Verify with `dig {{your-domain}}` and `curl -I http://{{your-domain}}/.well-known/acme-challenge/test` |
| Rate limit hit (5 cert requests / week) | Use staging endpoint: `--staging` for testing; switch to prod once flow works |
| Renewal hook didn't run | Check `/var/log/letsencrypt/letsencrypt.log`; ensure script is executable |
| nginx not reloaded after renewal | certbot's `--nginx` plugin should reload — confirm with `sudo certbot renew --dry-run` |
| Cert path changed (different `live/` subdir) | Don't hardcode — use `/etc/letsencrypt/live/<primary>/fullchain.pem` |
| Mixed content warnings | App is generating `http://` URLs while served over HTTPS — set `X-Forwarded-Proto` and have the app respect it |
| HSTS broke staging | Don't enable HSTS on staging domains, or use a separate subdomain |
| Wildcard cert won't auto-renew | Use a DNS plugin (Cloudflare, Route53) — manual challenges can't auto-renew |
| `Some challenges have failed` after IPv6 added | Add AAAA record matching your A record, or remove AAAA temporarily |
| `failed to find apparent dist-name` (old certbot) | `apt install --upgrade certbot` |
