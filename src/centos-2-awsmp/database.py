"""This module builds the database configuration for the AWS Product Load Form"""
# centos-2-awsmp/database.py

import configparser
import boto3
from pathlib import Path
from dataclasses import dataclass, field

@dataclass
class product_listing:
    product_id: str
    product_code: str
    listing_type: str = "AMI"
    accessibility: str = "Public"
    sku: str
    software_by: str
    title: str
    short_description: str
    full_description: str
    highlight_1: str
    highlight_2: str
    highlight_3: str
    product_category_1: str = "Operating Systems"
    product_category_2: str
    product_category_3: str
    resource_1_name: str
    resource_1_url: str
    resource_2_url: str
    resource_2_name: str
    resource_3_name: str
    resource_3_url: str
    image_url: str
    product_video: str
    support_offered: bool = True
    support_information: str
    support_detail: str
    refund_cancellation_policy: str
    
