import os
import requests
from botocore.config import Config

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

def build_download_url(release_version: str, architecture: str, file_name: str) -> str:
    return f'https://cloud.centos.org/centos/{release_version}-stream/{architecture}/images/{file_name}-{release_version}-latest.{architecture}.raw.xz'

def build_ami_name(release_version: str, architecture: str, file_name: str) -> str:
    return f'{file_name}-{release_version}-{build_date}.{architecture}'


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
