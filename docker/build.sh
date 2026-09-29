USER_ID=$1
GROUP_ID=$2
VERSION=$3

docker build --build-arg USER_ID=${USER_ID} --build-arg GROUP_ID=${GROUP_ID} -t apptestai/dashboard:${VERSION} .
