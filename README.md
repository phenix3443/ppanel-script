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

### Local Development

`compose.yaml` brings up the whole stack on your machine. This is the `develop`
environment: everything runs locally, nothing is published, and there are no
hostnames — you reach it over `localhost`.

```bash
docker compose up -d
```

| Service | Address |
| --- | --- |
| Backend API | `http://localhost:8080` |
| Admin web | `http://localhost:3001` |
| User web | `http://localhost:3002` |
| MySQL | `localhost:3306`, database `ppanel`, data in `./db` |
| Redis | `localhost:6379`, data in `./cache` |

Backend settings live in `config/ppanel.yaml`. The default administrator is
`admin@ppanel.dev` / `password` — change it before exposing this to anything.

The images come from Docker Hub and are pulled, never pushed. To try your own
build, build it locally over the same tag; there is still nothing to publish.

`develop` has its own database and shares nothing with the `test` deployment.
