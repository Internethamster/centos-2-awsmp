# This is a script to build an AMI from the CentOS Stream images found at 
# https://cloud.centos.org/centos/{release_version}-stream/{amzn_architecture}/images/{file_name}-{release_version}-latest.{architecture}.raw.xz' where 
# the architecture can be x86_64 or aarch64 depending on the platform we are running the script on. The Release Version is defined in a configuration file or on the command line 
# the config file is found by default in the home directory of the user at /home/<username>/.config/centos_build_image.toml
import os
import platform
import click
import datetime
import requests
import boto3
from botocore.config import Config
import time

docstring = """
    This python script is used to build an AMI from the CentOS Stream images found at
    https://cloud.centos.org/centos/{release_version}-stream/{amzn_architecture}/images/{file_name}-{release_version}-latest.{architecture}.raw.xz' where
    the architecture can be x86_64 or aarch64 depending on the platform we are running the script on. The Release Version is defined in a configuration file or on the command line
    the config file is found by default in the home directory of the user at /home/<username>/.config/centos_build_image.toml
"""

@click.command()
@click.option('--release-version', default=None, help='Release Version of CentOS Stream')
@click.option('--revision', default='0', help='incremented when building additional images on the same build date')
@click.option('--config-file', default=f'{os.environ["HOME"]}/.config/centos_build_config.toml', help='Path to the config file')
    
def build_download_url(release_version: str = release_version, architecture: str = architecture, file_name: str = file_name ):
    return f'https://cloud.centos.org/centos/{release_version}-stream/{architecture}/images/{file_name}-{release_version}-latest.{architecture}.raw.xz'


#Create a function that uses python libraries to download and save the cloud image using the url defined in the config file
def download_file(url: str) -> str:
   local_filename = url.split('/')[-1]
   # NOTE the stream=True parameter below
   with requests.get(url, stream=True) as r:
       r.raise_for_status()
       with open(local_filename, 'wb') as f:
           for chunk in r.iter_content(chunk_size=8192): 
               # If you have chunk encoded response uncomment if
               # and set chunk_size parameter to None.
               #if chunk: 
               f.write(chunk)
    return local_filename

def load_config(config_file):
       # If the config_file is located, then we will use it, otherwise we will use the default config file
    if config_file != f'{os.environ["HOME"]}/.config/centos_build_config.toml':
        try:
            config = load_config(config_file)
            return config
        except FileNotFoundError:
            print("Error: default location not found, trying home directory")
            config = load_config(f'{os.environ["HOME"]}/.centos_build_config.toml')
            return config
        finally:
            print("Error: could not load config file")
            exit(1)
    else:
        try:
            config = load_config(f'{os.environ["HOME"]}/.config/centos_build_config.toml')
            return config
        except FileNotFoundError:
            print("Error: could not load config file")
            exit(1)

def import_snapshot(s3_object_name: str, s3_bucket_region: str) -> str:
    '''
    This function uses the import_snapshot api from the ec2 client to import the snapshot we just created. 
    The function loops to determine the status of the snapshot import task for 6 minutes max and fails or until the snapshot import completes.
    '''
    config = load_config()
    s3_bucket = config['marketplace']['s3_bucket']
    s3_bucket_region = config['marketplace']['s3_bucket_region']
    boto_config = Config(region_name=s3_bucket_region, profile_name=profile)
    ec2 = boto3.client('ec2', config=boto_config)
    response = ec2.import_snapshot(
        Description=f'{s3_object_name} to {s3_bucket}',
        DiskContainer={
            'Description': f'{s3_object_name} HVM',
            'Format': 'qcow2',
            'UserBucket': {
                'S3Bucket': s3_bucket,
                'S3Key': f'{s3_bucket_prefix}{s3_object_name}'
            },
            'DeviceName': '/dev/sda1'
        },
        RoleName='centos-stream-import-role'
    )
    snapshot_task_id = response['SnapshotTaskId']
    # Loop to determine the status of the snapshot import task for 6 minutes max and fails or until the snapshot import completes.
    # The loop will sleep for 10 seconds between each iteration and will fail after 6 minutes
    # The loop will exit if the snapshot import task fails
    # The loop will return the snapshot id if the snapshot import task completes
    # The loop will exit if the snapshot import task is not found
    # The loop will exit if the snapshot import task is not in progress
    # The loop will exit if the snapshot import task is not in the expected state
    snapshot_status_complete = False
    while not snapshot_status_complete:
        response = ec2.describe_import_snapshot_tasks(
            ImportTaskIds=[
                snapshot_task_id,
            ]
        )
        snapshot_status = response['ImportSnapshotTasks'][0]['SnapshotTaskDetail']['Status']
        if snapshot_status == 'completed':
            snapshot_status_complete = True
            print(f'Snapshot import task {snapshot_task_id} completed')
            snapshot_id = response['ImportSnapshotTasks'][0]['SnapshotTaskDetail']['SnapshotId']
        elif snapshot_status == 'error':
            snapshot_status_complete = False
            print(f'Snapshot import task {snapshot_task_id} failed')
            exit(1)
        elif snapshot_status == 'cancelled':
            snapshot_status_complete = False
            print(f'Snapshot import task {snapshot_task_id} cancelled')
            exit(1)
        elif snapshot_status == 'cancelling':
            snapshot_status_complete = False
            print(f'Snapshot import task {snapshot_task_id} is failing')
            time.sleep(5)
        elif snapshot_status == 'pending':
            print(f'Snapshot import task {snapshot_task_id} is pending')
            time.sleep(10)
        else:
            snapshot_status_complete = False
            print(f'Snapshot import task {snapshot_task_id} failed')
            exit(1)
    return snapshot_id
