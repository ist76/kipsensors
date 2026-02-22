import sys
import os

# Путь к коду приложения
sys.path.insert(0, '/var/www/kipsensors/app')

# Прямой путь к библиотекам окружения kipvar
# В Ubuntu 24.04 это путь: .../kipvar/lib/python3.12/site-packages
venv_lib = '/var/www/kipsensors/kipvar/lib/python3.12/site-packages'
if os.path.exists(venv_lib):
    sys.path.insert(0, venv_lib)

from app import app as application

