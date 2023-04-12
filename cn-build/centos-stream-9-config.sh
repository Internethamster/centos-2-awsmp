BASE_URI="https://cloud.centos.org/centos"
S3_BUCKET="davdunc-floppy"
S3_PREFIX="disk-images"

MAJOR_RELEASE=9
NAME="CentOS-Stream-ec2"
ARCH=$(arch)

if [[ "$ARCH" == "aarch64" ]]; then
    ARCHITECTURE="arm64"
    CPE_RELEASE=1
    CPE_RELEASE_DATE=20230405
    CPE_RELEASE_REVISION=
    FILE_NAME_PREFIX="${NAME}-${ARCH}-${MAJOR_RELEASE}"

    QEMU_IMG="taskset -c 1 qemu-img"
    VIRT_CUSTOMIZE="taskset -c 1 virt-customize"
    VIRT_EDIT="taskset -c 1 virt-edit"
    VIRT_SYSPREP="taskset -c 1 virt-sysprep"

    INSTANCE_TYPE="m6g.large"
else
    ARCHITECTURE="$(arch)"
    CPE_RELEASE=1
    CPE_RELEASE_DATE=20230405
    CPE_RELEASE_REVISION=
    FILE_NAME_PREFIX="${NAME}-${MAJOR_RELEASE}"

    QEMU_IMG="qemu-img"
    VIRT_CUSTOMIZE="virt-customize"
    VIRT_EDIT="virt-edit"
    VIRT_SYSPREP="virt-sysprep"

    INSTANCE_TYPE="m6i.large"
fi

UPSTREAM_RELEASE="${MAJOR_RELEASE}-stream"
MINOR_RELEASE="${CPE_RELEASE_DATE}.${CPE_RELEASE}"
UPSTREAM_FILE_NAME="${FILE_NAME_PREFIX}-${MINOR_RELEASE}.${ARCH}"

# ${Base_URI}/${UPSTREAM_RELEASE}/${ARCH}/images/${FILE_NAME_PREFIX)-${UPSTREAM_FILE_NAME}.${ARCH}.raw.xz
# ${BASE_URI}/${UPSTREAM_RELEASE}/${ARCH}/images/${FILE_NAME_PREFIX}-${UPSTREAM_FILE_NAME}.${ARCH}.raw.xz
# ${BASE_URI}/${UPSTREAM_RELEASE}/${ARCH}/images/CHECKSUM
