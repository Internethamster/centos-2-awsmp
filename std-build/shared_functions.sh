usage() {
    echo "Usage: $0 [ -v VERSION ] [ -b BUCKET_NAME ] [ -k OBJECT_PREFIX ] [ -a ARCH ] [ -n NAME ] [ -r RELEASE ] [ -R REGION ] [ -d DRY_RUN ]" 1>&2
}

REGION=$(curl -s http://169.254.169.254/latest/dynamic/instance-identity/document  | jq -r ".region")

function err() {
    echo "[$(date +'%Y-%m-%dT%H:%M:%S%z')]: $@" >&2
}

exit_abnormal() {
    usage
    exit 1
}

function get_s3_bucket_location () {
    local BUCKET_NAME=$1

    local STORAGE_REGION=$(aws s3api get-bucket-location --bucket $BUCKET_NAME \
		--query 'LocationConstraint' --output text)
    if [[ "$STORAGE_REGION" == "null" ]]
    then
	STORAGE_REGION="us-east-1"
    fi
    printf "%s" $STORAGE_REGION
}

get_default_vpc_subnet () {
    local REGION=${1:-$(curl -s http://169.254.169.254/latest/dynamic/instance-identity/document  | jq -r ".region")}
    local VPC_ID=$(aws ec2 describe-vpcs --region $REGION --query "Vpcs[?IsDefault].VpcId" --output text)
    aws ec2 describe-subnets --region $REGION --filters "Name=vpc-id,Values=$VPC_ID" --query "Subnets[?MapPublicIpOnLaunch] | [0].SubnetId" --output text

}

get_default_sg_for_vpc () {
    local REGION=${1:-$(curl -s http://169.254.169.254/latest/dynamic/instance-identity/document  | jq -r ".region")}
    local VPC_ID=$(aws ec2 describe-vpcs --region $REGION --query "Vpcs[?IsDefault].VpcId" --output text)
    aws ec2 describe-security-groups --region $REGION --filters "Name=vpc-id,Values=${VPC_ID}" --query 'SecurityGroups[?GroupName == `default`].GroupId' --output text
}

while getopts ":f:v:b:k:a:n:r:R:dp" options; do
    case "${options}" in
	v)
	    VERSION=${OPTARG}
	    ;;
	b)
	    S3_BUCKET=${OPTARG}
	    ;;
	k)
	    S3_PREFIX=${OPTARG}
	    ;;
	r)
	    RELEASE=${OPTARG}
	    ;;
	R)
	    REGION=${OPTARG}
	    ;;
	a)
	    ARCH=${OPTARG}
	    ;;
	n)
	    NAME=${OPTARG}
	    ;;
	d)
	    DRY_RUN="--dry-run"
	    ;;
	p)
	    PSTATE="true"
	    ;;
	f)
	    FILE_FORMAT=${OPTARG}
	    ;;
	:)
	    "Error: -${OPTARG} requires an argument"
	    ;;
	*)
	    exit_abnormal
	    ;;
    esac
done

function copySnapshotToRegion {

    local IAD_snap=$snapshotId

    if [[ "$REGION" != "us-east-1" ]]
    then

	local IAD_snap=$(aws ec2 copy-snapshot --source-region $REGION --source-snapshot-id $snapshotId \
			     --region us-east-1 \
			     --description "Import Base CentOS${MAJOR_RELEASE} ${ARCHITECTURE} Image" \
			     --query 'SnapshotId' --output text
	      )
    fi

    echo $IAD_snap
}
