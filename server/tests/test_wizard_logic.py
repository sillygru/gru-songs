import os
import json
import unittest
import sys

# Setup env for testing
os.environ["GRUSONGS_TESTING"] = "true"
sys.path.append(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

from config_manager import ConfigManager, CONFIG_PATH

class TestWizardPersistence(unittest.TestCase):
    def setUp(self):
        if os.path.exists(CONFIG_PATH):
            os.remove(CONFIG_PATH)

    def test_persistence_logic(self):
        cm = ConfigManager()
        
        # Scenario 1: Empty
        self.assertFalse(cm.is_setup_complete())
        
        # Scenario 2: Only Discord
        cm.save_config({
            "use_discord_bot": True,
            "log_to_discord": True,
            "backup_enabled": None # Explicitly null
        })
        self.assertFalse(cm.is_setup_complete())
        
        # Scenario 3: Backups enabled but missing fields
        cm.save_config({
            "use_discord_bot": False,
            "backup_enabled": True,
            "backup_interval_hours": None
        })
        self.assertFalse(cm.is_setup_complete())
        
        # Scenario 4: Fully defined
        cm.save_config({
            "use_discord_bot": False,
            "backup_enabled": True,
            "backup_interval_hours": 6,
            "send_backups_to_discord": False,
            "skip_identical_backups": True
        })
        self.assertTrue(cm.is_setup_complete())

if __name__ == '__main__':
    unittest.main()
