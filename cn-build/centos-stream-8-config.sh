S3_BUCKET="davdunc-floppy"
S3_PREFIX="disk-images"

MAJOR_RELEASE=8
NAME="CentOS-Stream-ec2"
ARCH=$(arch)

if [[ "$ARCH" == "aarch64" ]]; then
    ARCHITECTURE="arm64"
    CPE_RELEASE=0
    CPE_RELEASE_DATE=20220913
    CPE_RELEASE_REVISION=

    QEMU_IMG="taskset -c 1 qemu-img"
    VIRT_CUSTOMIZE="taskset -c 1 virt-customize"
    VIRT_EDIT="taskset -c 1 virt-edit"
    VIRT_SYSPREP="taskset -c 1 virt-sysprep"

    INSTANCE_TYPE="m6g.large"
else
    ARCHITECTURE="$(arch)"
    CPE_RELEASE=0
    CPE_RELEASE_DATE=20220913
    CPE_RELEASE_REVISION=

    QEMU_IMG="qemu-img"
    VIRT_CUSTOMIZE="virt-customize"
    VIRT_EDIT="virt-edit"
    VIRT_SYSPREP="virt-sysprep"

    INSTANCE_TYPE="m6i.large"
fi
