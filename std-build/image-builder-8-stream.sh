#!/bin/bash
# CENTOS-Stream-8 BUILDER

set -euo pipefail

# Configuration variables
DRY_RUN=""
export AWS_PAGER=""
REGION=us-east-1
S3_BUCKET="aws-marketplace-upload-centos"
S3_PREFIX="disk-images"
DATE=$(date +%Y%m%d)
NAME="CentOS-Stream-ec2"
ARCH=$(arch)
MAJOR_RELEASE='8'
VERSION=${VERSION:-"FIXME"}
SNAPSHOT_STATUS_DIR="/tmp/snapshot_status"
mkdir -p "$SNAPSHOT_STATUS_DIR"

# Architecture-specific configurations
declare -A ARCH_ARCHITECTURE
declare -A ARCH_INSTANCE_TYPE
declare -A ARCH_TASKSET

# aarch64 configurations
ARCH_ARCHITECTURE[aarch64]="arm64"
ARCH_INSTANCE_TYPE[aarch64]="m6g.large"
ARCH_TASKSET[aarch64]="taskset -c 1"

# x86_64 configurations
ARCH_ARCHITECTURE[x86_64]="x86_64"
ARCH_INSTANCE_TYPE[x86_64]="m6i.large"
ARCH_TASKSET[x86_64]=""

# Set architecture-specific variables
if [[ -n "${ARCH_ARCHITECTURE[$ARCH]}" ]]; then
    ARCHITECTURE=${ARCH_ARCHITECTURE[$ARCH]}
    INSTANCE_TYPE=${ARCH_INSTANCE_TYPE[$ARCH]}
    TASKSET_PREFIX=${ARCH_TASKSET[$ARCH]}
else
    echo "Unsupported architecture: $ARCH"
    exit 1
fi

# Update CPE Release information
CPE_RELEASE=0
CPE_RELEASE_DATE=20240603
CPE_RELEASE_REVISION=""

# Configure virtualization tools
QEMU_IMG="${TASKSET_PREFIX} qemu-img"
VIRT_CUSTOMIZE="${TASKSET_PREFIX} virt-customize"
VIRT_EDIT="${TASKSET_PREFIX} virt-edit"
VIRT_SYSPREP="${TASKSET_PREFIX} virt-sysprep"

