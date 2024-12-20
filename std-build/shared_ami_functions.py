import os
import requests
from botocore.config import Config


#Create a function that uses python libraries to download and save the cloud image using the url defined in the config file
def download_file(url: str) -> str:
   local_filename = url.split('/')[-1]
   # NOTE the stream=True parameter below
   with requests.get(url, stream=True) as r:
       r.raise_for_status()
       with open(local_filename, 'wb') as f:
           for chunk in r.iter_content(chunk_size=8192): 
               # If you have chunk encoded response uncomment if
               # and set chunk_size parameter to None.
               #if chunk: 
               f.write(chunk)
    return local_filename

def build_download_url(release_version: str, architecture: str, file_name: str) -> str:
    return f'https://cloud.centos.org/centos/{release_version}-stream/{architecture}/images/{file_name}-{release_version}-latest.{architecture}.raw.xz'

def build_ami_name(release_version: str, architecture: str, file_name: str) -> str:
    return f'{file_name}-{release_version}-{build_date}.{architecture}'


def load_config(config_file):
       # If the config_file is located, then we will use it, otherwise we will use the default config file
    if config_file != f'{os.environ["HOME"]}/.config/centos_build_config.toml':
        try:
            config = load_config(config_file)
            return config
        except FileNotFoundError:
            print("Error: default location not found, trying home directory")
            config = load_config(f'{os.environ["HOME"]}/.centos_build_config.toml')
            return config
        finally:
            print("Error: could not load config file")
            exit(1)
    else:
        try:
            config = load_config(f'{os.environ["HOME"]}/.config/centos_build_config.toml')
            return config
        except FileNotFoundError:
            print("Error: could not load config file")
            exit(1)
