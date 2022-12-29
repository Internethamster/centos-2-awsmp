#!/bin/bash
## CENTOS-8-STREAM BUILDER for CN
set -euo pipefail

DATE=$(date +%Y%m%d)

source ${0%/*}/centos-stream-8-config.sh
source ${0%/*}/shared_functions.sh
${0%/*}/download-image.py

if [[ -z $REGION ]]
then
    exit_abnormal
fi

if [[ ! -e ${NAME}-${DATE}.txt ]]
then
    echo "0" > ${NAME}-${DATE}.txt
fi

if [ "$VERSION" == "FIXME" ]; then
    unset VERSION
    echo $(( $(cat ${NAME}-${MAJOR_RELEASE}-${DATE}.txt) + 1 )) > ${NAME}-${MAJOR_RELEASE}-${DATE}.txt
    VERSION=$(cat ${NAME}-${MAJOR_RELEASE}-${DATE}.txt)
fi

BASE_URI="https://cloud.centos.org/centos"

GenericImage="https://cloud.centos.org/centos/8-stream/aarch64/images/CentOS-Stream-ec2-8-20210603.0.aarch64.qcow2"
LINK="${BASE_URI}/${UPSTREAM_RELEASE}/$ARCH/images/${UPSTREAM_FILE_NAME}.qcow2"
LINK2="${BASE_URI}/${MAJOR_RELEASE}-stream/${ARCH}/images/${NAME}-${MINOR_RELEASE}.${ARCH}.qcow2"
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

IMAGE_NAME="${NAME}-${DATE}.${VERSION}.${ARCH}"

curl -C - -o ${UPSTREAM_FILE_NAME}.qcow2 $LINK

err "$LINK retrieved and saved at $(pwd)/${UPSTREAM_FILE_NAME}.qcow2"

CMD="qemu-img convert"
if [[ "$ARCHITECTURE" == "arm64" ]]; then
    CMD="taskset -c 0 $CMD"
fi

$CMD ./${UPSTREAM_FILE_NAME}.qcow2 ${IMAGE_NAME}.raw
err "${IMAGE_NAME}.raw created"

CMD="virt-edit"
if [[ "$ARCHITECTURE" == "arm64" ]]; then
    CMD="taskset -c 0  $CMD"
fi
$CMD ./${IMAGE_NAME}.raw /etc/sysconfig/selinux -e "s/^\(SELINUX=\).*/\1permissive/"
err "Modified ./${IMAGE_NAME}.raw to make it permissive"

CMD="virt-customize"
if [[ "$ARCHITECTURE" == "arm64" ]]; then
    CMD="taskset -c 0 $CMD"
fi
$CMD -a ./${IMAGE_NAME}.raw  --update --install cloud-init
err "virt-customize -a ./${IMAGE_NAME}.raw  --update --install cloud-init"

# virt-edit ./${IMAGE_NAME}.raw  /etc/cloud/cloud.cfg -e "s/name: centos/name: ec2-user/"
# err "Modified Image to move centos to ec2-user"

CMD=virt-customize
if [[ "$ARCHITECTURE" == "arm64" ]]; then
    CMD="taskset -c 0 $CMD"
fi
$CMD -a ./${IMAGE_NAME}.raw --selinux-relabel
err "virt-customize -a ./${IMAGE_NAME}.raw --selinux relabel"

CMD=virt-sysprep

if [[ "$ARCHITECTURE" == "arm64" ]]; then

    CMD="taskset -c 0 $CMD"
fi
$CMD -a ./${IMAGE_NAME}.raw
err "upgrading the current packages for the instance: ${IMAGE_NAME}"

err "Cleaned up the volume in preparation for the AWS Marketplace"

aws s3 cp ./${IMAGE_NAME}.raw  s3://${S3_BUCKET}/${S3_PREFIX}/
err "Upload ${IMAGE_NAME}.raw image to S3://${S3_BUCKET}/${S3_PREFIX}/"

DISK_CONTAINER="Description=\'${IMAGE_NAME}\',Format=raw,UserBucket={S3Bucket=${S3_BUCKET},S3Key=${S3_PREFIX}/${IMAGE_NAME}.raw}"
err DISK_CONTAINER="$DISK_CONTAINER"
IMPORT_SNAP=$(aws ec2 import-snapshot --region $REGION --client-token ${IMAGE_NAME}-$(date +%s) --description "Import Base $NAME ($ARCH) Image" --disk-container "$DISK_CONTAINER")
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

ImageId=$(aws ec2 register-image --region $REGION --architecture=$ARCHITECTURE \
	      --description="${NAME}.${MINOR_RELEASE} ($ARCH) for HVM Instances" \
              --virtualization-type hvm --root-device-name '/dev/sda1' \
              --name=${IMAGE_NAME} --ena-support --sriov-net-support simple \
	      --block-device-mappings "${DEVICE_MAPPINGS}" \
	      --output text)

err "Produced Image ID $ImageId"
echo "SNAPSHOT : ${snapshotId}, IMAGEID : ${ImageId}, NAME : ${IMAGE_NAME}" >> ${NAME}-${MINOR_RELEASE}.txt

if [[ "$ARCHITECTURE" == "arm64" ]]
then
    INSTANCE_TYPE="c6g.large"
else
    INSTANCE_TYPE="c5n.large"
fi



err "aws ec2 run-instances --region $REGION --subnet-id $SUBNET_ID --image-id $ImageId --instance-type c5n.large --key-name "davdunc@amazon.com" --security-group-ids $SECURITY_GROUP_ID"
aws ec2 run-instances --region $REGION --subnet-id $SUBNET_ID \
    --image-id $ImageId --instance-type $INSTANCE_TYPE --key-name "previous" \
    --security-group-ids $SECURITY_GROUP_ID $DRY_RUN && rm -f ./${IMAGE_NAME}.raw

SSM_NAME=${DATE}-${VERSION}
aws ssm put-parameter --name "/amis/centos/${ARCHITECTURE}/centos-stream-ec2-8/${SSM_NAME}"  \
    --type "String" --value $ImageId --data-type "aws:ec2:image"
aws ssm put-parameter --name "/amis/centos/${ARCHITECTURE}/centos-stream-ec2-8/latest"  \
    --type "String" --value $ImageId --data-type "aws:ec2:image"
