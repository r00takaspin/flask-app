ARG VERSION=1.0
ARG NAME=flask-app
ARG ARCHIVE=$NAME-$VERSION.tar.bz2

FROM centos as rpm-build
ARG VERSION
ARG NAME
ARG ARCHIVE

WORKDIR /tmp/src
COPY . .
RUN ./build/script/setup.sh && rm -rf setup.sh

RUN pip3.5 download --no-deps --dest ./vendor -r requirements.txt
RUN tar cjv -f $ARCHIVE build/ vendor/ main.py wsgi.py
RUN mkdir /tmp/app && cp $ARCHIVE /tmp/app/
RUN rpmbuild -bb build/rpm/$NAME.spec --define "_version $VERSION" --define "_sourcedir /tmp/app"

FROM centos/systemd as rpm-check
COPY build/script/setup.sh setup.sh
RUN ./setup.sh && rm -rf setup.sh
COPY --from=rpm-build /root/rpmbuild/RPMS/x86_64/*.rpm /tmp/
CMD ["/usr/sbin/init"]
