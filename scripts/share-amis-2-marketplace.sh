#!/bin/bash
set -x 
REGION=us-east-1
ImageId=$1
snapshotId=$(aws ec2 describe-images --region $REGION --owners self --image-ids $ImageId --query 'Images[].BlockDeviceMappings[].Ebs.SnapshotId' --output text)

aws ec2 modify-image-attribute \
    --image-id $ImageId  \
    --region $REGION \
    --attribute launchPermission \
    --operation-type add \
    --user-ids 679593333241 684062674729 425685993791 425685993791

aws ec2 describe-snapshots --snapshot-ids $snapshotId --region $REGION && \
aws ec2 modify-snapshot-attribute \
    --snapshot-id $snapshotId \
    --region $REGION \
    --attribute createVolumePermission \
    --operation-type add \
    --user-ids 679593333241 684062674729 425685993791 425685993791

aws ec2 describe-snapshot-attribute --region $REGION --attribute createVolumePermission --snapshot-id $snapshotId
aws ec2 describe-image-attribute --region $REGION --attribute launchPermission --image-id $ImageId
