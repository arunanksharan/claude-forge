# nginx Reverse Proxy

> Server blocks, SSE/WebSocket support, security headers, gzip/brotli, common configs per framework.

## Why nginx (and not the alternatives)

| Option | Verdict |
|--------|---------|
| **nginx** | Pick this. Battle-tested, fast, configurable, ubiquitous documentation. |
| **Caddy** | Auto-HTTPS is amazing for simple cases. Pick this if you want zero-config SSL and don't need nginx's depth. |
| **Traefik** | Best when you have many dynamic services (Docker labels, K8s ingress). Overkill for a single VPS. |
| **HAProxy** | TCP-level load balancing > HTTP. Use only if you specifically need it. |
| **Apache** | Use nginx instead. |

For a single VPS hosting one or a few apps: **nginx** for control, **Caddy** for simplicity. The configs below are nginx; the Caddy equivalent is shorter (Caddy handles SSL automatically, see `lets-encrypt-ssl.md`).

## Install

On Ubuntu/Debian:

```bash
sudo apt update && sudo apt install -y nginx
sudo systemctl enable --now nginx
sudo ufw allow 'Nginx Full'   # opens 80 + 443
```

## Layout

```
/etc/nginx/
├── nginx.conf                  # main config (rarely edited)
├── conf.d/
│   └── default.conf            # default site
├── sites-available/
│   ├── {{your-domain}}.conf    # your sites
│   └── {{another-domain}}.conf
└── sites-enabled/              # symlinks to sites-available
```

Convention varies by distro. On Ubuntu/Debian it's `sites-available` + `sites-enabled`; on others it's just `conf.d`. Either works.

## Base `nginx.conf`

The default is mostly fine. The bits worth tuning:

```nginx
# /etc/nginx/nginx.conf
user www-data;
worker_processes auto;
worker_rlimit_nofile 65535;

events {
    worker_connections 4096;
    multi_accept on;
}

http {
    include /etc/nginx/mime.types;
    default_type application/octet-stream;

    sendfile on;
    tcp_nopush on;
    tcp_nodelay on;

    keepalive_timeout 65;
    server_tokens off;                  # don't leak nginx version

    # client body size — tune to your largest expected upload
    client_max_body_size 10M;

    # gzip
    gzip on;
    gzip_vary on;
    gzip_proxied any;
    gzip_comp_level 6;
    gzip_min_length 1024;
    gzip_types
        text/plain text/css text/xml text/javascript
        application/json application/javascript application/xml+rss application/rss+xml
        application/atom+xml image/svg+xml;

    # brotli (if module installed)
    # brotli on;
    # brotli_comp_level 6;
    # brotli_types text/plain text/css application/json application/javascript text/xml application/xml application/xml+rss text/javascript;

    # logging
    log_format main escape=json
        '{'
            '"time":"$time_iso8601",'
            '"remote_addr":"$remote_addr",'
            '"request":"$request",'
            '"status":$status,'
            '"bytes":$body_bytes_sent,'
            '"referer":"$http_referer",'
            '"ua":"$http_user_agent",'
            '"rt":$request_time,'
            '"upstream_rt":"$upstream_response_time",'
            '"x_forwarded_for":"$http_x_forwarded_for"'
        '}';
    access_log /var/log/nginx/access.log main;
    error_log  /var/log/nginx/error.log warn;

    include /etc/nginx/conf.d/*.conf;
    include /etc/nginx/sites-enabled/*;
}
```

JSON access logs feed nicely into Loki / Datadog / CloudWatch. Plain text is harder to parse.

## A site config (HTTP-only, before SSL)

```nginx
# /etc/nginx/sites-available/{{your-domain}}.conf
server {
    listen 80;
    listen [::]:80;
    server_name {{your-domain}} www.{{your-domain}};

    # ACME challenge (for certbot)
    location /.well-known/acme-challenge/ {
        root /var/www/certbot;
    }

    # everything else proxies to the app
    location / {
        proxy_pass http://127.0.0.1:8000;
        proxy_http_version 1.1;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
    }
}
```

Enable:

```bash
sudo ln -s /etc/nginx/sites-available/{{your-domain}}.conf /etc/nginx/sites-enabled/
sudo nginx -t       # syntax check
sudo systemctl reload nginx
```

