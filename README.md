# EC2GroupAccessUpdater

This utility will update the IP address of a security group rule to the current public IP address of the machine running the utility. This is useful for updating security group rules containing entries for IP version 4 IP addresses of machines that don't have a static IP Address.

## Two Usage Options

You can use this utility in two ways:

### Option 1: .NET Compiled Executable (using AWS Access Keys)

Compile the .NET application and use it with direct AWS credentials:

**Build and Usage:**
```bash
# Build the application
dotnet build

# Run the executable
EC2GroupAccessUpdater.exe 
  -g, --group                 Required. Security Group Name
  -r, --ruleDescription       Required. Rule Description
  -e, --region                Required. AWS Region (e.g. us-east-1)
  -a, --awsAccessKeyId        Required. AWS Access Key Id
  -s, --awsSecretAccessKey    Required. AWS Secret Access Key
```

### Option 2: Bash Script (using AWS SSO Profile)

Use the bash script with AWS SSO authentication:

**Prerequisites:**
- AWS CLI installed and configured
- AWS SSO profile configured
- `jq` command-line JSON processor installed
- `curl` for getting public IP

**AWS CLI Configuration:**

Before using the bash script, you need to configure the AWS CLI with an SSO profile:

1. **Install AWS CLI**: Follow the [AWS CLI Installation Guide](https://docs.aws.amazon.com/cli/latest/userguide/install-cliv2.html)

2. **Configure SSO Profile**: Run the following command to set up an SSO profile:
   ```bash
   aws configure sso
   ```
   This will prompt you for:
   - SSO Start URL (provided by your AWS administrator)
   - SSO Region 
   - AWS Account and Role selection
   - Default region and output format

3. **Authenticate**: After configuration, authenticate with:
   ```bash
   aws sso login --profile your-profile-name
   ```

For detailed instructions, see the [AWS CLI User Guide on Configuring SSO](https://docs.aws.amazon.com/cli/latest/userguide/cli-configure-sso.html).

**Usage:**
```bash
# Run the bash script
./update-ec2-group-access.sh 
  -g, --group GROUP_NAME          Required. Security Group Name
  -r, --rule-description DESC     Required. Rule Description  
  -e, --region REGION             Required. AWS Region (e.g. us-east-1)
  -p, --profile PROFILE           Required. AWS Profile Name
```

**Examples:**
```bash
# Using short options
./update-ec2-group-access.sh -g my-security-group -r "Home Office Access" -e us-east-1 -p my-aws-profile

# Using long options
./update-ec2-group-access.sh --group my-sg --rule-description "Remote Access" --region us-west-2 --profile production
```

## How It Works

Both utilities perform the same core functionality:

1. **Authenticate with AWS** (via access keys or SSO profile)
2. **Get current public IP** from `https://checkip.amazonaws.com`
3. **Find the target security group rule** by description
4. **Update the rule** if the current IP differs from the rule's IP:
   - Revoke the existing rule with the old IP
   - Authorize a new rule with the current IP
5. **Report the results** of the operation

## Automated Scheduling (macOS)

The bash script can be scheduled to run automatically using macOS LaunchAgent (recommended over cron for GUI applications).

### Prerequisites for Scheduling
- macOS 15.6.1 (tested version)
- AWS CLI 2.28.21 (tested version)
- Terminal app with appropriate permissions

### Setup Instructions

1. **Create a wrapper script** (`cron-wrapper.sh`):
   ```bash
   #!/bin/bash
   # Wrapper script for EC2 Group Access Updater scheduled job
   # This ensures proper environment variables are set for GUI applications
   
   # Set the PATH to include common locations and AWS CLI (adjust for your installation)
   export PATH="/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin:/opt/homebrew/bin"
   
   # Set environment variables for GUI applications
   export DISPLAY=:0
   export HOME=/Users/$(whoami)
   
   # Set AWS CLI environment
   export AWS_PROFILE=your-profile-name
   export AWS_DEFAULT_REGION=your-region
   
   # Change to the script directory
   cd /path/to/EC2GroupAccessUpdater
   
   # Run the script with full path and redirect output to log file
   /path/to/EC2GroupAccessUpdater/update-ec2-group-access.sh \
     -g YourSecurityGroup \
     -r "Your Rule Description" \
     -e your-region \
     -p your-profile \
     >> /path/to/EC2GroupAccessUpdater/scheduled.log 2>&1
   
   # Log the completion time
   echo "$(date): Scheduled job completed" >> /path/to/EC2GroupAccessUpdater/scheduled.log
   ```

2. **Make the wrapper executable**:
   ```bash
   chmod +x cron-wrapper.sh
   ```

3. **Create a LaunchAgent plist file** (`com.yourname.ec2groupaccessupdater.plist`):
   ```xml
   <?xml version="1.0" encoding="UTF-8"?>
   <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
   <plist version="1.0">
   <dict>
       <key>Label</key>
       <string>com.yourname.ec2groupaccessupdater</string>
       <key>ProgramArguments</key>
       <array>
           <string>/path/to/EC2GroupAccessUpdater/cron-wrapper.sh</string>
       </array>
       <key>StartCalendarInterval</key>
       <dict>
           <key>Hour</key>
           <integer>7</integer>
           <key>Minute</key>
           <integer>0</integer>
       </dict>
       <key>StandardOutPath</key>
       <string>/path/to/EC2GroupAccessUpdater/launchd.log</string>
       <key>StandardErrorPath</key>
       <string>/path/to/EC2GroupAccessUpdater/launchd.log</string>
   </dict>
   </plist>
   ```

4. **Install and start the LaunchAgent**:
   ```bash
   # Copy to LaunchAgents directory
   cp com.yourname.ec2groupaccessupdater.plist ~/Library/LaunchAgents/
   
   # Load the service
   launchctl load ~/Library/LaunchAgents/com.yourname.ec2groupaccessupdater.plist
   
   # Verify it's loaded
   launchctl list | grep ec2groupaccessupdater
   ```

### Managing the Scheduled Job

```bash
# Stop the service
launchctl unload ~/Library/LaunchAgents/com.yourname.ec2groupaccessupdater.plist

# Start the service
launchctl load ~/Library/LaunchAgents/com.yourname.ec2groupaccessupdater.plist

# Remove the service completely
rm ~/Library/LaunchAgents/com.yourname.ec2groupaccessupdater.plist

# View logs
tail -f /path/to/EC2GroupAccessUpdater/launchd.log
```

### Important Notes

- **Browser Visibility**: The LaunchAgent approach ensures AWS SSO login browser windows are visible
- **File Locations**: Update all paths in the wrapper script and plist file to match your actual directory structure
- **Profile Names**: Replace `your-profile-name` with your actual AWS SSO profile name
- **Security Groups**: Update the security group name and rule description to match your needs
- **Testing**: Test the wrapper script manually before scheduling: `./cron-wrapper.sh`
- **Logs**: Check `launchd.log` for any errors or issues with scheduled runs

**Tested Environment:**
- macOS 15.6.1
- AWS CLI 2.28.21
- Python 3.13.7



