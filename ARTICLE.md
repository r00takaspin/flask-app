Цель этой статьи - наглядно продемонстрировать как упаковать flask приложение в RPM пакет для последующего деплоя. 
Так как свежих материалов по созданию пакетов на основе исходных кодов не так много, я решил написать собственную статью.

### Требование к приложению:
* приложение должно быть упаковано в RPM пакет вместе с зависимостями
* запуск приложения должен осуществляться за счет systemd
* приложение должно работать в многопоточном режиме

### Инструменты:
docker, flask, gunicorn, rpmbuild, pip

### План:
1. Создание тестового приложения
2. Запуск приложения через gunicorn, добавление конфига для systemd
3. Написание .spec файла для построения RPM пакета
4. Создание docker образов для сборки пакета и его установке на тестовую сборку

## Создание тестового приложения
### Подготовка окружения
Устанавливаем актуальную версию python и pip:
```bash
brew install python3
pip install flask
```

### Создание приложения

Создаем тестовое приложение, с <a href="http://flask.pocoo.org/">официального примера на сайте flask</a>:

```bash
mkdir -p flask-app && cd flask-app
# создаем venv
python3 -m venv venv
# активируем venv
. ./venv/bin/activate
# обновляем pip
pip install --upgrade pip

#TODO: добавить pytorch модель
cat <<EOT >> main.py
from flask import Flask
app = Flask(__name__)

@app.route("/")
def hello():
    return "Hello Хабр!"
EOT

pip install gunicorn

# фиксируем зависимости
pip freeze > requirements.txt
```

Файл зависимостей должен будет выглядеть следующим образом:
```bash
$ cat requirements.txt
Click==7.0
Flask==1.0.3
gunicorn==19.9.0
itsdangerous==1.1.0
Jinja2==2.10.1
MarkupSafe==1.1.1
Werkzeug==0.15.4
```

## Подготовим приложение к запуску в production
Создадим файл wsgi.py для запуска веб-сервера в многопоточном режиме:
```bash
echo "from main import app" >> wsgi.py
```

