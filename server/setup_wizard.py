import os
import sys
from config_manager import config_manager

def clear_screen():
    os.system('cls' if os.name == 'nt' else 'clear')

def print_header():
    print("=" * 60)
    print("      GRU SONGS SERVER - FIRST TIME SETUP WIZARD (v3.4.1)      ")
    print("=" * 60)
    print()

def ask_yes_no(question, default=None):
    hint = "[Y/n]" if default == True else "[y/N]" if default == False else "[y/n]"
    while True:
        choice = input(f"{question}{hint}: ").lower().strip()
        if not choice and default is not None:
            return default
        if choice in ['y', 'yes']:
            return True
        if choice in ['n', 'no']:
            return False
        print("Please enter 'y' or 'n'.")

def ask_input(question, default=None):
    hint = f"(default: {default})" if default else ""
    while True:
        val = input(f"{question}{hint}: ").strip()
        if not val and default is not None:
            return default
        if val:
            return val
        print("Input cannot be empty.")

def ask_int(question, default=None):
    while True:
        val = ask_input(question, str(default) if default else None)
        try:
            return int(val)
        except ValueError:
            print("Please enter a valid number.")

def run_wizard():
    clear_screen()
    print_header()
    print("Welcome! Let's configure your Gru Songs server.")
    print("Settings will be saved to config.json and .env.\n")

    config = config_manager.config

    # 1. Discord Bot Settings
    use_discord = ask_yes_no("Do you want to use a Discord Bot?", config.get("use_discord_bot"))
    config["use_discord_bot"] = use_discord

    if use_discord:
        token = input("Enter Discord Bot Token (leave empty to skip/edit later): ").strip()
        if token:
            config_manager.update_env("DISCORD_TOKEN", token)
        
        channel_id = input("Enter Discord Channel ID (leave empty to skip/edit later): ").strip()
        if channel_id:
            config_manager.update_env("DISCORD_CHANNEL_ID", channel_id)

        log_to_discord = ask_yes_no("Should the server log activities to Discord?", config.get("log_to_discord"))
        config["log_to_discord"] = log_to_discord
    else:
        config["log_to_discord"] = False

    print("\n--- Backup Settings ---")
    
    # 2. Backup Settings
    backup_enabled = ask_yes_no("Enable automatic backups?", config.get("backup_enabled"))
    config["backup_enabled"] = backup_enabled

    if backup_enabled:
        interval = ask_int("How often should backups run (in hours)?", config.get("backup_interval_hours", 6))
        config["backup_interval_hours"] = interval

        send_to_discord = False
        if use_discord:
            send_to_discord = ask_yes_no("Send backup ZIPs to the Discord channel?", config.get("send_backups_to_discord"))
            
            # If they want to send to discord but didn't set a channel ID yet
            if send_to_discord and not os.getenv("DISCORD_CHANNEL_ID"):
                channel_id = input("Backup to Discord requires a Channel ID. Enter it now (or press enter to skip/edit later): ").strip()
                if channel_id:
                    config_manager.update_env("DISCORD_CHANNEL_ID", channel_id)
            config["send_backups_to_discord"] = send_to_discord

        skip_identical = ask_yes_no("Skip backups if data hasn't changed?", config.get("skip_identical_backups", True))
        config["skip_identical_backups"] = skip_identical
    else:
        config["backup_interval_hours"] = None
        config["send_backups_to_discord"] = False
        config["skip_identical_backups"] = False

    config_manager.save_config(config)
    
    print("\n" + "=" * 60)
    print("Setup complete! config.json has been updated.")
    print("=" * 60)
    print("\nStarting server...\n")

if __name__ == "__main__":
    run_wizard()
