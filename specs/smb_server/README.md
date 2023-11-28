# Deploy SMB server

The [setup_smb_server.sh](./setup_smb_server.sh) deploys SMB server using [specs](./base) and configurable storage
class and storage size.

### Usage

```shell
bash setup_smb_server.sh <ACTION> <STORAGE_CLASS TO USE> <SIZE OF STORAGE TO PROVISION> <NAMESPACE TO DEPLOY SMB SERVER> <SMB_USERNAME> <SMB_PASSWORD>
```

To deploy the SMB server provide `ACTION=apply`, to destroy supply `ACTION=delete`.