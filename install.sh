#!/bin/bash

# 检查当前系统类型
if [[ $(uname -s) == "Linux" ]]; then
    if [[ -f /etc/os-release ]]; then
        source /etc/os-release
        if [[ $NAME == *"Ubuntu"* ]]; then
            os="ubuntu"
        elif [[ $ID == "debian" ]]; then
            os="debian"
        elif [[ $NAME == *"CentOS"* ]]; then
            os="centos"
        elif [[ $NAME == *"OpenEuler"* ]]; then
            os="openeuler"
        else
            echo "未知的linux版本"
            exit 1
        fi
    else
        echo "未知的linux版本"
        exit 1
    fi

    # 检查 CPU 架构
    ARCH=$(uname -m)
    if [[ $ARCH == "x86_64" ]]; then
        arch="x86_64"
    elif [[ $ARCH == "aarch64" ]]; then
        arch="arm64"
    else
        echo "不支持的系统架构"
        exit 1
    fi
else
    echo "不支持的系统架构"
    exit 1
fi

echo "OS: $os"
echo "Architecture: $arch"