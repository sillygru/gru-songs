import discord
from discord.ext import commands
import asyncio
import os
import signal
from settings import settings

class GruDiscordBot(commands.Bot):
# ... (rest of the class remains same)

    def __init__(self, queue, *args, **kwargs):
        # Using a simple prefix "!" for non-slash commands
        intents = discord.Intents.default()
        intents.message_content = True
        super().__init__(command_prefix="!", intents=intents, *args, **kwargs)
        self.queue = queue
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
        await channel.send("🚀 Gru Songs Backend Logger started!")

        while True:
            try:
                # Get all pending messages from the queue
                while True:
                    try:
                        message = self.queue.get_nowait()
                        if message is None:
                            return
                        if message:
                            await channel.send(message)
                    except:
                        # Queue is empty
                        break
            except Exception as e:
                pass # Silent fail in loop to prevent bot crash
            
            await asyncio.sleep(0.5) # Check every half second

    async def on_ready(self):
        print(f'Logged in as {self.user} (ID: {self.user.id})')
        print('------')

def run_bot(queue):
    # Ignore SIGINT (Ctrl+C) in the bot process so the parent can manage shutdown
    signal.signal(signal.SIGINT, signal.SIG_IGN)

    if not settings.DISCORD_TOKEN:
        print("DISCORD_TOKEN not set, skipping discord bot")
        return

    bot = GruDiscordBot(queue)

    @bot.command(name="status")
    async def status(ctx):
        await ctx.send("✅ Backend is online and recording stats.")

    @bot.command(name="stats")
    async def stats(ctx):
        # This could be expanded to show more interesting stats
        await ctx.send("📊 Stats recording is active. Use !ping to test latency.")

    @bot.command(name="ping")
    async def ping(ctx):
        await ctx.send(f"🏓 Pong! Latency: {round(bot.latency * 1000)}ms")

    try:
        bot.run(settings.DISCORD_TOKEN, log_handler=None)
    except Exception:
        pass
    finally:
        # Force exit to prevent hanging multiprocessing join
        os._exit(0)

if __name__ == "__main__":
    # For testing independently if needed
    from multiprocessing import Queue
    run_bot(Queue())
