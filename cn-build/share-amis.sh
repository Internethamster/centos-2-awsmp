#!/bin/env bash

NAME=${NAME:-$1}

ARCH="$(arch)"

if [[ "$ARCH" == "aarch64" ]]
then
    ARCHITECTURE="arm64"
else
    ARCHITECTURE=$ARCH
fi

REGION=cn-northwest-1

ImageId=$(aws ssm get-parameter --name /amis/centos/${ARCHITECTURE}/${NAME,,}/latest --query 'Parameter.Value' --output text)

snapshotId=$(aws ec2 describe-images --image-ids $ImageId \
                 --query 'Images[0].BlockDeviceMappings[?contains(DeviceName, `sda1`) == `true`].Ebs.SnapshotId' \
                 --output text)
	     

aws ec2 modify-snapshot-attribute \
    --snapshot-id $snapshotId \
    --region $REGION \
    --attribute createVolumePermission \
    --operation-type add \
    --user-ids 336777782633 882445023432 830553105645

aws ec2 describe-snapshot-attribute --attribute createVolumePermission --snapshot-id $snapshotId

aws ec2 modify-image-attribute \
    --image-id $ImageId  \
    --region $REGION \
    --attribute launchPermission \
    --operation-type add \
    --user-ids 336777782633 882445023432 830553105645

aws ec2 describe-image-attribute --attribute launchPermission --image-id $ImageId
