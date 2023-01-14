# Copy, build and update images for CentOS #

![CodeBuild_Badge](https://codebuild.us-west-2.amazonaws.com/badges?uuid=eyJlbmNyeXB0ZWREYXRhIjoiQ0tSMzNUcTJ3L0Z4ZG1iYTE0WmlHQ3kvMU9ab3hvd3NGVWhmTVBaYVJaemtwOVlxcm54OGNSRXdCdGp5T3hRRmN4Vi9ZTzVxQnU5ejJXQlg5VmlxaTg0PSIsIml2UGFyYW1ldGVyU3BlYyI6IlFRcHNRWCtkbVhpWmcxUk0iLCJtYXRlcmlhbFNldFNlcmlhbCI6MX0%3D&branch=main "CodeBuild Badge")

## Ansible Configuration  ##

- Set the /boto_profile/ in the aws_ec2.yml file in the ansible/inventory files to match the account in which the builds will be created. 
- Set the default region as aws_region to the region in which you will estabish your pipeline


# Copying images across multiple regions

Once the images are built in the Oregon (us-west-2) region, it's necessary to distribute them across all available regions for the deployment. 

A production isengard account can only include one of the opt-in
regions, so there will still need to be some copying of the images in
the AWS Marketplace.

## Generate the CLI Input ##

For the 8.5 images for arm64, I first describe the images and locate the most recently built: 

There are three components in the configuration that are needed for consitency in the distribution:

* The Name
* The Description
* A Unique identifier for the transaction (I generated it with `uuidgen`)

Here's an example from the distribution of the 8.5.2111 _ARM64_ images. 

`cat ./copy-ami-image-8.5.json`

```javascript

{
    "ClientToken": "9f1fb653-0c64-49a0-a994-1b070774ed6e",
    "Description": "CentOS-8-ec2-8.5.2111 (arm64) for HVM Instances",
    "Encrypted": false,
    "Name": "CentOS-8-ec2-8.5.2111-20211223-1.arm64",
    "SourceImageId": "ami-0f4f5fc1d370c72a3",
    "SourceRegion": "us-west-2",
    "DryRun": false
}
```
Don't encrypt the volumes, it makes them fail the copy process. (for now)
It would be ideal to have them encrypted. 

``` bash
for REGION in $(aws ec2 describe-regions --output text --query 'Regions[].RegionName')

for REGION in $(aws ec2 describe-regions --output text --query 'Regions[].RegionName')
do
    if [[ "$REGION" != "us-west-2" ]]
    then
        echo "Region : $REGION (below)" 
           aws ec2 --profile image-builder copy-image --region $REGION \
               --cli-input-json file://copy-ami-image-8.5.json
    fi
done

# Output
An error occurred (AuthFailure) when calling the CopyImage operation: AWS was not able to validate the provided access credentials
 {
    "ImageId": "ami-07ab5ea34aeead3df"
}
{
    "ImageId": "ami-0ce41f87a9159ec52"
}
{
    "ImageId": "ami-0ada6249ab9538e7e"
}
{
    "ImageId": "ami-02d7390ef71d53d0e"
}
{
    "ImageId": "ami-0823b33d9f0a575e7"
}
{
    "ImageId": "ami-001e3dbe94cf6668f"
}
{
    "ImageId": "ami-0cea66c28c1c6fc3b"
}
{
    "ImageId": "ami-000e278fa25a764fc"
}
{
    "ImageId": "ami-05c7db67785f3c0f6"
}
{
    "ImageId": "ami-0dced82e5f0bb05c8"
}

An error occurred (AuthFailure) when calling the CopyImage operation: AWS was not able to validate the provided access credentials
{
    "ImageId": "ami-027567b320f1f72c5"
}
{
    "ImageId": "ami-0fc8b457e09b02373"
}
{
    "ImageId": "ami-0484fa2d26c418cf0"
}

An error occurred (AuthFailure) when calling the CopyImage operation: AWS was not able to validate the provided access credentials
{
    "ImageId": "ami-0758e52c9f81208b1"
}
{
    "ImageId": "ami-002ff451764c67a8c"
}
{
    "ImageId": "ami-08f4c469c1791852b"
}
```
# Notes on Development

* How to pull the development branch.

```
curl -O --clobber https://github.com/Internethamster/centos-2-awsmp/archive/development/centos-2-awsmp-<version>.tar.gz
```

