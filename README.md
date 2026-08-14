# DeepSeek Harness 远程部署

[English](README.en.md) | 中文

DeepSeek Harness (dsh) 远程部署包 —— 平台无关方案，任何能跑 Docker 的 VPS 或服务器皆可部署。

> **适配版本**: dsh `0.1.0-rc.6`（2026-08-13 发布日版本）
> **部署形态**: nginx 边缘 + dsh 后端（三容器: Caddy/nginx/dsh）+ 持久卷
> **验证环境**: Zeabur Tokyo 节点 2C4G（部署路径 B）

---


> **免责声明**：本项目为社区项目，与 DeepSeek AI 无隶属、背书或赞助关系。所有商标归其各自所有者。

## ⚠️ 安全警告（必读）

本方案**解锁了 dsh 的特权平面**（设置 / 凭据 / 模型配置）——官方版本有意将其锁死在
loopback，直到真正认证层出现。使用本方案即表示你接受以下边界：

- **Basic Auth 是唯一安全防线。** 无限速、无审计、无双因素认证。密码弱或被泄露 =
  攻击者获得服务器上的 **agent 执行权（等价 shell）**。
- **任何通过认证的人都可以修改系统配置、读取凭据状态。**
- **建议仅个人自用。** 多用户或生产环境请在 nginx 前再加一层更强的认证（OAuth2/SSO、
  IP 白名单、fail2ban）。
- **dsh 处于 developer preview**，会有破坏性变更与未知漏洞。公网暴露风险自担。

永远不要把 dsh 后端绑到公网域名，永远不要使用默认密码，APK 内嵌凭据时勿外传。

---

> **核心亮点：移动端 UI 适配** —— dsh 官方前端是桌面优先设计，窄屏下多处布局崩塌。
> 本方案通过 nginx 注入 CSS 完成 20+ 项适配修复，详见下文《移动端 UI 适配明细》。

## 这是什么

