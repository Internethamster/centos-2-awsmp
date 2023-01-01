#!/bin/bash
# CENTOS-Stream-8 BUILDER

# Set up a file that includes the content
set -euo pipefail

DRY_RUN="" # Dry run is handled on the command line with the "-d" command option

S3_BUCKET="aws-marketplace-upload-centos"
S3_PREFIX="disk-images"
DATE=$(date +%Y%m%d)
release_name="CentOS-Cloud"
release_short="CentOS-Cloud"
release_version='9'
MAJOR_RELEASE=$release_version
NAME="CentOS-Stream-ec2"
ARCH=$(arch)

if [[ "$ARCH" == "aarch64" ]]; then
    ARCHITECTURE="arm64"
    CPE_RELEASE=0
    CPE_RELEASE_DATE=20221219
    CPE_RELEASE_REVISION=

    QEMU_IMG="taskset -c 1 qemu-img"
    VIRT_CUSTOMIZE="taskset -c 1 virt-customize"
    VIRT_EDIT="taskset -c 1 virt-edit"
    VIRT_SYSPREP="taskset -c 1 virt-sysprep"

    INSTANCE_TYPE="m6g.large"
else
    ARCHITECTURE="$(arch)"
    CPE_RELEASE=0
    CPE_RELEASE_DATE=20221219
    CPE_RELEASE_REVISION=

    QEMU_IMG="qemu-img"
    VIRT_CUSTOMIZE="virt-customize"
    VIRT_EDIT="virt-edit"
    VIRT_SYSPREP="virt-sysprep"

    INSTANCE_TYPE="m6i.large"
fi

