Цель этой статьи - наглядно показать как упаковать flask приложение на python3 в RPM пакет для последующего деплоя. Так как свежих материалов по созданию пакетов из приложений на основе исходников не так много, я решил написать собственную статью.

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

Договоримся, что корень приложения будет **/var/log/flask-app/**, создадим конфиг gynicorn

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
ExecStart=/var/app/flask-app/venv/bin/gunicorn --pythonpath /var/app/flask-app/sticker_app wsgi:app -c /var/app/flask-app/conf/gunicorn.conf --preload
ExecReload=/bin/kill -HUP $MAINPID
LimitNOFILE=1048000
LimitNPROC=32768

[Install]
WantedBy=multi-user.target
EOT
```

 Обратим внимание на то, как запускается приложение:

````bash
ExecStart=/var/app/flask-app/venv/bin/gunicorn --pythonpath /var/app/flask-app/sticker_app wsgi:app -c /var/app/flask-app/conf/gunicorn.conf --preload
````

Здесь следует обратить внимание на параметр —preload, который значительно ускоряет запуск приложения и уменьшает [количество потребляемой приложением памяти](http://docs.gunicorn.org/en/stable/settings.html#preload-app). 

## Создадим RPM пакет

Для создания пакетам нам понадобится утилита rpmbuild, docker образ, в котором будет собираться и тестироваться приложение. 

Сборка пакета состоит из следующи шагов:

1. Происходит проверка зависимостей 
2. Создаем арихв с исходными кодами приложения
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

# создаем пользователя
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
/var/app/%{name}/build/script/setup.sh

if [ $1 -gt 1 ]; then
    echo "Upgrade"
    mkdir -p /var/log/%{name}

    find %{__prefix}/%{name} -type f -name "*.py[co]" -delete
else
    echo "Install"

    mkdir -p /var/log/%{name}
fi

chown -R %{name}:%{name} /var/log/%{name}
chown -R %{name}:%{name} /var/app/stickersuggest

# remove all files int app root
find /var/app/%{name} -maxdepth 1 -type f -delete
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

Собирать rpm мы будем в докере:



