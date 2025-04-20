#!/bin/bash

# 配置变量
LOCAL_CONFIG_DIR="/path/to/local/nginx/conf"  # 本地配置文件目录（需替换）
NODES_FILE="nodes.conf"                       # 节点列表文件路径
BACKUP_DIR="/opt/nginx_backups"               # 远程备份目录
LOG_FILE="nginx_sync.log"                     # 日志文件
RELOAD_NGINX=true                            # 是否重载Nginx（true/false）

# 检查本地配置目录是否存在
if [ ! -d "$LOCAL_CONFIG_DIR" ]; then
    echo "错误：本地配置目录 $LOCAL_CONFIG_DIR 不存在！" | tee -a $LOG_FILE
    exit 1
fi

sync_config() {
    local IP="$1"
    local USER="$2"
    local REMOTE_PATH="$3"

    echo "开始同步节点: $IP ($USER@$REMOTE_PATH)" | tee -a $LOG_FILE

    # 远程备份旧配置
    ssh -o StrictHostKeyChecking=no $USER@$IP "mkdir -p $BACKUP_DIR && mv -f $REMOTE_PATH ${BACKUP_DIR}/nginx_$(date +%Y%m%m%S)" 2>>$LOG_FILE
    if [ $? -ne 0 ]; then
        echo "备份失败: $IP" | tee -a $LOG_FILE
        return 1
    fi

    # 同步配置文件
    rsync -avz --delete --progress -e "ssh -o StrictHostKeyChecking=no" $LOCAL_CONFIG_DIR/ $USER@$IP:$REMOTE_PATH 2>>$LOG_FILE
    if [ $? -ne 0 ]; then
        echo "同步失败: $IP" | tee -a $LOG_FILE
        return 1
    fi

    # 设置权限（可选）
    ssh $USER@$IP "chmod -R 644 $REMOTE_PATH/*.conf && chown -R nginx:nginx $REMOTE_PATH" 2>>$LOG_FILE
    echo "配置同步完成: $IP" | tee -a $LOG_FILE
}

reload_nginx() {
    local IP="$1"
    local USER="$2"

    echo "尝试重载Nginx: $IP" | tee -a $LOG_FILE
    ssh -o StrictHostKeyChecking=no $USER@$IP "nginx -t && nginx -s reload" 2>>$LOG_FILE
    if [ $? -eq 0 ]; then
        echo "Nginx重载成功: $IP" | tee -a $LOG_FILE
    else
        echo "Nginx重载失败: $IP" | tee -a $LOG_FILE
    fi
}

# 主流程
echo "开始同步Nginx配置..." | tee -a $LOG_FILE
while IFS=: read -r IP USER REMOTE_PATH; do
    if [ -z "$IP" ] || [ -z "$USER" ] || [ -z "$REMOTE_PATH" ]; then
        echo "警告：节点配置格式错误（跳过）：$IP:$USER:$REMOTE_PATH" | tee -a $LOG_FILE
        continue
    fi

    sync_config "$IP" "$USER" "$REMOTE_PATH"
    if [ $? -eq 0 ] && [ "$RELOAD_NGINX" = true ]; then
        reload_nginx "$IP" "$USER"
    fi
done < "$NODES_FILE"

echo "所有节点同步完成！" | tee -a $LOG_FILE