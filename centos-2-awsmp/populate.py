import pandas as pd
from openpyxl import load_workbook
import sqlite3
from dataclasses import dataclass

# TODO: Move this to a config file variable
# TODO: Download or duplicate the
CentOS_Images_URL = "https://git.centos.org/centos/centos.org/raw/main/f/_data/aws-images.csv"
Marketplace_Load_Form = './AWS_Marketplace_2P_Product_Load_Form.xlsx'
Marketplace_Load_Form_Sheet_Name = 'New AMI Version '

def load_form_copy(load_form: str):
    shutil.copy(load_form,
Updated_Load_Form = load_form_copy(Marketplace_Load_Form)
# Load the Data from the URL into the Datafram
CentOS_Images_df = pd.read_csv(CentOS_Images_URL)
Load_Form_2_df = pd.read_excel(Marketplace_Load_Form, header=2, sheet_name=Marketplace_Load_Form_Sheet_Name)
Load_Form_1_df = pd.read_excel(Marketplace_Load_Form, header=1, sheet_name=Marketplace_Load_Form_Sheet_Name)


# Create an in-memory images database
conn = sqlite3.connect('file:cachedb?mode=memory&cache=shared')
cur = conn.cursor()
CentOS_Images_df.to_sql('machine_images', conn, if_exists='replace', index=False)


# Load_Form_Writer = pd.ExcelWriter(Marketplace_Load_Form, engine='openpyxl')
# Load_Form_book   = load_workbook(Marketplace_Load_Form)
# Load_Form_Writer.book = Load_Form_book

def _unique_architectures(dataframe: pd.core.frame.DataFrame) -> numpy.ndarray:
    return dataframe['Architecture'].unique()
# For each Version and then each architecture, you will need a single line.
def _unique_Versions(dataframe: pd.core.frame.Dataframe) -> numpy.ndarray:
    return dataframe['Version'].unique()

# Assign a Row to each version
# First pull the detail from the Load Form into a dataframe
# - make the modifications there
# -

# A
@dataclass
class marketplace_listing():
    """Class for creating a product listing for the AWS Marketplace"""
    asin: str # Column A
    product_title: str #Column B
    listing_accessibility # Column C
    aws_accounts_accessible: list[str] = field(default_factory=list) # Column D
    eula_url: str # Column E
    aws_dependent_services: list = field(default=['AmazonEC2', 'AmazonEBS', 'AmazonVPC']) # Column F
    aws_terms: str # Column G
    short_description: str = "Short description of your product" # Column I
    description: str = "NEW DESCRIPTION" # Column J
    highlight_1: str # Column K
    highlight_2: str # Column L
    highlight_3: str # Column M
    product_category_1: str
    product_category_2: str
    product_category_3: str
    search_keywords: list[str] = field(default_factory=list)
    resource_name_1: str
    resource_name_2: str
    resource_name_3: str
    resource_url_1: str
    resource_url_2: str
    resource_url_3: str
    image_url: str
    product_video: str
    support_offered: bool = True
    support_information: str
    support_detail: str
    listing_type: str = "Single AMI"
    ami_virtualization_type: str = "HVM"
    architecture: str
    operating_system: str
    operating_system_version: str
    operating_system_username: str
    aws_services_required: list[str] = ['AmazonEC2', 'AmazonEBS', 'AmazonVPC']
    third_party_software_included: str
    version_title: str
    release_notes: str
    usage_instructions: str
    eula_text: str
    # region_availability['us-east-1'] = True
    region_availability: dict[str, bool] = field(default_factory=dict)
    # instance_availability['m5a.xlarge'] = True
    instance_availability: dict[str, bool] = field(default_factory=dict)
    security_group_1: str = field(default="tcp,22,22,0.0.0.0/0")
    security_group_2: str = field(init=False)
    security_group_3: str = field(init=False)
    security_group_4: str = field(init=False)
