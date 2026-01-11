import os
from sqlmodel import SQLModel, create_engine, Session
from settings import settings

class DatabaseManager:
    def __init__(self):
        self.users_dir = settings.USERS_DIR
        if not os.path.exists(self.users_dir):
            os.makedirs(self.users_dir)

    def _get_engine(self, db_name: str):
        url = f"sqlite:///{os.path.join(self.users_dir, db_name)}"
        return create_engine(url, connect_args={"check_same_thread": False})

    def get_global_users_engine(self):
        return self._get_engine("global_users.db")

    def get_uploads_engine(self):
        return self._get_engine("uploads.db")

    def get_user_data_engine(self, username: str):
        return self._get_engine(f"{username}_data.db")

    def get_user_playlists_engine(self, username: str):
        return self._get_engine(f"{username}_playlists.db")

    def get_user_stats_engine(self, username: str):
        return self._get_engine(f"{username}_stats.db")

    def init_global_dbs(self):
        # Create tables for global DBs
        from db_models import GlobalUser, Upload
        SQLModel.metadata.create_all(self.get_global_users_engine())
        SQLModel.metadata.create_all(self.get_uploads_engine())

    def init_user_dbs(self, username: str):
        # Create tables for specific user DBs
        from db_models import UserData, Favorite, SuggestLess, Playlist, PlaylistSong, PlaySession, PlayEvent
        
        # We need to filter metadata to only create relevant tables for each DB
        # This is a bit tricky with SQLModel as metadata is shared by default.
        # Strategy: Use explicit bind or target specific tables if possible, 
        # or just rely on the fact that creating extra empty tables in SQLite is cheap/harmless,
        # BUT strictly speaking we should separate them. 
        #
        # Better approach: 
        # Since SQLModel inherits from SQLAlchemy, we can create tables individually.
        
        # 1. User Data DB
        e_data = self.get_user_data_engine(username)
        UserData.__table__.create(e_data, checkfirst=True)
        Favorite.__table__.create(e_data, checkfirst=True)
        SuggestLess.__table__.create(e_data, checkfirst=True)
        
        # 2. Playlists DB
        e_pl = self.get_user_playlists_engine(username)
        Playlist.__table__.create(e_pl, checkfirst=True)
        PlaylistSong.__table__.create(e_pl, checkfirst=True)
        
        # 3. Stats DB
        e_stats = self.get_user_stats_engine(username)
        PlaySession.__table__.create(e_stats, checkfirst=True)
        PlayEvent.__table__.create(e_stats, checkfirst=True)

db_manager = DatabaseManager()
