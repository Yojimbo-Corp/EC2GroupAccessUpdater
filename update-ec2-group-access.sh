#!/bin/bash

# EC2 Group Access Updater - Bash Script Version
# Updates security group rules with current public IP using AWS SSO authentication

set -euo pipefail

# Default values
SECURITY_GROUP_NAME=""
RULE_DESCRIPTION=""
REGION=""
PROFILE=""

# Function to display help
show_help() {
    cat << EOF
Usage: $(basename "$0") [OPTIONS]

This script updates the IP address of a security group rule to the current public IP address 
of the machine running the script using AWS SSO authentication.

OPTIONS:
  -g, --group GROUP_NAME          Required. Security Group Name
  -r, --rule-description DESC     Required. Rule Description  
  -e, --region REGION             Required. AWS Region (e.g. us-east-1)
  -p, --profile PROFILE           Required. AWS Profile Name
  -h, --help                      Show this help message

EXAMPLES:
  $(basename "$0") -g my-security-group -r "Home Office Access" -e us-east-1 -p my-aws-profile
  $(basename "$0") --group my-sg --rule-description "Remote Access" --region us-west-2 --profile production

EOF
}

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        -g|--group)
            SECURITY_GROUP_NAME="$2"
            shift 2
            ;;
        -r|--rule-description)
            RULE_DESCRIPTION="$2"
            shift 2
            ;;
        -e|--region)
            REGION="$2"
            shift 2
            ;;
        -p|--profile)
            PROFILE="$2"
            shift 2
            ;;
        -h|--help)
            show_help
            exit 0
            ;;
        *)
            echo "Error: Unknown option $1" >&2
            show_help
            exit 1
            ;;
    esac
done

# Validate required arguments
if [[ -z "$SECURITY_GROUP_NAME" || -z "$RULE_DESCRIPTION" || -z "$REGION" || -z "$PROFILE" ]]; then
    echo "Error: All required arguments must be provided." >&2
    show_help
    exit 1
fi

# Check if AWS CLI is installed
if ! command -v aws &> /dev/null; then
    echo "Error: AWS CLI is not installed or not in PATH" >&2
    exit 1
fi

# Validate profile exists
if ! aws configure list-profiles | grep -q "^$PROFILE$"; then
    echo "Error: Profile '$PROFILE' not found. Available profiles:" >&2
    aws configure list-profiles >&2
    exit 1
fi

# Check if profile is already authenticated
echo "Checking authentication status for profile: $PROFILE"
if aws sts get-caller-identity --profile "$PROFILE" &>/dev/null; then
    echo "Profile '$PROFILE' is already authenticated. Skipping login step."
else
    echo "Profile '$PROFILE' needs authentication. Logging in with AWS SSO..."
    if ! aws sso login --profile "$PROFILE"; then
        echo "Error: AWS SSO login failed" >&2
        exit 1
    fi
fi

# Export AWS profile for subsequent commands
export AWS_PROFILE="$PROFILE"
export AWS_DEFAULT_REGION="$REGION"

