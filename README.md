# dsh-remote-deploy

DeepSeek Harness (dsh) 远程部署包 —— 基于 Zeabur + nginx 的生产级方案。

> **适配版本**: dsh `0.1.0-rc.6`（2026-08-13 发布日版本）
> **部署形态**: Zeabur 双服务（nginx 边缘 + dsh 后端）+ 持久卷
> **验证环境**: Zeabur Tokyo 节点（2核4G BYOS 服务器）

---

## 这是什么

[dsh](https://github.com/deepseek-ai/deepseek-harness) 是 DeepSeek AI 开源的 agent harness（智能体框架）。官方 v1 明确将部署加固（TLS、鉴权）列为 out-of-scope，且设置/凭据等特权 API 被硬锁在 loopback。

本仓库是一套**部署层方案**（不修改任何 dsh 源码），解决：

- 远程部署（dsh CLI 拒绝 `--host 0.0.0.0`，通过 Cordis patch 配置层解决）
- 安全暴露（nginx Basic Auth 充当官方等待的认证层）
- 特权平面解锁（设置页/模型配置/凭据在远程浏览器可用）
- 性能（gzip、immutable 缓存、Service Worker 离线缓存）
- 移动端适配（设置面板、弹窗、composer、字体、溢出修复）

## 架构

```
手机/浏览器 ──HTTPS──> Zeabur 网关
                        │
                        ▼
                nginx 服务（公网域名）
                ├─ Basic Auth（.htpasswd）
                ├─ gzip / immutable 缓存 / SW
                ├─ sub_filter: 注入移动端 CSS + SW 注册
                ├─ sub_filter: 改写 isLoopback（客户端侧解锁）
                └─ /api/ 改写 Host/Origin 为 127.0.0.1（服务端侧解锁）
                        │ 内网 http://dsh.zeabur.internal:3080
                        ▼
                dsh 服务（无公网域名）
                ├─ node:24 + @deepseek-ai/dsh
                ├─ DSH_HOME=/data/dsh-home（持久卷）
                ├─ profile patch: webserver 绑 0.0.0.0
                └─ home patch: trustedHosts 信任名单
```

## 目录结构

```
.
├── README.md
├── compat-check.sh          # dsh 升级后体检注入点
├── nginx/
│   ├── default.conf          # nginx 边缘配置（含全部注入规则）
│   └── sw.js                 # Service Worker（插件 JS 本地缓存）
├── css/
│   └── mobile.css           # 移动端适配 CSS（版本绑定，见踩坑#5）
└── dsh/
    ├── startup.sh            # dsh 容器启动脚本
    ├── cordis.patch.yml      # home 级 patch（trustedHosts）
    └── settings.yaml         # 服务端设置（模型/权限，热加载）
```

## 前置条件

- Zeabur 账号 + 一台 BYOS 服务器（Zeabur 已废弃共享集群，新项目必须挂服务器）
- DeepSeek API Key
- 一个域名（可选，Zeabur 自动生成域名也行）

## 部署步骤

### 方式 A：Zeabur Dashboard（推荐新手）

1. 创建项目（region 选你的服务器）
2. **服务 1: dsh**
   - 添加服务 → Prebuilt（Docker 镜像）→ `node:24`（完整版，slim 缺编译工具链，见踩坑#1）
   - 端口: 3080 / HTTP
   - 挂载卷: `/data`
   - Command: `sh`，Args: `-c` + 本仓库 `dsh/startup.sh` 内容
   - 环境变量: `DEEPSEEK_API_KEY`、`PUBLIC_DOMAIN`（你的 nginx 域名）
   - 不绑定公网域名
3. **服务 2: nginx**
   - 添加服务 → Prebuilt → `nginx:1.27-alpine`
   - 端口: 80 / HTTP
   - 配置文件管理：写入 `nginx/default.conf` 和 `nginx/sw.js`
   - 生成 htpasswd: `htpasswd -nb admin 你的密码` → 写入 `/etc/nginx/.htpasswd`
   - 绑定公网域名（生成域名只填前缀，见踩坑#3）
4. dsh 容器内写入 `dsh/cordis.patch.yml` 到 `$DSH_HOME/cordis.patch.yml`、`dsh/settings.yaml` 到 `$DSH_HOME/settings.yaml`
5. 重启两个服务，浏览器访问验证

### 方式 B：Zeabur GraphQL API（脚本化）

关键 mutation（详见 Zeabur 开放 API 文档）:

- `createProject(name, region)` — region 是 `server-<服务器ID>`
- `createPrebuiltService(projectID, schema: ServiceSpecSchemaInput)`
- `addDomain(serviceID, environmentID, domain, isGenerated)` — 生成域名只传前缀
- `createEnvironmentVariable(serviceID, environmentID, key, value)`
- `updateServiceConfig(serviceID, environmentID, path, content, ...)` — 写 nginx 配置文件
- `executeCommand(serviceID, environmentID, command)` — 容器内执行命令

本方案部署时的完整调用序列与参数见仓库 git 历史（部署过程记录）。

## 踩坑记录（重要）

1. **node:24-slim 编译失败**: dsh 依赖 node-pty（原生模块），slim 镜像缺 python/gcc。必须用完整版 `node:24`。
2. **CLI 拒绝 --host 0.0.0.0**: webserver 插件配置层合法接受 `0.0.0.0`，但 CLI 层故意拒绝。走 profile patch 配置层。
3. **Zeabur 生成域名规则**: `addDomain` 的 domain 参数只传前缀（如 `myapp`），系统自动补 `.zeabur.app`；传完整域名会报 DOMAIN_UNAVAILABLE。域名必须绑在 **nginx** 服务上，绑到 dsh 服务会绕过鉴权裸奔。
4. **启动脚本覆盖 profile patch**: 每次容器启动，启动脚本会重写 profile 级 cordis.patch.yml。跨重启的定制必须放 home 级 `$DSH_HOME/cordis.patch.yml`（应用顺序在 profile 之后）。
5. **CSS 类名是版本绑定的**: dsh 前端用 CSS Modules，类名含构建 hash（如 `VOzbGW_panel`）。升级 dsh 后类名大概率失效。用 `compat-check.sh` 体检，失效类名去新版本 `node_modules` 里 grep 组件重新定位。
6. **特权平面 loopback 锁**: 设置/凭据/预设等 RPC 用空信任列表校验 Host/Origin 是否 loopback（官方注释: 等真正认证层出现）。解法: nginx 改写 `/api/` 的 Host/Origin 为 `127.0.0.1:3080` + 改写客户端 isLoopback 为 true。前提是前面有 Basic Auth（即认证层）。
7. **session 导出 401**: 远程部署下 `/api/session.export` 下载可能 401（截至 rc.6 未修）。

## 升级指南

1. 升级前跑 `compat-check.sh`（在 dsh 容器内，指向新版本 node_modules）
2. 失效的 CSS 类名: 新版本中 `grep -r <组件特征> node_modules/@deepseek-ai/dsh-client-*/lib/*.js` 重新定位
3. sub_filter 注入点: 检查 `dsh-client-connection/lib/client.js` 中 isLoopback 表达式是否变化
4. 更新本 README 的适配版本号

## 安全说明

- Basic Auth 是唯一认证边界，密码强度 = 安全强度，无 rate limit
- 过认证 = 拥有 agent 执行权（等价 shell），勿分享 APK/凭据
- APK 内嵌凭据自用可接受，外传不可
- dsh 处于 developer preview，官方声明会有破坏性变更

## 敏感信息

本仓库不含任何真实密钥/密码。部署时自行填充：

- `.htpasswd`: `htpasswd -nb admin <密码>` 生成
- `DEEPSEEK_API_KEY`: Zeabur 环境变量
- `trustedHosts`: 换成你自己的域名

## 许可

部署方案: MIT。dsh 本体版权归 DeepSeek AI，MIT License。
