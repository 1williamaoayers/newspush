#!/bin/bash

# 临时修复脚本 - 清理并重新部署

echo "=== NewsPush 修复脚本 ==="
echo ""

# 1. 停止并删除所有相关容器
echo "[1/4] 清理旧容器和网络..."
docker stop newspush-api newspush-pusher 2>/dev/null || true
docker rm newspush-api newspush-pusher 2>/dev/null || true
docker network rm newspush-network 2>/dev/null || true

# 2. 删除有问题的镜像
echo "[2/4] 删除有问题的镜像..."
docker rmi ghcr.nju.edu.cn/1williamaoayers/newspush:latest 2>/dev/null || true
docker rmi ghcr.io/1williamaoayers/newspush:latest 2>/dev/null || true

# 3. 使用官方镜像(如果作者已修复)或使用备用方案
echo "[3/4] 尝试使用官方镜像..."
if docker pull ghcr.io/1williamaoayers/newspush:latest; then
    IMAGE_NAME="ghcr.io/1williamaoayers/newspush:latest"
    echo "✓ 官方镜像拉取成功"
else
    echo "✗ 官方镜像拉取失败"
    echo ""
    echo "建议: 需要重新构建镜像或等待作者修复"
    exit 1
fi

# 4. 重新创建网络
echo "[4/4] 重新创建网络..."
docker network create newspush-network

echo ""
echo "=== 清理完成 ==="
echo ""
echo "现在请重新运行安装脚本:"
echo "bash /home/newspush/install.sh"
echo ""
echo "或者手动启动容器:"
echo "docker run -d --name newspush-api --network newspush-network -p 4399:4399 --restart unless-stopped $IMAGE_NAME"
