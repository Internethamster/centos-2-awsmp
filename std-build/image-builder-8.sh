#!/bin/bash
# CENTOS-8 BUILDER
set -euo pipefail
MAJOR_RELEASE=8
NAME="CentOS-${MAJOR_RELEASE}"

ARCH="x86_64"
MINOR_RELEASE="3.2011-20201204.2"
VERSION=${1:-FIXME}

DATE=$(date +%Y%m%d)
REGION=cn-northwest-1
SUBNET_ID=subnet-0890b142
SECURITY_GROUP_ID=sg-5993f530
DRY_RUN="--dry-run"

usage() {
    echo "Usage: $0 [ -v VERSION ] [ -b BUCKET_NAME ] [ -k OBJECT_PREFIX ] [ -a ARCH ] [ -n NAME ] [ -r RELEASE ] [ -p ] " 1>&2
}
exit_abnormal() {
    usage
    exit 1
}


VERSION="FIXME"
S3_BUCKET="aws-marketplace-upload-centos"
S3_PREFIX="disk-images"

while getopts ":v:t:r:a:n:b:k:p" options; do
    case "${options}" in
        v)
            VERSION=${OPTARG}
            ;;
        t)
            S3_BUCKET=${OPTARG}
            ;;
        k)
            OBJECT_PREFIX=${OPTARG}
            ;;
        r)
            RELEASE=${OPTARG}
            ;;
        a)
            ARCH=${OPTARG}
            ;;
        n)
            NAME=${OPTARG}
            ;;
        :)
            "Error: -${OPTARG} requires an argument"
            ;;
        *)
            exit_abnormal
            ;;
    esac
done


FILE="${NAME}-ec2-${MAJOR_RELEASE}.${MINOR_RELEASE}.${ARCH}"
LINK="http://cloud.centos.org/centos/8/$ARCH/images/${FILE}.qcow2"

GenericImage="https://cloud.centos.org/centos/8/x86_64/images/CentOS-8-ec2-8.3.2011-20201204.2.x86_64.qcow2"

function err() {
    echo "[$(date +'%Y-%m-%dT%H:%M:%S%z')]: $@" >&2
}

if [ ! -e ${NAME}-${DATE}.txt ]; then
    echo "0" > ${NAME}-${DATE}.txt
fi

if [ "$VERSION" == "FIXME" ]; then
    echo $(( $(cat ${NAME}-${DATE}.txt) + 1 )) > ${NAME}-${DATE}.txt
    VERSION=$(cat ${NAME}-${DATE}.txt)
fi

IMAGE_NAME="${NAME}.${MINOR_RELEASE}-${DATE}_${VERSION}.${ARCH}"

curl -C - -o ${FILE}.qcow2 $LINK

err "$LINK retrieved and saved at $(pwd)/${FILE}.qcow2"

qemu-img convert ./${FILE}.qcow2 ${IMAGE_NAME}.raw
err "${IMAGE_NAME}.raw created"

virt-edit -a ./${IMAGE_NAME}.raw /etc/sysconfig/selinux -e "s/^\(SELINUX=\).*/\1permissive/"
err "Modified ./${IMAGE_NAME}.raw to make it permissive"

virt-customize -a ./${IMAGE_NAME}.raw  --update --install cloud-init
err "virt-customize -a ./${IMAGE_NAME}.raw  --update

# virt-edit ./${IMAGE_NAME}.raw  /etc/cloud/cloud.cfg -e "s/name: centos/name: ec2-user/"
# err "Modified Image to move centos to ec2-user"

virt-edit -a ./${IMAGE_NAME}.raw /etc/sysconfig/selinux -e "s/^\(SELINUX=\).*/\1enforcing/"
err "Modified ./${IMAGE_NAME}.raw to make it enforcing"

virt-customize -a ./${IMAGE_NAME}.raw --selinux-relabel
err "virt-customize -a ./${IMAGE_NAME}.raw --selinux relabel"

virt-sysprep -a ./${IMAGE_NAME}.raw
err "upgrading the current packages for the instance: ${IMAGE_NAME}"

err "Cleaned up the volume in preparation for the AWS Marketplace"

aws s3 cp ./${IMAGE_NAME}.raw  s3://davdunc-floppy/disk-images/
err "Upload ${IMAGE_NAME}.raw image to S3://davdunc-floppy/disk-images/"

DISK_CONTAINER="Description=${IMAGE_NAME},Format=raw,UserBucket={S3Bucket=davdunc-floppy,S3Key=disk-images/${IMAGE_NAME}.raw}"

IMPORT_SNAP=$(aws ec2 import-snapshot --region $REGION --client-token ${IMAGE_NAME}-$(date +%s) --description "Import Base $NAME ($ARCH) Image" --disk-container $DISK_CONTAINER)
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
              --description='${NAME}.${MINOR_RELEASE} ($ARCH) for HVM Instances' --virtualization-type hvm  \
              --root-device-name '/dev/sda1'     --name=${IMAGE_NAME}     --ena-support --sriov-net-support simple \
              --block-device-mappings "${DEVICE_MAPPINGS}" \
              --output text)

err "Produced Image ID $ImageId"
echo "SNAPSHOT : ${snapshotId}, IMAGEID : ${ImageId}, NAME : ${IMAGE_NAME}" >> ${NAME}-${MINOR_RELEASE}.txt

err "aws ec2 run-instances --region $REGION --subnet-id $SUBNET_ID --image-id $ImageId --instance-type c5n.large --key-name "davdunc@amazon.com" --security-group-ids $SECURITY_GROUP_ID"
aws ec2 run-instances --region $REGION --subnet-id $SUBNET_ID \
    --image-id $ImageId --instance-type c5n.large --key-name "previous" \
    --security-group-ids $SECURITY_GROUP_ID $DRY_RUN && rm -f ./${IMAGE_NAME}.raw
