using System;
using System.Linq;
using System.Net;
using System.Net.Http;
using Amazon;
using Amazon.EC2;
using Amazon.EC2.Model;
using Microsoft.Extensions.Configuration;

if(args.Length < 2)
{
    Console.WriteLine("Usage: EC2GroupAccessUpdater <SecurityGroupName> <RuleDescription>");
    return;
}

var builder = new ConfigurationBuilder()
    .AddJsonFile($"Properties/launchSettings.json", false, true);
    //.AddEnvironmentVariables();
var configurationRoot = builder.Build();

string awsAccessKeyId = configurationRoot.GetSection("profiles:EC2GroupAccessUpdater")["aws_access_key_id"] ?? "";
string awsSecretAccessKey = configurationRoot.GetSection("profiles:EC2GroupAccessUpdater")["aws_secret_access_key"] ?? "";

if(String.IsNullOrEmpty(awsSecretAccessKey) || String.IsNullOrEmpty(awsAccessKeyId))
{
    Console.WriteLine("AWS credentials (aws_access_key_id and aws_secret_access_key)  not found. Please provide them in the launchSettings.json or as environment variables.");
    return;
}

string securityGroupName = args[0];
string ruleDescription = args[1];

var region = RegionEndpoint.USWest2; 
var ec2Client = new AmazonEC2Client(awsAccessKeyId, awsSecretAccessKey, region);

try
{
    string currentCidrIp;
    using (var httpClient = new HttpClient())
    {
        currentCidrIp = await httpClient.GetStringAsync("https://checkip.amazonaws.com");
        currentCidrIp = currentCidrIp.Trim();
        currentCidrIp += "/32"; // Format for AWS
        Console.WriteLine($"Current CidrIp: {currentCidrIp}");
    }

    // Fetch the security group
    var describeSecurityGroupsResponse = await ec2Client.DescribeSecurityGroupsAsync(new DescribeSecurityGroupsRequest
    {
        GroupNames = new List<string> { securityGroupName }
    });

    var securityGroup = describeSecurityGroupsResponse.SecurityGroups.FirstOrDefault();
    if (securityGroup == null)
    {
        Console.WriteLine($"Security group '{securityGroupName}' not found.");
        return;
    }

    var ruleFound = false;
    foreach(var permission in securityGroup.IpPermissions)
    {
        foreach(var range in permission.Ipv4Ranges)
        {
            if (range.Description == ruleDescription)
            {
                Console.WriteLine($"Found rule with description '{ruleDescription}' and Ip Address of {range.CidrIp}");
                if (range.CidrIp != currentCidrIp)
                {
                    // Revoke old permission
                    var oldPermission = new IpPermission
                    {
                        IpProtocol = permission.IpProtocol,
                        FromPort = permission.FromPort,
                        ToPort = permission.ToPort,
                        Ipv4Ranges = new List<IpRange> { new IpRange { CidrIp = range.CidrIp } }
                    };

                    await ec2Client.RevokeSecurityGroupIngressAsync(new RevokeSecurityGroupIngressRequest
                    {
                        GroupId = securityGroup.GroupId,
                        IpPermissions = new List<IpPermission> { oldPermission }
                    }); 

                    // Prepare a new permission replicating the old one but update the IP address
                    var newPermission = new IpPermission
                    {
                        IpProtocol = permission.IpProtocol,
                        FromPort = permission.FromPort,
                        ToPort = permission.ToPort,
                        Ipv4Ranges = new List<IpRange> { new IpRange { CidrIp = currentCidrIp, Description = ruleDescription } }
                    };

                    // Authorize new permission
                    await ec2Client.AuthorizeSecurityGroupIngressAsync(new AuthorizeSecurityGroupIngressRequest
                    {
                        GroupId = securityGroup.GroupId,
                        IpPermissions = new List<IpPermission> { newPermission }
                    });

                    Console.WriteLine($"Rule updated with new IP: {currentCidrIp}");
                } 
                else
                {
                    Console.WriteLine("Rule already up to date.");
                }
                ruleFound = true;
                break;
            }
        }
        if(ruleFound)
        {
            break;
        }
    }

    if(!ruleFound)
    {
        Console.WriteLine($"Rule with description '{ruleDescription}' not found.");
    }
}
catch (Exception e)
{
    Console.WriteLine($"An error occurred: {e.Message}");
}
