usage() {
    echo "Usage: $0 [ -v VERSION ] [ -b BUCKET_NAME ] [ -k OBJECT_PREFIX ] [ -a ARCH ] [ -n NAME ] [ -r RELEASE ] [ -R REGION ]" 1>&2
}
exit_abnormal() {
    usage
    exit 1
}


while getopts ":v:b:k:a:n:r:R:p" options; do
    case "${options}" in
        v)
            VERSION=${OPTARG}
            ;;
        t)
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
        p)
            PSTATE="True"
            ;;
        :)
            "Error: -${OPTARG} requires an argument"
            ;;
        *)
            exit_abnormal
            ;;
    esac
done
