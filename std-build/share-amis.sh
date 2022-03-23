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
    --user-ids 679593333241 684062674729 425685993791 514427062609 014813956182

aws ec2 describe-snapshots --snapshot-ids $snapshotId --region $REGION && \
aws ec2 modify-snapshot-attribute \
    --snapshot-id $snapshotId \
    --region $REGION \
    --attribute createVolumePermission \
    --operation-type add \
    --user-ids 679593333241 684062674729 425685993791 514427062609 014813956182

aws ec2 describe-snapshot-attribute --region $REGION --attribute createVolumePermission --snapshot-id $snapshotId
aws ec2 describe-image-attribute --region $REGION --attribute launchPermission --image-id $ImageId

# 514427062609 is ec2-mvp-ops@amazon.com
# 425685993791 is a test account for validations from Red Hat
# 684062674729 is the account for sharing to the aws marketplace
# 679593333241 is the account for testing in the aws marketplace
# 014813956182 is the account for testing in the Lightsail group
