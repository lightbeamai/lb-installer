## Repository to maintain Lightbeam cluster installer related scripts

## Running the SMB permission checker

This repository includes a small utility to test read access to SMB/CIFS shares:
- Script: `smb_user_check_permission/smb_checker.py`
- Purpose: lists shares on an SMB server and attempts a read/list on each to report whether the provided user has read access.

Prerequisites
-------------
- Python 3.8+ (python3)
- pip
- Network access to the SMB server (TCP port 445 must be reachable)
- Optional: a virtual environment for installing dependencies

Install dependencies
--------------------
From the repository root run:

```bash
cd smb_user_check_permission
python3 -m venv .venv        # optional
source .venv/bin/activate   # optional
pip install -r requirements.txt
```

If you don't want to use a virtualenv, run the `pip install -r ...` command directly (you may need sudo depending on your environment).

Usage
-----

The script accepts the server, username and password. The username can include a domain using `user@domain` or `DOMAIN\\user` notation.

Examples:

```bash
# Test all shares on the server
python3 smb_user_check_permission/smb_checker.py \
	--server 192.168.1.1 \
	--username user@domain.com \
	--password 'YourSecretPassword'

# Test a single share (note the escaped backslash for DOMAIN\\user in bash)
python3 smb_user_check_permission/smb_checker.py -s 192.168.1.1 -u 'DOMAIN\\user' -p 'YourSecret' --share MyShare
```