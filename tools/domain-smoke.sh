#!/bin/sh
# domain 层无设备冒烟测试：把 .ets 纯逻辑转 Node TS 跑断言（Node>=23.6 transform-types）。
# 用法: sh tools/domain-smoke.sh   —— 任何修改 domain/ 之后必跑
#
# 设计约束：脚本只做一件机械事——相对 import 补 .ts 扩展名（Node ESM 要求显式扩展名）。
# 接口的 import type 直接写在源文件里（BSD sed 不支持 BRE \| 交替，别在脚本里加正则花活）。
set -e
cd "$(dirname "$0")/.."
OUT=$(mktemp -d)
trap 'rm -rf "$OUT"' EXIT
mkdir -p "$OUT/domain/model"

for f in entry/src/main/ets/domain/*.ets; do
  base=$(basename "$f" .ets)
  sed "s|from '\(\.[^']*\)'|from '\1.ts'|g" "$f" > "$OUT/domain/$base.ts"
done
for f in entry/src/main/ets/domain/model/*.ets; do
  base=$(basename "$f" .ets)
  sed "s|from '\(\.[^']*\)'|from '\1.ts'|g" "$f" > "$OUT/domain/model/$base.ts"
done

# runner 源码已写好 .ts 扩展名与 import type，原样复制
cp tools/smoke-runner.mts "$OUT/runner.mts"

node --experimental-transform-types "$OUT/runner.mts" 2>&1 \
  | grep -v 'ExperimentalWarning\|trace-warnings'