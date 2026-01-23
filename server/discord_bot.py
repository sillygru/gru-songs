import discord
from discord.ext import commands
import asyncio
import os
import signal
import datetime
from settings import settings

# Lazy import user_service inside commands/process to avoid global state issues
# But we can import the class/module structure
from user_service import user_service

class GruDiscordBot(commands.Bot):
    def __init__(self, queue, command_queue, *args, **kwargs):
        # Using a simple prefix "!" for non-slash commands
        intents = discord.Intents.default()
        intents.message_content = True
        super().__init__(command_prefix="!", intents=intents, *args, **kwargs)
        self.queue = queue
        self.command_queue = command_queue
        self.channel_id = int(settings.DISCORD_CHANNEL_ID) if settings.DISCORD_CHANNEL_ID else None

    async def setup_hook(self):
        self.bg_task = self.loop.create_task(self.check_queue())

    async def check_queue(self):
        await self.wait_until_ready()
        if not self.channel_id:
            print("DISCORD_CHANNEL_ID not set")
            return
            
        channel = self.get_channel(self.channel_id)
        if not channel:
            print(f"Discord Channel {self.channel_id} not found")
            return

        print(f"Bot connected and listening to channel: {channel.name}")
        await channel.send(f"Gru Songs Backend Logger started! (v{settings.VERSION})")

        while True:
            try:
                # Get all pending messages from the queue
                while True:
                    try:
                        message = self.queue.get_nowait()
                        if message is None:
                            return
                        
                        if isinstance(message, dict) and message.get("type") == "embed":
                            # Handle Embed
                            embed_data = message.get("data")
                            if embed_data:
                                await channel.send(embed=discord.Embed.from_dict(embed_data))
                        elif isinstance(message, dict) and message.get("type") == "file":
                            # Handle File
                            file_path = message.get("path")
                            filename = message.get("filename")
                            content = message.get("content", "")
                            if file_path and os.path.exists(file_path):
                                try:
                                    await channel.send(content=content, file=discord.File(file_path, filename=filename))
                                    # Delete temporary zip as requested
                                    os.remove(file_path)
                                except Exception as e:
                                    print(f"Failed to send file to discord: {e}")
                        elif message:
                            await channel.send(str(message))
                    except:
                        # Queue is empty
                        break
            except Exception as e:
                pass # Silent fail in loop to prevent bot crash
            
            await asyncio.sleep(0.5) # Check every half second

    async def on_ready(self):
        print(f'Logged in as {self.user} (ID: {self.user.id})')
        print('------')

def run_bot(queue, command_queue):
    # Ignore SIGINT (Ctrl+C) in the bot process so the parent can manage shutdown
    signal.signal(signal.SIGINT, signal.SIG_IGN)

    if not settings.DISCORD_TOKEN:
        print("DISCORD_TOKEN not set, skipping discord bot")
        return

    bot = GruDiscordBot(queue, command_queue)

    @bot.command(name="status")
    async def status(ctx):
        await ctx.send(f"Backend is online and recording stats. (v{settings.VERSION})")

    @bot.command(name="backup")
    async def backup(ctx, reset: str = "false"):
        reset_bool = reset.lower() == "true"
        
        # Send command to main process via queue
        if bot.command_queue:
            bot.command_queue.put({
                "command": "backup", 
                "reset": reset_bool,
                "requester": str(ctx.author)
            })
            if reset_bool:
                await ctx.send("Backup requested (Timer WILL be reset).")
            else:
                await ctx.send("Backup requested (Timer will NOT be reset).")
        else:
            await ctx.send("Internal Error: Command queue not available.")


    @bot.command(name="stats")
    async def stats(ctx, username: str = None):
        if not username:
            await ctx.send("Usage: !stats [username]")
            return

        # Fetch stats directly (Read-Only access to files is safe)
        summary = user_service.get_stats_summary(username)
        
        # Check if user exists (total_sessions is a good proxy, or check return structure)
        # get_stats_summary returns default structure even if empty file
        # Check if file exists to be sure? 
        # user_service.get_user returns None if no DB.
        user_info = user_service.get_user(username)
        if not user_info:
            await ctx.send(f"User '{username}' not found.")
            return

        # Build Embed
        embed = discord.Embed(title=f"Stats for {username}", color=0x1DB954)
        
        total_time_hrs = round(summary.get("total_play_time", 0) / 3600, 1)
        
        embed.add_field(name="Total Play Time", value=f"{total_time_hrs} hrs", inline=True)
        embed.add_field(name="Songs Played", value=f"{summary.get('total_songs_played', 0)}", inline=True)
        embed.add_field(name="Sessions", value=f"{summary.get('total_sessions', 0)}", inline=True)
        
        # Platform usage
        platforms = summary.get("platform_usage", {})
        if platforms:
            p_str = "\n".join([f"{k}: {v}" for k, v in platforms.items()])
            embed.add_field(name="Platforms", value=p_str, inline=False)
            
        embed.set_footer(text=f"Requested by {ctx.author.display_name} • {datetime.datetime.now().strftime('%Y-%m-%d %H:%M')}")
        
        await ctx.send(embed=embed)

    @bot.command(name="ping")
    async def ping(ctx):
        await ctx.send(f"Pong! Latency: {round(bot.latency * 1000)}ms")

    try:
        bot.run(settings.DISCORD_TOKEN, log_handler=None)
    except Exception:
        pass
    finally:
        # Force exit to prevent hanging multiprocessing join
        os._exit(0)

