#!/bin/false
## CentOS6 is deprecated. This is a placeholder, but no longer functional
# CENTOS-6 BUILDER
set -euo pipefail

NAME="CentOS-6"
ARCH="x86_64"
RELEASE="1907"
VERSION=${1:-FIXME}

DATE=$(date +%Y%m%d)
IMAGES_S3_BUCKET=aws-marketplace-upload-centos
S3_BUCKET_REGION=$(aws s3api get-bucket-location --bucket $IMAGES_S3_BUCKET \
                       --query 'LocationConstraint' --output text)
REGION=$S3_BUCKET_REGION
VpcID=$(aws ec2 describe-vpcs --region $S3_BUCKET_REGION --output text \
            --query 'Vpcs[?IsDefault == `true`].VpcId')
SUBNET_ID=$(aws ec2 describe-subnets --region $S3_BUCKET_REGION --output text \
                --query 'Subnets[?MapPublicIpOnLaunch == `true`].SubnetId | [0]')
SECURITY_GROUP_ID=$(aws ec2 describe-security-groups --region $S3_BUCKET_REGION \
                        --filters "Name=vpc-id,Values=${VpcID}" \
                        --query 'SecurityGroups[?GroupName == `default`].GroupId' \
                        --output text)
DRY_RUN="--dry-run"
FILE="${NAME}-${ARCH}-GenericCloud-${RELEASE}.qcow2"
LINK="http://cloud.centos.org/centos/6/images/${FILE}.xz"

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
IMAGE_NAME="${NAME}.${RELEASE}-${DATE}_${VERSION}.${ARCH}"

err "$LINK to be retrieved and saved at $(pwd)/${FILE}.xz"
curl -C - -o ${FILE}.xz ${LINK}

err "xz -d ${FILE}.xz"
xz -d --force ${FILE}.xz

err "${NAME}.${RELEASE}-${DATE}.$ARCH.raw created"
qemu-img convert \
         ./${FILE} ${IMAGE_NAME}.raw && rm ${FILE}

virt-edit ./${IMAGE_NAME}.raw /etc/sysconfig/selinux -e "s/^\(SELINUX=\).*/\1permissive/"
err "Modified ./${IMAGE_NAME}.raw to make it permissive"

virt-customize -v -a ./${IMAGE_NAME}.raw --update
err "virt-customize -a ./${IMAGE_NAME}.raw --update"

# The cloud-init configuration is already in the image, but the rpm is
#   not in the standard repository. It was necessary to install it
#   previously, but no longer.

# virt-customize -a ./${IMAGE_NAME}.raw --install cloud-init                                                                                                                                                       
# err "virt-customize -a ./${IMAGE_NAME}.raw --install cloud-init"                                                                                                                                                 

virt-customize -a ./${IMAGE_NAME}.raw --selinux-relabel
err "virt-customize -a ./${IMAGE_NAME}.raw --selinux-relabel"

err "upgrading the current packages for the instance: ${IMAGE_NAME}"
virt-sysprep -a ./${IMAGE_NAME}.raw

err "Cleaned up the volume in preparation for the AWS Marketplace"
err "Upload ${IMAGE_NAME}.raw image to S3://${IMAGES_S3_BUCKET}/disk-images/"
aws s3 --region ${S3_BUCKET_REGION} cp ./${IMAGE_NAME}.raw  s3://${IMAGES_S3_BUCKET}/disk-images/
rm ${IMAGE_NAME}.raw

DISK_CONTAINER="Description=${IMAGE_NAME},Format=raw,UserBucket={S3Bucket=${IMAGES_S3_BUCKET},S3Key=disk-images/${IMAGE_NAME}.raw}"

IMPORT_SNAP=$(aws ec2 import-snapshot --region ${S3_BUCKET_REGION} --client-token ${NAME}-$(date +%s) --description "Import Base ${NAME} (${ARCH}) Image" --disk-container $DISK_CONTAINER)
err "snapshot suceessfully imported to $IMPORT_SNAP"

snapshotTask=$(echo $IMPORT_SNAP | jq -Mr '.ImportTaskId')

while [[ "$(aws ec2 --region ${S3_BUCKET_REGION} describe-import-snapshot-tasks --import-task-ids ${snapshotTask} --query 'ImportSnapshotTasks[0].SnapshotTaskDetail.Status' --output text)" == "active" ]]
do
    aws ec2 --region ${S3_BUCKET_REGION} describe-import-snapshot-tasks --import-task-ids $snapshotTask
    err "import snapshot is still active."
    sleep 60
done
err "Import snapshot task is complete"

snapshotId=$(aws ec2 describe-import-snapshot-tasks --region ${S3_BUCKET_REGION} --import-task-ids ${snapshotTask} --query 'ImportSnapshotTasks[0].SnapshotTaskDetail.SnapshotId' --output text)

err "Created snapshot: $snapshotId"

sleep 20

DEVICE_MAPPINGS="[{\"DeviceName\": \"/dev/sda1\", \"Ebs\": {\"DeleteOnTermination\":true, \"SnapshotId\":\"${snapshotId}\", \"VolumeSize\":10, \"VolumeType\":\"gp2\"}}]"

err $DEVICE_MAPPINGS

ImageId=$(aws ec2 register-image --region ${S3_BUCKET_REGION} --architecture=${ARCH} \
                      --description="${NAME}.${RELEASE}-${DATE}_${VERSION} (${ARCH}) for HVM Instances"\
                      --virtualization-type hvm  \
                      --root-device-name '/dev/sda1' \
                      --name=${NAME}.${RELEASE}-${DATE}.$ARCH \
                      --ena-support --sriov-net-support simple \
                      --block-device-mappings "${DEVICE_MAPPINGS}" \
                      --output text)

if [ "$S3_BUCKET_REGION" != "us-east-1" ]
then
    err "Image: $ImageId in $S3_BUCKET_REGION must be copied to use-1"

    ImageId=$(aws ec2 copy-image --source-region $S3_BUCKET_REGION \
        --source-region $S3_BUCKET_REGION --source-image-id $ImageId \
        --description="${NAME}.${RELEASE}-${DATE}_${VERSION} (${ARCH}) for HVM Instances" \
        --name=${NAME}.${RELEASE}-${DATE}_${VERSION}.${ARCH} \
        --region us-east-1)

    ImageId=$(echo $ImageId | jq -Mr '.ImageId')
    err "Image copied to us-east-1 as $ImageId"
    snapshotId=$(aws ec2 describe-images --image-ids $ImageId \
        --region us-east-1 \
        --query 'Images[].BlockDeviceMappings[?DeviceName == `/dev/sda1`].Ebs.SnapshotId | []' \
        --output text)
    err "Snapshot copied to us-east-1 as $snapshotId"
fi

err "Produced Image ID $ImageId in $REGION"
echo "SNAPSHOT : ${snapshotId}, IMAGEID : ${ImageId}, NAME : ${IMAGE_NAME}, REGION : ${S3_BUCKET_REGION}" >> ${NAME}.${RELEASE}.txt
err "aws ec2 run-instances --region $S3_BUCKET_REGION --subnet-id $SUBNET_ID --image-id $ImageId --instance-type c5.large --key-name previous --security-group-ids $SECURITY_GROUP_ID"

aws ec2 run-instances --region us-east-1 --subnet-id $SUBNET_ID \
    --image-id $ImageId --instance-type c5.large --key-name "previous" \
    --security-group-ids $SECURITY_GROUP_ID $DRY_RUN && \
    rm -f ./${IMAGE_NAME}.raw
