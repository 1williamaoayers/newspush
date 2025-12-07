# 📰 NewsPush 新闻推送系统 (小白专用版)

![Docker](https://img.shields.io/docker/v/vikiboss/60s?style=flat&label=Docker) ![Node.js](https://img.shields.io/badge/Node.js-6DA55F?logo=node.js&logoColor=white)

这是一个**专为小白设计**的一键新闻推送系统。

无论您是否懂代码，只要复制下面的一行命令，就能在您的服务器（或玩客云、树莓派）上搭建一套自动新闻推送服务。每天早上，最新的**60秒读懂世界、百度热搜、知乎热榜**会自动推送到您的手机（飞书）上，让您躺在床上就能掌握天下事。

## ✨ 功能特点

*   **极简安装**: 只需要复制粘贴一行命令，剩下的交给脚本。
*   **全自动**: 自动安装 Docker、自动部署服务、自动设置定时任务。
*   **内容丰富**: 包含每日简报、每日一言、百度/头条/知乎热点新闻。
*   **完全免费**: 使用免费的飞书 Webhook 进行推送，稳定可靠。
*   **支持多平台**: 完美支持 x86 服务器、**玩客云**、树莓派等 ARM 设备。

## 🚀 一键安装 (推荐)

请使用 `root` 用户登录您的服务器，然后执行以下命令：

```bash
curl -O https://pull.aitgo.netlib.re/https://raw.githubusercontent.com/1williamaoayers/newspush/master/install.sh && bash install.sh
```

*(如果无法下载，请将 `install.sh` 的内容复制到您的服务器上保存为 `install.sh`，然后运行 `bash install.sh`)*

### 安装过程指引

脚本运行后，会以交互方式问您几个简单的问题：

1.  **飞书 Webhook 地址**: 
    *   如果您没有，可以直接回车使用测试地址（仅供测试）。
    *   推荐您自己申请一个：[如何获取飞书 Webhook？](https://www.feishu.cn/hc/zh-CN/articles/360024984973)
    *   *简单说：下载飞书 -> 建个群 -> 添加群机器人 -> 复制 Webhook 地址。*

2.  **安装目录**: 
    *   默认是 `/home/newspush`，直接回车即可。

3.  **推送时间**: 
    *   输入您想几点收到新闻（例如 `8` 代表早上 8 点），直接回车默认是 8 点。

**就这样！安装完成后，您就可以去喝杯咖啡了，系统会自动在每天指定时间为您推送新闻。**

---

## 🛠️ 常用操作

安装完成后，您可以进入安装目录（默认 `/home/newspush`）进行管理。

### 1. 手动立即推送一次
如果您想现在立刻收到一条新闻，执行：
```bash
bash /home/newspush/push_now.sh
```

### 2. 查看日志
如果发现没有收到推送，可以看看日志：
```bash
docker logs newspush-api    # 查看 API 服务日志
cat /home/newspush/push.log # 查看推送记录
```

### 3. 修改配置
如果您想修改推送时间或 Webhook 地址：
*   **修改推送时间**: `crontab -e` 修改定时任务。
*   **修改 Webhook**: 编辑 `/home/newspush/docker-compose.yml` 文件中的 `FEISHU_WEBHOOK_URL`，然后运行 `docker compose up -d` 重启。

---

## ❓ 常见问题

**Q: 我没有服务器，可以在电脑上跑吗？**
A: 可以，只要您的电脑安装了 Docker 并且不关机。不过推荐使用几块钱一个月的云服务器或者玩客云这种低功耗设备，24小时运行不费电。

**Q: 为什么 Docker 安装失败？**
A: 脚本默认使用阿里云镜像源安装 Docker。如果失败，可能是您的网络问题，建议手动安装 Docker 后再运行此脚本。

**Q: 玩客云能跑吗？**
A: **完美支持！** 本项目专门针对玩客云（ARM32）进行了优化，请放心使用。

---

## 🙏 鸣谢
本项目基于 [60s-api](https://github.com/vikiboss/60s) 开发 。
