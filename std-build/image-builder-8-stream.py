#!/usr/bin/python3

import requests as req
from bs4 import BeautifulSoup
soup = BeautifulSoup(html_doc, 'html.parser')
images_page = 'https://git.centos.org/centos/centos.org/blob/main/f/_data/aws-images.csv'


@dataclass
class Image(Object):
    def __init__(self):
        image_id = ""
        snapshot_id = ""
        product_codes = []
        marketplace_product_codes = []
