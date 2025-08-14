Repository to maintain Lightbeam cluster installer related scripts


### Ubuntu

####  For CPU cluster deployment

```bash
bash k8s-init.sh
setup-ubuntu-vm.sh
```

####  For GPU cluster deployment

```bash
bash k8s-init.sh
bash setup-ubuntu-vm-gpu.sh
```


#### Troubleshooting
- Run `kubeadm reset`
- Run `rm ~/.kube/config`
- Reboot the system
- Follow the above steps to install the cluster again.