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
docker pull php:8.1-apache
docker build --load . -t adamzammit/limesurvey:$VERSION

git add Dockerfile docker-compose.yml
git commit -m "$VERSION release"
git tag $VERSION-ecr

curl -o global-bundle.pem -fsL "https://truststore.pki.rds.amazonaws.com/global/global-bundle.pem"
AWS_PROFILE=kba aws ecr get-login-password --region eu-central-1 | docker login --username AWS --password-stdin 108782056908.dkr.ecr.eu-central-1.amazonaws.com
docker build . -t 108782056908.dkr.ecr.eu-central-1.amazonaws.com/limesurvey-dev:$VERSION
docker push 108782056908.dkr.ecr.eu-central-1.amazonaws.com/limesurvey-dev:$VERSION
