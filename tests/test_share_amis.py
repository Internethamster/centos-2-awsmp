# test functions in the centow-2-awsmp/share_amis.py script
import unittest
import boto3
import json
import os
import sys
import time
import share_amis
from moto import mock_ec2
from moto import mock_sts

class TestShareAmis(unittest.TestCase):

    @mock_ec2
    def test_get_regions(self):
        ec2 = boto3.client('ec2', region_name='us-east-1')
        regions = share_amis.get_regions(ec2)
        self.assertEqual(len(regions), 1)
        self.assertEqual(regions[0], 'us-east-1')

    @mock_ec2
    def test_get_images(self):
        ec2 = boto3.client('ec2', region_name='us-east-1')
        images = share_amis.get_images(ec2)
        self.assertEqual(len(images), 1)
        self.assertEqual(images[0]['ImageId'], 'ami-1234abcd')

    @mock_ec2
    def test_share_images(self):
        ec2 = boto3.client('ec2', region_name='us-east-1')
        share_amis.share_images(ec2, ['ami-1234abcd'], ['123456789012'])

if __name__ == '__main__':
    unittest.main()
