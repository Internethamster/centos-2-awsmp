#!/bin/bash
# CENTOS-7 BUILDER
set -euo pipefail

NAME="CentOS-7"
ARCH="x86_64"
RELEASE="2003"

DATE=$(date +%Y%m%d)
REGION=us-west-2
SUBNET_ID=subnet-f87a20d3
SECURITY_GROUP_ID=sg-973546bc
DRY_RUN="--dry-run"
S3_BUCKET="aws-marketplace-upload-centos"
FILE="${NAME}-${ARCH}-GenericCloud-${RELEASE}.qcow2.xz"
LINK="http://cloud.centos.org/centos/7/images/${FILE}"
GenericImage7="http://cloud.centos.org/centos/7/images/${NAME}-${ARCH}-GenericCloud-${RELEASE}.qcow2.xz"

function err() {
  echo "[$(date +'%Y-%m-%dT%H:%M:%S%z')]: $@" >&2
}


err "$LINK to be retrieved and saved at $(pwd)/${NAME}-${ARCH}.qcow2"
curl -C - -o ${FILE} $LINK


err "xz -d ${FILE}" 
xz -d --force ${FILE} 

err "${NAME}-${DATE}-${RELEASE}.$ARCH.raw created" 
qemu-img convert \
         ./${NAME}-${ARCH}-GenericCloud-${RELEASE}.qcow2 ${NAME}-${DATE}-${RELEASE}.${ARCH}.raw

err "Modified ./${NAME}-${DATE}-${RELEASE}.${ARCH}.raw to make it permissive"
virt-edit ./${NAME}-${DATE}-${RELEASE}.${ARCH}.raw /etc/sysconfig/selinux -e "s/^\(SELINUX=\).*/\1permissive/"

err "virt-customize -a ./${NAME}-${DATE}-${RELEASE}.${ARCH}.raw  --update --install cloud-init"
virt-customize -a ./${NAME}-${DATE}-${RELEASE}.${ARCH}.raw  --update --install cloud-init

# virt-edit ./${NAME}-${DATE}-${RELEASE}.${ARCH}.raw  /etc/cloud/cloud.cfg -e "s/name: centos/name: ec2-user/"
# err "Modified Image to move centos to ec2-user"

err "virt-customize -a ./${NAME}-${DATE}-${RELEASE}.${ARCH}.raw --selinux-relabel" 
virt-customize -a ./${NAME}-${DATE}-${RELEASE}.${ARCH}.raw --selinux-relabel

err "upgrading the current packages for the instance: ${NAME}-${DATE}-${RELEASE}.${ARCH}"
virt-sysprep -a ./${NAME}-${DATE}-${RELEASE}.${ARCH}.raw

err "Cleaned up the volume in preparation for the AWS Marketplace"
err "Upload ${NAME}-${DATE}-${RELEASE}.${ARCH}.raw image to S3://${S3_BUCKET}/disk-images/"
aws s3 cp ./${NAME}-${DATE}-${RELEASE}.${ARCH}.raw  s3://${S3_BUCKET}/disk-images/

DISK_CONTAINER="Description=${NAME}-${DATE}-${RELEASE}.${ARCH},Format=raw,UserBucket={S3Bucket=${S3_BUCKET},S3Key=disk-images/${NAME}-${DATE}-${RELEASE}.${ARCH}.raw}"
IMPORT_SNAP=$(aws ec2 import-snapshot --region $REGION --client-token ${NAME}-$(date +%s) --description "Import Base CentOS8 X86_64 Image" --disk-container $DISK_CONTAINER)
err "snapshot suceessfully imported to $IMPORT_SNAP"

snapshotTask=$(echo $IMPORT_SNAP | jq -Mr '.ImportTaskId')

while [[ "$(aws ec2 describe-import-snapshot-tasks --import-task-ids ${snapshotTask} --query 'ImportSnapshotTasks[0].SnapshotTaskDetail.Status' --output text)" == "active" ]] 
do
    aws ec2 --region $REGION describe-import-snapshot-tasks --import-task-ids $snapshotTask
    err "import snapshot is still active."
    sleep 60
done
err "Import snapshot task is complete" 

snapshotId=$(aws ec2 describe-import-snapshot-tasks --import-task-ids ${snapshotTask} --query 'ImportSnapshotTasks[0].SnapshotTaskDetail.SnapshotId' --output text)

err "Created snapshot: $snapshotId" 

sleep 20

DEVICE_MAPPINGS="[{\"DeviceName\": \"/dev/sda1\", \"Ebs\": {\"DeleteOnTermination\":true, \"SnapshotId\":\"${snapshotId}\", \"VolumeSize\":10, \"VolumeType\":\"gp2\"}}]"

err $DEVICE_MAPPINGS

ImageId=$(aws ec2 register-image --region $REGION --architecture=x86_64 \
	      --description="${NAME}-${DATE} 7.${RELEASE} (${ARCH}) for HVM Instances" --virtualization-type hvm  \
	      --root-device-name '/dev/sda1'     --name=${NAME}-${DATE}-${RELEASE}.$ARCH     --ena-support --sriov-net-support simple \
	      --block-device-mappings "${DEVICE_MAPPINGS}" \
	      --output text)

err "Produced Image ID $ImageId"

err "aws ec2 run-instances --region $REGION --subnet-id $SUBNET_ID --image-id $ImageId --instance-type c5n.large --key-name \"precious\" --security-group-ids $SECURITY_GROUP_ID"
aws ec2 run-instances --region $REGION --subnet-id $SUBNET_ID --image-id $ImageId --instance-type c5.large --key-name "previous" --security-group-ids $SECURITY_GROUP_ID $DRY_RUN && \
    rm -f ./${NAME}-${DATE}-${RELEASE}.${ARCH}.raw

# Share AMI with AWS Marketplace
# err "./share-amis.sh $snapshotId $ImageId"
# ./share-amis.sh $snapshotId $ImageId
