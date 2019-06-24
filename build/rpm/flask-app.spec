%define release %(date +%s)

Name:           flask-app
Version:        %{_version}
Release:        %{release}
Group:          Development/Libraries
Summary:        example all
License:        proprietary
Group:          Apps/sys
# обратим внимание на этот параметр, он означает, что пакет будет содержать исходные коды программы
Source0:        %{name}-%{_version}.tar.bz2
BuildRoot:      %{_tmppath}/%{name}-%{version}-buildroot

Requires:       python35u
BuildRequires:  python35u
BuildRequires:  python35u-devel
BuildRequires:  python-argparse
BuildRequires:  rpm-build
BuildRequires:  redhat-rpm-config

# убираем проверку правильности синтаксиса в .py файлах
%global __os_install_post %(echo '%{__os_install_post}' | sed -e 's!/usr/lib[^[:space:]]*/brp-python-bytecompile[[:space:]].*$!!g')

%description
%{name} built with generic python project spec

# создаем пользователя
%pre
/usr/bin/getent group %{name} || /usr/sbin/groupadd -r %{name}
/usr/bin/getent passwd %{name} || /usr/sbin/useradd -r -d /opt/%{name}/ -s /bin/false %{name} -g %{name}

%prep
tar xjf %{SOURCE0}

%install
mkdir -p %{buildroot}/var/app/%{name}/conf
cp -r %{_builddir}/*.* %{buildroot}/var/app/%{name}
cp -r %{_builddir}/vendor %{buildroot}/var/app/%{name}/vendor
cp -r %{_builddir}/build/config/gunicorn.conf %{buildroot}/var/app/%{name}/conf/gunicorn.conf

echo "Installing systemd config"
%{__install} -p -D -m 0644 %{_builddir}/build/systemd/%{name}.service %{buildroot}/usr/lib/systemd/system/%{name}.service

%post
python3.5 -m venv /var/app/%{name}/venv
. /var/app/flask-app/venv/bin/activate

pip3.5 install --upgrade pip
pip3.5 install /var/app/flask-app/vendor/*.*

if [ $1 -gt 1 ]; then
    echo "Upgrade"
    mkdir -p /var/log/%{name}

    find %{__prefix}/%{name} -type f -name "*.py[co]" -delete
else
    echo "Install"

    mkdir -p /var/log/%{name}
fi

chown -R %{name}:%{name} /var/log/%{name}
chown -R %{name}:%{name} /var/app/%{name}

# remove build files
rm -rf /var/app/%{name}/build
rm -rf /var/app/%{name}/vendor

%clean
rm -rf %{buildroot}

%files
%defattr(-,%{name},%{name},-)
/usr/lib/systemd/system/flask-app.service
/var/app/%{name}/conf
/var/app/%{name}/vendor
/var/app/%{name}/wsgi.py
/var/app/%{name}/main.py