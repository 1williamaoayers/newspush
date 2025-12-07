#!/bin/bash

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# 欢迎界面
clear
echo -e "${BLUE}=============================================================${NC}"
echo -e "${GREEN}       欢迎使用 NewsPush 一键部署脚本 (小白专用版)       ${NC}"
echo -e "${BLUE}=============================================================${NC}"
echo -e "这个脚本将帮助您："
echo -e "1. 自动安装 Docker (如果还没有的话)"
echo -e "2. 部署 60s 新闻 API 服务"
echo -e "3. 设置定时任务，每天早上自动推送到您的飞书"
echo -e ""
echo -e "${YELLOW}您只需要回答几个简单的问题即可完成配置！${NC}"
echo -e "${BLUE}=============================================================${NC}"
echo ""

# 检查 root 权限
if [ "$EUID" -ne 0 ]; then
  echo -e "${RED}请使用 root 权限运行此脚本！${NC}"
  echo "试试命令：sudo bash $0"
  exit 1
fi

# 1. 基础环境检查与安装
echo -e "${BLUE}[1/5] 检查环境...${NC}"

# 检查 jq (用于处理 JSON)
if ! command -v jq &> /dev/null; then
    echo -e "正在安装必要工具 jq..."
    if [ -f /etc/debian_version ]; then
        apt-get update && apt-get install -y jq
    elif [ -f /etc/redhat-release ]; then
        yum install -y jq
    elif [ -f /etc/alpine-release ]; then
        apk add jq
    fi
fi

echo ""

# 2. 获取用户配置
echo -e "${BLUE}[2/5] 配置您的推送服务${NC}"
echo -e "我们需要知道把新闻推送到哪里。推荐使用 ${GREEN}飞书 (Feishu)${NC}，完全免费且稳定。"
echo -e "如果您还没有飞书 Webhook 地址，请查看教程：https://www.feishu.cn/hc/zh-CN/articles/360024984973"
echo ""

# 交互式获取 Webhook
read -p "请输入您的飞书 Webhook 地址 (直接回车使用默认测试地址): " FEISHU_WEBHOOK
if [ -z "$FEISHU_WEBHOOK" ]; then
    FEISHU_WEBHOOK="https://www.feishu.cn/flow/api/trigger-webhook/e9eb3eb901b500ab55b2f44c50194268"
    echo -e "${YELLOW}已使用默认测试地址 (仅供测试，建议后续修改)${NC}"
fi

# 交互式获取安装目录
echo ""
read -p "请输入安装目录 (默认: /home/newspush): " INSTALL_DIR
if [ -z "$INSTALL_DIR" ]; then
    INSTALL_DIR="/home/newspush"
fi
echo -e "${GREEN}将在 ${INSTALL_DIR} 部署服务${NC}"

# 交互式获取推送时间
echo ""
echo -e "您希望每天几点推送新闻？(24小时制)"
echo -e "如果想设置多个时间点，请用逗号分隔 (例如: 8,12,18 代表早8点、午12点、晚6点)"
read -p "请输入小时 (默认: 8): " PUSH_HOUR_INPUT
if [ -z "$PUSH_HOUR_INPUT" ]; then
    PUSH_HOUR_INPUT="8"
fi

# 格式化 crontab 时间
# 将中文逗号替换为英文逗号，去除空格
CRON_HOURS=$(echo "$PUSH_HOUR_INPUT" | sed 's/，/,/g' | tr -d ' ')
echo -e "${GREEN}将在每天 ${CRON_HOURS} 点准时为您推送${NC}"

echo ""
echo -e "${BLUE}[3/5] 开始部署服务...${NC}"

# 创建目录
mkdir -p "$INSTALL_DIR"
cd "$INSTALL_DIR" || exit

# 下载必要文件 (这里模拟下载，实际应该从 GitHub 拉取或直接写入)
# 写入推送脚本逻辑
mkdir -p scripts

cat > scripts/push.js << 'EOF'
const http = require('http');
const https = require('https');
const url = require('url');

// 配置
const API_URL = process.env.SOURCE_URL || 'http://api:4399';
const WEBHOOK_URL = process.env.FEISHU_WEBHOOK_URL;

if (!WEBHOOK_URL) {
    console.error('未配置 FEISHU_WEBHOOK_URL');
    process.exit(1);
}

// 辅助函数：请求 API
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
            console.error(`请求 ${endpoint} 失败`, e);
            resolve(null);
        });
    });
}

