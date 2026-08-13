#!/bin/sh
# dsh 容器启动脚本（挂在 PREBUILT 服务的 command/args）
set -e
export DSH_HOME=/data/dsh-home
mkdir -p "$DSH_HOME"

# npm 全局装到持久卷，重启不重装
export PATH=/data/npm-global/bin:$PATH
if ! command -v dsh >/dev/null 2>&1; then
  npm config set prefix /data/npm-global
  npm install -g @deepseek-ai/dsh
fi

# 首次初始化 profile（web profile 首次使用自动从模板生成）
if [ ! -f "$DSH_HOME/profiles/web/cordis.patch.yml" ]; then
  dsh --profile web --dump-config >/dev/null 2>&1 || true
fi
if [ ! -f "$DSH_HOME/profiles/web/cordis.patch.yml" ]; then
  (dsh web --port 0 >/tmp/init.log 2>&1 &)
  for i in $(seq 1 40); do
    [ -f "$DSH_HOME/profiles/web/cordis.patch.yml" ] && break
    sleep 1
  done
  pkill -f 'dsh web' 2>/dev/null || true
  sleep 1
fi

# 注意：此脚本每次启动都会覆盖 profile 级 patch。
# 需要跨重启的定制（如 trustedHosts）请放在 home 级 $DSH_HOME/cordis.patch.yml
cat > "$DSH_HOME/profiles/web/cordis.patch.yml" <<'PATCH'
- id: webserver
  config:
    host: 0.0.0.0
    port: 3080
PATCH

TH=""
[ -n "$PUBLIC_DOMAIN" ] && TH="--trusted-host $PUBLIC_DOMAIN"
exec dsh web --port 3080 $TH
