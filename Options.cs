using CommandLine;
using System;
using System.Collections.Generic;
using System.Linq;
using System.Text;
using System.Threading.Tasks;

namespace EC2GroupAccessUpdater
{
    internal class Options
    {
        [Option('g', "group", Required = true, HelpText = "Security Group Name")]
        public string SecurityGroupName { get; set; } = "";

        [Option('r', "ruleDescription", Required = true, HelpText = "Rule Description")]
        public string RuleDescription { get; set; } = "";

        [Option('e', "region", Required = true, HelpText = "AWS Region (e.g. us-east-1)")]
        public string Region { get; set; } = "";

        [Option('a', "awsAccessKeyId", Required = true, HelpText = "AWS Access Key Id")]
        public string AwsAccessKeyId { get; set; } = "";

        [Option('s', "awsSecretAccessKey", Required = true, HelpText = "AWS Secret Access Key")]
        public string AwsSecretAccessKey { get; set; } = "";

    }
}

// Path: Program.cs
