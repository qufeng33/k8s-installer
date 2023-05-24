kubernetes_version=1.26.5

# 1. 安装lsb 用于判断当前系统版本
if [ -e "/usr/bin/yum" ]; then
  PM=yum
  if [ -e /etc/yum.repos.d/CentOS-Base.repo ] && grep -Eqi "release 6." /etc/redhat-release; then
    sed -i "s@centos/\$releasever@centos-vault/6.10@g" /etc/yum.repos.d/CentOS-Base.repo
    sed -i 's@centos/RPM-GPG@centos-vault/RPM-GPG@g' /etc/yum.repos.d/CentOS-Base.repo
    [ -e /etc/yum.repos.d/epel.repo ] && rm -f /etc/yum.repos.d/epel.repo
  fi
  if ! command -v lsb_release >/dev/null 2>&1; then
    if [ -e "/etc/euleros-release" ]; then
      yum -y install euleros-lsb
    elif [ -e "/etc/openEuler-release" -o -e "/etc/openeuler-release" ]; then
      if [ -n "$(grep -w '"20.03"' /etc/os-release)" ]; then
        rpm -Uvh https://repo.openeuler.org/openEuler-20.03-LTS-SP1/everything/aarch64/Packages/openeuler-lsb-5.0-1.oe1.aarch64.rpm
      else
        yum -y install openeuler-lsb
      fi
    elif [ -e "/etc/redhat-release" ]; then
      # 表示是centos Stream 9
      OS_TMP=$(cat /etc/redhat-release)
      if [ "${OS_TMP}" == "CentOS Stream release 9" ]; then
        PM=dnf
        dnf -y update && sudo dnf upgrade --refresh -y &&
          sudo dnf config-manager --set-enabled crb
        sudo dnf install \
          https://dl.fedoraproject.org/pub/epel/epel-release-latest-9.noarch.rpm \
          https://dl.fedoraproject.org/pub/epel/epel-next-release-latest-9.noarch.rpm
      else
        yum -y install redhat-lsb-core
      fi
    else
      yum -y install redhat-lsb-core
    fi
    clear
  fi
fi
if [ -e "/usr/bin/apt-get" ]; then
  PM=apt-get
  command -v lsb_release >/dev/null 2>&1 || {
    apt-get -y update >/dev/null
    apt-get -y install lsb-release
    clear
  }
fi
if command -v lsb_release >/dev/null 2>&1; then
  # Get OS Version
  OS=$(lsb_release -is)
  if [[ "${OS}" =~ ^CentOS$|^RedHat$|^Rocky$|^Fedora$|^Amazon$|^Alibaba$|^Aliyun$|^EulerOS$|^openEuler$|^CentOSStream$ ]]; then
    CentOS_ver=$(lsb_release -rs | awk -F. '{print $1}' | awk '{print $1}')
    [[ "${OS}" =~ ^Fedora$ ]] && [ ${CentOS_ver} -ge 19 ] >/dev/null 2>&1 && {
      CentOS_ver=7
      Fedora_ver=$(lsb_release -rs)
    }
    [[ "${OS}" =~ ^Amazon$|^Alibaba$|^Aliyun$|^EulerOS$|^openEuler$ ]] && CentOS_ver=7
  elif [[ "${OS}" =~ ^Debian$|^Deepin$|^Uos$|^Kali$ ]]; then
    Debian_ver=$(lsb_release -rs | awk -F. '{print $1}' | awk '{print $1}')
    [[ "${OS}" =~ ^Deepin$|^Uos$ ]] && [[ "${Debian_ver}" =~ ^20$ ]] && Debian_ver=10
    [[ "${OS}" =~ ^Kali$ ]] && [[ "${Debian_ver}" =~ ^202 ]] && Debian_ver=10
  elif [[ "${OS}" =~ ^Ubuntu$|^LinuxMint$|^elementary$ ]]; then
    Ubuntu_ver=$(lsb_release -rs | awk -F. '{print $1}' | awk '{print $1}')
    if [[ "${OS}" =~ ^LinuxMint$ ]]; then
      [[ "${Ubuntu_ver}" =~ ^18$ ]] && Ubuntu_ver=16
      [[ "${Ubuntu_ver}" =~ ^19$ ]] && Ubuntu_ver=18
      [[ "${Ubuntu_ver}" =~ ^20$ ]] && Ubuntu_ver=20
    fi
    if [[ "${OS}" =~ ^elementary$ ]]; then
      [[ "${Ubuntu_ver}" =~ ^5$ ]] && Ubuntu_ver=18
      [[ "${Ubuntu_ver}" =~ ^6$ ]] && Ubuntu_ver=20
    fi
  fi
  # Check OS Version
  if [ ${CentOS_ver} -lt 6 ] >/dev/null 2>&1 || [ ${Debian_ver} -lt 8 ] >/dev/null 2>&1 || [ ${Ubuntu_ver} -lt 14 ] >/dev/null 2>&1; then
    echo "${CFAILURE}不支持此系统, 请安装 CentOS 7+,Debian 10+,Ubuntu 18+ ${CEND}"
    kill -9 $$
  fi
