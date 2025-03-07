#!/bin/bash

# Enable debug mode and exit on error
set -e
set -x

# Constants
REGION="us-east-1"
MARKETPLACE_ACCOUNTS=(
    "679593333241" # AWS Marketplace Testing
    "684062674729" # AWS Marketplace
    "425685993791" # Red Hat Validation
    "514427062609" # EC2 MVP Ops
    "014813956182" # Lightsail Testing
    "264483973329" # Container Testing
)

# Error handling function
err() {
    echo "[$(date +'%Y-%m-%dT%H:%M:%S%z')]: $@" >&2
}

# Validate input parameters
if [ $# -ne 1 ]; then
    err "Usage: $0 <ImageId>"
    err "Example: $0 ami-12345678"
    exit 1
fi

ImageId="$1"

# Validate ImageId format
if [[ ! $ImageId =~ ^ami-[a-f0-9]{8,17}$ ]]; then
    err "Error: Invalid AMI ID format. Must start with 'ami-' followed by 8-17 hexadecimal characters."
    exit 1
fi

# Function to verify image exists
verify_image() {
    if ! aws ec2 describe-images --region "$REGION" --image-ids "$ImageId" >/dev/null 2>&1; then
        err "Error: Image $ImageId not found in region $REGION"
        exit 1
    fi
}

# Function to get snapshot ID
get_snapshot_id() {
    local snapshot_id
    snapshot_id=$(aws ec2 describe-images \
        --region "$REGION" \
        --owners self \
        --image-ids "$ImageId" \
        --query 'Images[].BlockDeviceMappings[].Ebs.SnapshotId' \
        --output text)
    
    if [ -z "$snapshot_id" ]; then
        err "Error: No snapshot found for AMI $ImageId"
        exit 1
    fi
    echo "$snapshot_id"
}

# Function to share AMI with accounts
share_ami() {
    local image_id="$1"
    local accounts="${MARKETPLACE_ACCOUNTS[@]}"
    
    err "Sharing AMI $image_id with marketplace accounts..."
    aws ec2 modify-image-attribute \
        --image-id "$image_id" \
        --region "$REGION" \
        --attribute launchPermission \
        --operation-type add \
        --user-ids "${accounts}"
}

# Function to share snapshot with accounts
share_snapshot() {
    local snapshot_id="$1"
    local accounts="${MARKETPLACE_ACCOUNTS[@]}"
    
    err "Sharing snapshot $snapshot_id with marketplace accounts..."
    if aws ec2 describe-snapshots --snapshot-ids "$snapshot_id" --region "$REGION" >/dev/null 2>&1; then
        aws ec2 modify-snapshot-attribute \
            --snapshot-id "$snapshot_id" \
            --region "$REGION" \
            --attribute createVolumePermission \
            --operation-type add \
            --user-ids "${accounts}"
    else
        err "Error: Unable to access snapshot $snapshot_id"
        exit 1
    fi
}

# Function to verify sharing
verify_sharing() {
    local image_id="$1"
    local snapshot_id="$2"
    
    err "Verifying sharing permissions..."
    aws ec2 describe-snapshot-attribute \
        --region "$REGION" \
        --attribute createVolumePermission \
        --snapshot-id "$snapshot_id"
    
    aws ec2 describe-image-attribute \
        --region "$REGION" \
        --attribute launchPermission \
        --image-id "$image_id"
}

# Main execution
main() {
    # Verify image exists
    verify_image
    
    # Get snapshot ID
    snapshotId=$(get_snapshot_id)
    err "Found snapshot ID: $snapshotId"
    
    # Share AMI
    share_ami "$ImageId"
    
    # Share snapshot
    share_snapshot "$snapshotId"
    
    # Verify sharing
    verify_sharing "$ImageId" "$snapshotId"
    
    err "Successfully shared AMI and snapshot with marketplace accounts"
}

# Execute main function
main
