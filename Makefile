.PHONY: rpm

NAME = flask-app
VERSION = 1.0

rpm:
	docker build --target rpm-build -t rpm-build .
 	docker run -v $(shell pwd)/rpm:/tmp/rpm rpm-build sh -c 'cp /root/rpmbuild/RPMS/x86_64/*.rpm /tmp/rpm'

rpm-check:
	docker kill rpm-check-cont || true
	docker rm rpm-check-cont || true
	DOCKER_BUILDKIT=1 docker build --target rpm-check -t rpm-check .
	docker run --privileged --name rpm-check-cont -v /sys/fs/cgroup:/sys/fs/cgroup:ro -p 8000:8000 -d rpm-check
	docker exec rpm-check-cont sh -c 'rpm -i /tmp/flask-app-*.rpm && systemctl enable flask-app && systemctl start flask-app && systemctl status flask-app'



