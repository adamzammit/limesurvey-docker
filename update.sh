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

docker pull php:8.1-apache
docker build . -t adamzammit/limesurvey:$VERSION-lts

docker-compose down

docker-compose up -d

sleep 60

curl -v --silent localhost:8082 2>&1 | grep 'HTTP/1.1 200 OK' && status=success || status=fail
curl -v --silent localhost:8082 2>&1 | grep 'LimeSurvey' && status2=success || status2=fail

docker-compose down

if [ "$status" == "success" ] && [ "$status2" == "success" ]; then

    docker buildx build --pull --no-cache --push --platform linux/amd64,linux/arm64,linux/ppc64le,linux/mips64le,linux/arm/v7,linux/arm/v6,linux/s390x -t adamzammit/limesurvey:$VERSION-lts -t adamzammit/limesurvey:lts -t acspri/limesurvey:$VERSION-lts -t acspri/limesurvey:lts .

    git add Dockerfile docker-compose.yml

    git commit -m "$VERSION-lts release"

    git tag $VERSION-lts

    git push --tags origin lts
else
    echo "Did not commit or push build: acspri/limesurvey:$VERSION-lts due to error" | mail -s "Error in build $VERSION-lts" adam@acspri.org.au
fi
