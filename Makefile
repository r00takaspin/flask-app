NAME = flask-app
VERSION = 1.0

rpm:
#	DOCKER_BUILDKIT=1 docker build --target rpm-build -t rpm-build .
	docker build --target rpm-build -t rpm-build .
	#TODO: remove
	docker run -it rpm-build sh -c 'rpm -i /root/rpmbuild/RPMS/x86_64/flask-app-*.rpm && ls -la /var/app/flask-app'