// 辅助函数：发送 Webhook
function sendWebhook(content) {
    const webhookUrl = new url.URL(WEBHOOK_URL);
    const options = {
        hostname: webhookUrl.hostname,
        path: webhookUrl.pathname + webhookUrl.search,
        method: 'POST',
        headers: { 'Content-Type': 'application/json' }
    };

    const req = https.request(options, (res) => {
        res.on('data', () => {}); // 消耗响应流
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
    const [news60s, baidu, toutiao, zhihu] = await Promise.all([
        fetchJson('/v2/60s'),
        fetchJson('/v2/baidu/hot'),
        fetchJson('/v2/toutiao'),
        fetchJson('/v2/zhihu')
    ]);

    let message = '';
    const separator = '='.repeat(50);

    // 1. 60秒读懂世界
    if (news60s) {
        message += `【每日新闻】${news60s.date} ${news60s.day_of_week}\n${separator}\n\n`;
        if (news60s.tip) message += `💡 ${news60s.tip}\n\n`;
        if (Array.isArray(news60s.news)) {
            news60s.news.forEach((n, i) => message += `${i + 1}. ${n}\n\n`);
        }
        if (news60s.link) message += `🔗 原文: ${news60s.link}\n\n`;
    }

    // 2. 热点新闻
    const appendHot = (title, list) => {
        if (!list || list.length === 0) return;
        message += `【${title}热榜】\n${separator}\n`;
        list.slice(0, 10).forEach((item, i) => { // 只取前10条
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
    appendHot('头条', toutiao);
    appendHot('知乎', zhihu);

    if (!message) {
        console.log('未获取到任何数据，取消推送');
        return;
    }

    message += `${separator}\n来源: NewsPush (基于 60s-api)`;
    
    console.log('正在推送至飞书...');
    sendWebhook(message);
}

main();
EOF

# 4. 启动服务
echo -e "${BLUE}[4/5] 启动服务容器...${NC}"

# 创建专用网络
docker network create newspush-network 2>/dev/null || true

# 清理旧容器
echo -e "正在清理旧容器..."
docker rm -f newspush-api newspush-pusher 2>/dev/null || true

# 启动 API 服务
echo -e "正在启动 API 服务..."
docker run -d \
    --name newspush-api \
    --network newspush-network \
    --restart unless-stopped \
    ghcr.io/1williamaoayers/newspush:latest

# 启动推送服务 (作为常驻容器，用于执行定时任务)
echo -e "正在启动推送服务..."
docker run -d \
    --name newspush-pusher \
    --network newspush-network \
    --restart unless-stopped \
    -v "$INSTALL_DIR/scripts:/app/scripts" \
    -e FEISHU_WEBHOOK_URL="$FEISHU_WEBHOOK" \
    -e SOURCE_URL="http://newspush-api:4399" \
    --entrypoint tail \
    ghcr.io/1williamaoayers/newspush:latest \
    -f /dev/null

if [ $? -ne 0 ]; then
    echo -e "${RED}服务启动失败！请检查 Docker 日志。${NC}"
    exit 1
fi

echo -e "${GREEN}服务已在后台运行！${NC}"

# 5. 设置定时任务
echo -e "${BLUE}[5/5] 设置定时任务...${NC}"

# 创建一个 helper 脚本方便用户手动推送
cat > push_now.sh << EOF
#!/bin/bash
echo "正在触发推送..."
docker exec newspush-pusher node /app/scripts/push.js
EOF
chmod +x push_now.sh

# 添加 crontab
# 移除旧的相同任务
crontab -l | grep -v "$INSTALL_DIR/push_now.sh" | crontab -

# 添加新任务
(crontab -l 2>/dev/null; echo "0 $CRON_HOURS * * * $INSTALL_DIR/push_now.sh >> $INSTALL_DIR/push.log 2>&1") | crontab -

echo -e "${GREEN}定时任务已设置：每天 ${CRON_HOURS} 点自动执行${NC}"
echo ""
echo -e "${BLUE}=============================================================${NC}"
echo -e "${GREEN}🎉 恭喜！部署已完成！${NC}"
echo -e "${BLUE}=============================================================${NC}"
echo -e "您可以随时执行以下命令："
echo -e "1. 手动立即推送一次："
echo -e "   ${YELLOW}bash $INSTALL_DIR/push_now.sh${NC}"
echo -e ""
echo -e "2. 查看运行日志："
echo -e "   ${YELLOW}docker logs newspush-api${NC}"
echo -e ""
echo -e "3. 修改配置："
echo -e "   编辑 ${INSTALL_DIR}/docker-compose.yml 文件，然后执行 docker compose up -d 重启"
echo -e "${BLUE}=============================================================${NC}"
echo ""

# 询问是否立即测试
read -p "是否现在立即测试推送一次？(y/n): " RUN_NOW
if [[ "$RUN_NOW" =~ ^[Yy]$ ]]; then
    bash push_now.sh
fi
