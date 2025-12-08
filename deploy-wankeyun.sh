#!/bin/bash

# 玩客云部署脚本 - 适用于 ARM32 架构
# 使用修复后的多架构镜像

set -e

# 颜色定义
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

clear
echo -e "${BLUE}=============================================================${NC}"
echo -e "${GREEN}       玩客云 NewsPush 部署脚本 (ARM32 专用)       ${NC}"
echo -e "${BLUE}=============================================================${NC}"
echo ""

# 配置
INSTALL_DIR="/home/newspush"
IMAGE_NAME="ghcr.io/1williamaoayers/newspush:latest"
FEISHU_WEBHOOK="${FEISHU_WEBHOOK_URL}"

# 1. 检查架构
echo -e "${YELLOW}[1/7] 检查系统架构...${NC}"
ARCH=$(uname -m)
echo "当前架构: $ARCH"

if [[ "$ARCH" != "armv7l" && "$ARCH" != "armhf" ]]; then
    echo -e "${RED}警告: 当前架构不是 ARM32 ($ARCH)${NC}"
    read -p "是否继续? (y/N): " CONTINUE
    if [[ ! "$CONTINUE" =~ ^[Yy]$ ]]; then
        exit 1
    fi
fi
echo ""

# 2. 检查 Docker
echo -e "${YELLOW}[2/7] 检查 Docker...${NC}"
if ! command -v docker &> /dev/null; then
    echo -e "${RED}Docker 未安装${NC}"
    echo "请先安装 Docker: curl -fsSL https://get.docker.com | bash"
    exit 1
fi
echo -e "${GREEN}✓ Docker 已安装${NC}"
docker --version
echo ""

# 3. 获取配置
echo -e "${YELLOW}[3/7] 配置推送服务${NC}"
if [ -z "$FEISHU_WEBHOOK" ]; then
    read -p "请输入飞书 Webhook 地址: " FEISHU_WEBHOOK
    if [ -z "$FEISHU_WEBHOOK" ]; then
        echo -e "${RED}错误: Webhook 地址不能为空${NC}"
        exit 1
    fi
fi
echo -e "${GREEN}✓ Webhook 已配置${NC}"
echo ""

# 4. 清理旧环境
echo -e "${YELLOW}[4/7] 清理旧环境...${NC}"
docker stop newspush-api newspush-pusher 2>/dev/null || true
docker rm newspush-api newspush-pusher 2>/dev/null || true
docker network rm newspush-network 2>/dev/null || true
echo -e "${GREEN}✓ 清理完成${NC}"
echo ""

# 5. 拉取镜像
echo -e "${YELLOW}[5/7] 拉取 ARM32 镜像...${NC}"
echo "镜像: $IMAGE_NAME"
if ! docker pull --platform linux/arm/v7 "$IMAGE_NAME"; then
    echo -e "${RED}镜像拉取失败${NC}"
    echo "请检查网络连接或镜像是否存在"
    exit 1
fi

# 验证镜像架构
PULLED_ARCH=$(docker inspect "$IMAGE_NAME" | jq -r '.[0].Architecture')
echo "镜像架构: $PULLED_ARCH"
if [ "$PULLED_ARCH" != "arm" ]; then
    echo -e "${YELLOW}警告: 镜像架构不是 arm${NC}"
fi
echo -e "${GREEN}✓ 镜像拉取成功${NC}"
echo ""

# 6. 部署服务
echo -e "${YELLOW}[6/7] 部署服务...${NC}"

# 创建目录
mkdir -p "$INSTALL_DIR/scripts"

# 创建网络
docker network create newspush-network

# 启动 API 服务
echo "启动 API 服务..."
docker run -d \
    --name newspush-api \
    --network newspush-network \
    -p 4399:4399 \
    --restart unless-stopped \
    "$IMAGE_NAME"

# 等待服务就绪
echo "等待服务启动..."
for i in {1..60}; do
    if curl -f http://localhost:4399/health > /dev/null 2>&1; then
        echo -e "${GREEN}✓ API 服务已启动 (${i}秒)${NC}"
        break
    fi
    if [ $i -eq 60 ]; then
        echo -e "${RED}服务启动超时${NC}"
        echo "查看日志:"
        docker logs --tail 50 newspush-api
        exit 1
    fi
    sleep 1
done

# 创建推送脚本 (CommonJS 版本,兼容性更好)
cat > "$INSTALL_DIR/scripts/push.cjs" << 'EOF'
const http = require('http');
const https = require('https');
const url = require('url');

const API_URL = process.env.SOURCE_URL || 'http://127.0.0.1:4399';
const WEBHOOK_URL = process.env.FEISHU_WEBHOOK_URL;

if (!WEBHOOK_URL) {
    console.error('未配置 FEISHU_WEBHOOK_URL');
    process.exit(1);
}

