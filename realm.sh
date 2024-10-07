#!/bin/bash

# 检查realm是否已安装
if [ -f "/root/realm/realm" ]; then
    echo "检测到realm已安装。"
    realm_status="已安装"
    realm_status_color="\033[0;32m" # 绿色
else
    echo "realm未安装。"
    realm_status="未安装"
    realm_status_color="\033[0;31m" # 红色
fi

# 检查realm服务状态
check_realm_service_status() {
    if systemctl is-active --quiet realm; then
        echo -e "\033[0;32m启用\033[0m" # 绿色
    else
        echo -e "\033[0;31m未启用\033[0m" # 红色
    fi
}

# 显示菜单的函数
show_menu() {
    clear
    echo "欢迎使用realm一键转发脚本"
    echo "realm版本v2.6.2"
    echo "修改by：Azimi"
    echo "========================"
    echo "1. 安装realm"
    echo "——————————————————"
    echo "2. 添加realm转发"
    echo "3. 查看realm转发"
    echo "4. 删除realm转发"
    echo "——————————————————"
    echo "5. 启动realm服务"
    echo "6. 停止realm服务"
    echo "——————————————————"
    echo "7. 卸载realm"
    echo "——————————————————"
    echo "8. 定时重启任务"
    echo "——————————————————"
    echo "9. 退出脚本"
    echo "========================"
    echo -e "realm 状态：${realm_status_color}${realm_status}\033[0m"
    echo -n "realm 转发状态："
    check_realm_service_status
}

# 部署环境的函数
deploy_realm() {
    mkdir -p /root/realm
    cd /root/realm
    wget -O realm.tar.gz https://github.com/zhboner/realm/releases/download/v2.6.2/realm-x86_64-unknown-linux-gnu.tar.gz
    tar -xvf realm.tar.gz
    chmod +x realm
    # 创建服务文件
    echo "[Unit]
Description=realm
After=network-online.target
Wants=network-online.target systemd-networkd-wait-online.service

[Service]
Type=simple
User=root
Restart=on-failure
RestartSec=5s
DynamicUser=true
WorkingDirectory=/root/realm
ExecStart=/root/realm/realm -c /root/realm/config.toml

[Install]
WantedBy=multi-user.target" > /etc/systemd/system/realm.service
    systemctl daemon-reload
    # 更新realm状态变量
    realm_status="已安装"
    realm_status_color="\033[0;32m" # 绿色
    echo "部署完成。"
}

# 卸载realm
uninstall_realm() {
    systemctl stop realm
    systemctl disable realm
    rm -rf /etc/systemd/system/realm.service
    systemctl daemon-reload
    rm -rf /root/realm
    rm -rf "$(pwd)"/realm.sh
    echo "realm已被卸载。"
    # 更新realm状态变量
    realm_status="未安装"
    realm_status_color="\033[0;31m" # 红色
}

