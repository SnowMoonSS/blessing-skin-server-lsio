# Blessing Skin Server - LinuxServer.io Image

基于 [LinuxServer.io](https://linuxserver.io/) 基础镜像构建的 [Blessing Skin Server](https://github.com/bs-community/blessing-skin-server) Docker 镜像——一个专为离线 Minecraft 服务器设计的自定义皮肤 & 披风托管 Web 应用。

本项目将 Blessing Skin 的容器化方案迁移到 LinuxServer.io 基础镜像之上，复用 LinuxServer 社区多年打磨的容器最佳实践。

## 关于 Blessing Skin

* 官网：[blessing.netlify.app](https://blessing.netlify.app/en/)
* 源码：[github.com/bs-community/blessing-skin-server](https://github.com/bs-community/blessing-skin-server)

## 本项目提供什么

| | |
| --- | --- |
| 基础镜像 | `ghcr.io/linuxserver/baseimage-debian:trixie` |
| 内置 init 系统 | `s6-overlay` 进程监督 |
| Web 服务器 | Apache (`mod_rewrite` + `.htaccess`) |
| PHP | 由 `PHP_VERSION` 构建参数决定：默认 `8.4`（trixie），可指定 `8.1`/`8.2` 等（经 `packages.sury.org`），含 `imagick`、`gd`、`zip` 等必需扩展 |
| 数据库 | 默认 SQLite（自包含），支持外部 MySQL/MariaDB |
| 运行用户 | `abc`（非 root，通过 `PUID`/`PGID` 映射） |

## LinuxServer Base Image 提供的功能

### 1. s6-overlay 进程监督系统

s6-overlay 作为 PID 1 运行，提供僵尸进程回收、服务依赖管理、优雅终止、自动重启与就绪通知。本仓库的 s6 配置位于：

* `root/etc/s6-overlay/s6-rc.d/init-bs-config/` — 配置初始化
* `root/etc/s6-overlay/s6-rc.d/svc-bs/` — Apache 服务

### 2. PUID / PGID 用户映射

通过 `PUID=1000`、`PGID=1000` 指定宿主机用户，容器内应用以该用户身份运行，挂载卷文件自动归属宿主机用户。

### 3. TZ 时区环境变量

通过 `TZ=Asia/Shanghai` 设定容器时区，无需额外挂载 `/etc/localtime`。

### 4. 自定义脚本（Custom Scripts）

挂载目录到 `/custom-cont-init.d`，放入可执行脚本即可在每次启动时、所有服务启动前执行。

### 5. 自定义服务（Custom Services）

挂载目录到 `/custom-services.d`，放入可执行脚本即可作为独立服务并行运行，s6 会监督并自动重启。

### 6. Docker Mods 扩展生态

通过 `DOCKER_MODS` 环境变量引用 LinuxServer 社区扩展层，例如：

```yaml
environment:
  - DOCKER_MODS=linuxserver/mods:universal-cloudflared
```

### 7. 标准化的 /config 与 /data

与 LinuxServer 官方一致，配置与数据分离：

* `/config` — 存放 `.env` 配置，挂载 `./config:/config` 持久化。
* `/data`  — 存放 `storage`（SQLite 数据库、日志、插件、framework 缓存等），挂载 `./data:/data` 持久化。
* 镜像把 `/app/storage` 软链到 `/data`、`/app/.env` 软链到 `/config/.env`；首次启动时把内置的 `storage` 目录树播种到 `/data`。

## 快速开始

### Docker Compose

```yaml
services:
  blessing-skin:
    image: ghcr.io/snowmoonss/blessing-skin-server:latest
    container_name: blessing-skin
    environment:
      - PUID=1000        # 宿主机用户 UID
      - PGID=1000        # 宿主机用户 GID
      - TZ=Asia/Shanghai
      # - DB_CONNECTION=mysql      # 使用外部 MySQL 时打开
      # - DB_HOST=mysql
      # - DB_PORT=3306
      # - DB_DATABASE=blessingskin
      # - DB_USERNAME=blessingskin
      # - DB_PASSWORD=secret
      # - APP_URL=https://skin.example.com
    ports:
      - "80:80"
    volumes:
      - ./config:/config   # .env 配置
      - ./data:/data       # storage / 数据库 / 插件等数据
    restart: unless-stopped
```

使用 SQLite 时无需额外配置；若使用 MySQL，请先创建数据库并取消上面的 `DB_*` 注释（使用 `DB_CONNECTION=mysql`）。

### 手动运行

```bash
docker run -d \
  --name blessing-skin \
  -p 80:80 \
  -e PUID=1000 -e PGID=1000 -e TZ=Asia/Shanghai \
  -v ./config:/config \
  -v ./data:/data \
  ghcr.io/snowmoonss/blessing-skin-server:latest
```

### 完成安装

启动后访问 `http://<host>/setup` 进入安装向导，按提示完成初始化。上传皮肤时请确认 `gd` / `imagick` 扩展正常（日志见 `/data/logs/laravel.log`）。

## 环境变量

| 变量 | 说明 | 默认值 |
| --- | --- | --- |
| `PUID` / `PGID` | 宿主机用户 UID/GID | `1000` |
| `TZ` | 容器时区 | 未设置 |
| `APP_URL` | 站点 URL | 未设置 |
| `APP_DEBUG` | 是否开启调试 | `false` |
| `DB_CONNECTION` | `sqlite` 或 `mysql` | `sqlite` |
| `DB_HOST` / `DB_PORT` | MySQL 地址 / 端口 | 未设置 |
| `DB_DATABASE` | 数据库名或 SQLite 文件路径 | `/data/database.db` |
| `DB_USERNAME` / `DB_PASSWORD` | MySQL 用户 / 密码 | 未设置 |
| `DB_PREFIX` | 数据表前缀 | 未设置 |
| `PWD_METHOD` | 密码哈希算法 | `BCRYPT` |
| `PLUGINS_DIR` | 插件目录 | `/data/plugins` |
| `PLUGINS_URL` | 插件 URL | 未设置 |
| `BLESSING_ENV` | 直接提供完整 `.env` 内容（多行），覆盖默认生成 | 未设置 |

> 所有 `DB_*` / `APP_*` 变量会在容器启动时写入 `/config/.env`；`BLESSING_ENV` 会整体写入 `.env`（适用于需要自定义更多配置项的进阶场景）。

## 开发与构建

### 源码构建（默认，git 分支）

```bash
docker build -f Dockerfile \
  --build-arg BUILDPLATFORM=linux/amd64 \
  --build-arg BLESSING_VERSION=dev \
  --build-arg BLESSING_SOURCE=git \
  -t blessing-skin:local .
```

### 从 Release 构建（稳定版，需 PHP 8.1）

```bash
docker build -f Dockerfile \
  --build-arg BUILDPLATFORM=linux/amd64 \
  --build-arg PHP_VERSION=8.1 \
  --build-arg BLESSING_VERSION=6.0.2 \
  --build-arg BLESSING_SOURCE=release \
  -t blessing-skin:local .
```

> 注意：稳定版 `6.0.2` 不支持 PHP 8.2 及以上，因此构建 `release` 时需显式指定 `--build-arg PHP_VERSION=8.1`（镜像会通过 `packages.sury.org` 安装 PHP 8.1）。从源码构建（`dev` 分支）推荐使用默认 PHP 8.4。

### 构建参数

| 参数 | 说明 | 默认值 |
| --- | --- | --- |
| `BUILDPLATFORM` | 构建平台 | `linux/amd64` |
| `PHP_VERSION` | 指定 PHP 版本（如 `8.1`/`8.2`/`8.4`），经 `packages.sury.org` 安装；留空使用发行版默认（trixie → `8.4`） | 空 |
| `BLESSING_REPO` | 源码仓库 | `https://github.com/bs-community/blessing-skin-server.git` |
| `BLESSING_VERSION` | 版本（git 分支/tag，或 release tag） | `dev` |
| `BLESSING_SOURCE` | `git`（源码构建）或 `release`（zip） | `git` |

## 许可证

* 本项目 Docker 构建文件与配置：MIT License
* [Blessing Skin Server](https://github.com/bs-community/blessing-skin-server)：MIT License
* [LinuxServer.io](https://linuxserver.io/) 基础镜像：GPL-3.0
* [s6-overlay](https://github.com/just-containers/s6-overlay)：ISC

## 致谢

* [Blessing Skin](https://github.com/bs-community/blessing-skin-server) — 优秀的皮肤托管应用
* [LinuxServer.io](https://linuxserver.io/) — 业界领先的 Docker 基础镜像与运维实践