# Source shared functions
source ${0%/*}/shared_functions.sh

# Version handling
if [ "$VERSION" == "FIXME" ]; then
    VERSION_FILE="${NAME}-${MAJOR_RELEASE}-${DATE}.txt"
    SUCCESS_FILE="${VERSION_FILE}.success"
    
    [ ! -e "$VERSION_FILE" ] && echo "0" > "$VERSION_FILE"  # Start at 1
    VERSION=$(cat "$VERSION_FILE")
    
    # If last run was successful, increment version
    if [ -f "$SUCCESS_FILE" ]; then
        VERSION=$((VERSION + 1))
        echo "$VERSION" > "$VERSION_FILE"
        rm "$SUCCESS_FILE"
    fi
fi

# Define image names and URLs
BASE_URL="https://cloud.centos.org/centos/${MAJOR_RELEASE}-stream/${ARCH}/images"
IMAGE_FILE="${NAME}-${MAJOR_RELEASE}-${CPE_RELEASE_DATE}.${CPE_RELEASE}.${ARCH}"
IMAGE_NAME="${NAME}-${MAJOR_RELEASE}-${CPE_RELEASE_DATE}.${CPE_RELEASE}-${DATE}.${VERSION}.${ARCH}"
LINK="${BASE_URL}/${IMAGE_FILE}.raw"

# Get AWS resource IDs
S3_REGION=$(get_s3_bucket_location $S3_BUCKET)
SUBNET_ID=$(get_default_vpc_subnet $S3_REGION)
SECURITY_GROUP_ID=$(get_default_sg_for_vpc $S3_REGION)

cleanup() {
    local exit_code=$?
    err "Cleaning up temporary files..."
    
    # Remove raw image files
    if [[ -f "${IMAGE_FILE}.raw" ]]; then
        err "Removing ${IMAGE_FILE}.raw"
        rm -f "${IMAGE_FILE}.raw"
    fi
    
    if [[ -f "${IMAGE_NAME}.raw" ]]; then
        err "Removing ${IMAGE_NAME}.raw"
        rm -f "${IMAGE_NAME}.raw"
    fi
    
    # Remove compressed files
    if [[ -f "${IMAGE_FILE}.raw.xz" ]]; then
        err "Removing ${IMAGE_FILE}.raw.xz"
        rm -f "${IMAGE_FILE}.raw.xz"
    fi
    
    err "Cleanup completed (version file preserved)"
    exit $exit_code
}

verify_url() {
    err "Attempting to verify URLs:"
    err "Checking: ${LINK}.xz"
    
    local curl_output=$(curl -ILs "${LINK}.xz" -w "%{http_code}")
    err "Curl output: ${curl_output}"
    
    err "Listing available files in directory:"
    curl -s "${BASE_URL}/" | grep "${NAME}-${MAJOR_RELEASE}"

    err "Constructed image name: ${IMAGE_NAME}"
    err "Constructed URL: ${LINK}"
    err "Using architecture: ${ARCH}"
    err "Using major release: ${MAJOR_RELEASE}"
    err "Using CPE release date: ${CPE_RELEASE_DATE}"
    err "Using CPE release: ${CPE_RELEASE}"
}

download_image() {
    local file_path="${IMAGE_FILE}.raw"
    
    err "Attempting to download: ${LINK}.xz"
    if curl -Is "${LINK}.xz" | grep -q "HTTP/.*200"; then
        err "Found compressed raw image at: ${LINK}.xz"
        curl -C - -o "${file_path}.xz" "${LINK}.xz"
        err "Decompressing image..."
        xz -d --force "${file_path}.xz"
        
        err "Files after decompression:"
        ls -l

        err "Renaming ${file_path} to ${IMAGE_NAME}.raw"
        mv "${file_path}" "${IMAGE_NAME}.raw"
        
        err "Files after rename:"
        ls -l
        
        if [[ ! -f "${IMAGE_NAME}.raw" ]]; then
            err "Error: Failed to create ${IMAGE_NAME}.raw"
            exit 1
        fi
    else
        err "Failed to find image at: ${LINK}.xz"
        err "Please verify the following:"
        err "1. Base URL: ${BASE_URL}"
        err "2. Image file: ${IMAGE_FILE}"
        err "3. Full URL: ${LINK}.xz"
        exit 1
    fi
}

process_image() {
    local raw_image="${IMAGE_NAME}.raw"
    
    if [[ ! -f "${raw_image}" ]]; then
        err "Error: Raw image file ${raw_image} not found!"
        err "Current directory contents:"
        ls -l
        exit 1
    fi
    
    err "Configuring SELinux and updating system..."
    ${VIRT_EDIT} -a "${raw_image}" /etc/sysconfig/selinux -e "s/^\(SELINUX=\).*/\1permissive/"
    err "Note: This release is End of Life"
    err "Modifying CentOS repository configuration..."
    ${VIRT_CUSTOMIZE} -a "${raw_image}" --run-command 'sed -i "s|#baseurl=http://mirror.centos.org|baseurl=http://vault.centos.org|g" /etc/yum.repos.d/CentOS-*'

    ${VIRT_CUSTOMIZE} -a "${raw_image}" --update
    ${VIRT_CUSTOMIZE} -a "${raw_image}" --selinux-relabel
    ${VIRT_EDIT} -a "${raw_image}" /etc/sysconfig/selinux -e "s/^\(SELINUX=\).*/\1enforcing/"
    ${VIRT_SYSPREP} -a "${raw_image}"
}

