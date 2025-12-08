#!/bin/bash

# 本地构建并部署脚本

echo "=== NewsPush 本地构建部署 ==="
echo ""

# 配置
INSTALL_DIR="/home/newspush"
FEISHU_WEBHOOK="${FEISHU_WEBHOOK_URL:-https://www.feishu.cn/flow/api/trigger-webhook/e9eb3eb901b500ab55b2f44c50194268}"

# 1. 清理旧环境
echo "[1/5] 清理旧环境..."
docker stop newspush-api newspush-pusher 2>/dev/null || true
docker rm newspush-api newspush-pusher 2>/dev/null || true
docker network rm newspush-network 2>/dev/null || true

# 2. 构建新镜像
echo "[2/5] 构建 Docker 镜像..."
cd "$(dirname "$0")"
docker build -t newspush-local:latest .

if [ $? -ne 0 ]; then
    echo "❌ 镜像构建失败！"
    exit 1
fi

echo "✓ 镜像构建成功"

# 3. 创建网络
echo "[3/5] 创建 Docker 网络..."
docker network create newspush-network

# 4. 启动 API 服务
echo "[4/5] 启动 API 服务..."
docker run -d \
    --name newspush-api \
    --network newspush-network \
    -p 4399:4399 \
    --restart unless-stopped \
    newspush-local:latest

# 等待服务就绪
echo "等待服务就绪..."
for i in {1..30}; do
    if curl -f http://localhost:4399/health > /dev/null 2>&1; then
        echo "✓ API 服务已启动"
        break
    fi
    sleep 1
done

# 5. 启动推送服务
echo "[5/5] 启动推送服务..."
mkdir -p "$INSTALL_DIR/scripts"

# 创建推送脚本(使用项目中的 TypeScript 版本)
cp scripts/news-push.ts "$INSTALL_DIR/scripts/"

docker run -d \
    --name newspush-pusher \
    --network container:newspush-api \
    --restart unless-stopped \
    -v "$INSTALL_DIR/scripts:/app/scripts" \
    -e FEISHU_WEBHOOK_URL="$FEISHU_WEBHOOK" \
    -e SOURCE_URL="http://127.0.0.1:4399" \
    --entrypoint tail \
    node:20-alpine \
    -f /dev/null

echo ""
echo "=== 部署完成 ==="
echo ""
echo "测试 API:"
echo "curl http://localhost:4399/v2/60s"
echo ""
echo "手动推送:"
echo "docker exec newspush-pusher node --import tsx /app/scripts/news-push.ts"