source ${0%/*}/shared_functions.sh

# Shared functions should set the region env var or we are in the wrong enviornment.
if [[ -z $REGION ]]
then
    exit_abnormal
fi

if [ ! -e ${NAME}-${DATE}.txt ]; then
    echo "0" > ${NAME}-${DATE}.txt
fi

if [ "$VERSION" == "FIXME" ]
then
    VERSION=
    echo $(( $(cat ${NAME}-${MAJOR_RELEASE}-${DATE}.txt) + 1 )) > ${NAME}-${MAJOR_RELEASE}-${DATE}.txt
    VERSION=$(cat ${NAME}-${MAJOR_RELEASE}-${DATE}.txt)
fi

IMAGE_NAME="${NAME}-${MAJOR_RELEASE}-${DATE}.${VERSION}.${ARCH}"
err "IMAGE NAME: ${IMAGE_NAME}"
FILE="${IMAGE_NAME}.qcow2"

LINK=https://cloud.centos.org/centos/${MAJOR_RELEASE}-stream/${ARCH}/images/${NAME}-${ARCH}-${MAJOR_RELEASE}-${CPE_RELEASE_DATE}.${CPE_RELEASE}.${ARCH}.qcow2

S3_REGION=$(get_s3_bucket_location $S3_BUCKET)

SUBNET_ID=$(get_default_vpc_subnet $S3_REGION)

SECURITY_GROUP_ID=$(get_default_sg_for_vpc $S3_REGION)

IMAGE_NAME="${NAME}-${MAJOR_RELEASE}-${CPE_RELEASE_DATE}.${CPE_RELEASE}-${DATE}.${VERSION}.${ARCH}"

if [[ $(curl -Is ${LINK}.xz | awk '/HTTP/ { print $2 }') == 200 ]] # Prefer the compressed file
   then
       err "$LINK to be retrieved and saved at ./${FILE}.xz"
       curl -C - -o ${FILE}.xz ${LINK}.xz
       FILE_STATE="COMPRESSED"
elif [[ $(curl -Is ${LINK} | awk '/HTTP/ { print $2 }') == 200 ]]
then
       err "$LINK to be retrieved and saved at ./${FILE}"
       curl -C - -o ${FILE} ${LINK}
       FILE_STATE="NORMAL"
else
    err "$FILE was not located"
    exit_abnormal
fi

if [[ "$FILE_STATE" == "COMPRESSED" ]]
   then
       err "xz -d ${FILE}.xz"
       xz -d --force ${FILE}.xz && FILE_STATE="NORMAL"
fi

err "$LINK retrieved and saved at $(pwd)/${FILE}"

${QEMU_IMG} convert ./${FILE} ${IMAGE_NAME}.raw && rm -f ${FILE}
err "${IMAGE_NAME}.raw created"

${VIRT_EDIT} -a ./${IMAGE_NAME}.raw /etc/sysconfig/selinux -e "s/^\(SELINUX=\).*/\1permissive/"
err "Modified ./${IMAGE_NAME}.raw to make it permissive"

${VIRT_CUSTOMIZE} -a ./${IMAGE_NAME}.raw  --update
err "${VIRT_CUSTOMIZE} -a ./${IMAGE_NAME}.raw  --update"

${VIRT_CUSTOMIZE} -a ./${IMAGE_NAME}.raw --selinux-relabel
err "${VIRT_CUSTOMIZE} -a ./${IMAGE_NAME}.raw --selinux-relabel"

${VIRT_EDIT} -a ./${IMAGE_NAME}.raw /etc/sysconfig/selinux -e "s/^\(SELINUX=\).*/\1enforcing/"
err "Modified ./${IMAGE_NAME}.raw to make it enforcing"

${VIRT_SYSPREP} -a ./${IMAGE_NAME}.raw
err "upgrading the current packages for the instance: ${IMAGE_NAME}"

err "Cleaned up the volume in preparation for the AWS Marketplace"

aws --region $S3_REGION s3 cp ./${IMAGE_NAME}.raw  s3://${S3_BUCKET}/${S3_PREFIX}/
err "Upload ${IMAGE_NAME}.raw image to S3://${S3_BUCKET}/${S3_PREFIX}/"
rm ${IMAGE_NAME}.raw

DISK_CONTAINER="Description=${IMAGE_NAME},Format=raw,UserBucket={S3Bucket=${S3_BUCKET},S3Key=${S3_PREFIX}/${IMAGE_NAME}.raw}"

IMPORT_SNAP=$(aws ec2 import-snapshot ${DRY_RUN} --region $S3_REGION --client-token ${IMAGE_NAME}-$(date +%s) --description "Import Base $NAME $MAJOR_RELEASE ($ARCH) Image" --disk-container $DISK_CONTAINER) &&\
    err "snapshot suceessfully imported to $IMPORT_SNAP"

snapshotTask=$(echo $IMPORT_SNAP | jq -Mr '.ImportTaskId')

while [[ "$(aws ec2 --region $S3_REGION describe-import-snapshot-tasks ${DRY_RUN} --import-task-ids ${snapshotTask} --query 'ImportSnapshotTasks[0].SnapshotTaskDetail.Status' --output text)" == "active" ]]
do
    aws ec2 --region $S3_REGION describe-import-snapshot-tasks ${DRY_RUN} --import-task-ids $snapshotTask
    err "import snapshot is still active."
    sleep 60
done
err "Import snapshot task is complete"

snapshotId=$(aws ec2 --region $S3_REGION describe-import-snapshot-tasks ${DRY_RUN} --import-task-ids ${snapshotTask} --query 'ImportSnapshotTasks[0].SnapshotTaskDetail.SnapshotId' --output text)
err "Created snapshot: $snapshotId"

sleep 20
IAD_snap=copySnapshotToRegion
err "Created $IAD_snap in us-east-1"
DEVICE_MAPPINGS="[{\"DeviceName\": \"/dev/sda1\", \"Ebs\": {\"DeleteOnTermination\":true, \"SnapshotId\":\"${IAD_snap}\", \"VolumeSize\":10, \"VolumeType\":\"gp2\"}}]"

err $DEVICE_MAPPINGS

ImageId=$(aws ec2 --region us-east-1 register-image ${DRY_RUN} --architecture=${ARCHITECTURE} \
              --description="${NAME}-${MAJOR_RELEASE} (${ARCHITECTURE}) for HVM Instances" \
              --virtualization-type hvm  \
              --root-device-name '/dev/sda1' \
              --name=${IMAGE_NAME} \
              --ena-support --sriov-net-support simple \
              --block-device-mappings "${DEVICE_MAPPINGS}" \
              --output text)

err "Produced Image ID $ImageId in us-east-1"
echo "SNAPSHOT : ${IAD_snap}, IMAGEID : ${ImageId}, NAME : ${IMAGE_NAME}" >> ${NAME}-${MAJOR_RELEASE}.txt

err "aws ec2 run-instances ${DRY_RUN} --region $S3_REGION --subnet-id $SUBNET_ID --image-id $ImageId --instance-type c5n.large --key-name "davdunc@amazon.com" --security-group-ids $SECURITY_GROUP_ID"
aws ec2 run-instances --region us-east-1 --subnet-id $SUBNET_ID \
    --image-id $ImageId --instance-type ${INSTANCE_TYPE} --key-name "previous" \
    --security-group-ids $SECURITY_GROUP_ID ${DRY_RUN}

# Share AMI with AWS Marketplace
# err "./share-amis.sh $snapshotId $ImageId"
# ./share-amis.sh $snapshotId $ImageId
