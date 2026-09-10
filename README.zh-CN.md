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

## 本地开发

`compose.yaml` 在本机拉起整套服务。这就是 `develop` 环境：全部跑在本地，
不发布任何东西，也没有域名——通过 `localhost` 访问。

```sh
docker compose up -d
```

| 服务 | 地址 |
| --- | --- |
| 后端 API | `http://localhost:8080` |
| 管理端 | `http://localhost:3001` |
| 用户端 | `http://localhost:3002` |
| MySQL | `localhost:3306`，库 `ppanel`，数据在 `./db` |
| Redis | `localhost:6379`，数据在 `./cache` |

后端配置在 `config/ppanel.yaml`。默认管理员是 `admin@ppanel.dev` / `password`，
往任何能被别人访问的地方放之前先改掉。

镜像从 Docker Hub 拉取，**不推送**。要验自己改的代码，本地 build 覆盖同一个 tag 即可，
同样没有发布环节。

`develop` 有自己独立的数据库，和 `test` 部署不共享任何东西。