aws_import_and_share() {
    local raw_image="${IMAGE_NAME}.raw"
    local import_status_file="${SNAPSHOT_STATUS_DIR}/${IMAGE_NAME}.import"
    local copy_status_file="${SNAPSHOT_STATUS_DIR}/${IMAGE_NAME}.copy"

    err "Uploading image to S3..."
    aws --region $S3_REGION s3 cp ./${raw_image} s3://${S3_BUCKET}/${S3_PREFIX}/
    DISK_CONTAINER="{\"Description\":\"${IMAGE_NAME}\",\"Format\":\"raw\",\"UserBucket\":{\"S3Bucket\":\"${S3_BUCKET}\",\"S3Key\":\"${S3_PREFIX}/${raw_image}\"}}"
    
    err "Importing snapshot..."
    IMPORT_SNAP=$(aws ec2 import-snapshot ${DRY_RUN} --region $S3_REGION \
        --client-token ${IMAGE_NAME}-$(date +%s) \
        --description "Import Base $NAME $MAJOR_RELEASE ($ARCH) Image" \
        --disk-container "$DISK_CONTAINER")
    
    snapshotTask=$(echo $IMPORT_SNAP | jq -Mr '.ImportTaskId')
    err "Snapshot import task ID: ${snapshotTask}"
    
    err "Waiting for snapshot import to complete..."
    while true; do
        status=$(aws ec2 --region $S3_REGION describe-import-snapshot-tasks \
            --import-task-ids ${snapshotTask} \
            --query 'ImportSnapshotTasks[0].SnapshotTaskDetail.Status' \
            --output text)
            
        err "Current import status: $status"
        
        case $status in
            completed)
                snapshotId=$(aws ec2 --region $S3_REGION describe-import-snapshot-tasks \
                    --import-task-ids ${snapshotTask} \
                    --query 'ImportSnapshotTasks[0].SnapshotTaskDetail.SnapshotId' \
                    --output text)
                echo "$snapshotId" > "$import_status_file"
                break
                ;;
            active)
                sleep 30
                ;;
            error|deleted|cancelled)
                err "Import failed with status: $status"
                error_message=$(aws ec2 --region $S3_REGION describe-import-snapshot-tasks \
                    --import-task-ids ${snapshotTask} \
                    --query 'ImportSnapshotTasks[0].SnapshotTaskDetail.StatusMessage' \
                    --output text)
                err "Error message: $error_message"
                exit 1
                ;;
        esac
    done

    if [[ "$S3_REGION" == "us-east-1" ]]; then
        err "Snapshot already in us-east-1, no copy needed..."
        IAD_snap=$snapshotId
        echo "$IAD_snap" > "$copy_status_file"
    else
        err "Processing snapshot copy to us-east-1..."
        copy_response=$(aws ec2 copy-snapshot \
            --source-region "$S3_REGION" \
            --source-snapshot-id "$snapshotId" \
            --destination-region "us-east-1" \
            --description "Copy of $IMAGE_NAME snapshot" \
            --output json)
        
        IAD_snap=$(echo "$copy_response" | jq -r '.SnapshotId')
        err "Started copy of snapshot. New snapshot ID: $IAD_snap"
        
        err "Waiting for snapshot copy to complete..."
        while true; do
            copy_status=$(aws ec2 describe-snapshots \
                --snapshot-ids "$IAD_snap" \
                --region us-east-1 \
                --query 'Snapshots[0].State' \
                --output text 2>/dev/null || echo "pending")
                
            err "Current copy status: $copy_status"
            
            case $copy_status in
                completed)
                    echo "$IAD_snap" > "$copy_status_file"
                    break
                    ;;
                pending)
                    sleep 30
                    ;;
                error)
                    err "Snapshot copy failed"
                    exit 1
                    ;;
            esac
        done
    fi

    DEVICE_MAPPINGS="[{\"DeviceName\": \"/dev/sda1\", \"Ebs\": {\"DeleteOnTermination\":true, \"SnapshotId\":\"${IAD_snap}\", \"VolumeSize\":10, \"VolumeType\":\"gp2\"}}]"
    
    ImageId=$(aws ec2 --region us-east-1 register-image \
        --architecture=$ARCHITECTURE \
        --description="${NAME} ${MAJOR_RELEASE} ($ARCH) for HVM Instances" \
        --virtualization-type hvm \
        --root-device-name '/dev/sda1' \
        --name=${IMAGE_NAME} \
        --ena-support --sriov-net-support simple \
        --block-device-mappings "${DEVICE_MAPPINGS}" \
        --boot-mode uefi-preferred \
        --imds-support 'v2.0' \
        --output text)
    
    err "Created Image ID: $ImageId in us-east-1"
    echo "SNAPSHOT : ${IAD_snap}, IMAGEID : ${ImageId}, NAME : ${IMAGE_NAME}" >> ${NAME}-${MAJOR_RELEASE}.txt
    
    aws ec2 run-instances --region us-east-1 \
        --subnet-id $SUBNET_ID \
        --image-id $ImageId \
        --instance-type ${INSTANCE_TYPE} \
        --key-name "previous" \
        --security-group-ids $SECURITY_GROUP_ID ${DRY_RUN}
    
    ${0%/*}/share-amis.sh $ImageId
    touch "$SUCCESS_FILE"
}

# Set up the trap
trap cleanup EXIT ERR SIGINT SIGTERM

# Main execution
verify_url
download_image
process_image
aws_import_and_share