else
  # centos stream 9
  if [ -e "/etc/redhat-release" ]; then
    OS_TMP=$(cat /etc/redhat-release)
    if [ "${OS_TMP}" == "CentOS Stream release 9" ]; then
      CentOS_ver=9
      OS='CentOS Stream release 9'
      PM=dnf
    fi
  else
    echo "${CFAILURE}${PM} source failed! ${CEND}"
    kill -9 $$
  fi
fi

function detect_host_info() {
  HOST_PLATFORM=${HOST_PLATFORM_OVERRIDE:-"$(uname -s)"}
  case "${HOST_PLATFORM}" in
    Linux|linux)
      HOST_PLATFORM="linux"
      ;;
    *)
      echo "Unknown, unsupported platform: ${HOST_PLATFORM}." >&2
      echo "Supported platform(s): linux." >&2
      echo "Bailing out." >&2
      exit 2
  esac
  HOST_ARCH=${HOST_ARCH_OVERRIDE:-"$(uname -m)"}
  case "${HOST_ARCH}" in
    x86_64*|i?86_64*|amd64*)
      HOST_ARCH="amd64"
      ;;
    aHOST_arch64*|aarch64*|arm64*)
      HOST_ARCH="arm64"
      ;;
    *)
      echo "Unknown, unsupported architecture (${HOST_ARCH})." >&2
      echo "Supported architecture(s): amd64 and arm64." >&2
      echo "Bailing out." >&2
      exit 2
      ;;
  esac
}
detect_host_info

ARCH=$(uname -m)
VERSION=$(lsb_release -ds)


# 2. 根据当前系统，架构和版本是否支持安装 kubernetes,如果不符合要求，立即退出
if [[ "$OS" == @(Debian|Ubuntu|openEuler)* ]] && [[ "$ARCH" == @(x86_64|arm64)* ]]; then
  echo "系统类型: $OS"
  echo "系统架构: $ARCH"
  echo "Kubernetes 安装条件符合要求"
else
  echo "无法识别该系统，请手动配置"
  exit 1
fi

# 3. 关闭防火墙、selinux和swap，配置时间同步
if [[ "$OS" =~ ^(CentOS|Fedora|openEuler|Red\s?Hat) ]]; then
  sudo systemctl stop firewalld
  sudo systemctl disable firewalld
fi
sudo setenforce 0
sudo sed -i 's/^SELINUX=.*/SELINUX=disabled/' /etc/selinux/config
sudo swapoff -a
sudo sed -i '/ swap / s/^/#/' /etc/fstab
timedatectl set-ntp true

# 4. 根据当前系统，架构和版本，更换应用源，使用阿里云的源，并更新源
echo "更新应用源"
if [[ "$OS" =~ ^(Ubuntu|Debian) ]]; then
  sudo cp /etc/apt/sources.list /etc/apt/sources.list.bak
  sudo sed -i 's/archive.ubuntu.com/mirrors.aliyun.com/g' /etc/apt/sources.list
  sudo sed -i 's/security.ubuntu.com/mirrors.aliyun.com/g' /etc/apt/sources.list
  sudo $PM update
