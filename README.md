# EC2GroupAccessUpdater
This utility will update the IP address of a security group rule to the current public IP address of the machine running the utility. 
This is useful for updating security group rules containing entries for IP version 4 IP addresses of machines that don't have a static IP Address.

## Usage:
```
EC2GroupAccessUpdater.exe 
  -g, --group                 Required. Security Group Name

  -r, --ruleDescription       Required. Rule Description

  -e, --region                Required. AWS Region (e.g. us-east-1)

  -a, --awsAccessKeyId        Required. AWS Access Key Id

  -s, --awsSecretAccessKey    Required. AWS Secret Access Key
```





