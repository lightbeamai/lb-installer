#!/usr/bin/env bash

while getopts d:p: flag
do
    case "${flag}" in
        d) install_docker=${OPTARG};;
        p) docker_diskpath=${OPTARG};;
    esac
done
: ${install_docker:="false"}
: ${docker_diskpath:="/var/lib/docker"}
echo "install_docker: $install_docker";
echo "docker_diskpath: $docker_diskpath";

if [ $install_docker = "true" ]; then
        echo 'Installing docker..'
        sudo dnf config-manager --add-repo=https://download.docker.com/linux/centos/docker-ce.repo
        sudo dnf install --nobest -y docker-ce
        sudo systemctl enable --now docker
        systemctl is-active docker
        systemctl is-enabled docker
  if [ $docker_diskpath != "/var/lib/docker" ]; then
cat <<EOF | sudo tee /etc/docker/daemon.json
{
  "data-root": "$docker_diskpath"
}
EOF
systemctl daemon-reload && systemctl restart docker
  fi
else
  echo "Installing podman podman-docker iproute-tc"
  sudo yum install -y iproute-tc podman podman-docker vim
  systemctl start podman
  systemctl enable podman
fi


# Create the .conf file to load the modules at bootup
cat <<EOF | sudo tee /etc/modules-load.d/k8s.conf
overlay
br_netfilter
EOF

sudo modprobe overlay
sudo modprobe br_netfilter

# Set up required sysctl params, these persist across reboots.
cat <<EOF | sudo tee /etc/sysctl.d/k8s.conf
net.bridge.bridge-nf-call-iptables  = 1
net.ipv4.ip_forward                 = 1
net.bridge.bridge-nf-call-ip6tables = 1
EOF

sudo sysctl --system
setenforce 0
sed -i --follow-symlinks 's/SELINUX=enforcing/SELINUX=disabled/g' /etc/sysconfig/selinux
echo '1' > /proc/sys/net/bridge/bridge-nf-call-iptables

# Disable Swap Permanently.
swapoff -a                 # Disable all devices marked as swap in /etc/fstab.
sed -e '/swap/ s/^#*/#/' -i /etc/fstab   # Comment the correct mounting point.
systemctl mask swap.target               # Completely disabled.

sudo setenforce 0
sudo sed -i 's/^SELINUX=enforcing$/SELINUX=permissive/' /etc/selinux/config
systemctl disable firewalld
systemctl status firewalld

export VERSION=1.28
sudo curl -L -o /etc/yum.repos.d/devel:kubic:libcontainers:stable.repo https://download.opensuse.org/repositories/devel:/kubic:/libcontainers:/stable/CentOS_8/devel:kubic:libcontainers:stable.repo
sudo curl -L -o /etc/yum.repos.d/devel:kubic:libcontainers:stable:cri-o:$VERSION.repo https://download.opensuse.org/repositories/devel:kubic:libcontainers:stable:cri-o:$VERSION/CentOS_8/devel:kubic:libcontainers:stable:cri-o:$VERSION.repo
sudo yum install cri-o -y
systemctl start crio

TIMEOUT=300
SLEEP_INTERVAL=1