elif [[ "$OS" =~ ^(CentOS|Fedora|Red\s?Hat) ]]; then
  sudo $PM install -y epel-release
  sudo sed -i 's/download.fedoraproject.org/pub.ezbox.cc/g' /etc/yum.repos.d/epel.repo
  sudo sed -i 's/mirrorlist=https/mirrorlist=http/g' /etc/yum.repos.d/epel.repo
  sudo $PM makecache
elif [[ "$OS" =~ .*openEuler.*  ]]; then
  cp /etc/yum.repos.d/openEuler.repo /etc/yum.repos.d/openEuler.repo.backup
  sed -i "s#repo.openeuler.org#mirrors.aliyun.com/openeuler#g" /etc/yum.repos.d/openEuler.repo
  sudo $PM makecache
else
  echo "无法识别该系统，请手动配置"
  exit 1
fi


# 5. 配置内核参数，转发 IPv4 并让 iptables 看到桥接流量, 并确认
echo "添加ipv4转发"
echo 1 > /proc/sys/net/ipv4/ip_forward
cat <<EOF | sudo tee /etc/sysctl.d/k8s.conf
net.bridge.bridge-nf-call-ip6tables = 1
net.bridge.bridge-nf-call-iptables = 1
net.ipv4.ip_forward = 1
EOF
sudo sysctl --system


# 6. 加载 br_netfilter 和 overlay 模块，并确认
echo "加载 br_netfilter 和 overlay 模块"
sudo modprobe br_netfilter
sudo modprobe overlay
sudo lsmod | grep -E 'br_netfilter|overlay'


# 7. 安装 containerd / runc / CNI plugins
function install_runtime() {
    echo "安装 containerd"
    containerd_version=$(curl --silent "https://api.github.com/repos/containerd/containerd/releases/latest" | grep '"tag_name":' | sed -E 's/.*"([^"]+)".*/\1/')
    echo "containerd 最新版本号为：$containerd_version"
    containerd_package=containerd-${containerd_version:1}-linux-${HOST_ARCH}.tar.gz

    wget https://ghproxy.com/https://github.com/containerd/containerd/releases/download/${containerd_version}/$containerd_package
    tar Cxzvf /usr/local $containerd_package
    if [ ! -d /etc/containerd/  ];then
        mkdir /etc/containerd/
    fi
    containerd config default > /etc/containerd/config.toml
    sed -i 's/config_path\ =.*/config_path = \"\/etc\/containerd\/certs.d\"/g' /etc/containerd/config.toml
    sed -i 's#SystemdCgroup = false#SystemdCgroup = true#g' /etc/containerd/config.toml
    sed -i 's/sandbox_image\ =.*/sandbox_image\ =\ "registry.aliyuncs.com\/google_containers\/pause:3.9"/g' /etc/containerd/config.toml|grep sandbox_image
    wget -c -O /etc/systemd/system/containerd.service https://ghproxy.com/https://raw.githubusercontent.com/containerd/containerd/main/containerd.service



    echo "安装 runc"
    runc_version=$(curl --silent "https://api.github.com/repos/opencontainers/runc/releases/latest" | grep '"tag_name":' | sed -E 's/.*"([^"]+)".*/\1/')
    echo "runc 最新版本号为：$runc_version"
    runc_package=runc.${HOST_ARCH}
    wget https://ghproxy.com/https://github.com/opencontainers/runc/releases/download/${runc_version}/$runc_package
    install -m 755 $runc_package /usr/local/sbin/runc

    echo "安装 CNI plugins"
    cni_version=$(curl --silent "https://api.github.com/repos/containernetworking/plugins/releases/latest" | grep '"tag_name":' | sed -E 's/.*"([^"]+)".*/\1/')
    echo "cni 最新版本号为：$cni_version"
    cni_package=cni-plugins-linux-${HOST_ARCH}-${cni_version}.tgz
    wget https://ghproxy.com/https://github.com/containernetworking/plugins/releases/download/${cni_version}/$cni_package
    mkdir -p /opt/cni/bin
    tar Cxzvf /opt/cni/bin $cni_package
}

