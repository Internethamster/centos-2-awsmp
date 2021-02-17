#!/bin/bash
# CENTOS-7 BUILDER
set -x -euo pipefail

NAME="CentOS-7"
ARCH="x86_64"
RELEASE="2009"

S3_PREFIX="disk-images"
S3_BUCKET="aws-marketplace-upload-centos"

VERSION="FIXME"
DATE=$(date +%Y%m%d)


source ./shared_functions.sh


if [[ -z $REGION ]]; then
    exit_abnormal
fi

FILE="${NAME}-${ARCH}-GenericCloud-${RELEASE}.qcow2"
LINK="http://cloud.centos.org/centos/7/images/${FILE}"

S3_REGION=$(get_s3_bucket_location $S3_BUCKET)

SUBNET_ID=$(get_default_vpc_subnet $S3_REGION)
SECURITY_GROUP_ID=$(get_default_sg_for_vpc $S3_REGION)

if [ ! -e ${NAME}-${DATE}.txt ]; then
    echo "0" > ${NAME}-${DATE}.txt
fi

if [ "$VERSION" == "FIXME" ]; then
    echo $(( $(cat ${NAME}-${DATE}.txt) + 1 )) > ${NAME}-${DATE}.txt
    VERSION=$(cat ${NAME}-${DATE}.txt)
fi


IMAGE_NAME="${NAME}-${RELEASE}-${DATE}_${VERSION}.${ARCH}"
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

aws --region $S3_REGION s3 cp ./${IMAGE_NAME}.raw  s3://${S3_BUCKET}/${S3_PREFIX}/
rm ${IMAGE_NAME}.raw

DISK_CONTAINER="Description=${IMAGE_NAME},Format=raw,UserBucket={S3Bucket=${S3_BUCKET},S3Key=${S3_PREFIX}/${IMAGE_NAME}.raw}"

IMPORT_SNAP=$(aws ec2 import-snapshot --region $S3_REGION --client-token ${NAME}-$(date +%s) --description "Import Base ${NAME} ${ARCH} Image" --disk-container $DISK_CONTAINER)
err "snapshot suceessfully imported to $IMPORT_SNAP"

snapshotTask=$(echo $IMPORT_SNAP | jq -Mr '.ImportTaskId')

while [[ "$(aws ec2 --region $S3_REGION describe-import-snapshot-tasks --import-task-ids ${snapshotTask} --query 'ImportSnapshotTasks[0].SnapshotTaskDetail.Status' --output text)" == "active" ]] 
do
    aws ec2 --region $S3_REGION describe-import-snapshot-tasks --import-task-ids $snapshotTask
    err "import snapshot is still active."
    sleep 60
done
err "Import snapshot task is complete" 

snapshotId=$(aws ec2 --region $S3_REGION describe-import-snapshot-tasks --import-task-ids ${snapshotTask} --query 'ImportSnapshotTasks[0].SnapshotTaskDetail.SnapshotId' --output text)

err "Created snapshot: $snapshotId" 

sleep 20

DEVICE_MAPPINGS="[{\"DeviceName\": \"/dev/sda1\", \"Ebs\": {\"DeleteOnTermination\":true, \"SnapshotId\":\"${snapshotId}\", \"VolumeSize\":10, \"VolumeType\":\"gp2\"}}]"

err $DEVICE_MAPPINGS

ImageId=$(aws ec2 register-image --region $S3_REGION --architecture=x86_64 \
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

aws ec2 run-instances --region $S3_REGION --subnet-id $SUBNET_ID --image-id $ImageId --instance-type c5.large --key-name "previous" --security-group-ids $SECURITY_GROUP_ID $DRY_RUN && \
    rm -f ./${IMAGE_NAME}.raw

# Share AMI with AWS Marketplace
# err "./share-amis.sh $snapshotId $ImageId"
# ./share-amis.sh $snapshotId $ImageId

