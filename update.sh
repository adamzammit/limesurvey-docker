#!/bin/bash

#Fail on any error
set -e

#extract version from URL
VERSION=`echo $1 | sed 's|.*limesurvey\([0-9\.]*\)\+.*|\1|'`

curl "$1" > $VERSION.zip 

SHA256=`sha256sum $VERSION.zip | awk '{print $1}'`

rm docker-compose.yml

sed -e  "s/LIME_VER/$VERSION/g" docker-compose.yml.template > docker-compose.yml

rm Dockerfile

sed -e "s|LIME_URL|$1|g" Dockerfile.template > Dockerfile
sed -i -e "s/LIME_SHA/$SHA256/g" Dockerfile

rm $VERSION.zip

docker buildx build --no-cache --pull --output type=image,push=false --platform linux/amd64,linux/arm64,linux/ppc64le,linux/mips64le,linux/arm/v7,linux/arm/v6,linux/s390x -t adamzammit/limesurvey:$VERSION -t adamzammit/limesurvey:5 -t acspri/limesurvey:$VERSION -t acspri/limesurvey:5 .

docker-compose down

rm -rf sessions upload plugins config

docker-compose up -d

sleep 60

curl -v --silent localhost:8082 2>&1 | grep 'HTTP/1.1 200 OK' && status=success || status=fail
curl -v --silent localhost:8082 2>&1 | grep 'LimeSurvey' && status2=success || status2=fail

docker-compose down

if [ "$status" == "success" ] && [ "$status2" == "success" ]; then

    docker push adamzammit/limesurvey:$VERSION
    docker push adamzammit/limesurvey:5
    docker push acspri/limesurvey:$VERSION
    docker push acspri/limesurvey:5

    git add Dockerfile docker-compose.yml

    git commit -m "$VERSION release"

    git tag $VERSION

    git push --tags origin v5
else
    echo "Did not commit or push build: acspri/limesurvey:$VERSION due to error" | mail -s "Error in build $VERSION" adam@acspri.org.au
fi
