### Steps to generate the Salesforce Refresh token
#### For Unix and MacOS Operating System
1. Login to Salesforce from an account with admin access.
2. Run script `bash generate-salesforce-refresh-token.sh`
3. Enter the value of `InstanceUrl`, `Consumer Key`, `Consumer Secret` and `redirect_uri` from the connected-app details.
4. Open the printed URL in the browser and accept the connected-app permissions.
5. Copy the `code` parameter from the redirected URL and paste it in the console.![Salesforce Code Screenshot](./salesforce-code.png)
6. Refresh token will be printed on the console.

#### For Windows Operating System
1. Login to Salesforce from an account with admin access.
2. Run script `bash generate-salesforce-refresh-token-powershell.ps1`
3. Enter the value of `InstanceUrl`, `Consumer Key`, `Consumer Secret` and `redirect_uri` from the connected-app details.
4. Open the printed URL in the browser and accept the connected-app permissions.
5. Copy the `code` parameter from the redirected URL and paste it in the console.![Salesforce Code Screenshot](./salesforce-code.png)
6. Refresh token will be printed on the console.