echo "Getting current public IP address..."
# Get current public IP address
if ! CURRENT_IP=$(curl -s https://checkip.amazonaws.com); then
    echo "Error: Failed to get current public IP address" >&2
    exit 1
fi

# Trim whitespace and add /32 for CIDR notation
CURRENT_IP=$(echo "$CURRENT_IP" | tr -d '[:space:]')
CURRENT_CIDR_IP="$CURRENT_IP/32"
echo "Current CidrIp: $CURRENT_CIDR_IP"

echo "Fetching security group details..."
# Get security group details
if ! SG_JSON=$(aws ec2 describe-security-groups --group-names "$SECURITY_GROUP_NAME" --region "$REGION" 2>/dev/null); then
    echo "Error: Security group '$SECURITY_GROUP_NAME' not found or access denied" >&2
    exit 1
fi

# Extract security group ID
SG_ID=$(echo "$SG_JSON" | jq -r '.SecurityGroups[0].GroupId // empty')
if [[ -z "$SG_ID" ]]; then
    echo "Error: Could not extract security group ID" >&2
    exit 1
fi

echo "Found security group: $SG_ID"

# Find the rule with matching description
RULE_FOUND=false
EXISTING_CIDR=""
IP_PROTOCOL=""
FROM_PORT=""
TO_PORT=""

# Parse security group rules to find matching rule description
while IFS= read -r permission; do
    # Get IP protocol, from port, and to port for this permission
    PERM_IP_PROTOCOL=$(echo "$permission" | jq -r '.IpProtocol')
    PERM_FROM_PORT=$(echo "$permission" | jq -r '.FromPort // empty')
    PERM_TO_PORT=$(echo "$permission" | jq -r '.ToPort // empty')
    
    # Check each IPv4 range in this permission
    while IFS= read -r range; do
        RANGE_DESCRIPTION=$(echo "$range" | jq -r '.Description // empty')
        RANGE_CIDR=$(echo "$range" | jq -r '.CidrIp')
        
        if [[ "$RANGE_DESCRIPTION" == "$RULE_DESCRIPTION" ]]; then
            echo "Found rule with description '$RULE_DESCRIPTION' and IP Address of $RANGE_CIDR"
            RULE_FOUND=true
            EXISTING_CIDR="$RANGE_CIDR"
            IP_PROTOCOL="$PERM_IP_PROTOCOL"
            FROM_PORT="$PERM_FROM_PORT"
            TO_PORT="$PERM_TO_PORT"
            break
        fi
    done < <(echo "$permission" | jq -c '.IpRanges[]?')
    
    if [[ "$RULE_FOUND" == true ]]; then
        break
    fi
done < <(echo "$SG_JSON" | jq -c '.SecurityGroups[0].IpPermissions[]')

if [[ "$RULE_FOUND" == false ]]; then
    echo "Rule with description '$RULE_DESCRIPTION' not found."
    exit 0
fi

# Check if IP address needs updating
if [[ "$EXISTING_CIDR" == "$CURRENT_CIDR_IP" ]]; then
    echo "Rule already up to date."
    exit 0
fi

echo "Updating rule with new IP address..."

# Prepare port parameters
PORT_PARAMS=""
if [[ "$FROM_PORT" != "null" && "$FROM_PORT" != "" ]]; then
    PORT_PARAMS="--from-port $FROM_PORT"
fi
if [[ "$TO_PORT" != "null" && "$TO_PORT" != "" ]]; then
    PORT_PARAMS="$PORT_PARAMS --to-port $TO_PORT"
fi

# Revoke old rule
echo "Revoking old rule with IP: $EXISTING_CIDR"
if ! aws ec2 revoke-security-group-ingress \
    --group-id "$SG_ID" \
    --protocol "$IP_PROTOCOL" \
    $PORT_PARAMS \
    --cidr "$EXISTING_CIDR" \
    --region "$REGION"; then
    echo "Error: Failed to revoke old security group rule" >&2
    exit 1
fi

# Authorize new rule with updated IP and description
echo "Authorizing new rule with IP: $CURRENT_CIDR_IP"

# Build the IP permissions JSON for the authorize command
IP_PERMISSIONS_JSON=$(jq -n \
  --arg protocol "$IP_PROTOCOL" \
  --arg fromPort "$FROM_PORT" \
  --arg toPort "$TO_PORT" \
  --arg cidr "$CURRENT_CIDR_IP" \
  --arg description "$RULE_DESCRIPTION" \
  '[{
    IpProtocol: $protocol,
    IpRanges: [{
      CidrIp: $cidr,
      Description: $description
    }]
  } | if $fromPort != "null" and $fromPort != "" then . + {FromPort: ($fromPort | tonumber)} else . end
    | if $toPort != "null" and $toPort != "" then . + {ToPort: ($toPort | tonumber)} else . end
  ]')

if ! aws ec2 authorize-security-group-ingress \
    --group-id "$SG_ID" \
    --ip-permissions "$IP_PERMISSIONS_JSON" \
    --region "$REGION"; then
    echo "Error: Failed to authorize new security group rule" >&2
    exit 1
fi

echo "Rule updated with new IP: $CURRENT_CIDR_IP"
