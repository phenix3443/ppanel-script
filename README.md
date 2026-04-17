<div align="center">

<img width="160" src="https://raw.githubusercontent.com/perfect-panel/ppanel-assets/refs/heads/main/logo.svg">

<h1>PPanel Quick Deployment Guide</h1>

This is a quick deployment script provided by PPanel

English · [中文](./README.zh-CN.md)

</div>

### Script Deployment

Run the following commands to deploy PPanel:

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/perfect-panel/ppanel-script/refs/heads/main/install.sh)
```

```bash
bash <(wget -qO- https://raw.githubusercontent.com/perfect-panel/ppanel-script/refs/heads/main/install.sh)
```

### Local Telepresence Workflow

Use [`telepresence.sh`](./telepresence.sh) with Telepresence-style dev domains to switch traffic to a local frontend or local backend.

```bash
VITE_ALLOWED_HOSTS=.home.arpa \
VITE_DEVTOOLS_PORT=42170 \
./telepresence.sh up frontend --frontend user
```

- `up frontend`: route traffic to a local frontend while keeping the k3s backend
- `up server`: route traffic to a local backend and automatically resolve the active k3s MySQL / Redis dependencies
- `up both`: route traffic to both a local frontend and a local backend while the local backend still reuses the active k3s MySQL / Redis dependencies

Before replacing workloads, the script reads the real backend dependency config from `ppanel-secret` in the `ppanel-dev` namespace, prints the resolved values, and unless you explicitly override them, automatically port-forwards the k3s MySQL / Redis services for the local backend runtime.
If the local replacement runtime cannot reach those dependencies, the script now fails fast.
The script also prints the active admin email and automatically lowers Telepresence traffic-agent resource defaults before connecting so development namespace quotas are less likely to block intercepts.

`up frontend` also forces the frontend API target back to `/api` on the intercepted domain so it does not accidentally inherit `127.0.0.1:8080` from a local `.env.local`.

If you want to override the auto-resolved dependency targets, pass them through CLI options instead of environment variables, for example:

```bash
./telepresence.sh up server \
  --mysql-host host.docker.internal \
  --mysql-port 13306 \
  --mysql-database ppanel_dev \
  --mysql-user root \
  --mysql-password dev-root-password \
  --redis-host host.docker.internal \
  --redis-port 16379
```

If you need to tune the Telepresence traffic-agent resource profile, you can override the defaults with:

```bash
TELEPRESENCE_AGENT_REQUEST_CPU=10m
TELEPRESENCE_AGENT_LIMIT_CPU=25m
TELEPRESENCE_AGENT_REQUEST_MEMORY=32Mi
TELEPRESENCE_AGENT_LIMIT_MEMORY=64Mi
TELEPRESENCE_AGENT_INIT_REQUEST_CPU=5m
TELEPRESENCE_AGENT_INIT_LIMIT_CPU=10m
TELEPRESENCE_AGENT_INIT_REQUEST_MEMORY=16Mi
TELEPRESENCE_AGENT_INIT_LIMIT_MEMORY=32Mi
```

If the cluster does not have a Telepresence `traffic-manager` yet, append `--install-traffic-manager` on the first run.

The script assumes `ppanel-script`, `ppanel-frontend`, and `ppanel-server` live as sibling directories.