def migrate_snapshot(snapshot_id: str, s3_object_name: str, s3_bucket_region: str) -> str:
    """
    This function uses the migrate_snapshot api from the ec2 client to migrate the snapshot we just created.
    The function loops to determine the status of the snapshot migration task for 6 minutes max and fails or until the snapshot migration completes.
    """
    # copy the snapshot to the region from which it will be imported into marketplace. This is normally us-east-1 from the s3_bucket_region
    # use the dynamodb table name created in the create_db.py file or found in the marketplace section of the centos_build_config.toml file
    # use botocore to build a configuration for the boto3 client from the app.region and app.profile assignments in the toml file
    boto_config = Config(region_name=s3_bucket_region, profile_name=profile)
    ec2 = boto3.client('ec2', config=boto_config)
    response = ec2.copy_snapshot(
        Description=f'{s3_object_name} (HVM)',
        DestinationRegion=region,
        SourceRegion=s3_bucket_region,
        SourceSnapshotId=snapshot_id
    )
    snapshot_id = response['SnapshotId']

    dynamodb = boto3.resource('dynamodb', config=boto_config)
    table = dynamodb.Table(config['marketplace']['dynamodb_table'])
    #TODO: post the snapshot id for the product_id in the dynamodb table
    table.update_item(
        Key={
            'centosid': product_id
        },
        UpdateExpression='SET snapshot_id = :val1',
        ExpressionAttributesValues={
            ':val1': snapshot_id
        }
    )
    return snapshot_id

def register_image(snapshot_id: str) -> str:
    ''''
    In this function, the snapshot id is used to register the image file as a new version of the AMI.
    The function uses the register_image api from the ec2 client to register the image file as a new version of the AMI.
    The function returns the ami id of the registered image.
    '''
    boto_config = Config(region_name=region, profile_name=profile)
    ec2 = boto3.client('ec2', config=boto_config)
    response = ec2.register_image(
        Architecture=amzn_architecture,
        BlockDeviceMappings=[
            {
                'DeviceName': '/dev/sda1',
                'Ebs': {
                    'DeleteOnTermination': True,
                    'SnapshotId': snapshot_id,
                    'VolumeSize': 8,
                    'VolumeType': 'gp3'
                }
            }
        ],
        Description=f'CentOS Stream {release_version} ({amzn_architecture}) HVM {build_date}',
        EnaSupport=True,
        Imdsv2Support=True,
        Name=f'{file_name}-{release_version}-{amzn_architecture}-{build_date}.{architecture}.{revision}',
        RootDeviceName='/dev/sda1',
        VirtualizationType='hvm',
        SriovNetSupport='simple',
        ImageLocation=f'{s3_bucket}/{s3_bucket_prefix}{file_name}-{release_version}-{build_date}.{architecture}.qcow2'
    )
    ami_id = response['ImageId']
    boto_config = Config(region_name=region, profile_name=profile)
    dynamodb = boto3.resource('dynamodb', config=boto_config)
    table = dynamodb.Table(config['marketplace']['dynamodb_table'])
    table.update_item(
        Key={
            'centosid': product_id
        },
        UpdateExpression='SET ami_id = :val1',
        ExpressionAttributeValues={
            ':val1': ami_id
        }
    )
    return ami_id


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

if __name__ == '__main__':
    build_ami(release_version=release_version, config_file=config_file)
