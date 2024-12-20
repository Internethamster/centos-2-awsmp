import os
import toml
import click
import time
import urllib.request
import ssl
import click 
import boto3
from botocore.config import Config
import platform

@click.command()
@click.option('--release_version', default='8', help='Specify the release version of CentOS Stream')
@click.option('--config_file', default='~/.config/centos_build_config.toml', help='Specify the path to the config file')
#TODO: create a function to set the configuration based on the config file
def load_config(config_file: str) -> dict:
    """
    This function loads the configuration file and returns a dictionary with the configuration.
    """
    if not os.path.exists(config_file):
        print(f"Error: {config_file} does not exist")
        return {}
    app_config = toml.load(open(config_file))
    return app_config

home_dir = os.path.expanduser('~') # need this for the conditional statements below. 
architecture = platform.machine()
amzn_architecture = architecture
if architecture == 'aarch64':
    amzn_architecture = 'arm64'

#todo: create a cli structure so that we can override the release version

def download_file(file_location: str)-> str:
    """
    This function downloads the file from the given URL and returns the name of the artifact downloaded. The file name is collected from the url
    use the native python libraries to download the files, not the system commands. 
    """
    ssl._create_default_https_context = ssl._create_unverified_context
    file_name = file_location.split('/')[-1]
    urllib.request.urlretrieve(file_location, file_name)
    return file_name
def run(release_version: str, config_file: str):
    """
    This function is the main entry point for the script.
    It takes a release version as input and performs the following tasks:
    1. Downloads the latest version of the CentOS Stream image
    2. Uncompress the raw file for next steps
    3. runs the virt-customize command on the image to update all of the packages
    4. Updates the version in the dynamodb table for the product ID
    5. Uploads the image file to an S3 bucket
    6. Register the image file as a new version of the AMI

    """

    if config_file != f'{home_dir}/.config/centos_build_config.toml':
        config = load_config(config_file)
    else:
        try:
            config = load_config(f'{home_dir}/.centos_build_config.toml')
        except FileNotFoundError:
            config = load_config(f'{home_dir}/.config/centos_build_config.toml')
        finally:
            print("Error: could not load config file")
            exit(1) 

    REGION = config['app']['region']
    PROFILE = config['app']['profile']
    S3_BUCKET = config['marketplace']['s3_bucket']
    S3_BUCKET_PREFIX = config['marketplace']['s3_bucket_prefix']
    release_name = config['centos']['release_name']
    release_short = config['centos']['release_short']
    release_version = config['centos']['release_version']
    file_name = config['centos']['name']
    product_id = config['marketplace']['product_id']

    #DONE: Build the base_url using the content of the variables collected from the 
    base_url = f'https://cloud.centos.org/centos/{release_version}-stream/{amzn_architecture}/images/{file_name}-{release_version}-latest.{architecture}.raw.xz'

    #DONE: download the file from the url
    download_file(base_url)
    #DONE: uncompress the file if the file is compressed
    if os.path.exists(f'{file_name}-{release_version}-latest.{architecture}.raw.xz'):
        os.system(f'unxz {file_name}-{release_version}-latest.{architecture}.raw.xz')
    #DONE: run the virt-customize command on the file
    os.system(f'virt-customize -a {file_name}-{release_version}-latest.{architecture}.raw --run-command "dnf update -y"')
    #DONE: run the virt-sysprep on the file
    os.system(f'virt-sysprep -a {file_name}-{release_version}-latest.{architecture}.raw --operations machine-id,net-hostname,net-hwaddr --logdir ./virt-sysprep.log')
    #DONE: update the dynamodb table with the new version
    # use the dynamodb table name created in the create_db.py file or found in the marketplace section of the centos_build_config.toml file
    # use botocore to build a configuration for the boto3 client from the app.region and app.profile assignments in the toml file
    config = Config(region_name=REGION, profile_name=PROFILE)
    dynamodb = boto3.resource('dynamodb', region_name=REGION)
    table = dynamodb.Table('aws-mp-ami-import')
    #TODO: use the product id of the marketplace listing to identify the product that we are updating in the dynamodb table. The product id is in the config file.
    table.update_item(
        Key={
            'product-id': 'centos-2-awsmp'
        },
        UpdateExpression='SET version = :val1',
        ExpressionAttributeValues={
            ':val1': release_version
        }
    )
    #DONE: Update the filename that we are uploading to s3 by replacing the word "latest" with the date in an iso8601 format YYYYMMDD
    s3_upload_date = datetime.datetime.now().strftime('%Y%m%d')
    s3_upload_name = f'{file_name}-{release_version}-{s3_upload_date}.{architecture}.raw'
    #DONE: upload the file to s3
    s3.upload_file(s3_upload_name, S3_BUCKET, f'{S3_BUCKET_PREFIX}/{file_name}-{release_version}-latest.{architecture}.raw')
    #TODO: use the uploaded file to register the s3 object as a snapshot. After the snapshot is complete, register the snapshot as an ami
    snapshot_complete = False
    #TODO: importing the snapshot should return output that includes the snapshot id. we will need to save that snapshot id when the import task is completed. 
    snapshot_task = ec2.import_snapshot(
        Description=f'CentOS {release_version} Stream {amzn_architecture} based on Amazon Linux 2',
        DiskContainer={
            'Description': f'CentOS {release_version} Stream {amzn_architecture} based on Amazon Linux 2',
            'Format': 'raw',
            'Url': f's3://{S3_BUCKET}/{S3_BUCKET_PREFIX}/{file_name}-{release_version}-{s3_upload_date}.{architecture}.raw',
            'UserBucket': {
                'S3Bucket': S3_BUCKET,
                'S3Key': f'{S3_BUCKET_PREFIX}/{file_name}-{release_version}-{s3_upload_date}.{architecture}.raw'
            }
        }
    )
    snapshot_task_id = snapshot_task['ImportTaskId']
    #TODO: monitor the snapshot import. When it is complete, then you can begin the register-image process
    while snapshot_complete == False:
        snapshot_status = ec2.describe_import_snapshot_tasks(
            ImportTaskIds=[
                'import-snapshot-task-id'
            ]
        )
        if snapshot_status['ImportSnapshotTasks'][0]['SnapshotTaskDetail']['Status'] == 'completed':
            snapshot_complete = True
            snapshot_id = snapshot_status['ImportSnapshotTasks'][0]['SnapshotTaskDetail']['SnapshotId']
        else:
            time.sleep(30)
    #DONE: register the image file as a new version of the AMI
    ec2.register_image(
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
        Description=f'CentOS {release_version} Stream {amzn_architecture} {s3_upload_date}',
        EnaSupport=True,
        Imdsv2Support=True,
        Name=f'CentOS Stream {release_version} {amzn_architecture}, {s3_upload_date}',
        RootDeviceName='/dev/sda1',
        VirtualizationType='hvm',
        SriovNetSupport='simple',
        ImageLocation=f'{S3_BUCKET}/{S3_BUCKET_PREFIX}/{file_name}-{release_version}-{s3_upload_date}.{architecture}.raw'
    )

    if __name__ == '__main__':
        #TODO: create a CLI to override the values found in the toml config file. Also, create a config file option to pass in an alternative config file. 

        #TODO: use the click library to create the cli
        #TODO: execute run with all of the content. 
        run(release_version)



def cli(release_version: str, config_file: str) -> None:
    run(release_version, config_file)

if __name__ == '__main__':
    print(f'Running with release version: {release_version}')
    print(f'Running with config file: {config_file}')
    cli(release_version, config_file)