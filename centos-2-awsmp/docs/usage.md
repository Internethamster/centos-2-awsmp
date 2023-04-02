centos-2-awsmp

```
$ centos-2-awsmp update_images --centos-stream-release 9
```

For further information about flags and environment variables:

```
$ centos-2-awsmp -h
```

#### Centos-2-awsmp Flags and Arguments

```bash
usage: centos-2-awsmp [-h]

positional arguments:

optional arguments:
  -h, --help                    show this help message and exit
  -r  --centos-stream-release   centos stream release [89]
  -a  --all                     update all releases
  -d  --debug                   show all of the debug level logging
  -j  --json                    return details in raw json format
  -v  --version                 display the current version of centos-2-awsmp
  -l [LOAD_FORM], --load-form   AWS Marketplace Load Form to update

  --sql-file  [FILENAME]        file in which to store the sqlite database
  --dynamo-db [TABLENAME]       write to dynamo_db table

  environment variable examples:
    CENTOS-2-AWSMP_COLORIZE=1
    CENTOS-2-AWSMP_SQLITE_DB=filename
    CENTOS-2-AWSMP_DYNAMO_DB=centosimages
    CENTOS-2-AWSMP_LOAD_FORM=Fedora-CentOS_Product_Load_Form-base.xlsx
    CENTOS-2-AWSMP_RELEASE=9
```
