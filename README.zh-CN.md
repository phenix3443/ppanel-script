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

使用 [`telepresence.sh`](./telepresence.sh) 启动本地前后端联调环境，并配合 Telepresence 风格的开发域名使用。

```sh
VITE_ALLOWED_HOSTS=.home.arpa \
VITE_DEVTOOLS_PORT=42170 \
./telepresence.sh up frontend --frontend user
```

如果你的本地目录结构不是默认的同级仓库布局，也可以通过 `PPANEL_ROOT`、`FRONTEND_ROOT` 或 `SERVER_ROOT` 覆盖默认路径。
