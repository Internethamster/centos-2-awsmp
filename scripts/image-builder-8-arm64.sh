#!/bin/bash
set -x -eu -o pipefail
RELEASE=$1
DATE=$(date +%Y%m%d)
REGION=us-west-2
SUBNET_ID=subnet-f87a20d3
SECURITY_GROUP_ID=sg-973546bc
DRY_RUN="--dry-run"
NAME="CentOS-8-ec2-8.2.2004"
BUILD_DATE=$(date +%Y%m%d)
IMAGE="CentOS-8-ec2-8.2.2004-20200611.2"
ARCH=$(arch)
ARCHITECTURE="arm64"
LINK="http://cloud.centos.org/centos/8/${ARCH}/images/${IMAGE}.${ARCH}.qcow2"



GenericImage="http://cloud.centos.org/centos/8/x86_64/images/CentOS-8-GenericCloud-8.2.2004-20200611.2.x86_64.qcow2"

function err() {
  echo "[$(date +'%Y-%m-%dT%H:%M:%S%z')]: $@" >&2
}



curl -C - -o ${NAME}-${ARCHITECTURE}.qcow2 http://cloud.centos.org/centos/8/${ARCH}/images/${NAME}-20200611.2.${ARCH}.qcow2

err "$LINK retrieved and saved at $(pwd)/${NAME}-${ARCHITECTURE}.qcow2"

RAW_DISK_NAME="${NAME}-${DATE}-${RELEASE}.${ARCHITECTURE}" # Do not include the extension
err "$RAW_DISK_NAME create begins"
qemu-img convert -p \
	 ./${NAME}-${ARCHITECTURE}.qcow2 ${RAW_DISK_NAME}.raw
err "$RAW_DISK_NAME create complete"

err "Modified ./${RAW_DISK_NAME}.raw to make it permissive"
virt-edit ./${RAW_DISK_NAME}.raw /etc/sysconfig/selinux -e "s/^\(SELINUX=\).*/\1permissive/"

err "virt-customize -a ./${RAW_DISK_NAME}.raw  --update --install cloud-init"
virt-customize -a ./${RAW_DISK_NAME}.raw  --update --install cloud-init

# virt-edit ./${RAW_DISK_NAME}.raw  /etc/cloud/cloud.cfg -e "s/name: centos/name: ec2-user/"
# err "Modified Image to move centos to ec2-user"

err "virt-customize -a ./${RAW_DISK_NAME}.raw --selinux relabel" 
virt-customize -a ./${RAW_DISK_NAME}.raw --selinux-relabel

err "upgrading the current packages for the instance: ${NAME}-${DATE}-${RELEASE}.${ARCHITECTURE}"
virt-sysprep -a ./${RAW_DISK_NAME}.raw

err "Cleaned up the volume in preparation for the AWS Marketplace"
err "Upload ${RAW_DISK_NAME}.raw image to S3://aws-marketplace-upload-centos/disk-images/"
aws s3 cp ./${RAW_DISK_NAME}.raw  s3://aws-marketplace-upload-centos/disk-images/

DISK_CONTAINER="Description=${IMAGE},Format=raw,UserBucket={S3Bucket=aws-marketplace-upload-centos,S3Key=disk-images/${RAW_DISK_NAME}.raw}"
IMPORT_SNAP=$(aws ec2 import-snapshot --region $REGION --client-token ${NAME}-$(date +%s) --description "Import Base CentOS8 X86_64 Image" --disk-container $DISK_CONTAINER)
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

ImageId=$(aws ec2 register-image --region $REGION --architecture=x86_64 \
	      --description='CentOS 8.2.2004 (x86_64) for HVM Instances' --virtualization-type hvm  \
	      --root-device-name '/dev/sda1' \
	      --name=${NAME}-${DATE}-${RELEASE}.${ARCHITECTURE} \
	      --ena-support --sriov-net-support simple \
	      --block-device-mappings "${DEVICE_MAPPINGS}" \
	      --output text
	  )

err "Produced Image ID $ImageId"

err "aws ec2 run-instances --region $REGION --subnet-id $SUBNET_ID --image-id $ImageId --instance-type m5.large --key-name "davdunc@amazon.com" --security-group-ids $SECURITY_GROUP_ID"
aws ec2 run-instances --region $REGION --subnet-id $SUBNET_ID --image-id $ImageId --instance-type m5.large --key-name "davdunc@amazon.com" --security-group-ids $SECURITY_GROUP_ID $DRY_RUN && \
    rm -f ./${RAW_DISK_NAME}.raw

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
    --user-ids "Add=[{UserId=679593333241}, {UserId=684062674729}, {UserId=425685993791}]"
