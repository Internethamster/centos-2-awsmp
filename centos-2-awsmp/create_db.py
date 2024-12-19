# ./create_db.py
#use a toml config file to import values stored in the APPCONFIG dictionary object
from __future__ import print_function # Python 2/3 compatibility
import toml
import boto3
from botocore.client import Config

APPCONFIG = toml.load('/home/davdunc/.centos_build_config.toml')

my_config = Config(
    signature_version = 'v4',
    retries = {
        'max_attempts': 4,
        'mode': 'standard'
    }
)
# create a dynamodb resource using the config
my_dynamodb = boto3.resource('dynamodb', config=my_config)
# the table definition should include the table name, the primary key of the AWS Marketplace listing product id, the AMI ID in us-east-1 , the last updated date, but does not require provisioned throughput

table = dynamodb.create_table(
    TableName='centosinawsmp',
    KeySchema=[
        {
            'AttributeName': 'centosid',
            'KeyType': 'HASH'  #Partition key
        }
    ],
    AttributeDefinitions=[
        {
            'AttributeName': 'centosid',
            'AttributeType': 'S'
        },
 
    ],
    ProvisionedThroughput={
        'ReadCapacityUnits': 10,
        'WriteCapacityUnits': 10
    },
)

print("Table status:", table.table_status)
