#!/bin/bash

# ARM32 多架构构建测试脚本
# 用于在本地验证 Docker 镜像是否支持 ARM32 架构

set -e

echo "=== ARM32 多架构构建测试 ==="
echo ""

# 颜色定义
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# 1. 检查 Docker Buildx
echo -e "${YELLOW}[1/6] 检查 Docker Buildx...${NC}"
if ! docker buildx version > /dev/null 2>&1; then
    echo -e "${RED}错误: Docker Buildx 未安装${NC}"
    echo "请运行: docker buildx install"
    exit 1
fi
echo -e "${GREEN}✓ Docker Buildx 已安装${NC}"
echo ""

# 2. 创建或使用 multiarch builder
echo -e "${YELLOW}[2/6] 设置多架构构建器...${NC}"
if ! docker buildx inspect multiarch > /dev/null 2>&1; then
    echo "创建新的 builder: multiarch"
    docker buildx create --name multiarch --use
else
    echo "使用现有 builder: multiarch"
    docker buildx use multiarch
fi
docker buildx inspect --bootstrap
echo -e "${GREEN}✓ 构建器已就绪${NC}"
echo ""

# 3. 构建多架构镜像
echo -e "${YELLOW}[3/6] 开始构建多架构镜像...${NC}"
echo "架构: linux/amd64, linux/arm64, linux/arm/v7"
echo ""

docker buildx build \
    --platform linux/amd64,linux/arm64,linux/arm/v7 \
    -t newspush:multiarch-test \
    --progress=plain \
    .

if [ $? -eq 0 ]; then
    echo -e "${GREEN}✓ 多架构构建成功${NC}"
else
    echo -e "${RED}✗ 构建失败${NC}"
    exit 1
fi
echo ""

# 4. 构建并加载 ARM32 镜像到本地
echo -e "${YELLOW}[4/6] 构建 ARM32 镜像 (linux/arm/v7)...${NC}"
docker buildx build \
    --platform linux/arm/v7 \
    -t newspush:arm32-test \
    --load \
    .

if [ $? -eq 0 ]; then
    echo -e "${GREEN}✓ ARM32 镜像构建成功${NC}"
else
    echo -e "${RED}✗ ARM32 构建失败${NC}"
    exit 1
fi
echo ""

# 5. 验证镜像
echo -e "${YELLOW}[5/6] 验证镜像...${NC}"

# 检查架构
ARCH=$(docker inspect newspush:arm32-test | jq -r '.[0].Architecture')
echo "镜像架构: $ARCH"

if [ "$ARCH" != "arm" ]; then
    echo -e "${RED}警告: 架构不是 arm${NC}"
fi

# 检查 tsx 是否存在
echo "检查 tsx 依赖..."
docker run --rm --platform linux/arm/v7 newspush:arm32-test ls -la /app/node_modules/tsx > /dev/null 2>&1
if [ $? -eq 0 ]; then
    echo -e "${GREEN}✓ tsx 依赖存在${NC}"
else
    echo -e "${RED}✗ tsx 依赖缺失${NC}"
    exit 1
fi

# 检查 Node.js 版本
echo "Node.js 版本:"
docker run --rm --platform linux/arm/v7 newspush:arm32-test node --version

echo ""

# 6. 运行时测试
echo -e "${YELLOW}[6/6] 运行时测试...${NC}"

# 启动容器
echo "启动测试容器..."
docker run -d \
    --name newspush-arm32-test \
    --platform linux/arm/v7 \
    -p 14399:4399 \
    newspush:arm32-test

# 等待启动
echo "等待服务启动 (最多 60 秒)..."
for i in {1..60}; do
    if curl -f http://localhost:14399/health > /dev/null 2>&1; then
        echo -e "${GREEN}✓ 服务启动成功 (${i}秒)${NC}"
        break
    fi
    if [ $i -eq 60 ]; then
        echo -e "${RED}✗ 服务启动超时${NC}"
        docker logs newspush-arm32-test
        docker stop newspush-arm32-test
        docker rm newspush-arm32-test
        exit 1
    fi
    sleep 1
done

# 测试 API
echo ""
echo "测试 API 接口..."

# 健康检查
if curl -f http://localhost:14399/health > /dev/null 2>&1; then
    echo -e "${GREEN}✓ /health 正常${NC}"
else
    echo -e "${RED}✗ /health 失败${NC}"
fi

# 60s 接口
if curl -f http://localhost:14399/v2/60s > /dev/null 2>&1; then
    echo -e "${GREEN}✓ /v2/60s 正常${NC}"
else
    echo -e "${RED}✗ /v2/60s 失败${NC}"
fi

# 清理
echo ""
echo "清理测试容器..."
docker stop newspush-arm32-test
docker rm newspush-arm32-test

echo ""
echo -e "${GREEN}=== 测试完成 ===${NC}"
echo ""
echo "镜像标签:"
echo "  - newspush:multiarch-test (多架构)"
echo "  - newspush:arm32-test (ARM32)"
echo ""
echo "下一步:"
echo "1. 推送代码到 GitHub 触发 Actions 构建"
echo "2. 在玩客云上测试部署"
echo ""