# 删除转发规则的函数
delete_forward() {
    echo "当前转发规则："
    local IFS=$'\n' # 设置IFS仅以换行符作为分隔符
    local lines=($(grep -n 'listen =' /root/realm/config.toml)) # 搜索所有包含 listen 的行
    if [ ${#lines[@]} -eq 0 ]; then
        echo "没有发现任何转发规则。"
        return
    fi
    local index=1
    for line in "${lines[@]}"; do
        local line_number=$(echo $line | cut -d ':' -f 1)  # 获取 listen 行的行号
        local listen_info=$(sed -n "${line_number}p" /root/realm/config.toml | cut -d '"' -f 2)  # 获取 listen 信息
        local remote_info=$(sed -n "$((line_number + 1))p" /root/realm/config.toml | cut -d '"' -f 2)  # 获取 remote 信息
        local remark=$(sed -n "$((line_number-1))p" /root/realm/config.toml | grep "^# 备注:" | cut -d ':' -f 2-)  # 获取备注

        # 在一行中显示备注、监听端口和远程地址信息
        if [ -n "$remark" ]; then
            echo "${index}. 备注: ${remark}, listen: ${listen_info}, remote: ${remote_info}"
        else
            echo "${index}. listen: ${listen_info}, remote: ${remote_info}"
        fi
        let index+=1
    done

    echo "请输入要删除的转发规则序号，直接按回车返回主菜单。"
    read -p "选择: " choice
    if [ -z "$choice" ]; then
        echo "返回主菜单。"
        return
    fi

    if ! [[ $choice =~ ^[0-9]+$ ]]; then
        echo "无效输入，请输入数字。"
        return
    fi

    if [ $choice -lt 1 ] || [ $choice -gt ${#lines[@]} ]; then
        echo "选择超出范围，请输入有效序号。"
        return
    fi

    local chosen_line=${lines[$((choice-1))]} # 根据用户选择获取相应行
    local line_number=$(echo $chosen_line | cut -d ':' -f 1) # 获取 listen 行号

    # 找到当前规则的 [[endpoints]] 所在行
    local endpoints_line=$(grep -B 1 "^listen" /root/realm/config.toml | grep -n '^\[\[endpoints\]\]' | awk -F: -v line_number=$line_number '$1 < line_number {print $1}' | tail -n 1)

    # 如果没有找到[[endpoints]]行，说明格式可能有问题
    if [ -z "$endpoints_line" ]; then
        echo "未能找到匹配的[[endpoints]]，请检查配置文件格式。"
        return
    fi

    # 计算要删除的范围，从[[endpoints]]开始到 remote 行结束
    local start_line=$endpoints_line
    local end_line=$(($line_number + 1))

    # 如果有备注，范围从备注开始
    local prev_line=$((start_line-1))
    local prev_content=$(sed -n "${prev_line}p" /root/realm/config.toml | grep "^# 备注:")
    if [ -n "$prev_content" ]; then
        start_line=$prev_line  # 如果有备注，从备注那一行开始删除
    fi

    # 使用 sed 删除选中的转发规则和备注
    sed -i "${start_line},${end_line}d" /root/realm/config.toml

    echo "转发规则及其备注已删除。"
}



#查看转发规则
show_all_conf() {
    echo "当前转发规则："
    local IFS=$'\n' # 设置IFS仅以换行符作为分隔符
    local lines=($(grep -n 'listen =' /root/realm/config.toml)) # 搜索所有包含 listen 的行
    if [ ${#lines[@]} -eq 0 ]; then
        echo "没有发现任何转发规则。"
        return
    fi
    local index=1
    for line in "${lines[@]}"; do
        local line_number=$(echo $line | cut -d ':' -f 1)  # 获取 listen 行的行号
        local listen_info=$(sed -n "${line_number}p" /root/realm/config.toml | cut -d '"' -f 2)  # 获取 listen 信息
        local remote_info=$(sed -n "$((line_number + 1))p" /root/realm/config.toml | cut -d '"' -f 2)  # 获取 remote 信息
        local remark=$(sed -n "$((line_number-1))p" /root/realm/config.toml | grep "^# 备注:" | cut -d ':' -f 2-)  # 获取备注

        # 在一行内显示备注、监听端口和远程IP信息
        if [ -n "$remark" ]; then
            echo "${index}. 备注: ${remark}, listen: ${listen_info}, remote: ${remote_info}"
        else
            echo "${index}. listen: ${listen_info}, remote: ${remote_info}"
        fi
        let index+=1
    done
}


# 添加转发规则
add_forward() {
    while true; do
        read -p "请输入本地监听端口: " local_port
        read -p "请输入需要转发的IP地址: " ip
        read -p "请输入需要转发IP的端口: " port
        read -p "请输入备注: " remark

        # 追加到 config.toml 文件，包括备注
        echo "# 备注: $remark
[[endpoints]]
listen = \"0.0.0.0:$local_port\"
remote = \"$ip:$port\"" >> /root/realm/config.toml

        read -p "是否继续添加(Y/N)? " answer
        if [[ $answer != "Y" && $answer != "y" ]]; then
            break
        fi
    done
}


# 启动服务
start_service() {
    sudo systemctl unmask realm.service
    sudo systemctl daemon-reload
    sudo systemctl restart realm.service
    sudo systemctl enable realm.service
    echo "realm服务已启动并设置为开机自启。"
}

# 停止服务
stop_service() {
    systemctl stop realm
    echo "realm服务已停止。"
}

# 定时任务
cron_restart() {
  echo -e "------------------------------------------------------------------"
  echo -e "gost定时重启任务: "
  echo -e "-----------------------------------"
  echo -e "[1] 配置gost定时重启任务"
  echo -e "[2] 删除gost定时重启任务"
  echo -e "-----------------------------------"
  read -p "请选择: " numcron
  if [ "$numcron" == "1" ]; then
    echo -e "------------------------------------------------------------------"
    echo -e "gost定时重启任务类型: "
    echo -e "-----------------------------------"
    echo -e "[1] 每？小时重启"
    echo -e "[2] 每日？点重启"
    echo -e "-----------------------------------"
    read -p "请选择: " numcrontype
    if [ "$numcrontype" == "1" ]; then
      echo -e "-----------------------------------"
      read -p "每？小时重启: " cronhr
      echo "0 0 */$cronhr * * ? * systemctl restart realm" >>/etc/crontab
      echo -e "定时重启设置成功！"
    elif [ "$numcrontype" == "2" ]; then
      echo -e "-----------------------------------"
      read -p "每日？点重启: " cronhr
      echo "0 0 $cronhr * * ? systemctl restart realm" >>/etc/crontab
      echo -e "定时重启设置成功！"
    else
      echo "输入错误，请重试"
      exit
    fi
  elif [ "$numcron" == "2" ]; then
    sed -i "/realm/d" /etc/crontab
    echo -e "定时重启任务删除完成！"
  else
    echo "输入错误，请重试"
    exit
  fi
}

# 主循环
while true; do
    show_menu
    read -p "请选择一个选项: " choice
    # 去掉输入中的空格
    choice=$(echo $choice | tr -d '[:space:]')

    # 检查输入是否为数字，并在有效范围内
    if ! [[ "$choice" =~ ^[1-9]$ ]]; then
        echo "无效选项: $choice"
        continue
    fi

    case $choice in
        1)
            deploy_realm
            ;;
        2)
            add_forward
            ;;
        3)
            show_all_conf
            ;;
        4)
            delete_forward
            ;;
        5)
            start_service
            ;;
        6)
            stop_service
            ;;
        7)
            uninstall_realm
            ;;
        8)
            cron_restart
            ;;  
        9)
            echo "退出脚本。"  # 显示退出消息
            exit 0            # 退出脚本
            ;;
        *)
            echo "无效选项: $choice"
            ;;
    esac
    read -p "按任意键继续..." key
done
