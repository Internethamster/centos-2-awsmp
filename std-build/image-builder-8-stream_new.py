# This is a script to build an AMI from the CentOS Stream images found at 
# https://cloud.centos.org/centos/{release_version}-stream/{amzn_architecture}/images/{file_name}-{release_version}-latest.{architecture}.raw.xz' where 
# the architecture can be x86_64 or aarch64 depending on the platform we are running the script on. The Release Version is defined in a configuration file or on the command line 
# the config file is found by default in the home directory of the user at /home/<username>/.config/centos_build_image.toml
import os
import platform
import click
import datetime
import boto3
import time
from botocore.config import Config
from shared_ami_functions import *

docstring = """
    This python script is used to build an AMI from the CentOS Stream images found at
    https://cloud.centos.org/centos/{release_version}-stream/{amzn_architecture}/images/{file_name}-{release_version}-latest.{architecture}.raw.xz' where
    the architecture can be x86_64 or aarch64 depending on the platform we are running the script on. The Release Version is defined in a configuration file or on the command line
    the config file is found by default in the home directory of the user at /home/<username>/.config/centos_build_image.toml
"""

   

def build_ami(release_version, config_file):
    """
    This the main entry point for the script.
    It takes a release version and the config-file as input and performs the following tasks:
    1. Downloads the latest version of the CentOS Stream image
    2. Uncompress the raw file for next steps
    3. runs the virt-customize command on the image to update all of the packages
    4. Updates the version in the dynamodb table for the product ID
    5. Uploads the image file to an S3 bucket
    6. Register the image file as a new version of the AMI

    """
    config = load_config(config_file)
    # if the release version is not provided, then we will use the version in the config file
    if release_version is None:
        release_version = config['centos']['release_version']

    region = config['app']['region']
    profile = config['app']['profile']
    release_short = config['centos']['release_short']
    major_release = config['centos']['major_release']
    file_name = config['centos']['name']
    product_id = config['marketplace']['product_id']
    s3_bucket = config['marketplace']['s3_bucket']
    s3_bucket_region = config['marketplace']['s3_bucket_region']
    s3_bucket_prefix = config['marketplace']['s3_bucket_prefix']
    build_date = datetime.datetime.now().strftime('%Y%m%d')
    architecture = platform.machine()
    if architecture == 'x86_64':
        amzn_architecture = 'x86_64'
    elif architecture == 'aarch64':
        # The platform architecture is always arm64, but the instance os will identify as aarch64
        amzn_architecture = 'arm64'
    # Configure the base_url using the content from the config and the command line. 
    base_url = build_download_url(release_version=release_version, architecture=architecture, file_name=file_name)
    downloaded_file = download_file(base_url)
    # Uncompress the file if the file is compressed
    if os.path.exists(f'{file_name}-{release_version}-latest.{architecture}.raw.xz'):
        os.system(f'unxz {file_name}-{release_version}-latest.{architecture}.raw.xz')
        os.system(f'qemu-img convert -f raw {file_name}-{release_version}-latest.{architecture}.raw -O qcow2 {file_name}-{release_version}-{build_date}.{architecture}.{revision}.qcow2')
        os.system(f'qemu-img resize {file_name}-{release_version}-{build_date}.{architecture}.{revision}.qcow2 8G')
        os.system(f'virt-customize -a {file_name}-{release_version}-{build_date}.{architecture}.{revision}.qcow2 --run-command "dnf update -y"')
        os.system(f'virt-sysprep -a {file_name}-{release_version}-{build_date}.{architecture}.{revision}.qcow2 --operations machine-id,net-hostname,net-hwaddr --logdir ./virt-sysprep.log')
        # Update the dynamodb table with the new version
        # use the dynamodb table name created in the create_db.py file or found in the marketplace section of the centos_build_config.toml file
        # use botocore to build a configuration for the boto3 client from the app.region and app.profile assignments in the toml file
        boto_config = Config(region_name=region, profile_name=profile)
        dynamodb = boto3.resource('dynamodb', config=boto_config)

        table = dynamodb.Table(config['marketplace']['dynamodb_table'])
        table.update_item(
            Key={
                'centosid': product_id
            },
            UpdateExpression='SET release_date = :val1, file_name = :val2',
            ExpressionAttributeValues={
                ':val1': build_date,
                ':val2': f'{file_name}-{release_version}-{build_date}.{architecture}.{revision}.qcow2'
            }
        )
        # Upload the image to S3
        boto_config = Config(region_name=s3_bucket_region, profile_name=profile)
        s3 = boto3.client('s3', config=boto_config)
        s3.upload_file(f'{file_name}-{release_version}-{build_date}.{architecture}.qcow2', 
                       s3_bucket, f'{s3_bucket_prefix}{file_name}-{release_version}-{build_date}.{architecture}.qcow2')
        # import snapshot to the same region as the s3 bucket region
        boto_config = Config(region_name=s3_bucket_region, profile_name=profile)

        ec2 = boto3.client('ec2', config=boto_config)
        snapshot_complete = False
        snapshot_id = import_snapshot(f'{file_name}-{release_version}-{build_date}.{architecture}.qcow2')
        # migrate snapshot to the region from which it will be imported into marketplace. This is normally us-east-1 from the s3_bucket_region
        snapshot_id = migrate_snapshot(snapshot_id, f'{file_name}-{release_version}-{build_date}.{architecture}.qcow2')
        ami_id = register_image(snapshot_id)
        response = ec2.describe_images(
            ImageIds=[
                ami_id,
            ]
        )
        print(response)

#DONE: include click for cli support
@click.command()
@click.option('--release-version', default=None, help='Release Version of CentOS Stream')
@click.option('--revision', default='0', help='incremented when building additional images on the same build date')
@click.option('--config-file', default=f'{os.environ["HOME"]}/.config/centos_build_config.toml', help='Path to the config file')


if __name__ == '__main__':
    build_ami(release_version=release_version, config_file=config_file)
