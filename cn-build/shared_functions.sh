function err() {
  echo "[$(date +'%Y-%m-%dT%H:%M:%S%z')]: $@" >&2
}


function put_ssm_parameters() {
    SSM_NAME=${DATE}-${VERSION}
    err "saving ssm public parameter /amis/centos/${ARCHITECTURE}/${NAME}/${SSM_NAME}"
    err "saving ssm public parameter /amis/centos/${ARCHITECTURE}/${NAME}/latest" 
    aws ssm put-parameter --name "/amis/centos/${ARCHITECTURE}/centos-stream-ec2-8/${SSM_NAME}"  \
        --type "String" --value $ImageId --data-type "aws:ec2:image"
    aws ssm put-parameter --name "/amis/centos/${ARCHITECTURE}/centos-stream-ec2-8/latest"  \
        --type "String" --value $ImageId --data-type "aws:ec2:image"
}
