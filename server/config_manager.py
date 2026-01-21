import json
import os
from dotenv import load_dotenv, set_key

CONFIG_PATH = os.path.join(os.path.dirname(__file__), "config.json")
ENV_PATH = os.path.join(os.path.dirname(__file__), ".env")

class ConfigManager:
    def __init__(self):
        self.config = self._load_config()

    def _load_config(self):
        if os.path.exists(CONFIG_PATH):
            try:
                with open(CONFIG_PATH, 'r') as f:
                    return json.load(f)
            except Exception:
                return {}
        return {}

    def save_config(self, config):
        self.config = config
        with open(CONFIG_PATH, 'w') as f:
            json.dump(config, f, indent=4)

    def update_env(self, key, value):
        if not os.path.exists(ENV_PATH):
            with open(ENV_PATH, 'w') as f:
                f.write("")
        set_key(ENV_PATH, key, value)
        # Reload env after update
        load_dotenv(ENV_PATH, override=True)

    def is_setup_complete(self):
        required_keys = [
            "use_discord_bot",
            "backup_enabled",
        ]
        
        # Check if config is empty
        if not self.config:
            return False

        # Basic check
        for key in required_keys:
            if key not in self.config or self.config[key] is None:
                return False
        
        # Discord specific check
        if self.config.get("use_discord_bot"):
            if self.config.get("log_to_discord") is None:
                return False
            
        # Backup specific check
        if self.config.get("backup_enabled"):
            for k in ["backup_interval_hours", "send_backups_to_discord", "skip_identical_backups"]:
                if k not in self.config or self.config[k] is None:
                    return False
                
        return True

    def get(self, key, default=None):
        return self.config.get(key, default)

config_manager = ConfigManager()
