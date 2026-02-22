import os
import json

class Config:
    # Якорь безопасности для сессий
    SECRET_KEY = os.environ.get('SECRET_KEY') or 'kiptest_final_stable_2026_v2.3'
    
    # БАЗОВЫЕ ЗНАЧЕНИЯ (Заглушки для режима "холодного старта")
    # Эти данные будут перезаписаны, если найден файл в папке instance
    DB_USER = 'guest'
    DB_PASSWORD = ''
    DB_HOST = 'localhost'
    DB_NAME = 'kiptest'
    
    SQLALCHEMY_TRACK_MODIFICATIONS = False

    @classmethod
    def load_runtime_config(cls):
        basedir = os.path.abspath(os.path.dirname(__file__))
        config_path = os.path.join(basedir, 'instance', 'db_params.json')
        
        if os.path.exists(config_path):
            try:
                with open(config_path, 'r', encoding='utf-8') as f:
                    data = json.load(f)
                    cls.DB_USER = data.get('DB_USER', cls.DB_USER)
                    cls.DB_PASSWORD = data.get('DB_PASSWORD', cls.DB_PASSWORD)
                    cls.DB_NAME = data.get('DB_NAME', cls.DB_NAME)
                    cls.DB_HOST = data.get('DB_HOST', cls.DB_HOST)
            except Exception:
                pass

    @classmethod
    def get_base_uri(cls, user, password):
        # Здесь мы храним драйвер в одном месте
        driver = 'mysql+mysqlconnector'
        return f"{driver}://{user}:{password}@{cls.DB_HOST}/"

    @property
    def SQLALCHEMY_DATABASE_URI(self):
        self.load_runtime_config()
        base = self.get_base_uri(self.DB_USER, self.DB_PASSWORD)
        return f"{base}{self.DB_NAME}"
