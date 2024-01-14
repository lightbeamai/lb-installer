# Check user permissions for DynamoDB

### Pre-requisites

Install [aws](https://docs.aws.amazon.com/cli/latest/userguide/getting-started-install.html) on the machine.

### Run the script

The script prompts for AWS access key, AWS secret key and region. It then prompts for regions where comma 
separated list can be provided for which stats needs to be fetched. If nothing is provided, it defaults 
for all regions.
The script supports 2 modes, `stats` and `full_metadata`. It prompts for mode, default is stats.
Running the script in `stats` mode will print table and record count per region.
Running in `full_metadata` will print table names too along with above stats.


```shell 
bash run.sh
```
