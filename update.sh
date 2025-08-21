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


#local build first for testing
docker pull php:8.3-apache
docker build . --load -t adamzammit/limesurvey:$VERSION

docker compose down

rm -rf sessions upload plugins config mysql

docker compose up -d

sleep 60

curl -v --silent localhost:8082 2>&1 | grep 'HTTP/1.1 200 OK' && status=success || status=fail
curl -v --silent localhost:8082 2>&1 | grep 'LimeSurvey' && status2=success || status2=fail

docker compose down

if [ "$status" == "success" ] && [ "$status2" == "success" ]; then

    docker buildx build --no-cache --pull --push --platform linux/amd64,linux/arm64,linux/arm/v7 -t adamzammit/limesurvey:$VERSION -t adamzammit/limesurvey:latest -t acspri/limesurvey:$VERSION -t acspri/limesurvey:latest .

    git add Dockerfile docker-compose.yml

    git commit -m "$VERSION release"

    git tag $VERSION

    git push --tags origin master
else
    echo "Did not commit or push build: acspri/limesurvey:$VERSION due to error" | mail -s "Error in build $VERSION" adam@acspri.org.au
fi