After this works, run certbot (see `lets-encrypt-ssl.md`) to add SSL. The post-SSL config below is what certbot will produce + what you'll customize.

## Production HTTPS site

```nginx
# /etc/nginx/sites-available/{{your-domain}}.conf

# redirect HTTP → HTTPS
server {
    listen 80;
    listen [::]:80;
    server_name {{your-domain}} www.{{your-domain}};

    location /.well-known/acme-challenge/ {
        root /var/www/certbot;
    }

    location / {
        return 301 https://$host$request_uri;
    }
}

# canonical: redirect www → apex
server {
    listen 443 ssl http2;
    listen [::]:443 ssl http2;
    server_name www.{{your-domain}};

    ssl_certificate     /etc/letsencrypt/live/{{your-domain}}/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/{{your-domain}}/privkey.pem;

    return 301 https://{{your-domain}}$request_uri;
}

# the real server
server {
    listen 443 ssl http2;
    listen [::]:443 ssl http2;
    server_name {{your-domain}};

    # SSL
    ssl_certificate     /etc/letsencrypt/live/{{your-domain}}/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/{{your-domain}}/privkey.pem;
    include /etc/letsencrypt/options-ssl-nginx.conf;            # certbot's recommended SSL config
    ssl_dhparam /etc/letsencrypt/ssl-dhparams.pem;

    # security headers
    add_header Strict-Transport-Security "max-age=63072000; includeSubDomains; preload" always;
    add_header X-Content-Type-Options "nosniff" always;
    add_header X-Frame-Options "SAMEORIGIN" always;
    add_header Referrer-Policy "strict-origin-when-cross-origin" always;
    add_header Permissions-Policy "camera=(), microphone=(), geolocation=()" always;
    # CSP — start with report-only and tighten over time
    # add_header Content-Security-Policy "default-src 'self'; script-src 'self' 'unsafe-inline' 'unsafe-eval'; ..." always;

    # logs (per-site if you want)
    access_log /var/log/nginx/{{your-domain}}.access.log main;
    error_log  /var/log/nginx/{{your-domain}}.error.log warn;

    # body size for uploads
    client_max_body_size 25M;

    # main app
    location / {
        proxy_pass http://127.0.0.1:8000;
        proxy_http_version 1.1;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        proxy_set_header Connection "";
        proxy_buffering on;
        proxy_read_timeout 60s;
        proxy_connect_timeout 5s;
        proxy_send_timeout 60s;
    }

    # static assets — long cache
    location /_next/static/ {                # Next.js
        proxy_pass http://127.0.0.1:3000;
        proxy_cache_valid 200 1y;
        add_header Cache-Control "public, max-age=31536000, immutable";
    }

    location ~* \.(jpg|jpeg|png|gif|ico|svg|webp|woff2?)$ {
        proxy_pass http://127.0.0.1:8000;
        expires 30d;
        add_header Cache-Control "public, max-age=2592000, immutable";
    }

    # SSE endpoint — long timeout, no buffering
    location /api/v1/events/stream {
        proxy_pass http://127.0.0.1:8000;
        proxy_http_version 1.1;
        proxy_set_header Connection "";
        proxy_set_header X-Accel-Buffering no;       # disable buffering for SSE
        proxy_buffering off;
        proxy_cache off;
        proxy_read_timeout 24h;
        chunked_transfer_encoding on;
    }

    # WebSocket upgrade
    location /ws {
        proxy_pass http://127.0.0.1:8000;
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_read_timeout 24h;
        proxy_send_timeout 24h;
    }

    # health/metrics — restricted
    location /metrics {
        allow 10.0.0.0/8;     # internal monitoring only
        deny all;
        proxy_pass http://127.0.0.1:8000;
    }
}
```

### Why these specific settings

| Setting | Why |
|---------|-----|
| `proxy_http_version 1.1` + `Connection ""` | Reuses upstream connections; 1.0 closes after each |
| `X-Forwarded-Proto $scheme` | App knows if the original request was HTTPS |
| `X-Real-IP` and `X-Forwarded-For` | App sees real client IP, not nginx's |
| `X-Accel-Buffering no` for SSE | Otherwise nginx buffers the entire stream |
| Long `proxy_read_timeout` for SSE/WS | SSE/WebSocket connections live for hours |
| `Cache-Control: immutable` on hashed assets | Browser doesn't even revalidate; perfect for `/_next/static/` |
| HSTS `preload` | Eligible for browser preload list (after submission) |
| `server_tokens off` | Don't leak nginx version |
| `client_max_body_size` | Defaults to 1M; bump for file uploads |

