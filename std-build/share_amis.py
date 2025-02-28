# using the boto3 and botocore libraries, from a parameter passed to this script, identify an ami in us-east-1 or another region if specified on the command line  and share that ami to a list of accounts. Once that ami is shared, Identify the snapshot or snapshots associated with that ami and share them to the same list of accounts. 
# it may be necessary to modify the boto profile from the command line.     
# 514427062609 is ec2-mvp-ops@amazon.com
# 425685993791 is a test account for validations from Red Hat
# 684062674729 is the account for sharing to the aws marketplace
# 679593333241 is the account for testing in the aws marketplace
# 014813956182 is the account for testing in the Lightsail group
# 264483973329 is the account for testing containers, but fails the AMI as well. 
#!/usr/bin/env python3
import argparse
import boto3
import botocore
import sys

def parse_args():
    parser = argparse.ArgumentParser()
    parser.add_argument('--ami-id', required=True, help='AMI ID to share')
    parser.add_argument('--region', default='us-east-1', help='AWS region')
    parser.add_argument('--profile', default='default', help='AWS profile to use')
    return parser.parse_args()

def get_aws_client(service, region, profile=None):
    session = boto3.Session(profile_name=profile) if profile else boto3.Session()
    return session.client(service, region_name=region)

def get_ami_snapshots(ec2_client, ami_id):
    try:
        response = ec2_client.describe_images(ImageIds=[ami_id])

        ami = response['Images'][0]
        snapshots = [block['Ebs']['SnapshotId'] for block in ami.get('BlockDeviceMappings', []) if 'Ebs' in block]
        return snapshots
    except botocore.exceptions.ClientError as e:
        print(f"Error getting AMI details: {e}")
        sys.exit(1)

def share_ami(ec2_client, ami_id, accounts):

    try:
        ec2_client.modify_image_attribute(
            ImageId=ami_id,
            LaunchPermission={'Add': [{'UserId': account} for account in accounts]}
        )

    except botocore.exceptions.ClientError as e:
        print(f"Error sharing AMI: {e}")
        sys.exit(1)

def share_snapshot(ec2_client, snapshot_id, accounts):

    try:
        ec2_client.modify_snapshot_attribute(
            SnapshotId=snapshot_id,
            CreateVolumePermission={'Add': [{'UserId': account} for account in accounts]}
        )

    except botocore.exceptions.ClientError as e:
        print(f"Error sharing snapshot: {e}")
        sys.exit(1)

def main():

    args = parse_args()
    target_accounts = [
        '514427062609', '425685993791', '684062674729',
        '679593333241', '014813956182', '264483973329'
    ]
    
    ec2_client = get_aws_client('ec2', args.region, args.profile)
    
    # Share AMI
    share_ami(ec2_client, args.ami_id, target_accounts)
    
    # Get and share snapshots
    snapshots = get_ami_snapshots(ec2_client, args.ami_id)
    for snapshot_id in snapshots:
        share_snapshot(ec2_client, snapshot_id, target_accounts)

if __name__ == '__main__':
    main()
    print("AMI and snapshots shared successfully.")

