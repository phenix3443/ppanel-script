<div align="center">

<img width="160" src="https://raw.githubusercontent.com/perfect-panel/ppanel-assets/refs/heads/main/logo.svg">

<h1>PPanel 快速部署指南</h1>

这是由 PPanel 提供支持的快速部署脚本

[英文](./README.md) · 中文

</div>

## 脚本部署

运行以下命令来部署 PPanel：

```sh
bash <(curl -fsSL https://raw.githubusercontent.com/perfect-panel/ppanel-script/refs/heads/main/install.sh)
```

```sh
bash <(wget -qO- https://raw.githubusercontent.com/perfect-panel/ppanel-script/refs/heads/main/install.sh)
```

## 本地 Telepresence 联调

使用 [`telepresence.sh`](./telepresence.sh) 配合 Telepresence 风格的开发域名切换本地前端或本地后端。

```sh
VITE_ALLOWED_HOSTS=.home.arpa \
VITE_DEVTOOLS_PORT=42170 \
./telepresence.sh up frontend --frontend user
```

- `up frontend`：切到本地前端，后端继续使用 k3s 中的部署
- `up server`：切到本地后端，依赖继续使用共享的 MySQL / Redis
- `up both`：前后端都切到本地；依赖仍使用共享的 MySQL / Redis

默认会通过 `host.docker.internal:13306` 和 `host.docker.internal:16379` 连接共享依赖。
脚本会使用 Telepresence 连接 `ppanel-dev` 命名空间，并为前端或后端创建 intercept。

如果要显式指定共享依赖，请直接通过命令行参数传入，而不是依赖环境变量，例如：

```sh
./telepresence.sh up server \
  --mysql-host host.docker.internal \
  --mysql-port 13306 \
  --mysql-database ppanel_dev \
  --mysql-user root \
  --mysql-password dev-root-password \
  --redis-host host.docker.internal \
  --redis-port 16379
```

如果集群里还没有安装 Telepresence `traffic-manager`，可以在首次执行时追加 `--install-traffic-manager`。

脚本默认假设 `ppanel-script`、`ppanel-frontend`、`ppanel-server` 是同级目录。
