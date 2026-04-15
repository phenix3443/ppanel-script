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

Use [`telepresence.sh`](./telepresence.sh) to bring up the local frontend/backend workflow used with Telepresence-style dev domains.

```bash
VITE_ALLOWED_HOSTS=.home.arpa \
VITE_DEVTOOLS_PORT=42170 \
./telepresence.sh up frontend --frontend user
```

You can also override `PPANEL_ROOT`, `FRONTEND_ROOT`, or `SERVER_ROOT` if your local checkout layout differs from the default sibling-repo structure.