## SSE / WebSocket cheatsheet

```nginx
# inside a location block
proxy_http_version 1.1;
proxy_set_header Upgrade $http_upgrade;     # for WebSocket
proxy_set_header Connection "upgrade";       # for WebSocket
proxy_set_header X-Accel-Buffering no;       # for SSE
proxy_buffering off;                         # for SSE / streaming
proxy_read_timeout 24h;
```

For SSE: don't set `Upgrade`/`Connection: upgrade`. SSE is plain HTTP with `Content-Type: text/event-stream`. The buffering and timeout flags are what matter.

For WebSocket: set the upgrade headers. Long timeouts.

## Rate limiting

```nginx
# at the http {} level (in nginx.conf or a snippet)
limit_req_zone $binary_remote_addr zone=api:10m rate=10r/s;
limit_req_zone $binary_remote_addr zone=auth:10m rate=5r/m;

# in server block
location /api/v1/auth/ {
    limit_req zone=auth burst=10 nodelay;
    limit_req_status 429;
    proxy_pass http://127.0.0.1:8000;
}

location /api/ {
    limit_req zone=api burst=20 nodelay;
    proxy_pass http://127.0.0.1:8000;
}
```

`burst=N` allows bursts above the rate. `nodelay` processes burst immediately (instead of evenly spacing them).

For real protection, add a CDN (Cloudflare) in front. nginx rate limiting is for sanity, not DDoS.

## Static file serving

If your app has truly static files that don't need to go through the app process:

```nginx
location /static/ {
    alias /var/www/{{project-slug}}/static/;
    expires 30d;
    add_header Cache-Control "public, immutable";
    access_log off;     # static access doesn't need logs
}
```

Faster than proxying through the app. But for hashed assets (Next.js, Vite), proxy + cache is fine — the URL changes on rebuild.

## Multiple apps on one server

```nginx
# api.example.com
server {
    listen 443 ssl http2;
    server_name api.example.com;
    location / { proxy_pass http://127.0.0.1:8000; }
}

# app.example.com
server {
    listen 443 ssl http2;
    server_name app.example.com;
    location / { proxy_pass http://127.0.0.1:3000; }
}

# admin.example.com
server {
    listen 443 ssl http2;
    server_name admin.example.com;
    location / { proxy_pass http://127.0.0.1:3001; }
}
```

Each subdomain has its own server block + own LE cert (or one wildcard cert).

## Testing & reload

```bash
sudo nginx -t                  # syntax check; ALWAYS run before reload
sudo systemctl reload nginx    # graceful reload — no dropped connections
sudo systemctl restart nginx   # full restart — drops connections briefly
```

Never `restart` if `reload` will do.

To test from outside:

```bash
curl -I https://{{your-domain}}/
curl -I https://{{your-domain}}/api/v1/health
# verify HTTP/2:
curl -I --http2 https://{{your-domain}}/
```

Use https://www.ssllabs.com/ssltest/ to grade your TLS config — aim for A+.

## Common pitfalls

| Pitfall | Fix |
|---------|-----|
| `client_max_body_size` 413 errors | Bump in server block; defaults to 1M |
| WebSocket disconnects after 60s | Set `proxy_read_timeout 24h` for WS routes |
| SSE only flushes when complete | `proxy_buffering off` and `X-Accel-Buffering no` header |
| Real client IP not seen by app | App must trust `X-Forwarded-For`; nginx must set it |
| `502 Bad Gateway` after deploy | App not listening yet, or wrong port; check `journalctl` for nginx and the app |
| HSTS too aggressive in dev | Don't set HSTS on staging unless you're prepared for the consequences |
| CSP breaks the app | Start with `Content-Security-Policy-Report-Only` to test |
| `/health` blocked by auth middleware | Configure your app to skip auth on `/health` |
| nginx upgrade resets sites-enabled | Use `dpkg-divert` or backup before upgrades |
| Slow because gzip not applied | Check `gzip_types` includes your content type; gzip doesn't run for binary by default |
