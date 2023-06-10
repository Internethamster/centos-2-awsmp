#!/bin/python3
from dataclasses import dataclass
from typing import Protocol


@dataclass
class Load_Form:
    product_code: str
    product_title
    instance_types: list
    regions: list
    special_regions: list
    partition: str

