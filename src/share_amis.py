#!/usr/bin/env python3
import sys
import os.path

import argparse
import logging
import boto3
import botocore
from botocore import config
import configparser

# if the configuration file is available, then we need to charge the config
# if the file is run interactively, then the cli will override them.
config_file = "share_amis.ini"
if os.path.exists(os.path.sep.join(['.', config_file])):
    image_config = configparser.ConfigParser()
    image_config.read(config_file)
    accounts = image_config['DEFAULT']['accounts'].split()
    region   = image_config['DEFAULT']['region'].strip()
    profile  = image_config['DEFAULT']['profile'].strip()


def _identify_snapshot_id(listing: callable) -> str:
    '''returns the snapshotId from the Image details'''
    Image_details = listing._get_image_details()
    # the official machine images have one and only one volume
    SnapshotId = Image_details['BlockDeviceMappings'][0]['Ebs']['SnapshotId']
    logging.warning("snapshotId determined from the image_details")
    logging.debug(f"Image details include {SnapshotId}")
    return SnapshotId

    

class listing():
    def __init__(self, image_id: str, ec2_client):
        self.image_id = image_id
        self.ec2_client = ec2_client
        self.snapshot_id = None
        self.image_attributes = None
        self.snapshot_attributes = None
        
    def _get_image_details(self) -> dict:
        '''returns a dictionary with the image details'''
        Image_details = self.ec2_client.describe_images(ImageIds=[self.image_id])['Images'][0]
        logging.warning(f'Image_details created for {self.image_id}')
        return Image_details

    def modify_image_attribute(self, accounts: list):
        response = self.ec2_client.modify_image_attribute(
            ImageId = self.image_id,
            Attribute='LaunchPermission',
            LaunchPermission={
                'Add': [ {'UserId': account } for account in accounts ]
            })
        logging.info(f"{response}")

    def modify_snapshot_attribute(self, accounts: list):
        response = self.ec2_client.modify_snapshot_attribute(
            Attribute='createVolumePermission',
            SnapshotId=self.snapshot_id,
            CreateVolumePermission={
                'Add': [ {'UserId': account } for account in accounts ]
            })
        logging.info(f"{response}")


    # def __str__(self):
    #     print(f"Image: {self.image_id}, SnapshotId: {self.snapshot_id}")
    
        
def add_snapshot_id_to_listing(ec2_client, listing) -> str:
    '''returns the snapshotId from the Image details'''
    Image_details = get_image_details(ec2_client, listing)
    # the official machine images have one and only one volume
    SnapshotId = Image_details['BlockDeviceMappings'][0]['Ebs']['SnapshotId']
    logging.warning("snapshotId determined from the image_details")
    logging.debug(f"Image details include {SnapshotId}")
    listing.snapshot_id(SnapshotId)
    
    
def add_image_launch_permissions_to_listing(listing, accounts, ec2_client):
    '''A function to share the image id with the assigned accounts'''
    response = ec2_client.modify_image_attributes(
        ImageId = listing.image_id,
        LaunchPermission={
            'Add': [ {'UserId': account } for account in accounts ]
            })
    return response

def add_launch_permissions_to_listing_snapshot(listing, accounts, ec2_client):
    response = ec2_client.modify_snapshot_attribute(
        ImageId = listing.image_id,
        Attribute='createVolumePermission',
        CreateVolumePermission={
            'Add': [ {'UserId': account } for account in accounts ]
            })
    return response
def ec2_client(profile='default', region='us-east-1'):
    try:
        session = boto3.Session(profile_name=profile)
        client = session.client('ec2', region_name=region)
    except Exception as e:
        logging.debug(f"{type(e)} raised while assembling the client")
        sys.exit(1)
    return client

def main(args: dict):
    '''main() is called when the file is run as a script'''
    config_file = "share_amis.ini"
    if os.path.exists(os.path.sep.join(['.', config_file])):
        image_config = configparser.ConfigParser()
        image_config.read(config_file)
        if image_config['DEFAULT']['accounts']:
            accounts = image_config['DEFAULT']['accounts'].split()
        if image_config['DEFAULT']['region']:
            region   = image_config['DEFAULT']['region'].strip()
        if image_config['DEFAULT']['profile']:
            profile  = image_config['DEFAULT']['profile'].strip()
        try:
            image = image_config['DEFAULT']['image_id']
        except KeyError as e:
            logging.debug("no image found in the config file")
    
    try:
        if args.region:
            region = args.region
        if args.profile:
            profile = args.profile
        if args.accounts:
            accounts = args.accounts.split()
        if args.image:
            image = args.image
        # if the session and ec2_client aren't created, you won't get the details you need. 
    except Exception as e:
        logging.info('failed to properfly create a session and/or client')
        sys.exit(1)
        
        # we need the snapshot id to ensure that we are getting the right image

    target_listing = listing(image, ec2_client(profile, region))
    target_listing.snapshot_id = _identify_snapshot_id(target_listing)
    target_listing.modify_image_attribute(accounts)
    target_listing.modify_snapshot_attribute(accounts)

if __name__ == "__main__":

    logging.info('The script was called interactively')

    parser = argparse.ArgumentParser()
    parser.add_argument("-a", "--accounts", help="comma separated list of accounts to share the image", type=str, required=False, nargs="+")
    parser.add_argument("-r", "--region", help="region in which the AMIs you want to share are saved", default="us-east-1")
    parser.add_argument("-p", "--profile", help="boto3 session profile name to use", default="default")
    parser.add_argument("-I", "--image", help="The AWS Machine Image [AMI] Id to share to the accounts")

    args = parser.parse_args()
    main(args)
