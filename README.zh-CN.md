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
- `up server`：切到本地后端，并自动解析当前 k3s `ppanel-server` 的 MySQL / Redis 依赖
- `up both`：前后端都切到本地；本地后端仍自动复用 k3s 中的 MySQL / Redis

脚本会先从 `ppanel-dev` 命名空间里的 `ppanel-secret` 读取当前部署使用的真实依赖配置，打印解析结果，并在未显式覆盖时自动将 k3s 的 MySQL / Redis 端口转发到本地，再让本地 `ppanel-server` 通过这些链路访问依赖。
如果依赖无法从本地替代运行环境连通，脚本会直接报错退出。
脚本也会打印当前生效的管理员邮箱，并在连接 Telepresence 前自动将 traffic-agent 的默认资源请求压低到适合开发环境 quota 的水平。

`up frontend` 模式会显式将前端 API 指向被 intercept 域名下的 `/api`，避免误用本地 `.env.local` 里的 `127.0.0.1:8080`。

如果要显式覆盖自动发现到的依赖，请直接通过命令行参数传入，而不是依赖环境变量，例如：

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

如果需要调整 Telepresence traffic-agent 的资源配置，可以通过以下环境变量覆盖默认值：

```sh
TELEPRESENCE_AGENT_REQUEST_CPU=10m
TELEPRESENCE_AGENT_LIMIT_CPU=25m
TELEPRESENCE_AGENT_REQUEST_MEMORY=32Mi
TELEPRESENCE_AGENT_LIMIT_MEMORY=64Mi
TELEPRESENCE_AGENT_INIT_REQUEST_CPU=5m
TELEPRESENCE_AGENT_INIT_LIMIT_CPU=10m
TELEPRESENCE_AGENT_INIT_REQUEST_MEMORY=16Mi
TELEPRESENCE_AGENT_INIT_LIMIT_MEMORY=32Mi
```

如果集群里还没有安装 Telepresence `traffic-manager`，可以在首次执行时追加 `--install-traffic-manager`。

脚本默认假设 `ppanel-script`、`ppanel-frontend`、`ppanel-server` 是同级目录。
