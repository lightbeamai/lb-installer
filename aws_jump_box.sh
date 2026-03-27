#!/usr/bin/env bash

sudo apt-get update
sudo apt-get install -y unzip jq

curl -LO "https://dl.k8s.io/release/v1.32.1/bin/linux/amd64/kubectl"
sudo chmod +x kubectl
sudo mv kubectl /usr/local/bin/
kubectl version

wget https://get.helm.sh/helm-v3.13.1-linux-amd64.tar.gz
tar -xvf helm-v3.13.1-linux-amd64.tar.gz
sudo mv linux-amd64/helm /usr/local/bin/

# Install docker.
sudo apt-get -y remove docker docker-engine docker.io containerd runc
sudo apt-get update -y
sudo apt-get install -y \
    apt-transport-https \
    ca-certificates \
    curl \
    gnupg-agent \
    software-properties-common

curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo apt-key add -

sudo add-apt-repository \
   "deb [arch=amd64] https://download.docker.com/linux/ubuntu \
   $(lsb_release -cs) \
   stable"

sudo apt-get update -y
sudo apt-get install docker-ce docker-ce-cli containerd.io -y
docker_status=`systemctl status docker | grep "running" | wc -l`
echo "$docker_status"
if [ $docker_status == 1 ]; then
   echo "Docker installed and running .."
else
   echo "Docker installed but not running.."
fi

# Setup terraform CLI.
sudo apt-get update && sudo apt-get install -y gnupg software-properties-common curl
curl -fsSL https://apt.releases.hashicorp.com/gpg | sudo apt-key add -
sudo apt-add-repository "deb [arch=amd64] https://apt.releases.hashicorp.com $(lsb_release -cs) main"
sudo apt-get update && sudo apt-get install -y terraform=v1.3.7

# Setup aws cli.
curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip"
unzip awscliv2.zip
sudo ./aws/install
aws --version

# Setup python3.
sudo cp /usr/bin/python3 /usr/bin/python
sudo apt install -y python3-pip

# Ensure bash-completion is available
if ! type _init_completion >/dev/null 2>&1; then
    # Try to install if system is Debian/Ubuntu
    if [ -f /etc/debian_version ]; then
        echo "Installing bash-completion..."
        apt-get update -y
        apt-get install -y bash-completion
    else
        echo "bash-completion not installed and cannot auto-install."
    fi
fi

# Load bash-completion if present
if [ -f /etc/bash_completion ]; then
    . /etc/bash_completion
elif [ -f /usr/share/bash-completion/bash_completion ]; then
    . /usr/share/bash-completion/bash_completion
fi

# Enable kubectl autocompletion
if command -v kubectl >/dev/null 2>&1; then
    source <(kubectl completion bash)
else
    echo "kubectl not found in PATH. Autocomplete not enabled."
fi

apt install python3-pip python3-virtualenv -y 

# Optional: Add 'k' alias
alias k=kubectl
complete -o default -F __start_kubectl k

# Create Lightbeam systemd service and script
tee /usr/local/bin/lightbeam.sh > /dev/null <<'EOF'
#!/usr/bin/env bash

trap 'kill $(jobs -p)' EXIT
/usr/bin/kubectl port-forward service/kong-proxy -n lightbeam --address 0.0.0.0 80:80 443:443 --kubeconfig /root/.kube/config &
PID=$!

/bin/systemd-notify --ready

while(true); do
    FAIL=0
    kill -0 $PID
    if [[ $? -ne 0 ]]; then FAIL=1; fi

    status_code=$(curl -s -o /dev/null -w "%{http_code}" http://localhost/api/health)
    curl_exit=$?
    echo "Lightbeam cluster health check: $status_code (curl exit: $curl_exit)"
    if [[ $curl_exit -ne 0 || ( $status_code -ne 200 && $status_code -ne 301 ) ]]; then
        FAIL=1
    fi

    if [[ $FAIL -eq 0 ]]; then /bin/systemd-notify WATCHDOG=1; fi
    sleep 1
done
EOF
chmod ugo+x /usr/local/bin/lightbeam.sh

tee /etc/systemd/system/lightbeam.service > /dev/null <<'EOF'
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

# Mark packages on hold to avoid an auto upgrade.
apt-mark hold kubelet
apt-mark hold kubectl
apt-mark hold kubeadm
apt-mark hold containerd.io
apt-mark hold docker-buildx-plugin
apt-mark hold docker-ce
apt-mark hold docker-ce-cli
apt-mark hold docker-ce-rootless-extras
apt-mark hold docker-compose-plugin
apt-mark hold snapd
apt-mark hold systemd
apt-mark hold systemd-sysv
apt-mark hold systemd-timesyncd
