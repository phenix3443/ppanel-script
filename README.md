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
- `up server`: route traffic to a local backend while keeping shared MySQL / Redis
- `up both`: route traffic to both a local frontend and a local backend while still using shared MySQL / Redis

By default the script connects to shared dependencies through `host.docker.internal:13306` and `host.docker.internal:16379`.
The script uses Telepresence to connect to the `ppanel-dev` namespace and create intercepts for the frontend or backend workloads.

If you want to make the shared dependency targets explicit, pass them through CLI options instead of environment variables, for example:

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

If the cluster does not have a Telepresence `traffic-manager` yet, append `--install-traffic-manager` on the first run.

The script assumes `ppanel-script`, `ppanel-frontend`, and `ppanel-server` live as sibling directories.
