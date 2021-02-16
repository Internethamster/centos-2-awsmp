#!/bin/bash
# CENTOS-7 BUILDER
set -x -euo pipefail


VERSION="FIXME"
DATE=$(date +%Y%m%d)
FILE="${NAME}-${ARCH}-GenericCloud-${RELEASE}.qcow2"
LINK="http://cloud.centos.org/centos/7/images/${FILE}.xz"


source ./shared_functions.sh


if [[ -z $NAME ]] ; then
    NAME="CentOS-7"
fi
if [[ -z $ARCH ]] ; then
    ARCH="x86_64"
fi
if [[ -z $RELEASE ]]; then
    RELEASE="2003"
fi

if [[ -z $S3_BUCKET ]]; then
    S3_BUCKET="aws-marketplace-upload-centos"
fi

if [[ -z $S3_PREFIX ]]; then
    S3_PREFIX="disk-images"
fi

if [[ -z $REGION ]]; then
    exit_abnormal
fi

SUBNET_ID=$(get_default_vpc_subnet $REGION)
SECURITY_GROUP_ID=$(get_default_sg_for_vpc $REGION)

if [ ! -e ${NAME}-${DATE}.txt ]; then
    echo "0" > ${NAME}-${DATE}.txt
fi

if [ "$VERSION" == "FIXME" ]; then
    echo $(( $(cat ${NAME}-${DATE}.txt) + 1 )) > ${NAME}-${DATE}.txt
    VERSION=$(cat ${NAME}-${DATE}.txt)
fi


IMAGE_NAME="${NAME}-${RELEASE}-${DATE}_${VERSION}.${ARCH}"

err "$LINK to be retrieved and saved at $(pwd)/${FILE}.xz"
curl -C - -o ${FILE}.xz ${LINK}


err "xz -d ${FILE}.xz"
xz -d --force ${FILE}.xz

err "${NAME}-${RELEASE}-${DATE}.$ARCH.raw created" 
qemu-img convert \
         ./${FILE} ${IMAGE_NAME}.raw && rm ${FILE}

virt-edit ./${IMAGE_NAME}.raw /etc/sysconfig/selinux -e "s/^\(SELINUX=\).*/\1permissive/"
err "Modified ./${IMAGE_NAME}.raw to make it permissive"

virt-customize -a ./${IMAGE_NAME}.raw --update --install cloud-init
err "virt-customize -a ./${IMAGE_NAME}.raw --update --install cloud-init"

virt-customize -a ./${IMAGE_NAME}.raw --selinux-relabel
err "virt-customize -a ./${IMAGE_NAME}.raw --selinux-relabel" 

err "upgrading the current packages for the instance: ${IMAGE_NAME}"
virt-sysprep -a ./${IMAGE_NAME}.raw

err "Cleaned up the volume in preparation for the AWS Marketplace"
err "Upload ${IMAGE_NAME}.raw image to S3://${S3_BUCKET}/${S3_PREFIX}/"

aws s3 cp ./${IMAGE_NAME}.raw  s3://${S3_BUCKET}/${S3_PREFIX}/
rm ${IMAGE_NAME}.raw

DISK_CONTAINER="Description=${IMAGE_NAME},Format=raw,UserBucket={S3Bucket=${S3_BUCKET},S3Key=${S3_PREFIX}/${IMAGE_NAME}.raw}"

IMPORT_SNAP=$(aws ec2 import-snapshot --region $REGION --client-token ${NAME}-$(date +%s) --description "Import Base ${NAME} ${ARCH} Image" --disk-container $DISK_CONTAINER)
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
	      	      --description="${NAME}-${RELEASE}-${DATE}_${VERSION} (${ARCH}) for HVM Instances"\
	      	      --virtualization-type hvm  \
		      --root-device-name '/dev/sda1' \
		      --name=${NAME}-${RELEASE}-${DATE}.$ARCH \
		      --ena-support --sriov-net-support simple \
		      --block-device-mappings "${DEVICE_MAPPINGS}" \
		      --output text)

err "Produced Image ID $ImageId"
echo "SNAPSHOT : ${snapshotId}, IMAGEID : ${ImageId}, NAME : ${IMAGE_NAME}" >> ${NAME}-${RELEASE}.txt
err "aws ec2 run-instances --region $REGION --subnet-id $SUBNET_ID --image-id $ImageId --instance-type c5.large --key-name previous --security-group-ids $SECURITY_GROUP_ID"

aws ec2 run-instances --region $REGION --subnet-id $SUBNET_ID --image-id $ImageId --instance-type c5.large --key-name "previous" --security-group-ids $SECURITY_GROUP_ID $DRY_RUN && \
    rm -f ./${IMAGE_NAME}.raw

# Share AMI with AWS Marketplace
# err "./share-amis.sh $snapshotId $ImageId"
# ./share-amis.sh $snapshotId $ImageId

