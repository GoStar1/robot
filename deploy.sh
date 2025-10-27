#!/bin/bash

# Laravel Blockchain Robot - Docker Deployment Script
# 快速部署脚本

set -e

echo "========================================="
echo "Laravel Blockchain Robot 部署脚本"
echo "========================================="
echo ""

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# 检查 Docker 是否安装
if ! command -v docker &> /dev/null; then
    echo -e "${RED}错误: Docker 未安装${NC}"
    echo "请先安装 Docker: https://docs.docker.com/get-docker/"
    exit 1
fi

# 检查 Docker Compose 是否安装
if ! command -v docker-compose &> /dev/null; then
    echo -e "${RED}错误: Docker Compose 未安装${NC}"
    echo "请先安装 Docker Compose"
    exit 1
fi

echo -e "${GREEN}✓ Docker 环境检查通过${NC}"
echo ""

# 检查 .env 文件
if [ ! -f .env ]; then
    echo -e "${YELLOW}未找到 .env 文件，从 .env.docker 复制...${NC}"
    cp .env.docker .env
    echo -e "${GREEN}✓ .env 文件已创建${NC}"
    echo -e "${YELLOW}警告: 请编辑 .env 文件，修改数据库密码和应用配置！${NC}"
    echo ""
    read -p "是否现在编辑 .env 文件? (y/n) " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        ${EDITOR:-nano} .env
    fi
else
    echo -e "${GREEN}✓ .env 文件已存在${NC}"
fi

echo ""
echo "开始部署..."
echo ""

# 停止现有容器
echo "1. 停止现有容器..."
docker-compose down 2>/dev/null || true
echo -e "${GREEN}✓ 完成${NC}"
echo ""

# 构建镜像
echo "2. 构建 Docker 镜像..."
docker-compose build --no-cache
echo -e "${GREEN}✓ 完成${NC}"
echo ""

# 启动容器
echo "3. 启动容器..."
docker-compose up -d
echo -e "${GREEN}✓ 完成${NC}"
echo ""

# 等待 MySQL 就绪
echo "4. 等待 MySQL 启动..."
sleep 10
until docker-compose exec -T mysql mysqladmin ping -h localhost --silent 2>/dev/null; do
    echo "等待 MySQL 就绪..."
    sleep 2
done
echo -e "${GREEN}✓ MySQL 已就绪${NC}"
echo ""

# 安装 Composer 依赖
echo "5. 安装 Composer 依赖..."
docker-compose exec -T app composer install --no-dev --optimize-autoloader --no-interaction
echo -e "${GREEN}✓ 完成${NC}"
echo ""

# 生成应用密钥
echo "6. 生成应用密钥..."
docker-compose exec -T app php artisan key:generate --force
echo -e "${GREEN}✓ 完成${NC}"
echo ""

# 运行数据库迁移
echo "7. 运行数据库迁移..."
docker-compose exec -T app php artisan migrate --force
echo -e "${GREEN}✓ 完成${NC}"
echo ""

# 创建存储链接
echo "8. 创建存储链接..."
docker-compose exec -T app php artisan storage:link
echo -e "${GREEN}✓ 完成${NC}"
echo ""

# 设置权限
echo "9. 设置目录权限..."
docker-compose exec -T app chown -R www-data:www-data /var/www/html/storage
docker-compose exec -T app chown -R www-data:www-data /var/www/html/bootstrap/cache
docker-compose exec -T app chmod -R 775 /var/www/html/storage
docker-compose exec -T app chmod -R 775 /var/www/html/bootstrap/cache
echo -e "${GREEN}✓ 完成${NC}"
echo ""

# 清除和缓存配置
echo "10. 优化应用..."
docker-compose exec -T app php artisan config:cache
docker-compose exec -T app php artisan route:cache
docker-compose exec -T app php artisan view:cache
echo -e "${GREEN}✓ 完成${NC}"
echo ""

# 显示容器状态
echo "========================================="
echo "部署完成！"
echo "========================================="
echo ""
docker-compose ps
echo ""

# 获取服务器 IP
SERVER_IP=$(hostname -I | awk '{print $1}' 2>/dev/null || echo "localhost")

echo "========================================="
echo "访问信息："
echo "========================================="
echo -e "应用主页:       ${GREEN}http://${SERVER_IP}${NC}"
echo -e "phpMyAdmin:     ${GREEN}http://${SERVER_IP}:8080${NC}"
echo ""
echo "phpMyAdmin 登录信息："
echo "  服务器: mysql"
echo "  用户名: root"
echo "  密码: 请查看 .env 文件中的 DB_ROOT_PASSWORD"
echo ""
echo "========================================="
echo "常用命令："
echo "========================================="
echo "查看日志:       docker-compose logs -f app"
echo "查看容器状态:   docker-compose ps"
echo "停止服务:       docker-compose down"
echo "重启服务:       docker-compose restart"
echo "进入容器:       docker-compose exec app bash"
echo ""
echo "区块链命令:"
echo "执行任务:       docker-compose exec app php artisan blockchain:task"
echo "RPC 心跳:       docker-compose exec app php artisan blockchain:rpc-heartbeat"
echo ""
echo -e "${GREEN}部署成功！${NC}"