Договоримся, что корень приложения будет **/var/app/flask-app/**, создадим конфиг gynicorn:

```bash
mkdir -p build/config
cat <<EOT>> build/config/gunicorn.conf
bind = '0.0.0.0:8000'
proc_name = 'flask-app'
accesslog = '/var/log/flask-app/access.log'
errorlog = '/var/log/flask-app/error.log'
timeout = 3
# число воркеров следуем ставить равным числу ядер*2 
workers = 8
EOT
```

Создадим теперь конфиг для  systemd:

```bash
mkdir -p build/systemd
cat <<EOT>> build/systemd/flask-app.service
[Unit]
Description=flask-app
After=network.target

[Service]
# имя пользователя и группа, под которым будет запущено приложение
User=flask-app
Group=flask-app
# директория в которой запускается приложение, конфиги приложения должны находиться в ней, иначе могут случиться ошибки доступа к файлам
WorkingDirectory=/var/app/flask-app
Type=simple
ExecStart=/var/app/flask-app/venv/bin/gunicorn --pythonpath /var/app/flask-app/flask-app wsgi:app -c /var/app/flask-app/conf/gunicorn.conf --preload
ExecReload=/bin/kill -HUP $MAINPID
LimitNOFILE=1048000
LimitNPROC=32768

[Install]
WantedBy=multi-user.target
EOT
```

 Обратим внимание на то, как запускается приложение:

````bash
ExecStart=/var/app/flask-app/venv/bin/gunicorn --pythonpath /var/app/flask-app/flask-app wsgi:app -c /var/app/flask-app/conf/gunicorn.conf --preload
````

Здесь следует обратить внимание на параметр —preload, который значительно ускоряет запуск приложения и уменьшает [количество потребляемой приложением памяти](http://docs.gunicorn.org/en/stable/settings.html#preload-app). 

## Создадим RPM пакет

Для создания пакета нам понадобится утилита rpmbuild, docker образ, в котором будет собираться и тестироваться приложение. 

Сборка пакета состоит из следующи шагов:

1. Происходит проверка зависимостей 
2. Создается архив с исходными кодами приложения
3. При сборке пакета необходимые файлы копируются из папки %{_builddir} в папку %{buildroot} в разделе %install
4. Список тех файлов, которые попадут на целевую систему описываются в %files, остальные файлы будут проигнорированы
5. Создается пакет в папке /root/rpmbuild/RPMS/x86_64/

Шаги установки пакета:

1. Происходит проверка зависимостей
2. Отрабатывает хук %pre, здесь мы создаем нового пользователя, под которым будет запускаться приложение
3. Отрабатывает хук %post, где мы установим venv, установим все нужные зависимости и создадим сервис в systemd

Чтобы создать пакет, нужно сначала создать spec файл, в котором определены этапы сборки. 

```bash
mkdir -p build/rpm
cat <<EOT> build/rpm/flask-app.spec
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

# создаем пользователя, под которым будет запущено приложение
%pre
/usr/bin/getent group %{name} || /usr/sbin/groupadd -r %{name}
/usr/bin/getent passwd %{name} || /usr/sbin/useradd -r -d /opt/%{name}/ -s /bin/false %{name} -g %{name}

%prep
if [ -d %{name} ]; then
    echo "Cleaning out stale build directory" 1>&2
    rm -rf %{name}
fi

# распаковка архива с исходными кодами
mkdir -p %{name}
tar xjf %{SOURCE0} -C %{name}

%install
mkdir -p -m0755 %{buildroot}/var/app/%{name}
mkdir -p -m0755 %{buildroot}/var/app/%{name}/conf

cp -r %{_builddir}/%{name}/build %{buildroot}/var/app/%{name}
cp %{_builddir}/%{name}/build/config/gunicorn.conf %{buildroot}/var/app/%{name}/conf/gunicorn.conf

echo "Installing systemd config"
    %{__install} -p -D -m 0644 %{_builddir}/%{name}/build/systemd/%{name}.service %{buildroot}/usr/lib/systemd/system/%{name}.service

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

# 
chown -R %{name}:%{name} /var/log/%{name}
chown -R %{name}:%{name} /var/app/%{name}

# remove build files
rm -rf /var/app/%{name}/build
rm -rf /var/app/%{name}/vendor

%clean
rm -rf %{buildroot}

%files
%defattr(-,%{name},%{name},-)
/usr/lib/systemd/system/%{name}.service
%config(noreplace) /var/app/%{name}/conf

/var/app/%{name}
EOT
```

Для сборки RPM пакета добавим Dockerfile:

```dockerfile
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
```

Для сборки RPM пакета выполним следующие команды:

```bash
# образ для сборки RPM пакета
docker build --target rpm-build -t rpm-build .
docker run -v $(pwd)/rpm:/tmp/rpm rpm-build sh -c 'cp /root/rpmbuild/RPMS/x86_64/*.rpm /tmp/rpm'
```

После этого, в директории rpm появится файл с пакетом:

```bash
$ ls -la ./rpm
total 1296
drwxr-xr-x   3 voldemar  staff      96 Jun 24 22:19 .
drwxr-xr-x  14 voldemar  staff     448 Jun 24 22:22 ..
-rw-r--r--   1 voldemar  staff  662348 Jun 24 22:19 flask-app-1.0-1561403919.x86_64.rpm
```

Теперь проверим, как пакет установится в конечную систему, сделаем это при помощи докера. Для этого, нам понадобится добавить еще один stage в Dockerfile:

```do
...

FROM centos/systemd as rpm-check
COPY build/script/setup.sh setup.sh
RUN ./setup.sh && rm -rf setup.sh
COPY --from=rpm-build /root/rpmbuild/RPMS/x86_64/*.rpm /tmp/
CMD ["/usr/sbin/init"]

```

По умолчанию systemd отключен в docker образах, так как подразумевается, что в контейнере будет запущен всего один процесс. Для этого нам придется воспользоваться официальным образом centos/systemd.

Указанный выше конфиг запускает systemd демон, но тем самым он блокирует IO. Поэтому нам нужно запустить контейнер c флагом -d и подключиться к нему из другой сессии, чтобы установить пакет и проверить   то, как запустился веб-сервер:

```bash
docker kill rpm-check-cont || true
docker rm rpm-check-cont || true
DOCKER_BUILDKIT=1 docker build --target rpm-check -t rpm-check .
docker run --privileged --name rpm-check-cont -v /sys/fs/cgroup:/sys/fs/cgroup:ro -d rpm-check
docker exec rpm-check-cont sh -c 'rpm -i /tmp/flask-app-*.rpm && systemctl enable flask-app && systemctl start flask-app && systemctl status flask-app'
```

