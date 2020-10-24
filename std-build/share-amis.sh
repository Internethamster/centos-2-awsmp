REGION=cn-northwest-1 
snapshotId=${1:-snap-0ba13c36039a89f59}
ImageId=${2:-ami-0217a0210ea0fec9c}
	     

aws ec2 modify-snapshot-attribute \
    --snapshot-id $snapshotId \
    --region $REGION \
    --attribute createVolumePermission \
    --operation-type add \
    --user-ids 336777782633 882445023432 830553105645

aws ec2 describe-snapshot-attribute --attribute createVolumePermission --snapshot-id $snapshotId

aws ec2 modify-image-attribute \
    --image-id $ImageId  \
    --region $REGION \
    --attribute launchPermission \
    --operation-type add \
    --user-ids 336777782633 882445023432 830553105645

aws ec2 describe-image-attribute --attribute launchPermission --image-id $ImageId

