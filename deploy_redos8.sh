#!/bin/bash

# =================================================================
# Скрипт автоматического развертывания kipsensors на RedOS 8
# Архитектура: Apache + mod_wsgi + MariaDB + SELinux (Enforcing)
# =================================================================

set -e

echo "--- Инициализация развертывания системы kipsensors ---"

# 1. Запрос параметров с дефолтными значениями
read -p "Имя системного пользователя [sensorsys]: " SYS_USER
SYS_USER=${SYS_USER:-sensorsys}

read -p "Название директории проекта в /var/www/ [sensorvar]: " PROJ_NAME
PROJ_NAME=${PROJ_NAME:-sensorvar}

read -p "Название БД в MariaDB [sensordb]: " DB_NAME
DB_NAME=${DB_NAME:-sensordb}

read -p "Имя технического пользователя БД [tech1]: " DB_USER
DB_USER=${DB_USER:-tech1}

read -s -p "Пароль технического пользователя БД [tech1pswd]: " DB_PASS
echo
DB_PASS=${DB_PASS:-tech1pswd}

PROJECT_ROOT="/var/www/$PROJ_NAME"

# 2. Установка системных пакетов
echo "Шаг 0: Установка системных зависимостей..."
sudo dnf install -y httpd mariadb-server python3 python3-pip python3-mod_wsgi gcc python3-devel openssl-devel mariadb-devel

# Проверка версии Python для RedOS 8
if command -v python3.11 &>/dev/null; then
    PYTHON_BIN=$(command -v python3.11)
else
    PYTHON_BIN=$(command -v python3)
fi
echo "Используется: $PYTHON_BIN"

# 3. Подготовка пользователя и структуры директорий
echo "Шаг 1: Создание пользователя $SYS_USER и подготовка $PROJECT_ROOT..."
if ! id "$SYS_USER" &>/dev/null; then
    sudo useradd -r -m -s /sbin/nologin "$SYS_USER"
fi

# Превентивное создание папки для конфигураций
sudo mkdir -p "$PROJECT_ROOT/instance"
# Копирование кода из текущей директории (папка app должна быть рядом со скриптом)
sudo cp -r ./app/* "$PROJECT_ROOT/"

# 4. Настройка прав доступа (POSIX)
echo "Шаг 2: Настройка прав доступа (POSIX)..."
sudo chown -R "$SYS_USER:apache" "$PROJECT_ROOT"
sudo find "$PROJECT_ROOT" -type d -exec chmod 755 {} +
sudo find "$PROJECT_ROOT" -type f -exec chmod 644 {} +
sudo chmod 775 "$PROJECT_ROOT"
sudo chmod 775 "$PROJECT_ROOT/instance"

# 5. Настройка SELinux (Критический этап для Enforcing)
echo "Шаг 3: Настройка политик SELinux..."
# Удаляем старые правила для этого пути, если они были
sudo semanage fcontext -d "$PROJECT_ROOT(/.*)?" 2>/dev/null || true
# Регистрируем новые правила (чтение/запись для проекта и выполнение для venv)
sudo semanage fcontext -a -t httpd_sys_rw_content_t "$PROJECT_ROOT(/.*)?"
sudo semanage fcontext -a -t httpd_sys_script_exec_t "$PROJECT_ROOT/kipvar(/.*)?"
sudo restorecon -Rv "$PROJECT_ROOT"
# Разрешаем веб-серверу сетевые соединения с БД
sudo setsebool -P httpd_can_network_connect_db on

# 6. Виртуальное окружение
echo "Шаг 4: Создание venv и установка библиотек Python..."
sudo -u "$SYS_USER" "$PYTHON_BIN" -m venv "$PROJECT_ROOT/kipvar"
sudo -u "$SYS_USER" "$PROJECT_ROOT/kipvar/bin/pip" install --upgrade pip
sudo -u "$SYS_USER" "$PROJECT_ROOT/kipvar/bin/pip" install flask flask-bootstrap flask-login sqlalchemy mysql-connector-python

# Повторная разметка venv после установки бинарных библиотек (.so)
sudo restorecon -Rv "$PROJECT_ROOT/kipvar"

# 7. Настройка MariaDB
echo "Шаг 5: Инициализация БД и пользователя..."
sudo systemctl enable --now mariadb
sudo mysql -u root -e "CREATE DATABASE IF NOT EXISTS $DB_NAME; 
CREATE USER IF NOT EXISTS '$DB_USER'@'localhost' IDENTIFIED BY '$DB_PASS'; 
GRANT ALL PRIVILEGES ON $DB_NAME.* TO '$DB_USER'@'localhost'; 
FLUSH PRIVILEGES;"

# 8. Конфигурация Apache и генерация WSGI
echo "Шаг 6: Настройка Apache и генерация точки входа..."

# Генерация kipsensors.wsgi с динамическими путями
cat <<EOF | sudo -u "$SYS_USER" tee "$PROJECT_ROOT/kipsensors.wsgi"
import sys
import os

# Путь к коду приложения
sys.path.insert(0, '$PROJECT_ROOT')

# Пути к библиотекам venv (Python 3.11)
venv_paths = [
    '$PROJECT_ROOT/kipvar/lib64/python3.11/site-packages',
    '$PROJECT_ROOT/kipvar/lib/python3.11/site-packages'
]

for path in venv_paths:
    if os.path.exists(path):
        sys.path.insert(0, path)

from app import app as application
EOF

sudo chown "$SYS_USER:apache" "$PROJECT_ROOT/kipsensors.wsgi"
sudo chmod 664 "$PROJECT_ROOT/kipsensors.wsgi"
sudo restorecon -v "$PROJECT_ROOT/kipsensors.wsgi"

# Конфигурация виртуального хоста
cat <<EOF | sudo tee /etc/httpd/conf.d/kipsensors.conf
<VirtualHost *:80>
    ServerName localhost
    WSGIDaemonProcess kipsensors user=$SYS_USER group=apache threads=5 python-home=$PROJECT_ROOT/kipvar
    WSGIProcessGroup kipsensors
    WSGIScriptAlias / $PROJECT_ROOT/kipsensors.wsgi

    <Directory $PROJECT_ROOT>
        Require all granted
    </Directory>

    ErrorLog logs/kipsensors-error_log
    CustomLog logs/kipsensors-access_log common
</VirtualHost>
EOF

if [ -f /etc/httpd/conf.d/welcome.conf ]; then
    sudo mv /etc/httpd/conf.d/welcome.conf /etc/httpd/conf.d/welcome.conf.bak
fi

sudo systemctl restart httpd
sudo systemctl enable httpd

echo "---------------------------------------------------"
echo "Развертывание на RedOS 8 завершено успешно."
echo "Адрес: http://localhost/"
echo "---------------------------------------------------"
