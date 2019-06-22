ARG VERSION=1.0
ARG NAME=flask-app
ARG ARCHIVE=$NAME-$VERSION.tar.bz2

FROM centos as basic
RUN yum update -y --nogpgcheck
RUN yum install https://centos7.iuscommunity.org/ius-release.rpm -y --nogpgcheck && \
    yum install epel-release rpm-build yum-utils python35u python35u-devel python35u-pip -y --nogpgcheck && \
    pip3.5 install --upgrade pip

FROM basic as rpm-build
ARG VERSION
ARG NAME
ARG ARCHIVE

WORKDIR /tmp/src
COPY . .
RUN pip3.5 download --no-deps --dest ./vendor -r requirements.txt
RUN ls -la
RUN tar cjv -f $ARCHIVE build/ vendor/ main.py wsgi.py
RUN ls -la
RUN mkdir /tmp/app && cp $ARCHIVE /tmp/app/

RUN rpmbuild -bb build/rpm/$NAME.spec --define "_version $VERSION" --define "_sourcedir /tmp/app"