[dsh](https://github.com/deepseek-ai/deepseek-harness) 是 DeepSeek AI 开源的 agent harness（智能体框架）。官方 v1 明确将部署加固（TLS、鉴权）列为 out-of-scope，且设置/凭据等特权 API 被硬锁在 loopback。

本仓库是一套**部署层方案**（不修改任何 dsh 源码），解决：

- **零源码修改**（Zero source-code changes）—— 不动 dsh 一行代码，全部通过部署层（Cordis patch / nginx sub_filter）实现；升级官方版本无需重新打补丁
- **移动端 UI 适配**（核心）—— 20+ 项修复：设置面板纵向布局与滚动、弹窗避让侧栏、composer 防重叠、字号体系、token 信息换行、轨迹页图表全宽、对话页禁横滑
- 特权平面解锁（设置页/模型配置/凭据在远程浏览器可用）
- 安全暴露（nginx Basic Auth 充当官方等待的认证层）
- 性能（gzip、immutable 缓存、Service Worker 离线缓存）
- 远程部署（dsh CLI 拒绝 `--host 0.0.0.0`，通过 Cordis patch 配置层解决）

## 架构（平台无关）

```
手机/浏览器 ──HTTPS──> TLS 终结（Caddy 或平台网关）
                          │
                          ▼
                  nginx 边缘（公网入口）
                  ├─ Basic Auth（.htpasswd）
                  ├─ gzip / immutable 缓存 / Service Worker
                  ├─ sub_filter: 注入移动端 CSS + SW 注册
                  ├─ sub_filter: 改写 isLoopback（客户端侧解锁）
                  └─ /api/ 改写 Host/Origin 为 127.0.0.1（服务端侧解锁）
                          │ 内网（Docker 网络或平台内网）
                          ▼
                  dsh 后端（无公网入口）
                  ├─ node:24 + @deepseek-ai/dsh
                  ├─ DSH_HOME=/data/dsh-home（持久卷）
                  ├─ profile patch: webserver 绑 0.0.0.0
                  └─ home patch: trustedHosts 信任名单
```

## 目录结构

```
.
├── README.md / README.zh.md
├── docker-compose.yml        # 方式 A：任意 VPS 一键部署
├── Caddyfile                 # 自动 HTTPS（Let's Encrypt）
├── compat-check.sh           # dsh 升级后体检注入点
├── nginx/
│   ├── default.conf          # nginx 边缘配置（含全部注入规则）
│   └── sw.js                 # Service Worker（插件 JS 本地缓存）
├── css/
│   └── mobile.css           # 移动端适配 CSS（版本绑定，见踩坑#5）
└── dsh/
    ├── startup.sh            # dsh 容器启动脚本（自动初始化配置）
    ├── cordis.patch.yml      # home 级 patch（trustedHosts）
    └── settings.yaml         # 服务端设置（模型/权限，热加载）
```

## 前置条件

- 任意 Linux 服务器（能跑 Docker 即可；裸机也行，见下）
- DeepSeek API Key
- 一个域名 + DNS 解析（Caddy 自动签发 HTTPS 证书）

## 部署

### 方式 A：Docker Compose（任意 VPS，推荐）

```sh
# 1. 准备凭据
export DEEPSEEK_API_KEY=sk-xxx
export PUBLIC_DOMAIN=your.domain.com

# 2. 生成 Basic Auth 密码文件
htpasswd -nb admin 你的密码 > nginx/.htpasswd

# 3. 改域名
sed -i 's/YOUR.DOMAIN.COM/your.domain.com/' Caddyfile

# 4. 改信任名单
dsed 替换 dsh/cordis.patch.yml 里的占位域名

# 5. 启动
docker compose up -d
```

说明：
- dsh 服务通过 network alias `dsh.zeabur.internal` 与 nginx 配置兼容，两种部署路径共用同一份 default.conf
- `./dsh` 目录挂载为只读配置源，startup.sh 首次启动自动初始化 home patch 与 settings
- 持久数据在 `dsh-data` 卷；配置即代码，仓库即备份

### 方式 B：Zeabur（平台特定路径）

1. 创建项目（region 选你的服务器）
2. 服务 1: dsh —— Prebuilt `node:24`，端口 3080/HTTP，挂卷 `/data`，Command/Args 用 `dsh/startup.sh` 内容，环境变量 `DEEPSEEK_API_KEY`、`PUBLIC_DOMAIN`，不绑公网域名
3. 服务 2: nginx —— Prebuilt `nginx:1.27-alpine`，端口 80/HTTP，配置文件管理写入 `nginx/default.conf` 与 `nginx/sw.js`，htpasswd 写入 `/etc/nginx/.htpasswd`，绑定公网域名
4. dsh 容器内写入 home patch 与 settings.yaml（或用 executeCommand）
5. 重启两个服务验证

> Zeabur 特有注意：生成域名只传前缀；域名必须绑在 nginx 服务上（见踩坑#3）。

## 截图展示

![对话视图](docs/screenshots/01-chat-view.jpg)

![轨迹视图](docs/screenshots/02-trajectory-view.jpg)



## 移动端 UI 适配明细（css/mobile.css）

以下修复全部通过 nginx `sub_filter` 注入 CSS 实现，不修改 dsh 源码。

| 区域 | 问题 | 修复 |
|---|---|---|
| 设置面板 | 左右分栏在窄屏挤压（右侧仅 127px） | 改纵向布局，导航横滚，内容区独立滚动 |
| 设置面板 | 内容溢出无法滚动 | `max-height:82vh + overflow-y:auto` |
| 设置面板 | 导航条撑满面板 | 导航条自适应高度 + 内容区 `flex:1` |
| 模型/上下文弹窗 | 被左侧 56px 侧栏遮挡 | 模型弹窗 `left:0`；上下文弹窗 `left:-206px`（避开侧栏） |
| 底部 composer | 命令/模型/思考强度按钮叠在一起 | `flex-wrap` 允许换行，模型按钮省略号截断 |
| AI 回复正文 | 字号偏大 | 11.5px（可调） |
| 消息元信息（用时/tok/s） | nowrap 撑到 361px 溢出屏幕 | 多行换行 + 10px |
| 底部 token 状态栏 | 672px 内容挤在 267px 容器 | 多行换行 + 9px |
| 对话页 | 被超宽元素带出横向滚动 | `overflow-x:hidden` 锁死 |
| 轨迹页条形图 | 图例+条形并排贴边，窄屏被裁 | 图例独占一行全宽 + 条形全宽 |
| 全局 | 字体基准 16px 偏大 | `html,body` 15px |

> 注意：类名是 CSS Modules hash（版本绑定）。升级 dsh 后跑 `compat-check.sh` 体检。

## 踩坑记录（重要）

1. **node:24-slim 编译失败**: dsh 依赖 node-pty（原生模块），slim 镜像缺 python/gcc。必须用完整版 `node:24`。
2. **CLI 拒绝 --host 0.0.0.0**: webserver 插件配置层合法接受 `0.0.0.0`，但 CLI 层故意拒绝。走 profile patch 配置层。
3. **（仅 Zeabur）生成域名规则**: `addDomain` 只传前缀；域名必须绑在 **nginx** 服务上，绑到 dsh 服务会绕过鉴权裸奔。
4. **启动脚本覆盖 profile patch**: 脚本每次启动重写 profile 级 cordis.patch.yml。跨重启定制放 home 级 `$DSH_HOME/cordis.patch.yml`。
5. **CSS 类名是版本绑定的**: dsh 前端用 CSS Modules，类名含构建 hash。升级后用 `compat-check.sh` 体检并重新定位。
6. **特权平面 loopback 锁**: 设置/凭据/预设 RPC 用空信任列表校验 Host/Origin 是否 loopback（官方注释: 等真正认证层出现）。解法: nginx 改写 `/api/` Host/Origin 为 `127.0.0.1:3080` + 客户端 isLoopback 改写为 true。前提是前面有 Basic Auth。
7. **session 导出 401**: 远程部署下 `/api/session.export` 下载可能 401（截至 rc.6 未修）。

## 升级指南

1. 升级前跑 `compat-check.sh`（dsh 容器内，指向新版本 node_modules）
2. 失效的 CSS 类名: 新版本 `grep -r <组件特征> node_modules/@deepseek-ai/dsh-client-*/lib/*.js` 重新定位
3. sub_filter 注入点: 检查 `dsh-client-connection/lib/client.js` 中 isLoopback 表达式
4. 更新本 README 的适配版本号

## 安全说明

- Basic Auth 是唯一认证边界，密码强度 = 安全强度，无 rate limit
- 过认证 = 拥有 agent 执行权（等价 shell），勿分享 APK/凭据
- APK 内嵌凭据自用可接受，外传不可
- dsh 处于 developer preview，官方声明会有破坏性变更

## 敏感信息

本仓库不含任何真实密钥/密码。部署时自行填充：

- `.htpasswd`: `htpasswd -nb admin <密码>` 生成
- `DEEPSEEK_API_KEY`: 环境变量
- `trustedHosts`: 换成你自己的域名

## 许可

部署方案: MIT。dsh 本体版权归 DeepSeek AI，MIT License。