install_runtime


# 7. 配置镜像加速
if [ ! -d /etc/containerd/certs.d  ];then
  mkdir /etc/containerd/certs.d
fi
if [ ! -d /etc/containerd/certs.d/docker.io ];then
  mkdir /etc/containerd/certs.d/docker.io
fi
cat > /etc/containerd/certs.d/docker.io/hosts.toml << EOF
server = “https://docker.io”
[host.“docker.m.daocloud.io”]
  capabilities = [“pull”, “resolve”]
[host.“https://docker.mirrors.ustc.edu.cn”]
  capabilities = [“pull”, “resolve”]
EOF
mkdir -p /etc/containerd/certs.d/gcr.io
cat > /etc/containerd/certs.d/gcr.io/hosts.toml << EOF
server = “https://gcr.io”
[host.“https://gcr.m.daocloud.io”]
  capabilities = [“pull”, “resolve”]
EOF
mkdir -p /etc/containerd/certs.d/k8s.gcr.io
cat > /etc/containerd/certs.d/k8s.gcr.io/hosts.toml << EOF
server = “https://k8s.gcr.io”
[host.“https://k8s-gcr.m.daocloud.io”]
  capabilities = [“pull”, “resolve”]
EOF
mkdir -p /etc/containerd/certs.d/quay.io
cat > /etc/containerd/certs.d/quay.io/hosts.toml << EOF
server = “https://quay.io”
[host.“https://quay.m.daocloud.io”]
  capabilities = [“pull”, “resolve”]
EOF
mkdir -p /etc/containerd/certs.d/registry.k8s.io
cat > /etc/containerd/certs.d/registry.k8s.io/hosts.toml << EOF
server = “https://registry.k8s.io”
[host.“https://k8s.m.daocloud.io”]
  capabilities = [“pull”, “resolve”]
EOF
systemctl start containerd && systemctl enable containerd



# 8. 安装 kubelet kubeadm kubectl
if [[ "$OS" =~ ^(Ubuntu|Debian) ]]; then
  sudo apt-get update && apt-get install -y apt-transport-https
  sudo curl https://mirrors.aliyun.com/kubernetes/apt/doc/apt-key.gpg | apt-key add - 
  cat <<EOF >/etc/apt/sources.list.d/kubernetes.list
deb https://mirrors.aliyun.com/kubernetes/apt/ kubernetes-xenial main
EOF
  sudo apt-get update
  sudo apt-get install -y apt-transport-https ca-certificates curl
  sudo apt-get install -y kubelet-$kubernetes_version kubeadm-$kubernetes_version kubectl-$kubernetes_version
  sudo apt-mark hold kubelet kubeadm kubectl
elif [[ "$OS" =~ ^(CentOS|Fedora|openEuler|Red\s?Hat) ]]; then
  cat <<EOF > /etc/yum.repos.d/kubernetes.repo
[kubernetes]
name=Kubernetes
baseurl=https://mirrors.aliyun.com/kubernetes/yum/repos/kubernetes-el7-x86_64/
enabled=1
gpgcheck=1
repo_gpgcheck=1
gpgkey=https://mirrors.aliyun.com/kubernetes/yum/doc/yum-key.gpg https://mirrors.aliyun.com/kubernetes/yum/doc/rpm-package-key.gpg
EOF
  sudo yum update -y
  echo "kubelet-$kubernetes_version"
  sudo yum install -y kubelet-$kubernetes_version kubeadm-$kubernetes_version kubectl-$kubernetes_version --disableexcludes=kubernetes
  sudo systemctl enable --now kubelet
else
  echo "无法识别该系统，请手动配置"
  exit 1
fi