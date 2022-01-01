from openpyxl import load_workbook
import configparser
import argparse
from pathlib import Path
import os

# **** CONSTANTS ****


def buildconfigfilepath(filepath, extension='ini'):
    base_filename = os.path.splitext(filepath)[0]
    ext_filename = base_filename + '.' + extension
    return ext_filename

class metadata_sheet(Object):
    def __init__(self, Workbook_name, Workbook_path):
        Workbook_Path = self.Workbook_path
        Workbook_Name = self.Workbook_name

    @property
    def worksheet(self):
        
    builder_client = boto3.client('ec2', build_config)

if __name__ == "__main__":
    default_ini_file = buldconfigfilepath(__file__)
    
    parser = argparse.ArgumentParser()
    parser.add_argument( "-r", "--region", type=str, help="The region in which to find content.")
    parser.add_argument( "-p", "--profile", type=str, help="The profile to use. (normally taken from IAM)")
    parser.add_argument( "-c", "--config", type=str, help="The config file for custom configuration",
                         default=default_ini_file)

    args = parser.parse_args()
                         
