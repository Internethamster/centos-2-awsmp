from openpyxl import load_workbook
import sqlalchemy
import configparser
import argparse
from pathlib import Path
import os


from pathlib import PurePath, Path

def buildconfigfilepath(filepath, extension='ini'):
    '''Build a configuration file path for the default location for the .ini file'''
    stem = PurePath(filepath).stem
    suffix = extension
    base_filename = stem + '.' + suffix
    parent = PurePath(filepath).parent
    print(f"{parent} is parent.")
    path_config = os.path.join(parent, base_filename)
    print(f"{path_config} is what we are trying to locate.")
    if os.path.isfile(path_config):
        return path_config
    else:
        # default to the current working directory
        parent = os.getcwd()
        path_config = os.path.join(parent, base_filename)
        return path_config

class metadata_sheet(Object):
    '''An AWS Marketplace Product Load Form includes a worksheet for updates'''
    def __init__(self, Workbook_name, Workbook_path):
        Workbook_Path = self.Workbook_path
        Workbook_Name = self.Workbook_name

    @property
    def worksheet(self):

class product(Object):
    ```This is a single product. Each product has defaults. A modified product is a version.```
    def __init__(self, product_id):
        self.product_id = product_id



if __name__ == "__main__":
    default_ini_file = buldconfigfilepath(__file__)

    parser = argparse.ArgumentParser(prog="awsmp-mp-loadform", description="Create a version in the AWS MP Load Form")

    parser.add_argument( "-r", "--region", type=str, help="The region in which to find content.")
    parser.add_argument( "-p", "--profile", type=str, help="The profile to use. (normally taken from IAM)")
    parser.add_argument( "-c", "--config", type=str,
                         help="The config file for custom configuration", default=default_ini_file )
    args = parser.parse_args()

    try:
        config = configparser.ConfigParser()
        config.read(args.config)
