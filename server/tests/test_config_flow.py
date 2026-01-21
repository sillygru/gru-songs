import os
import json
import unittest
import sys
from unittest.mock import patch, MagicMock

# Setup env for testing
os.environ["GRUSONGS_TESTING"] = "true"
sys.path.append(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

from config_manager import ConfigManager, CONFIG_PATH, ENV_PATH
from settings import Settings

class TestConfigFlow(unittest.TestCase):
    def setUp(self):
        # Backup existing config/env if any
        self.old_config = None
        if os.path.exists(CONFIG_PATH):
            with open(CONFIG_PATH, 'r') as f:
                self.old_config = f.read()
            os.remove(CONFIG_PATH)
            
        self.old_env = None
        if os.path.exists(ENV_PATH):
            with open(ENV_PATH, 'r') as f:
                self.old_env = f.read()
            os.remove(ENV_PATH)

    def tearDown(self):
        # Restore old config/env
        if os.path.exists(CONFIG_PATH):
            os.remove(CONFIG_PATH)
        if self.old_config:
            with open(CONFIG_PATH, 'w') as f:
                f.write(self.old_config)

        if os.path.exists(ENV_PATH):
            os.remove(ENV_PATH)
        if self.old_env:
            with open(ENV_PATH, 'w') as f:
                f.write(self.old_env)

    def test_fresh_start_incomplete(self):
        """Case: No config file exists."""
        cm = ConfigManager()
        self.assertFalse(cm.is_setup_complete(), "Setup should be incomplete on fresh start")

    def test_partial_config_incomplete(self):
        """Case: config.json exists but missing fields."""
        cm = ConfigManager()
        cm.save_config({"use_discord_bot": True})
        self.assertFalse(cm.is_setup_complete(), "Setup should be incomplete with partial fields")
        
        cm.save_config({
            "use_discord_bot": True,
            "log_to_discord": True,
            "backup_enabled": True
            # Missing interval and other backup settings
        })
        self.assertFalse(cm.is_setup_complete(), "Setup should be incomplete with missing backup interval")

    def test_complete_config(self):
        """Case: All fields correctly set."""
        cm = ConfigManager()
        cm.save_config({
            "use_discord_bot": True,
            "log_to_discord": True,
            "backup_enabled": True,
            "backup_interval_hours": 6,
            "send_backups_to_discord": True,
            "skip_identical_backups": True
        })
        self.assertTrue(cm.is_setup_complete(), "Setup should be complete when all fields are present")

    def test_env_creation_and_update(self):
        """Case: ConfigManager creates and updates .env file."""
        cm = ConfigManager()
        cm.update_env("TEST_KEY", "TEST_VALUE")
        
        self.assertTrue(os.path.exists(ENV_PATH))
        with open(ENV_PATH, 'r') as f:
            content = f.read()
            # Be flexible with quotes (python-dotenv might use ' or ")
            self.assertTrue('TEST_KEY="TEST_VALUE"' in content or "TEST_KEY='TEST_VALUE'" in content)

    def test_settings_validation_edge_cases(self):
        """Case: Settings validation for Discord."""
        s = Settings()
        
        # 1. Disabled
        with patch.object(ConfigManager, 'get', return_value=False):
            valid, msg = s.validate_discord()
            self.assertFalse(valid)
            self.assertIn("disabled", msg.lower())

        # 2. Enabled but missing token
        with patch.object(ConfigManager, 'get', return_value=True), \
             patch('os.getenv', side_effect=lambda k, d=None: None if k == "DISCORD_TOKEN" else "123"):
            valid, msg = s.validate_discord()
            self.assertFalse(valid)
            self.assertIn("token", msg.lower())

        # 3. Enabled but default/invalid token
        with patch.object(ConfigManager, 'get', return_value=True), \
             patch('os.getenv', side_effect=lambda k, d=None: "guess" if k == "DISCORD_TOKEN" else "123"):
            valid, msg = s.validate_discord()
            self.assertFalse(valid)
            self.assertIn("invalid", msg.lower())

    @patch('setup_wizard.input', side_effect=['y', 'token123', 'channel456', 'y', 'y', '3', 'y', 'y'])
    def test_wizard_flow(self, mock_input):
        """Case: Simulating the setup wizard execution."""
        from setup_wizard import run_wizard
        run_wizard()
        
        cm = ConfigManager()
        self.assertTrue(cm.is_setup_complete())
        self.assertEqual(cm.get("backup_interval_hours"), 3)
        self.assertTrue(cm.get("use_discord_bot"))
        
        # Verify .env was updated (mocking os.getenv for the verify part)
        with patch('os.getenv', side_effect=lambda k, d=None: 'token123' if k == 'DISCORD_TOKEN' else 'channel456'):
            s = Settings()
            self.assertEqual(s.DISCORD_TOKEN, 'token123')
            self.assertEqual(s.DISCORD_CHANNEL_ID, 'channel456')

if __name__ == '__main__':
    unittest.main()
