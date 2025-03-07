#!/bin/bash

# Default values and globals
VERSION=${VERSION:-FIXME}

# Function to get IMDSv2 token
function get_imds_token() {
    curl -X PUT "http://169.254.169.254/latest/api/token" \
        -H "X-aws-ec2-metadata-token-ttl-seconds: 21600" \
        -s
}

# Function to get region using IMDSv2
function get_instance_region() {
    local token=$(get_imds_token)
    if [[ -z "$token" ]]; then
        err "Failed to obtain IMDSv2 token"
        return 1
    fi

    local region=$(curl -H "X-aws-ec2-metadata-token: $token" \
        -s http://169.254.169.254/latest/dynamic/instance-identity/document \
        | jq -r ".region")
    
    if [[ -z "$region" || "$region" == "null" ]]; then
        err "Failed to determine region from instance metadata"
        return 1
    fi
    echo "$region"
}

REGION=${REGION:-$(get_instance_region)}


# Logging and error handling functions
function err() {
    echo "[$(date +'%Y-%m-%dT%H:%M:%S%z')]: $@" >&2
}

function usage() {
    echo "Usage: $0 [ -v VERSION ] [ -b BUCKET_NAME ] [ -k OBJECT_PREFIX ] [ -a ARCH ] [ -n NAME ] [ -r RELEASE ] [ -R REGION ] [ -d DRY_RUN ]" 1>&2
}

function exit_abnormal() {
    usage
    exit 1
}

# AWS Resource Management Functions
function get_s3_bucket_location() {
    local BUCKET_NAME=$1
    
    if [[ -z "$BUCKET_NAME" ]]; then
        err "Bucket name not provided"
        return 1
    fi

    local STORAGE_REGION=$(aws s3api get-bucket-location \
        --bucket $BUCKET_NAME \
        --query 'LocationConstraint' \
        --output text)

    if [[ "$STORAGE_REGION" == "null" ]]; then
        STORAGE_REGION="us-east-1"
    fi
    
    printf "%s" $STORAGE_REGION
}

# Updated functions that use the global REGION by default
function get_default_vpc_subnet() {
    local region=${1:-$REGION}  # Use passed region or global REGION
    
    local VPC_ID=$(aws ec2 describe-vpcs --region $region \
        --query "Vpcs[?IsDefault].VpcId" --output text)
    
    if [[ -z "$VPC_ID" ]]; then
        err "No default VPC found in region $region"
        return 1
    fi

    aws ec2 describe-subnets --region $region \
        --filters "Name=vpc-id,Values=$VPC_ID" \
        --query "Subnets[?MapPublicIpOnLaunch] | [0].SubnetId" \
        --output text --no-cli-pager
}

function get_default_sg_for_vpc() {
    local region=${1:-$REGION}  # Use passed region or global REGION
    
    local VPC_ID=$(aws ec2 describe-vpcs --region $region \
        --query "Vpcs[?IsDefault].VpcId" --output text)
    
    if [[ -z "$VPC_ID" ]]; then
        err "No default VPC found in region $region"
        return 1
    fi

    aws ec2 describe-security-groups --region $region \
        --filters "Name=vpc-id,Values=${VPC_ID}" \
        --query 'SecurityGroups[?GroupName == `default`].GroupId' \
        --output text
}

function copySnapshotToRegion() {
    local source_snapshot_id=$1
    local source_region=${2:-$REGION}
    local destination_region=${3:-"us-east-1"}
    
    if [[ -z "$source_snapshot_id" ]]; then
        err "Source snapshot ID not provided"
        return 1
    fi

    if [[ "$source_region" == "$destination_region" ]]; then
        echo "$source_snapshot_id"
        return 0
    fi
    local copy_response
    copy_response=$(aws ec2 copy-snapshot \
        --source-region "$source_region" \
        --source-snapshot-id "$source_snapshot_id" \
        --destination-region "$destination_region" \
        --description "Import Base ${NAME}-${MAJOR_RELEASE} ${ARCHITECTURE} Image" \
        --output json)

    if [[ $? -ne 0 ]]; then
        err "Failed to copy snapshot"
        return 1
    fi

    echo "$copy_response" | jq -r '.SnapshotId'
}

# Command line argument parsing
while getopts ":f:v:b:k:a:n:r:R:dp" options; do
    case "${options}" in
        v) VERSION=${OPTARG:-FIXME} ;;
        b) S3_BUCKET=${OPTARG} ;;
        k) S3_PREFIX=${OPTARG} ;;
        r) RELEASE=${OPTARG} ;;
        R) 
            REGION=${OPTARG}
            [[ -z $REGION ]] && REGION=$(get_instance_region)
            ;;
        a) ARCH=${OPTARG} ;;
        n) NAME=${OPTARG} ;;
        d) DRY_RUN="--dry-run" ;;
        p) PSTATE="true" ;;
        f) FILE_FORMAT=${OPTARG} ;;
        :) err "Error: -${OPTARG} requires an argument" ;;
        *) exit_abnormal ;;
    esac
done

# Function to check AWS CLI availability
function check_aws_cli() {
    if ! command -v aws &> /dev/null; then
        err "AWS CLI is not installed or not in PATH"
        return 1
    fi
}

# Function to validate AWS credentials
function validate_aws_credentials() {
    if ! aws sts get-caller-identity &> /dev/null; then
        err "Invalid or missing AWS credentials"
        return 1
    fi
}

# Add spinner function for long-running operations
function spinner() {
    local pid=$1
    local delay=0.75
    local spinstr='|/-\'
    while [ "$(ps a | awk '{print $1}' | grep $pid)" ]; do
        local temp=${spinstr#?}
        printf " [%c]  " "$spinstr"
        local spinstr=$temp${spinstr%"$temp"}
        sleep $delay
        printf "\b\b\b\b\b\b"
    done
    printf "    \b\b\b\b"
}
