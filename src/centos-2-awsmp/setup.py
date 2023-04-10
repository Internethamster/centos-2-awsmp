#!/usr/bin/env/python

   # Copyright 2022 David Duncan <davdunc@gmail.com>
   #
   # Licensed under the Apache License, Version 2.0 (the "License");
   # you may not use this file except in compliance with the License.
   # You may obtain a copy of the License at
   #
   #     http://www.apache.org/licenses/LICENSE-2.0
   #
   # Unless required by applicable law or agreed to in writing, software
   # distributed under the License is distributed on an "AS IS" BASIS,
   # WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
   # See the License for the specific language governing permissions and
   # limitations under the License.
from distutils.cmd import Command # pylint: disable=deprecated-module
from setuptools import setup, find_packages
# pylint: enable=unused-import
import centos-2-awsmp

# pylint: disable=consider-using-f-string
long_description = """
%(README)s

# News

%(CHANGES)s

""" % read('README', 'CHANGES')
# pylint: enable=consider-using-f-string

setup(
    name='centos-2-awsmp',
    version=centos-2-awsmp.__version__,
    description='An Application for building the product load details for AWS Marketplace',
    long_description=long_description,
    long_desscription_content_type='text/markdown',
    classifiers=[
        "Development Status :: 1 - Planning",
        "Environment :: Console",
        "Intended Audience :: Developers"
        "Programming Language :: Python :: 3",
        "Programming Language :: Python :: 3.10",
    ],
    keywords='centos-2-awsmp centos awsmarketplace aws marketplace',
    author='David Duncan',
    author_email='davdunc@gmail.com',
    maintainer='David Duncan'
    maintainer_email='davdunc@gmail.com',
    url='https://github/Internethamster/centos-2-awsmp',
    license='ASL2.0',
    packages=find_packages(),
    entry_points={
        'console_scripts': [
            'centos-2-awsmp = centos-2-awsmp.awsmp:command_line_runner',
            ]
        },
    install_requires=[
        'boto3',
        'pandas',
    ],
    cmdclass={
        'lint': Lint
        }
    )
