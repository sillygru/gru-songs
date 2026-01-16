import os
import json
import time
import random
import logging
import uuid
from typing import List, Optional, Dict
from collections import defaultdict

from settings import settings
from models import QueueItem, QueueState, ShufflePersonality, ShuffleConfig
from user_service import user_service
from services import music_service

logger = logging.getLogger("uvicorn.error")

class QueueService:
    def __init__(self):
        pass

    def _get_queue_path(self, username: str):
        return os.path.join(settings.USERS_DIR, f"{username}_queue.json")

    def get_queue(self, username: str) -> QueueState:
        path = self._get_queue_path(username)
        if os.path.exists(path):
            try:
                with open(path, "r") as f:
                    data = json.load(f)
                    return QueueState(**data)
            except Exception as e:
                logger.error(f"Failed to load queue for {username}: {e}")
        
        # Return empty state if none exists
        return QueueState()

    def save_queue(self, username: str, queue_state: QueueState):
        path = self._get_queue_path(username)
        try:
            with open(path, "w") as f:
                f.write(queue_state.json())
        except Exception as e:
            logger.error(f"Failed to save queue for {username}: {e}")

    def sync_queue(self, username: str, client_queue: List[QueueItem], current_index: int, client_version: int) -> QueueState:
        # Simple "Server Authoritative" strategy for now:
        # If server version > client version, server wins (send back server state).
        # If client version >= server version, client wins (update server state).
        # EXCEPT: If client is just coming online, it might have 'offline' changes.
        # For this implementation, we will trust the client's explicit sync request 
        # as the latest truth if the version is higher, otherwise we return server state.
        
        server_state = self.get_queue(username)
        
        if client_version > server_state.version:
            # Client has newer state (e.g. offline changes)
            new_state = QueueState(
                items=client_queue, 
                current_index=current_index, 
                version=client_version
            )
            self.save_queue(username, new_state)
            return new_state
        else:
            # Server has equal or newer state, or client is stale
            # Return server state to force client to catch up
            return server_state

    def get_next_song(self, username: str) -> Optional[QueueItem]:
        queue_state = self.get_queue(username)
        
        # 1. Check for priority items after current index
        # We need to look at items *after* current_index
        next_index = queue_state.current_index + 1
        
        # Logic:
        # If we have items in the queue after current_index, check if they are priority.
        # However, the instruction says: "The server is responsible for... Weighted shuffle selection"
        # and "Returning the next song on-demand".
        # If the client asks for "next song", it usually means the current one finished or was skipped.
        
        # If we are in "Shuffle Mode", we should GENERATE the next song and append it 
        # if there isn't a manual priority song waiting.
        
        # Get user shuffle config
        summary = user_service.get_stats_summary(username)
        shuffle_state = summary.get("shuffle_state", {})
        config_dict = shuffle_state.get("config", {})
        config = ShuffleConfig(**config_dict)
        
        if not config.enabled:
            # Linear playback
            if next_index < len(queue_state.items):
                queue_state.current_index = next_index
                self.save_queue(username, queue_state)
                return queue_state.items[next_index]
            else:
                return None # End of queue

        # Shuffle Mode
        
        # Check if the IMMEDIATE next item is a user-queued priority item
        if next_index < len(queue_state.items):
            next_item = queue_state.items[next_index]
            if next_item.is_priority:
                # Play the priority item
                queue_state.current_index = next_index
                self.save_queue(username, queue_state)
                return next_item
            # If not priority, and we are in shuffle mode, we might want to replace/re-shuffle 
            # the 'next up' if it was pre-generated, OR just generate a new one if we are at end.
            # For simplicity: If there are items, we assume they are the "Next Up" list. 
            # But the prompt implies server calculates next shuffled track.
            
            # Let's assume the client maintains a small buffer, but if it runs out or asks, we give one.
            # If there are items remaining that are NOT priority, are they "shuffled" items or "manual" items?
            # Standard behavior: Queue is mixture of manual and shuffled.
            # If we just play the next one, we are fine.
            
            queue_state.current_index = next_index
            self.save_queue(username, queue_state)
            return next_item

        # Queue is exhausted (or at least past the cursor). Generate a new song.
        next_song_filename = self._pick_next_shuffled_song(username, config, shuffle_state)
        
        if not next_song_filename:
            return None
            
        new_item = QueueItem(
            queue_id=str(uuid.uuid4()),
            song_filename=next_song_filename,
            is_priority=False,
            added_at=time.time()
        )
        
        queue_state.items.append(new_item)
        queue_state.current_index = len(queue_state.items) - 1
        queue_state.version += 1 # Server mutation increments version
        
        self.save_queue(username, queue_state)
        return new_item

    def _pick_next_shuffled_song(self, username: str, config: ShuffleConfig, shuffle_state: dict) -> Optional[str]:
        all_songs = music_service.list_songs()
        if not all_songs:
            return None
            
        # Filter context
        history_list = shuffle_state.get("history", [])
        # Convert history to list of filenames if it's dicts
        history_filenames = []
        for h in history_list:
            if isinstance(h, dict):
                history_filenames.append(h.get("filename"))
            else:
                history_filenames.append(h)
                
        favorites = user_service.get_favorites(username)
        suggest_less = user_service.get_suggest_less(username)
        play_counts = user_service.get_play_counts(username)
        
        # Resolve consistent playlists if needed
        consistent_songs = set()
        if config.personality == ShufflePersonality.CONSISTENT:
             playlists = user_service.get_playlists(username)
             for p in playlists:
                 if p['id'] in config.consistent_playlists:
                     for s in p['songs']:
                         consistent_songs.add(s['filename'])

        # Calculate weights
        candidates = []
        weights = []
        
        last_played_filename = history_filenames[0] if history_filenames else None
        last_played_artist = None
        last_played_album = None
        
        if last_played_filename:
            # Find metadata
            for s in all_songs:
                if s['filename'] == last_played_filename:
                    last_played_artist = s.get('artist')
                    last_played_album = s.get('album')
                    break
        
        for song in all_songs:
            fname = song['filename']
            # Hard exclude: don't play the exact same song immediately again (unless it's the only one)
            if last_played_filename == fname and len(all_songs) > 1:
                continue

            weight = self._calculate_weight(
                song, 
                config, 
                favorites, 
                suggest_less, 
                play_counts, 
                history_filenames,
                consistent_songs,
                last_played_artist,
                last_played_album
            )
            candidates.append(fname)
            weights.append(weight)
            
        if not candidates:
            return None
            
        return random.choices(candidates, weights=weights, k=1)[0]

    def _calculate_weight(
        self, 
        song: dict, 
        config: ShuffleConfig, 
        favorites: List[str], 
        suggest_less: List[str],
        play_counts: Dict[str, int],
        history: List[str],
        consistent_songs: set,
        last_artist: Optional[str],
        last_album: Optional[str]
    ) -> float:
        weight = 1.0
        fname = song['filename']
        
        # --- Personality: DEFAULT ---
        if config.personality == ShufflePersonality.DEFAULT:
            # 1. Favorites & Suggest Less
            if fname in favorites: weight *= config.favorite_multiplier
            if fname in suggest_less: weight *= config.suggest_less_multiplier
            
            # 2. Anti-repeat (History)
            if config.anti_repeat_enabled and history:
                try:
                    idx = history.index(fname)
                    # Linear decay: 0.05 at index 0, up to 1.0 at limit
                    # Formula: 0.95 * (1.0 - (idx / limit)) -> reduction
                    # weight *= (1 - reduction)
                    # Simplified from Dart logic:
                    reduction = 0.95 * (1.0 - (idx / config.history_limit))
                    weight *= (1.0 - max(0.0, reduction))
                except ValueError:
                    pass
            
            # 3. Streak Breaker
            if config.streak_breaker_enabled and last_artist:
                if song.get('artist') == last_artist and last_artist != 'Unknown':
                    weight *= 0.5
                if song.get('album') == last_album and last_album != 'Unknown Album':
                    weight *= 0.7

        # --- Personality: EXPLORER ---
        elif config.personality == ShufflePersonality.EXPLORER:
            count = play_counts.get(fname, 0)
            
            if count == 0:
                weight *= 10.0 # Huge boost for unplayed
            elif count < 5:
                weight *= 3.0  # Boost for rare
            elif count > 20:
                weight *= 0.5  # Penalize overplayed
                
            # Favorites are neutral (1.0) or slight boost? Prompt says "favorites... weight reduced influence".
            # Let's keep them neutral or slight.
            if fname in favorites: weight *= 1.1 
            
            # Suggest less is strong penalty
            if fname in suggest_less: weight *= 0.1
            
            # Anti-repeat is softer
            if history:
                try:
                    idx = history.index(fname)
                    # Max reduction 50%
                    reduction = 0.5 * (1.0 - (idx / config.history_limit))
                    weight *= (1.0 - max(0.0, reduction))
                except ValueError:
                    pass

        # --- Personality: CONSISTENT ---
        elif config.personality == ShufflePersonality.CONSISTENT:
            # 1. Favorites: Strong boost
            if fname in favorites: weight *= 3.0
            
            # 2. Selected Playlists
            if fname in consistent_songs: weight *= 5.0
            
            # 3. Most played boost
            count = play_counts.get(fname, 0)
            if count > 10:
                weight *= 1.5
            if count > 50:
                weight *= 2.0
                
            # 4. Anti-repeat: Relaxed
            # Only penalize very recent songs strongly
            if history:
                try:
                    idx = history.index(fname)
                    if idx < 10: # Only care about last 10
                         weight *= 0.05 # Don't play immediate repeats
                    # No artist/streak penalty
                except ValueError:
                    pass
                    
        return max(0.0001, weight)

queue_service = QueueService()
