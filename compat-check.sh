#!/bin/sh
# dsh 升级后运行：检查所有注入点是否仍匹配当前版本
# 用法：容器内 ./compat-check.sh
DSH_LIB="${1:-/data/npm-global/lib/node_modules/@deepseek-ai/dsh/node_modules}"

echo "== sub_filter 注入点（期望 >=1）=="
c=$(grep -c "isLoopbackHostname(pageLocation.hostname)" \
  "$DSH_LIB/@deepseek-ai/dsh-client-connection/lib/client.js" 2>/dev/null || echo 0)
echo "isLoopback改写: $c"

echo "== CSS 类名存活检查 =="
for cls in VOzbGW_panel VOzbGW_navList VOzbGW_content uV2eYG_row \
           _7KE1Ra_trigger _7KE1Ra_menu JObwrW_panel JObwrW_trigger \
           _markdown_1nba0_5 Sxvs8a_body Sxvs8a_root FJxK0a_root \
           p-xYUq_timeStart p-xYUq_timeEnd p-xYUq_actions \
           _1p9O6q_plot _1p9O6q_labels _1p9O6q_track \
           wSkVaW_scrollBody wSkVaW_header Md3f7G_scroll; do
  hit=$(grep -rl "$cls" "$DSH_LIB"/*/lib/*.js 2>/dev/null | head -1)
  if [ -n "$hit" ]; then
    echo "$cls: OK"
  else
    echo "$cls: 失效（需在新版本中重新定位类名）"
  fi
done