function fetchJson(endpoint) {
    return new Promise((resolve, reject) => {
        http.get(`${API_URL}${endpoint}`, (res) => {
            let data = '';
            res.on('data', (chunk) => data += chunk);
            res.on('end', () => {
                try {
                    const json = JSON.parse(data);
                    resolve(json.code === 200 ? json.data : null);
                } catch (e) {
                    console.error(`解析 ${endpoint} 失败`, e);
                    resolve(null);
                }
            });
        }).on('error', (e) => {
            console.error(`请求 ${endpoint} 失败`, e.message);
            resolve(null);
        });
    });
}

function sendWebhook(content) {
    const webhookUrl = new url.URL(WEBHOOK_URL);
    const options = {
        hostname: webhookUrl.hostname,
        path: webhookUrl.pathname + webhookUrl.search,
        method: 'POST',
        headers: { 'Content-Type': 'application/json' }
    };

    const req = https.request(options, (res) => {
        res.on('data', () => {});
        if (res.statusCode === 200) {
            console.log('✅ 推送成功！');
        } else {
            console.error(`❌ 推送失败，状态码: ${res.statusCode}`);
        }
    });

    req.on('error', (e) => console.error('❌ 推送请求错误', e));
    req.write(JSON.stringify({
        msg_type: 'text',
        content: { text: content }
    }));
    req.end();
}

async function main() {
    console.log('正在获取新闻数据...');
    const [news60s, baidu, zhihu] = await Promise.all([
        fetchJson('/v2/60s'),
        fetchJson('/v2/baidu/hot'),
        fetchJson('/v2/zhihu')
    ]);

    let message = '';
    const separator = '='.repeat(50);

    if (news60s) {
        message += `【每日新闻】${news60s.date} ${news60s.day_of_week}\n${separator}\n\n`;
        if (news60s.tip) message += `💡 ${news60s.tip}\n\n`;
        if (Array.isArray(news60s.news)) {
            news60s.news.forEach((n, i) => message += `${i + 1}. ${n}\n\n`);
        }
        if (news60s.link) message += `🔗 原文: ${news60s.link}\n\n`;
    }

    const appendHot = (title, list) => {
        if (!list || list.length === 0) return;
        message += `【${title}热榜】\n${separator}\n`;
        list.slice(0, 10).forEach((item, i) => {
            const text = item.title || item.keyword || item.name;
            const link = item.url || item.link;
            if (text) {
                message += `${i + 1}. ${text}\n`;
                if (link) message += `   🔗 ${link}\n`;
            }
        });
        message += '\n';
    };

    appendHot('百度', baidu);
    appendHot('知乎', zhihu);

    if (!message) {
        console.log('未获取到任何数据，取消推送');
        return;
    }

    message += `${separator}\n来源: NewsPush (玩客云)`;
    
    console.log('正在推送至飞书...');
    sendWebhook(message);
}

main();
EOF

# 启动推送服务
echo "启动推送服务..."
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

echo -e "${GREEN}✓ 服务部署完成${NC}"
echo ""

# 7. 设置定时任务
echo -e "${YELLOW}[7/7] 设置定时任务...${NC}"

# 创建手动推送脚本
cat > "$INSTALL_DIR/push_now.sh" << EOF
#!/bin/bash
echo "正在触发推送..."
docker exec newspush-pusher node /app/scripts/push.cjs
EOF
chmod +x "$INSTALL_DIR/push_now.sh"

# 询问推送时间
read -p "请输入推送时间 (小时, 0-23, 默认 8): " PUSH_HOUR
PUSH_HOUR=${PUSH_HOUR:-8}

# 添加 crontab
crontab -l 2>/dev/null | grep -v "$INSTALL_DIR/push_now.sh" | crontab -
(crontab -l 2>/dev/null; echo "0 $PUSH_HOUR * * * $INSTALL_DIR/push_now.sh >> $INSTALL_DIR/push.log 2>&1") | crontab -

echo -e "${GREEN}✓ 定时任务已设置: 每天 ${PUSH_HOUR} 点${NC}"
echo ""

# 完成
echo -e "${BLUE}=============================================================${NC}"
echo -e "${GREEN}🎉 部署完成！${NC}"
echo -e "${BLUE}=============================================================${NC}"
echo ""
echo "服务信息:"
echo "  - API 地址: http://localhost:4399"
echo "  - 推送时间: 每天 ${PUSH_HOUR}:00"
echo ""
echo "常用命令:"
echo "  - 手动推送: bash $INSTALL_DIR/push_now.sh"
echo "  - 查看日志: docker logs newspush-api"
echo "  - 重启服务: docker restart newspush-api"
echo ""

# 询问是否立即测试
read -p "是否立即测试推送? (y/N): " TEST_NOW
if [[ "$TEST_NOW" =~ ^[Yy]$ ]]; then
    echo ""
    echo "测试推送..."
    bash "$INSTALL_DIR/push_now.sh"
fi

echo ""
echo -e "${GREEN}部署脚本执行完毕！${NC}"