export dotCount=0
export maxDots=15
function showMessage() { # This function prints dots with message and used in a loop while waiting for a condition.
  msg=$1
  dc=$dotCount
  if [ $dc = 0 ]; then
    i=0
    len=${#msg}
    len=$[$len+$maxDots]
    b=""
    while [ $i -ne $len ]
    do
      b="$b "
      i=$[$i+1]
    done
    echo -e -n "\r$b"
    dc=1
  else
    msg="$msg"
    i=0
    while [ $i -ne $dc ]
    do
      msg="$msg."
      i=$[$i+1]
    done
    dc=$[$dc+1]
    if [ $dc = $maxDots ]; then
      dc=0
    fi
  fi
  export dotCount=$dc
  echo -e -n "\r$msg"
}

function serviceStatusCheck() {
    # This function checks service is active or inactive.
    timeCheck=0
    while true
      do
        service=$1
        exit_required=$2
        DOCKER_SERVICE_STATUS="$(systemctl is-active $service)"
        if [ "${DOCKER_SERVICE_STATUS}" = "active" ]; then
          echo ""
          echo "$service running.."
          break
        fi
        showMessage "$service status check"
        sleep $SLEEP_INTERVAL
        timeCheck=$[timeCheck+$SLEEP_INTERVAL]
        if [ $timeCheck -gt $TIMEOUT ]; then
          echo ""
          echo "$service not running, Timeout error."
          echo ""
          if [ "${exit_required}" = "True" ]; then
            exit 1
          fi
        fi
      done
}

sudo systemctl enable --now crio
sudo systemctl start crio

sudo podman image trust set -f /etc/pki/rpm-gpg/RPM-GPG-KEY-redhat-release registry.access.redhat.com
sudo podman image trust set -f /etc/pki/rpm-gpg/RPM-GPG-KEY-redhat-release registry.redhat.io

cat <<EOF > /etc/containers/registries.d/registry.access.redhat.com.yaml
docker:
     registry.access.redhat.com:
         sigstore: https://access.redhat.com/webassets/docker/content/sigstore
EOF

cat <<EOF > /etc/containers/registries.d/registry.redhat.io.yaml
docker:
     registry.redhat.io:
         sigstore: https://registry.redhat.io/containers/sigstore
EOF

cat <<EOF | tee /etc/yum.repos.d/kubernetes.repo
[kubernetes]
name=Kubernetes
baseurl=https://pkgs.k8s.io/core:/stable:/v$VERSION/rpm/
enabled=1
gpgcheck=1
gpgkey=https://pkgs.k8s.io/core:/stable:/v$VERSION/rpm/repodata/repomd.xml.key
exclude=kubelet kubeadm kubectl cri-tools kubernetes-cni
EOF

dnf makecache
dnf install -y kubelet kubeadm kubectl --disableexcludes=kubernetes

sudo systemctl enable --now kubelet
sudo systemctl start kubelet &
serviceStatusCheck "kubelet.service" "False"
echo "kubelet Service is $(systemctl is-active kubelet)"
echo "kubeadm reset"
sudo yes | kubeadm reset

if [ $install_docker = "true" ]; then
  sudo kubeadm init --pod-network-cidr=192.168.0.0/16 --cri-socket /var/run/dockershim.sock
else
  sudo kubeadm init --pod-network-cidr=192.168.0.0/16
fi

mkdir -p /root/.kube
sudo yes | cp -f /etc/kubernetes/admin.conf /root/.kube/config
sudo chown $(id -u):$(id -g) /root/.kube/config

kubectl taint nodes --all node-role.kubernetes.io/master-

if [ $install_docker = "true" ]; then
  kubectl apply -f https://docs.projectcalico.org/v3.9/manifests/calico-typha.yaml
else
  kubectl create -f https://raw.githubusercontent.com/projectcalico/calico/v3.26.1/manifests/tigera-operator.yaml
  kubectl create -f https://raw.githubusercontent.com/projectcalico/calico/v3.26.1/manifests/custom-resources.yaml
fi

echo "3. Setup helm"
sudo curl -L -O https://get.helm.sh/helm-v3.13.1-linux-amd64.tar.gz && sudo tar -xvf helm-v3.13.1-linux-amd64.tar.gz && sudo mv linux-amd64/helm /usr/bin/ && sudo rm helm-v3.13.1-linux-amd64.tar.gz
helm version

# Setup python3.
sudo cp /usr/bin/python3 /usr/bin/python
sudo dnf install -y python3-pip wget git

# At times coredns isn't functioning after installing the networking plugins. So restart it.
kubectl -n kube-system rollout restart deployment coredns

cat <<'EOF' > /usr/local/bin/lightbeam.sh
#!/usr/bin/env bash

trap 'kill $(jobs -p)' EXIT

/usr/bin/kubectl port-forward service/kong-proxy -n lightbeam --address 0.0.0.0 80:80 --kubeconfig /root/.kube/config &
PID1=$!

/usr/bin/kubectl port-forward service/kong-proxy -n lightbeam --address 0.0.0.0 443:443 --kubeconfig /root/.kube/config &
PID2=$!

/bin/systemd-notify --ready

while true; do
    FAIL=0

    kill -0 $PID1
    if [[ $? -ne 0 ]]; then FAIL=1; fi

    kill -0 $PID2
    if [[ $? -ne 0 ]]; then FAIL=1; fi

    status_code=$(curl -s -o /dev/null -w "%{http_code}" http://localhost/api/health)
    echo "Lightbeam cluster health check: $status_code"
    if [[ $? -ne 0 || $status_code -ne 200 ]]; then FAIL=1; fi

    if [[ $FAIL -eq 0 ]]; then /bin/systemd-notify WATCHDOG=1; fi

    sleep 1
done
EOF

echo "Script /usr/local/bin/lightbeam.sh has been created."
chmod ugo+x /usr/local/bin/lightbeam.sh

cat <<EOF > /etc/systemd/system/lightbeam.service
[Unit]
Description=LightBeam Application
After=network-online.target
Wants=network-online.target systemd-networkd-wait-online.service

StartLimitIntervalSec=500
StartLimitBurst=10000

[Service]
Type=notify
Restart=always
RestartSec=1
TimeoutSec=5
WatchdogSec=5
ExecStart=/usr/local/bin/lightbeam.sh

[Install]
WantedBy=multi-user.target
EOF

echo "Systemd service file /etc/systemd/system/lightbeam.service has been created."

# Reload systemd, enable and start the service
systemctl daemon-reload
systemctl enable lightbeam.service
systemctl start lightbeam.service

echo "Done! Ready to deploy LightBeam Cluster!!"
