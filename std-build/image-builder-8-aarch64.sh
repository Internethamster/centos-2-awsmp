#!/bin/bash

set -x -eu -o pipefail
# CentOS-8-ec2-8.4.2105-20210603.0.aarch64.qcow2
MAJOR_RELEASE="8"
MINOR_RELEASE="4.2105"
CPE_RELEASE_DATE="20210603"
CPE_RELEASE_REVISION="2"
RELEASE=$1
BUCKET_NAME=aws-marketplace-upload-centos
OBJECT_KEY="disk-images/"
DATE=$(date +%Y%m%d)
REGION=us-east-1
SUBNET_ID=subnet-f87a20d3
SECURITY_GROUP_ID=sg-973546bc
DRY_RUN="--dry-run"
NAME="CentOS-${MAJOR_RELEASE}-ec2-${MAJOR_RELEASE}.${MINOR_RELEASE}"
BUILD_DATE=$(date +%Y%m%d)
IMAGE="${NAME}-${CPE_RELEASE_DATE}.${CPE_RELEASE_REVISION}"
ARCH=$(arch)
if [[ "$ARCH" == "aarch64" ]]; then
    ARCHITECTURE="arm64"
else
    ARCHITECTURE="$(arch)"
fi

GenericImage="http://cloud.centos.org/centos/${MAJOR_RELEASE}/${ARCH}/images/${NAME}-${CPE_RELEASE_DATE}.${CPE_RELEASE_REVISION}.${ARCH}.qcow2"
LINK="https://cloud.centos.org/centos/${MAJOR_RELEASE}/${ARCH}/images/${IMAGE}.${ARCH}.qcow2"


function err() {
  echo "[$(date +'%Y-%m-%dT%H:%M:%S%z')]: $@" >&2
}

RAW_DISK_NAME="${NAME}-${BUILD_DATE}.${RELEASE}.${ARCHITECTURE}"
err "$RAW_DISK_NAME will be created from $LINK" 

curl -C - -o ${RAW_DISK_NAME}.qcow2 $LINK
err "$LINK retrieved and saved at $(pwd)/${RAW_DISK_NAME}.qcow2"

taskset -c 0 qemu-img convert \
	 ./${RAW_DISK_NAME}.qcow2 ${RAW_DISK_NAME}.raw

err "Modified ./${RAW_DISK_NAME}.raw to make it permissive"
taskset -c 0 virt-edit ./${RAW_DISK_NAME}.raw /etc/sysconfig/selinux -e "s/^\(SELINUX=\).*/\1permissive/"
err "virt-customize -a ./${RAW_DISK_NAME}.raw  --update"
taskset -c 1 virt-customize -a ./${RAW_DISK_NAME}.raw --update

# virt-edit ./${RAW_DISK_NAME}.raw  /etc/cloud/cloud.cfg -e "s/name: centos/name: ec2-user/"
# err "Modified Image to move centos to ec2-user"

err "virt-customize -a ./${RAW_DISK_NAME}.raw --selinux relabel" 
virt-customize -a ./${RAW_DISK_NAME}.raw --selinux-relabel

err "Modified ./${RAW_DISK_NAME}.raw to make it enforcing"
taskset -c 1 virt-edit ./${RAW_DISK_NAME}.raw /etc/sysconfig/selinux -e "s/^\(SELINUX=\).*/\1enforcing/"

err "upgrading the current packages for the instance: ${NAME}-${DATE}-${RELEASE}.${ARCHITECTURE}"
virt-sysprep -a ./${RAW_DISK_NAME}.raw

err "Cleaned up the volume in preparation for the AWS Marketplace"
err "Upload ${RAW_DISK_NAME}.raw image to s3://aws-marketplace-upload-centos/disk-images/"
aws s3 cp ./${RAW_DISK_NAME}.raw  s3://aws-marketplace-upload-centos/disk-images/

DISK_CONTAINER="Description=${IMAGE},Format=raw,UserBucket={S3Bucket=aws-marketplace-upload-centos,S3Key=disk-images/${RAW_DISK_NAME}.raw}"

IMPORT_SNAP=$(aws ec2 import-snapshot --region $REGION --client-token ${NAME}-$(date +%s) --description "Import Base CentOS8 ${ARCHITECTURE} Image" --disk-container $DISK_CONTAINER)
err "snapshot suceessfully imported to $IMPORT_SNAP"

snapshotTask=$(echo $IMPORT_SNAP | jq -Mr '.ImportTaskId')

while [[ "$(aws ec2 describe-import-snapshot-tasks --import-task-ids ${snapshotTask} --query 'ImportSnapshotTasks[0].SnapshotTaskDetail.Status' --output text)" == "active" ]] 
do
    aws ec2 describe-import-snapshot-tasks --import-task-ids $snapshotTask
    err "import snapshot is still active."
    sleep 60
done

snapshotId=$(aws ec2 describe-import-snapshot-tasks --import-task-ids ${snapshotTask} --query 'ImportSnapshotTasks[0].SnapshotTaskDetail.SnapshotId' --output text)

err "Created snapshot: $snapshotId" 

sleep 20

DEVICE_MAPPINGS="[{\"DeviceName\": \"/dev/sda1\", \"Ebs\": {\"DeleteOnTermination\":true, \"SnapshotId\":\"${snapshotId}\", \"VolumeSize\":10, \"VolumeType\":\"gp2\"}}]"

err $DEVICE_MAPPINGS

ImageId=$(aws ec2 register-image --region us-east-1 --architecture=$ARCHITECTURE \
	      --description="${NAME} (${ARCHITECTURE}) for HVM Instances" --virtualization-type hvm  \
	      --root-device-name '/dev/sda1'     --name=${RAW_DISK_NAME} \
	      --ena-support --sriov-net-support simple \
	      --block-device-mappings "${DEVICE_MAPPINGS}" \
	      --output text)

err "Produced Image ID $ImageId"

err "aws ec2 run-instances --region $REGION --subnet-id $SUBNET_ID --image-id $ImageId --instance-type m6g.large --key-name "davdunc@amazon.com" --security-group-ids $SECURITY_GROUP_ID"
aws ec2 run-instances --region $REGION --subnet-id $SUBNET_ID --image-id $ImageId --instance-type m6g.large --key-name "davdunc@amazon.com" --security-group-ids $SECURITY_GROUP_ID $DRY_RUN && \
    rm -f ./${RAW_DISK_NAME}.raw
    rm -f ./${RAW_DISK_NAME}.qcow2


# Share AMI with AWS Marketplace
aws ec2 modify-snapshot-attribute \
    --snapshot-id $snapshotId \
    --region $REGION \
    --attribute createVolumePermission \
    --operation-type add \
    --user-ids 679593333241 684062674729 425685993791

aws ec2 modify-image-attribute \
    --image-id $ImageId  \
    --region $REGION \
    --attribute launchPermission \
    --operation-type add \
    --user-ids 679593333241 684062674729 425685993791
